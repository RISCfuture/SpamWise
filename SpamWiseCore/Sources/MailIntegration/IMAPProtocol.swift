import Foundation

extension IMAPAdapter {
  static func moveMapping(_ rows: [[IMAPToken]], uid: Int) -> (validity: UInt64, uid: Int)? {
    let mappings = rows.filter { $0.contains { $0.isAtom("[COPYUID") } }
    guard mappings.count == 1, let row = mappings.first,
      row.filter({ $0.isAtom("[COPYUID") }).count == 1,
      let index = row.firstIndex(where: { $0.isAtom("[COPYUID") }), index + 3 < row.count,
      let validity = row[index + 1].text.flatMap(UInt32.init), validity > 0,
      row[index + 2].text == String(uid), let destination = row[index + 3].text,
      destination.hasSuffix("]"), let destinationUID = UInt32(destination.dropLast()),
      destinationUID > 0
    else { return nil }
    return (UInt64(validity), Int(destinationUID))
  }
}

/// Tokens preserve literals as opaque bytes so message content cannot become protocol syntax.
enum IMAPToken: Equatable, Sendable {
  case atom(String), string(String), literal(Data), open, close
  var text: String? {
    switch self {
      case .atom(let text), .string(let text): text
      case .literal(let data): String(data: data, encoding: .utf8)
      default: nil
    }
  }
  func isAtom(_ expected: String) -> Bool {
    if case .atom(let value) = self { value.uppercased() == expected.uppercased() } else { false }
  }
}

actor IMAPResponseReader {
  private let transport: any IMAPTransport
  private var buffer = Data()
  init(transport: any IMAPTransport) { self.transport = transport }

  func read() async throws -> [IMAPToken] {
    var tokens: [IMAPToken] = []
    var total = 0, literals = 0, depth = 0
    while true {
      let line = try await readLine()
      total += line.count
      var segment = try Self.tokenize(line)
      var literalLength: Int?
      if let last = segment.last, case .atom(let text) = last, text.hasPrefix("{") {
        guard text.hasSuffix("}"), let length = Int(text.dropFirst().dropLast()), length >= 0 else {
          throw IMAPError.malformedResponse
        }
        guard length <= 2_000_000 else { throw IMAPError.limitExceeded }
        literalLength = length
        segment.removeLast()
      }
      for token in segment {
        if token == .open { depth += 1 }
        if token == .close { depth -= 1 }
        guard depth >= 0, depth <= 12 else { throw IMAPError.malformedResponse }
      }
      tokens += segment
      guard tokens.count <= 4096, total <= 2_100_000 else { throw IMAPError.limitExceeded }
      guard let literalLength else {
        guard depth == 0 else { throw IMAPError.malformedResponse }
        return tokens
      }
      literals += 1
      total += literalLength
      guard literals <= 8, total <= 2_100_000 else { throw IMAPError.limitExceeded }
      tokens.append(.literal(try await readBytes(literalLength)))
    }
  }

  private func readLine() async throws -> Data {
    while true {
      if let range = buffer.range(of: Data([13, 10])) {
        guard range.lowerBound <= 65_536 else { throw IMAPError.limitExceeded }
        let line = Data(buffer[..<range.lowerBound])
        buffer.removeSubrange(..<range.upperBound)
        buffer = Data(buffer)
        return line
      }
      guard buffer.count <= 65_536 else { throw IMAPError.limitExceeded }
      try await appendChunk()
    }
  }
  private func readBytes(_ length: Int) async throws -> Data {
    while buffer.count < length { try await appendChunk() }
    let data = Data(buffer.prefix(length))
    buffer.removeFirst(length)
    buffer = Data(buffer)
    return data
  }
  private func appendChunk() async throws {
    try Task.checkCancellation()
    let chunk = try await transport.receive()
    guard !chunk.isEmpty else { throw IMAPError.unavailable }
    guard chunk.count <= 65_536, buffer.count + chunk.count <= 2_100_000 else {
      throw IMAPError.limitExceeded
    }
    buffer.append(chunk)
  }
  private static func tokenize(_ data: Data) throws -> [IMAPToken] {
    let bytes = Array(data)
    var offset = 0
    var tokens: [IMAPToken] = []
    while offset < bytes.count {
      switch bytes[offset] {
        case 32: offset += 1
        case 40: tokens.append(.open); offset += 1
        case 41: tokens.append(.close); offset += 1
        case 34: tokens.append(.string(try quoted(bytes, offset: &offset)))
        default:
          let start = offset
          while offset < bytes.count, ![32, 40, 41].contains(bytes[offset]) {
            guard bytes[offset] > 32, bytes[offset] < 127, bytes[offset] != 34 else {
              throw IMAPError.malformedResponse
            }
            offset += 1
          }
          tokens.append(.atom(String(decoding: bytes[start..<offset], as: UTF8.self)))
      }
      guard tokens.count <= 4096 else { throw IMAPError.limitExceeded }
    }
    return tokens
  }
  private static func quoted(_ bytes: [UInt8], offset: inout Int) throws -> String {
    offset += 1
    var value: [UInt8] = []
    while offset < bytes.count {
      let byte = bytes[offset]
      offset += 1
      if byte == 34 {
        guard let string = String(bytes: value, encoding: .utf8) else {
          throw IMAPError.malformedResponse
        }
        return string
      }
      if byte == 92 {
        guard offset < bytes.count, [34, 92].contains(bytes[offset]) else {
          throw IMAPError.malformedResponse
        }
        value.append(bytes[offset]); offset += 1
      } else {
        guard byte >= 32, byte != 127 else { throw IMAPError.malformedResponse }
        value.append(byte)
      }
    }
    throw IMAPError.malformedResponse
  }
}

actor IMAPSession {
  let reader: IMAPResponseReader
  let transport: any IMAPTransport
  private var tag = 0
  init(transport: any IMAPTransport) {
    self.transport = transport; reader = .init(transport: transport)
  }

  func open(configuration: IMAPConfiguration, credential: IMAPCredential) async throws -> Set<
    String
  > {
    try await transport.connect()
    let greeting = try await reader.read()
    guard greeting.count >= 2, greeting[0].isAtom("*"), greeting[1].isAtom("OK") else {
      throw IMAPError.rejected
    }
    let capabilities = try await capabilities()
    switch credential {
      case .password(let password):
        guard !capabilities.contains("LOGINDISABLED") else { throw IMAPError.authenticationFailed }
        _ = try await command("LOGIN \(Self.quote(configuration.username)) \(Self.quote(password))")
      case .oauthBearer(let token):
        guard capabilities.contains("AUTH=OAUTHBEARER"), capabilities.contains("SASL-IR"),
          !token.isEmpty, token.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 })
        else {
          throw IMAPError.authenticationFailed
        }
        let user = configuration.username.replacingOccurrences(of: "=", with: "=3D")
          .replacingOccurrences(of: ",", with: "=2C")
        let response =
          "n,a=\(user),\u{1}host=\(configuration.host)\u{1}port=\(configuration.port)\u{1}auth=Bearer \(token)\u{1}\u{1}"
        _ = try await command(
          "AUTHENTICATE OAUTHBEARER \(Data(response.utf8).base64EncodedString())"
        )
    }
    return try await self.capabilities()
  }
  func capabilities() async throws -> Set<String> {
    let rows = try await command("CAPABILITY")
    return Set(
      rows.filter { $0.count > 1 && $0[1].isAtom("CAPABILITY") }
        .flatMap { $0.dropFirst(2).compactMap(\.text).map { $0.uppercased() } }
    )
  }
  func command(_ command: String) async throws -> [[IMAPToken]] {
    try Task.checkCancellation()
    guard !command.contains("\r"), !command.contains("\n"), command.utf8.count <= 60_000 else {
      throw IMAPError.invalidConfiguration
    }
    tag += 1
    let identifier = "S\(tag)"
    try await transport.send(Data("\(identifier) \(command)\r\n".utf8))
    var rows: [[IMAPToken]] = []
    var bytes = 0
    for _ in 0..<2048 {
      let row = try await reader.read()
      guard let first = row.first else { throw IMAPError.malformedResponse }
      if first.isAtom(identifier) {
        guard row.count >= 2, row[1].isAtom("OK") else { throw IMAPError.rejected }
        return rows + [row]
      }
      guard first.isAtom("*"), row.count > 1, !row[1].isAtom("BYE") else {
        throw IMAPError.rejected
      }
      bytes += row.reduce(0) { count, token in
        if case .literal(let data) = token {
          count + data.count
        } else {
          count + (token.text?.utf8.count ?? 1)
        }
      }
      guard bytes <= 4_200_000 else { throw IMAPError.limitExceeded }
      rows.append(row)
    }
    throw IMAPError.limitExceeded
  }
  static func quote(_ value: String) throws -> String {
    guard !value.isEmpty, value.utf8.count <= 8192,
      value.utf8.allSatisfy({ $0 >= 32 && $0 < 127 })
    else { throw IMAPError.invalidConfiguration }
    return "\""
      + value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

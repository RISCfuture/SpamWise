import Foundation
import NIOCore
import NIOEmbedded
import Testing
@testable import MailIntegration
import SpamWiseCore

/// A scripted IMAP conversation. Each exchange names the command it expects; the server answers with the client's own tag.
struct IMAPTranscript: Sendable {
  static let defaultCapabilities = "IMAP4rev1 MOVE SPECIAL-USE"
  var greeting = "* OK ready"
  /// Server output is delivered in chunks of at most this many bytes.
  var fragment = 65_536
  private(set) var exchanges: [Exchange] = []

  /// Greeting, capability discovery and LOGIN.
  static func authenticated(capabilities: String = defaultCapabilities, fragment: Int = 65_536)
    -> Self
  {
    var transcript = Self()
    transcript.fragment = fragment
    return
      transcript
      .then("CAPABILITY", "* CAPABILITY \(capabilities)")
      .then("LOGIN")
      .then("CAPABILITY", "* CAPABILITY \(capabilities)")
  }

  /// Expects a command starting with `command` and answers with `responses` and a tagged completion.
  func then(_ command: String, _ responses: String..., completion: String = "OK done") -> Self {
    var copy = self
    copy.exchanges.append(.init(command: command, responses: responses, completion: completion))
    return copy
  }

  /// Expects a command and never answers it.
  func stalls(at command: String) -> Self {
    var copy = self
    copy.exchanges.append(.init(command: command, responses: [], completion: nil))
    return copy
  }

  /// Special-use discovery listing the given Junk and Sent mailboxes.
  func roles(junk: String = "Junk Mail", sent: String = "Sent") -> Self {
    then("LIST", "* LIST (\\Junk) \"/\" \"\(junk)\"", "* LIST (\\Sent) \"/\" \"\(sent)\"")
  }

  func examine(_ mailbox: String = "INBOX", validity: Int, exists: Int = 1, uidNext: Int? = nil)
    -> Self
  {
    var responses = ["* OK [UIDVALIDITY \(validity)] ok", "* \(exists) EXISTS"]
    if let uidNext { responses.append("* OK [UIDNEXT \(uidNext)] predicted") }
    var copy = self
    copy.exchanges.append(
      .init(command: "EXAMINE \"\(mailbox)\"", responses: responses, completion: "OK done")
    )
    return copy
  }

  func select(_ mailbox: String = "INBOX", validity: Int, permanentFlags: String? = nil) -> Self {
    then(
      "SELECT \"\(mailbox)\"",
      "* OK [UIDVALIDITY \(validity)] ok",
      "* 1 EXISTS",
      "* OK [PERMANENTFLAGS (\(permanentFlags ?? "\\Flagged \\*"))] ok",
      completion: "OK [READ-WRITE] selected"
    )
  }

  /// A UID FETCH answered with the complete message body.
  func body(_ raw: String, uid: Int, sequence: Int = 1) -> Self {
    then(
      "UID FETCH \(uid) ",
      "* \(sequence) FETCH (UID \(uid) RFC822.SIZE \(raw.utf8.count) BODY[] {\(raw.utf8.count)}\r\n\(raw))"
    )
  }

  /// Sequence-range metadata for each row.
  func metadata(_ rows: [Row]) -> Self {
    var copy = self
    copy.exchanges.append(
      .init(
        command: "FETCH ",
        responses: rows.map { "* \($0.sequence) FETCH (UID \($0.uid) RFC822.SIZE \($0.size))" },
        completion: "OK done"
      )
    )
    return copy
  }

  /// A UID MOVE, optionally reporting the destination's COPYUID mapping.
  func move(uid: Int, to mailbox: String, copyUID: (validity: Int, uid: Int)?) -> Self {
    then(
      "UID MOVE \(uid) \"\(mailbox)\"",
      completion: copyUID.map { "OK [COPYUID \($0.validity) \(uid) \($0.uid)] moved" } ?? "OK moved"
    )
  }

  struct Exchange: Sendable {
    var command: String
    var responses: [String]
    var completion: String?
  }

  /// One message's sequence number, UID and size in a metadata FETCH.
  struct Row: Sendable {
    var sequence: Int
    var uid: Int
    var size: Int

    init(_ sequence: Int, uid: Int, size: Int) {
      self.sequence = sequence; self.uid = uid; self.size = size
    }
  }
}

/// Serves one transcript per connection over in-memory NIO channels and records every command.
actor IMAPTestServer {
  private var pending: [IMAPTranscript]
  /// Commands received, without tags, in order.
  private(set) var commands: [String] = []
  private(set) var connections = 0

  init(_ transcripts: IMAPTranscript...) { pending = transcripts }

  /// Opens the next scripted connection through the production response pipeline.
  func connect() async throws -> IMAPConnection {
    guard !pending.isEmpty else { throw IMAPError.unavailable }
    let transcript = pending.removeFirst()
    connections += 1
    let channel = NIOAsyncTestingChannel()
    let connection = try await channel.testingEventLoop.executeInContext {
      try IMAPPipeline.configure(channel)
    }
    try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 993))
    Task { await serve(transcript, on: channel) }
    return connection
  }

  func adapter(
    _ configuration: IMAPConfiguration = .test,
    validations: Store? = nil,
    password: String = "secret"
  ) -> IMAPAdapter {
    IMAPAdapter(
      configuration: configuration,
      credentials: { .password(password) },
      validations: validations,
      connector: { _ in try await self.connect() }
    )
  }

  private func serve(_ transcript: IMAPTranscript, on channel: NIOAsyncTestingChannel) async {
    var input = CommandInput()
    do {
      try await send(transcript.greeting + "\r\n", fragment: transcript.fragment, on: channel)
      for exchange in transcript.exchanges {
        let (tag, command) = try await input.next(from: channel)
        commands.append(command)
        guard command.hasPrefix(exchange.command) else {
          Issue.record("Expected “\(exchange.command)”, received “\(command)”")
          return
        }
        guard let completion = exchange.completion else { return }
        let reply = exchange.responses.map { $0 + "\r\n" }.joined() + "\(tag) \(completion)\r\n"
        try await send(reply, fragment: transcript.fragment, on: channel)
      }
    } catch {}
  }

  private func send(_ text: String, fragment: Int, on channel: NIOAsyncTestingChannel) async throws
  {
    let bytes = Array(text.utf8)
    for start in stride(from: 0, to: bytes.count, by: fragment) {
      try await channel.writeInbound(
        ByteBuffer(bytes: bytes[start..<min(start + fragment, bytes.count)])
      )
    }
  }
}

/// Reassembles client commands, granting continuation to synchronizing literals.
private struct CommandInput {
  private var buffered: [UInt8] = []

  private static func synchronizingLiteralLength(_ line: [UInt8]) -> Int? {
    guard let text = String(bytes: line, encoding: .utf8), text.hasSuffix("}"),
      let open = text.lastIndex(of: "{")
    else { return nil }
    return Int(text[text.index(after: open)..<text.index(before: text.endIndex)])
  }

  mutating func next(from channel: NIOAsyncTestingChannel) async throws -> (String, String) {
    var command: [UInt8] = []
    while true {
      let line = try await nextLine(from: channel)
      command += line
      guard let literal = Self.synchronizingLiteralLength(line) else { break }
      try await channel.writeInbound(ByteBuffer(string: "+ go ahead\r\n"))
      command += try await bytes(literal, from: channel)
    }
    let text = try #require(String(bytes: command, encoding: .utf8))
    let parts = text.split(separator: " ", maxSplits: 1)
    return (String(parts.first ?? ""), parts.count > 1 ? String(parts[1]) : "")
  }

  private mutating func nextLine(from channel: NIOAsyncTestingChannel) async throws -> [UInt8] {
    while true {
      if let end = buffered.indices.first(where: {
        buffered[$0] == 13 && $0 + 1 < buffered.count && buffered[$0 + 1] == 10
      }) {
        let line = Array(buffered[..<end])
        buffered.removeFirst(end + 2)
        return line
      }
      try await receive(from: channel)
    }
  }

  private mutating func bytes(_ count: Int, from channel: NIOAsyncTestingChannel) async throws
    -> [UInt8]
  {
    while buffered.count < count { try await receive(from: channel) }
    defer { buffered.removeFirst(count) }
    return Array(buffered.prefix(count))
  }

  private mutating func receive(from channel: NIOAsyncTestingChannel) async throws {
    let buffer = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
    buffered += buffer.readableBytesView
  }
}

extension IMAPConfiguration {
  static let test = IMAPConfiguration(
    id: "account",
    host: "imap.example.com",
    username: "user",
    allowsActions: true
  )
}

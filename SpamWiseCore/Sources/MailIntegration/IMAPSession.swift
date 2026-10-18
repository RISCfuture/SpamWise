import Foundation
import NIOCore
import NIOIMAP

/// One authenticated IMAP connection that issues tagged commands strictly one at a time.
///
/// Sessions are confined to the adapter actor that opened them.
final class IMAPSession {
  private static let maximumResponsesPerCommand = 2048
  private static let maximumCommandResponseBytes = 4_200_000
  private static let reuseWindow = Duration.seconds(10)
  private static let oauthBearer = AuthenticationMechanism("OAUTHBEARER")
  /// Capabilities advertised after authentication, uppercased.
  private(set) var capabilities: Set<String> = []
  private let connection: IMAPConnection
  private var responses: AsyncThrowingStream<Response, any Error>.AsyncIterator
  private let opened = ContinuousClock.now
  private var tag = 0
  private var failed = false

  /// True while the connection is healthy and young enough to finish another operation before the cutoff.
  var isReusable: Bool {
    !failed && connection.channel.isActive && ContinuousClock.now - opened < Self.reuseWindow
  }

  init(connection: IMAPConnection) {
    self.connection = connection
    responses = connection.responses.makeAsyncIterator()
  }

  /// Closes the connection without issuing a mailbox command.
  func close() {
    failed = true
    connection.channel.close(promise: nil)
  }

  /// Reads the greeting, authenticates with the configured mechanism and records post-login capabilities.
  func open(configuration: IMAPConfiguration, credential: IMAPCredential) async throws {
    guard case .untagged(.conditionalState(.ok)) = try await nextResponse() else {
      throw IMAPError.rejected
    }
    let advertised = try await refreshCapabilities()
    do {
      switch credential {
        case .password(let password):
          try await login(configuration: configuration, password: password, advertised: advertised)
        case .oauthBearer(let token):
          try await authenticate(configuration: configuration, token: token, advertised: advertised)
      }
    } catch IMAPError.rejected {
      throw IMAPError.authenticationFailed
    }
    _ = try await refreshCapabilities()
  }

  /// Sends one tagged command and collects its bounded untagged responses until the matching completion.
  func command(_ command: Command) async throws -> IMAPReply {
    do {
      return try await exchange(command)
    } catch {
      failed = true
      throw error
    }
  }
}

extension IMAPSession {
  private func refreshCapabilities() async throws -> Set<String> {
    let reply = try await command(.capability)
    capabilities = Set(
      reply.untagged.flatMap { payload -> [Capability] in
        if case .capabilityData(let values) = payload { values } else { [] }
      }.map { String($0.name.uppercased()) + ($0.value.map { "=" + $0.uppercased() } ?? "") }
    )
    return capabilities
  }

  private func login(configuration: IMAPConfiguration, password: String, advertised: Set<String>)
    async throws
  {
    guard !advertised.contains("LOGINDISABLED") else { throw IMAPError.authenticationFailed }
    try IMAPWireText.validate(password)
    _ = try await command(.login(username: configuration.username, password: password))
  }

  private func authenticate(
    configuration: IMAPConfiguration,
    token: String,
    advertised: Set<String>
  ) async throws {
    guard advertised.contains("AUTH=OAUTHBEARER"), advertised.contains("SASL-IR"), !token.isEmpty,
      token.utf8.allSatisfy({ (33...126).contains($0) })
    else { throw IMAPError.authenticationFailed }
    let user = configuration.username.replacingOccurrences(of: "=", with: "=3D")
      .replacingOccurrences(of: ",", with: "=2C")
    let response =
      "n,a=\(user),\u{1}host=\(configuration.host)\u{1}port=\(configuration.port)\u{1}auth=Bearer \(token)\u{1}\u{1}"
    _ = try await command(
      .authenticate(
        mechanism: Self.oauthBearer,
        initialResponse: InitialResponse(ByteBuffer(string: response))
      )
    )
  }

  private func exchange(_ command: Command) async throws -> IMAPReply {
    try Task.checkCancellation()
    tag += 1
    let tag = "S\(tag)"
    do {
      try await connection.channel.writeAndFlush(
        IMAPClientHandler.Message.part(.tagged(TaggedCommand(tag: tag, command: command)))
      )
    } catch {
      throw IMAPError.unavailable
    }
    var reply = IMAPReply.Builder(
      maximumResponses: Self.maximumResponsesPerCommand,
      maximumBytes: Self.maximumCommandResponseBytes
    )
    while true {
      switch try await nextResponse() {
        case .tagged(let completion):
          guard completion.tag == tag else { throw IMAPError.malformedResponse }
          guard case .ok(let text) = completion.state else { throw IMAPError.rejected }
          return try reply.finish(completion: text)
        case .untagged(.conditionalState(.bye)), .fatal: throw IMAPError.rejected
        case .untagged(let payload): try reply.append(payload)
        case .fetch(let part): try reply.append(part)
        case .authenticationChallenge: try await declineChallenge()
        case .idleStarted: throw IMAPError.malformedResponse
      }
    }
  }

  /// Answers a SASL error challenge with the empty client response the mechanism requires.
  private func declineChallenge() async throws {
    do {
      try await connection.channel.writeAndFlush(
        IMAPClientHandler.Message.part(.continuationResponse(ByteBuffer(bytes: [1])))
      )
    } catch {
      throw IMAPError.unavailable
    }
  }

  private func nextResponse() async throws -> Response {
    do {
      if let response = try await responses.next(isolation: #isolation) { return response }
    } catch {
      try Task.checkCancellation()
      throw IMAPError(connectionFailure: error)
    }
    try Task.checkCancellation()
    throw IMAPError.unavailable
  }
}

/// Validates text the client sends as an IMAP string: bounded, non-empty printable ASCII.
enum IMAPWireText {
  private static let maximumBytes = 8192

  static func validate(_ value: String) throws {
    guard !value.isEmpty, value.utf8.count <= maximumBytes,
      value.utf8.allSatisfy({ (32..<127).contains($0) })
    else { throw IMAPError.invalidConfiguration }
  }
}

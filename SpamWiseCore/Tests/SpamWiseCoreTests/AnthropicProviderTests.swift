import Foundation
import Network
import Synchronization
import Testing
import SpamWiseCore
@testable import Classifier

@Test(arguments: [
  (503, "Service Unavailable", ClassificationError.network),
  (
    403, #"{"type":"error","error":{"type":"permission_error","message":"Fixture"}}"#,
    ClassificationError.missingCredential
  )
])
func `maps Anthropic server and permission failures to retryable and credential errors`(
  status: Int,
  body: String,
  expected: ClassificationError
) async throws {
  let server = try await LoopbackHTTPServer(status: status, body: body)
  defer { server.stop() }
  let classifier = ClaudeClassifier(
    model: .claudeHaiku,
    key: { "fixture" },
    baseURL: server.baseURL
  )
  await #expect(throws: expected) { try await classifier.classify(providerInput()) }
}

/// Answers every loopback connection with one fixed HTTP response.
private final class LoopbackHTTPServer: Sendable {
  private let listener: NWListener
  let baseURL: URL

  init(status: Int, body: String) async throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    let response = Data(
      """
      HTTP/1.1 \(status) Fixture\r\nContent-Type: application/json\r\nContent-Length: \
      \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)
      """.utf8
    )
    listener.newConnectionHandler = { connection in
      connection.start(queue: .global())
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
        connection.send(
          content: response,
          completion: .contentProcessed { _ in connection.cancel() }
        )
      }
    }
    try await Self.start(listener)
    self.listener = listener
    let port = try #require(listener.port)
    baseURL = try #require(URL(string: "http://127.0.0.1:\(port.rawValue)"))
  }

  private static func start(_ listener: NWListener) async throws {
    let pending = PendingStart()
    try await withCheckedThrowingContinuation { continuation in
      pending.continuation.withLock { $0 = continuation }
      listener.stateUpdateHandler = { state in
        switch state {
          case .ready: pending.continuation.withLock { $0.take() }?.resume()
          case .failed(let error):
            pending.continuation.withLock { $0.take() }?.resume(throwing: error)
          default: break
        }
      }
      listener.start(queue: .global())
    }
  }

  func stop() { listener.cancel() }

  private final class PendingStart: Sendable {
    let continuation = Mutex<CheckedContinuation<Void, any Error>?>(nil)
  }
}

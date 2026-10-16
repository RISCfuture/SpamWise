public import Foundation
import Network
import Dispatch
import Synchronization

/// Failures while configuring or communicating with an IMAP server.
public protocol IMAPOperationError: Error {}

/// Failures from the bounded IMAP wire protocol; server text and credentials are never included.
public enum IMAPError: String, IMAPOperationError, LocalizedError, Sendable {
  case invalidConfiguration, unavailable, authenticationFailed, malformedResponse, limitExceeded
  case unsupported, rejected, deadlineExceeded
  /// A non-sensitive category suitable for presentation.
  public var errorDescription: String? {
    String(localized: "Couldn’t complete the IMAP operation.")
  }
  /// The connection or protocol failure, without server text or credentials.
  public var failureReason: String? {
    switch self {
      case .invalidConfiguration: String(localized: "The IMAP configuration is invalid.")
      case .unavailable: String(localized: "The IMAP connection is unavailable.")
      case .authenticationFailed: String(localized: "IMAP authentication failed.")
      case .malformedResponse: String(localized: "The IMAP server returned an invalid response.")
      case .limitExceeded:
        String(localized: "The IMAP response exceeds the supported resource limits.")
      case .unsupported: String(localized: "The IMAP server does not support this operation.")
      case .rejected: String(localized: "The IMAP server rejected the operation.")
      case .deadlineExceeded: String(localized: "The IMAP operation timed out.")
    }
  }
}

/// A connected, encrypted byte stream. Implementations must cancel pending I/O when closed.
public protocol IMAPTransport: Sendable {
  /// Connects to the configured server using verified TLS.
  func connect() async throws
  /// Writes bounded protocol bytes without logging them.
  func send(_ data: Data) async throws
  /// Receives at most 64 KiB; empty data denotes end of stream.
  func receive() async throws -> Data
  /// Cancels outstanding operations and releases the connection.
  func close() async
}

/// System TLS transport with certificate and hostname verification and a 30-second session lifetime.
public actor IMAPTLSTransport: IMAPTransport {
  private static let maximumChunkBytes = 65_536
  private static let sessionLifetimeSec: TimeInterval = 30
  private let connection: NWConnection
  private let queue = DispatchQueue(label: "codes.tim.SpamWise.imap")
  /// Creates an implicit TLS connection; plaintext and STARTTLS are not supported.
  public init(configuration: IMAPConfiguration) throws {
    try configuration.validate()
    guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
      throw IMAPError.invalidConfiguration
    }
    connection = NWConnection(host: .init(configuration.host), port: port, using: .tls)
  }
  /// Establishes TLS, enforcing a deadline for the entire session.
  public func connect() async throws {
    let connection = connection
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      let gate = IMAPConnectionGate()
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        connection.stateUpdateHandler = { state in
          switch state {
            case .ready: gate.finish(continuation, error: nil)
            case .failed, .cancelled: gate.finish(continuation, error: IMAPError.unavailable)
            default: break
          }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.sessionLifetimeSec) { connection.cancel() }
      }
    } onCancel: {
      connection.cancel()
    }
  }
  /// Writes a command over TLS.
  public func send(_ data: Data) async throws {
    guard data.count <= Self.maximumChunkBytes else { throw IMAPError.limitExceeded }
    let connection = connection
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        connection.send(
          content: data,
          completion: .contentProcessed { error in
            if error != nil {
              continuation.resume(throwing: IMAPError.unavailable)
            } else {
              continuation.resume()
            }
          }
        )
      }
    } onCancel: {
      connection.cancel()
    }
  }
  /// Receives a bounded chunk, cancelling the connection when its task is cancelled.
  public func receive() async throws -> Data {
    let connection = connection
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumChunkBytes) {
          data,
          _,
          _,
          error in
          if error != nil {
            continuation.resume(throwing: IMAPError.unavailable)
          } else {
            continuation.resume(returning: data ?? Data())
          }
        }
      }
    } onCancel: {
      connection.cancel()
    }
  }
  /// Closes the connection without issuing a mailbox command.
  public func close() async { connection.cancel() }
}

private final class IMAPConnectionGate: Sendable {
  private let completed = Mutex(false)
  func finish(_ continuation: CheckedContinuation<Void, any Error>, error: IMAPError?) {
    let shouldResume = completed.withLock { value in
      guard !value else { return false }
      value = true
      return true
    }
    guard shouldResume else { return }
    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
  }
}

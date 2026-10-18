import ArgumentParser
import Darwin
import Dispatch
import Foundation
import MailIntegration
import SpamWiseCore

/// Command-line arguments that cannot be used together or with this configuration.
enum DaemonUsageError: Error, LocalizedError, Equatable {
  case missingConfiguration
  case onceWithPolling
  case pollInterval(ClosedRange<Int>)
  case pageLimit(ClosedRange<Int>)
  case modelRequiresStatePath
  case invalidProbeUID

  var errorDescription: String? {
    switch self {
      case .missingConfiguration: "--config needs a configuration file path."
      case .onceWithPolling: "--once cannot be combined with --poll-seconds."
      case .pollInterval(let range):
        "--poll-seconds must be from \(range.lowerBound) to \(range.upperBound)."
      case .pageLimit(let range): "--limit must be from \(range.lowerBound) to \(range.upperBound)."
      case .modelRequiresStatePath:
        "--model changes the store's model; set statePath in the configuration so the app's model stays unchanged."
      case .invalidProbeUID: "The probe UID must be a positive number."
    }
  }
}

/// How one failed operation is reported and whether polling can continue after it.
struct DaemonFailure {
  let error: any Error

  /// A short, non-sensitive category for logs.
  var category: String {
    switch error {
      case let error as IMAPError:
        switch error {
          case .authenticationFailed: "authentication"
          case .invalidConfiguration: "configuration"
          case .unavailable, .deadlineExceeded: "network"
          case .malformedResponse, .limitExceeded, .rejected, .unsupported: "server"
        }
      case is IntegrationError, is ActionNotAttempted: "mail"
      case is ClassificationError: "classification"
      case is DaemonUsageError, is DecodingError: "configuration"
      case is StoreError: "storage"
      default: "other"
    }
  }

  /// Whether the failure cannot clear without changing the configuration or validation.
  var isConfiguration: Bool {
    error is DaemonUsageError || error is DecodingError
      || (error as? IMAPError) == .invalidConfiguration
      || (error as? IntegrationError) == .accountUnverified
  }

  /// Whether the server rejected the credential.
  var isAuthentication: Bool { (error as? IMAPError) == .authenticationFailed }

  /// The localized description and reason, which carry no server text or secrets.
  var message: String {
    let localized = error as? any LocalizedError
    return [localized?.errorDescription ?? error.localizedDescription, localized?.failureReason]
      .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// Writes the category and message to standard error.
  func report(_ context: String) {
    FileHandle.standardError.write(Data("\(context) (\(category)): \(message)\n".utf8))
  }
}

/// Runs `operation`, cancelling it on SIGINT or SIGTERM; failures exit with status 1.
func runCancellable(_ operation: @escaping @Sendable () async throws -> Void) async throws {
  let task = Task { try await operation() }
  let signals = [SIGINT, SIGTERM].map { number in
    _ = signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler { task.cancel() }
    source.resume()
    return source
  }
  defer { for source in signals { source.cancel() } }
  do {
    try await task.value
  } catch is CancellationError {
    print("Stopped.")
  } catch {
    DaemonFailure(error: error).report(
      "Headless operation failed; uncertain actions are not retried"
    )
    throw ExitCode.failure
  }
}

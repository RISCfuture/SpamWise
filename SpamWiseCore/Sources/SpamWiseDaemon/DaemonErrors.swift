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
      case .missingConfiguration:
        String(localized: "--config needs a configuration file path.", bundle: .module)
      case .onceWithPolling:
        String(localized: "--once cannot be combined with --poll-seconds.", bundle: .module)
      case .pollInterval(let range):
        String(
          localized:
            "--poll-seconds must be from \(range.lowerBound, format: .number.grouping(.never)) to \(range.upperBound, format: .number.grouping(.never)).",
          bundle: .module
        )
      case .pageLimit(let range):
        String(
          localized:
            "--limit must be from \(range.lowerBound, format: .number.grouping(.never)) to \(range.upperBound, format: .number.grouping(.never)).",
          bundle: .module
        )
      case .modelRequiresStatePath:
        String(
          localized:
            "--model changes the store’s model; set statePath in the configuration so the app’s model stays unchanged.",
          bundle: .module
        )
      case .invalidProbeUID:
        String(localized: "The probe UID must be a positive number.", bundle: .module)
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

  /// The localized description and reason, then what to do next, all without server text or secrets.
  var message: String {
    let localized = error as? any LocalizedError
    return [
      localized?.errorDescription ?? error.localizedDescription, localized?.failureReason,
      suggestion
    ]
    .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /**
   What to do next at the command line.

   The errors' own suggestions are written for the app and name its Settings window, while the
   daemon reads its account and credentials from the configuration file.
   */
  var suggestion: String? {
    switch error {
      case let error as IMAPError: Self.suggestion(for: error)
      case IntegrationError.accountUnverified:
        String(
          localized: "Run spamwise-daemon validate with this configuration first.",
          bundle: .module
        )
      case is DecodingError:
        String(
          localized: "Correct the configuration file, then run the command again.",
          bundle: .module
        )
      case StoreError.missingAppGroup:
        String(
          localized: "Set statePath in the configuration file to use a store of the daemon’s own.",
          bundle: .module
        )
      case StoreError.lockUnavailable:
        String(localized: "Run the command again in a moment.", bundle: .module)
      default: nil
    }
  }

  private static func suggestion(for error: IMAPError) -> String? {
    switch error {
      case .authenticationFailed:
        String(
          localized: "Check the credential that the configuration file refers to.",
          bundle: .module
        )
      case .invalidConfiguration:
        String(localized: "Correct the account in the configuration file.", bundle: .module)
      case .unavailable, .deadlineExceeded:
        String(
          localized:
            "Check the server address in the configuration file and the network connection.",
          bundle: .module
        )
      case .malformedResponse, .limitExceeded, .rejected, .unsupported: nil
    }
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
    print(String(localized: "Stopped.", bundle: .module))
  } catch {
    DaemonFailure(error: error).report(
      String(
        localized: "Headless operation failed; uncertain actions are not retried",
        bundle: .module
      )
    )
    throw ExitCode.failure
  }
}

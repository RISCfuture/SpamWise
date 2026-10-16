import Foundation
import OSLog
import SpamWiseCore

/// Records configuration hints for developers in the unified log, never in the interface.
nonisolated enum DeveloperDiagnostics {
  private static let logger = Logger(subsystem: "codes.tim.SpamWise", category: "Diagnostics")

  /// Logs the signing or entitlement hint that `error` suggests, if any.
  static func record(_ error: any Error) {
    guard case .status(let status) = error as? KeychainError else { return }
    logger.error(
      "Keychain status \(status, privacy: .public); check the shared Keychain access-group entitlement."
    )
  }

  /// Logs why shared storage didn't open, with only the error's domain and code.
  static func recordStorageFailure(_ error: any Error) {
    let error = error as NSError
    logger.fault(
      "Shared storage didn’t open (\(error.domain, privacy: .public) \(error.code, privacy: .public)); check signing and App Group access."
    )
  }
}

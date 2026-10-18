import Foundation
import SpamWiseCore

extension AppModel {
  nonisolated static func describe(_ error: any Error) -> String {
    if error is CancellationError {
      return String(localized: "Cancelled — no further actions requested.")
    }
    if let localizedError = error as? any LocalizedError {
      var details = [
        localizedError.errorDescription, localizedError.failureReason,
        localizedError.recoverySuggestion
      ].compactMap { $0 }.filter { !$0.isEmpty }
      if error as? IntegrationError == .permissionDenied {
        details.append(
          String(
            localized:
              "Automation permission denied. Allow SpamWise in System Settings → Privacy & Security → Automation."
          )
        )
      } else if case .status = error as? KeychainError {
        details.append(
          String(
            localized: "Keychain unavailable. Check the signed app’s shared Keychain entitlement."
          )
        )
      }
      if !details.isEmpty { return details.joined(separator: " ") }
    }
    return String(
      localized: "Operation unavailable. Mail stays unchanged; check Help for troubleshooting."
    )
  }

}

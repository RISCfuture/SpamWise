import Foundation

/// Failures while checking a provider key before saving it.
protocol KeyVerificationFailure: Error {}

/// Why a provider key wasn’t checked; nothing was sent and Keychain is unchanged.
nonisolated enum KeyVerificationError: KeyVerificationFailure, LocalizedError, Equatable {
  /// Keep filtering on this Mac is on, so no request may reach a provider.
  case localOnly

  var errorDescription: String? { String(localized: "The key wasn’t verified.") }
  var failureReason: String? {
    String(localized: "Keep filtering on this Mac is on, so SpamWise sends nothing to providers.")
  }
  var recoverySuggestion: String? {
    String(localized: "Turn off Keep filtering on this Mac in Provider settings, then try again.")
  }
}

import Foundation
import SpamWiseCore
import MailIntegration

/// The app's saved IMAP connection; its credential lives in Keychain.
struct IMAPAppConnection: Codable, Sendable {
  static let storeKey = "imap-app-connection-v1"
  var account: IMAPConfiguration
  var oauthBearer: Bool
  var credentialService: String { "codes.tim.SpamWise.imap." + stableHash(Data(account.id.utf8)) }

  /// The saved connection, or nil when none is saved; a damaged record throws its decoding error.
  static func saved(in store: Store) async throws -> Self? {
    try await store.read(storeKey, default: Optional<Self>.none)
  }
}

/// Failures while setting up the app's separate IMAP connection.
enum IMAPSetupError: IMAPOperationError, LocalizedError {
  case noSavedConnection, invalidPort, credentialRequired

  var errorDescription: String? { String(localized: "Couldn’t set up the IMAP connection.") }
  var failureReason: String? {
    switch self {
      case .noSavedConnection: String(localized: "No IMAP connection is saved.")
      case .invalidPort: String(localized: "The TLS port must be a number from 1 to 65535.")
      case .credentialRequired:
        String(localized: "Enter the password or token for this server and username.")
    }
  }
  var recoverySuggestion: String? {
    self == .noSavedConnection ? String(localized: "Save the IMAP connection first.") : nil
  }
}

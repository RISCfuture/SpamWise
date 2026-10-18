import Foundation
import SpamWiseCore
import MailIntegration

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
  case storageUnavailable, noSavedConnection, invalidPort

  var errorDescription: String? { String(localized: "Couldn’t set up the IMAP connection.") }
  var failureReason: String? {
    switch self {
      case .storageUnavailable: String(localized: "Shared storage is unavailable.")
      case .noSavedConnection: String(localized: "No IMAP connection is saved.")
      case .invalidPort: String(localized: "The TLS port must be a number from 1 to 65535.")
    }
  }
  var recoverySuggestion: String? {
    self == .noSavedConnection ? String(localized: "Save the IMAP connection first.") : nil
  }
}

extension AppModel {
  /// An adapter for the saved connection; actions stay gated by the persisted account validation.
  func configuredIMAPAdapter() async throws -> IMAPAdapter {
    guard let store else { throw IMAPSetupError.storageUnavailable }
    guard let connection = try await IMAPAppConnection.saved(in: store) else {
      throw IMAPSetupError.noSavedConnection
    }
    var configuration = connection.account
    configuration.allowsActions = true
    return IMAPAdapter(
      configuration: configuration,
      credentials: {
        let value = try APIKeychain(service: connection.credentialService).read()
        return connection.oauthBearer ? .oauthBearer(value) : .password(value)
      },
      validations: store
    )
  }

  /// The integration that addresses `record`'s message: IMAP for IMAP identities, Apple Mail otherwise.
  func mailAdapter(for record: DecisionRecord) async throws -> any MailClientAdapter {
    record.identity.mailboxValidity == nil ? adapter : try await configuredIMAPAdapter()
  }
}

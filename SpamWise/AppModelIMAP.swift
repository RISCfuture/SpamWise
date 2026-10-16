import Foundation
import SpamWiseCore
import MailIntegration

struct IMAPAppConnection: Codable, Sendable {
  static let storeKey = "imap-app-connection-v1"
  var account: IMAPConfiguration
  var oauthBearer: Bool
  var credentialService: String { "codes.tim.SpamWise.imap." + stableHash(Data(account.id.utf8)) }

  static func load(from store: Store) async throws -> Self {
    guard let connection = try await store.read(storeKey, default: Optional<Self>.none) else {
      throw IMAPError.invalidConfiguration
    }
    return connection
  }
}

extension AppModel {
  func configuredIMAPCorrectionAdapter() async throws -> IMAPCorrectionAdapter {
    IMAPCorrectionAdapter(adapter: try await configuredIMAPAdapter(validateConnection: false))
  }
  func configuredIMAPAdapter(validateConnection: Bool = true) async throws -> IMAPAdapter {
    guard let store else { throw IMAPError.invalidConfiguration }
    let connection = try await IMAPAppConnection.load(from: store)
    var configuration = connection.account
    configuration.allowsActions = try await IMAPAccountValidation.isValidated(
      configuration,
      store: store
    )
    let adapter = IMAPAdapter(
      configuration: configuration,
      credentials: {
        let value = try APIKeychain(service: connection.credentialService).read()
        return connection.oauthBearer ? .oauthBearer(value) : .password(value)
      }
    )
    if validateConnection { _ = try await adapter.validateReadOnly() }
    return adapter
  }
}

nonisolated struct IMAPCorrectionAdapter: MailClientAdapter {
  let adapter: IMAPAdapter
  func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope? {
    try await adapter.lookup(identity)
  }
  func recentMessages(limit: Int) async throws -> [MailEnvelope] {
    try await adapter.recentMessages(limit: limit)
  }
  func importHistory() async throws -> [String: HistoryIndex] {
    try await adapter.importHistory()
  }
  func perform(_ action: MailAction, for identity: MessageIdentity) async throws -> ActionReceipt {
    _ = try await adapter.validateReadOnly()
    return try await adapter.perform(action, for: identity)
  }
}

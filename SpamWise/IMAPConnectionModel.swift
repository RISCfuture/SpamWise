import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// The draft and actions behind the app's separate IMAP connection.
@MainActor
@Observable
final class IMAPConnectionModel {
  /// The implicit-TLS IMAP port a new draft starts with.
  static let defaultPort = String(IMAPConfiguration.defaultPort)
  var host = ""
  var username = ""
  var port = IMAPConnectionModel.defaultPort
  var credential = ""
  var oauthBearer = false
  var accountID = IMAPConnectionModel.newAccountID()
  /// Whether a connection is saved, as of the latest load, save or removal.
  private(set) var hasSavedConnection = false
  /// Loading, saving and checking the connection.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private var hasLoaded = false

  /// The connection's account as people recognize it, such as “name@example.com on imap.example.com”.
  var accountName: String { String(localized: "\(username) on \(host)") }

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  private static func newAccountID() -> String { "imap:" + UUID().uuidString }

  @concurrent
  private static func deleteCredential(service: String) async throws {
    try APIKeychain(service: service).delete()
  }

  /// Fills the draft from the saved connection once, keeping later edits to the draft.
  func loadIfNeeded() {
    guard !hasLoaded else { return }
    hasLoaded = true
    operation.run(retryable: true) { [self] in
      guard let saved = try await IMAPAppConnection.saved(in: services.requireStore()) else {
        return nil
      }
      host = saved.account.host; username = saved.account.username
      port = String(saved.account.port); accountID = saved.account.id
      oauthBearer = saved.oauthBearer
      hasSavedConnection = true
      return nil
    }
  }

  /// Saves the draft and its credential, selecting IMAP with dry run on.
  func save() {
    guard let port = UInt16(port), port > 0 else {
      operation.run { throw IMAPSetupError.invalidPort }
      return
    }
    let secret = credential
    credential = ""
    operation.run { [self] in
      try await save(connection(port: port), secret: secret, store: services.requireStore())
      hasSavedConnection = true
      await shared.refresh()
      return String(
        localized:
          """
          Connection saved with dry run on. Check the connection so SpamWise can find its Junk \
          mailbox.
          """
      )
    }
  }

  /// Checks the saved connection read-only and records whether its mailboxes are validated.
  func check() {
    operation.run(retryable: true) { [self] in
      let store = try services.requireStore()
      guard let connection = try await IMAPAppConnection.saved(in: store) else {
        throw IMAPSetupError.noSavedConnection
      }
      let result = try await services.imapAdapter().validateReadOnly()
      let validated = try await IMAPAccountValidation.record(
        result,
        for: connection.account,
        store: store
      )
      await shared.refresh()
      return validated
        ? String(localized: "Connected. SpamWise found the Inbox and Junk mailboxes.")
        : String(
          localized:
            """
            Connected, but SpamWise can’t move mail on this server. It needs IMAP MOVE support and \
            exactly one Junk mailbox.
            """
        )
    }
  }

  /**
   Forgets the saved connection: removes its password from Keychain and its mailbox check, then
   returns to Apple Mail with dry run on. Mail on the server is unchanged.
   */
  func forget() {
    operation.run { [self] in
      let store = try services.requireStore()
      if let saved = try await IMAPAppConnection.saved(in: store) {
        try await Self.deleteCredential(service: saved.credentialService)
        try await IMAPAccountValidation.revoke(saved.account, scope: .app, store: store)
      }
      try await store.update(
        IMAPAppConnection.storeKey,
        default: Optional<IMAPAppConnection>.none
      ) { $0 = nil }
      try await StateRepository.editSettings(store) { settings in
        var advanced = settings.advancedOptions
        advanced.transport = .appleMail
        settings.advancedOptions = advanced
        settings.dryRun = true
      }
      clearDraft()
      await shared.refresh()
      return String(
        localized:
          "IMAP connection forgotten and its password removed. SpamWise now uses Apple Mail."
      )
    }
  }

  private func clearDraft() {
    host = ""; username = ""; port = Self.defaultPort; credential = ""; oauthBearer = false
    accountID = Self.newAccountID(); hasSavedConnection = false
  }

  private func connection(port: UInt16) -> IMAPAppConnection {
    IMAPAppConnection(
      account: .init(
        id: accountID,
        host: host.trimmingCharacters(in: .whitespacesAndNewlines),
        port: port,
        username: username.trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      oauthBearer: oauthBearer
    )
  }

  private func save(_ connection: IMAPAppConnection, secret: String, store: Store) async throws {
    try connection.account.validate()
    try saveCredential(secret, for: connection)
    let replaced = try await store.update(
      IMAPAppConnection.storeKey,
      default: Optional<IMAPAppConnection>.none
    ) { saved in
      defer { saved = connection }
      return saved
    }
    if let replaced, replaced.credentialService != connection.credentialService {
      try? APIKeychain(service: replaced.credentialService).delete()
    }
    try await StateRepository.editSettings(store) { settings in
      var advanced = settings.advancedOptions
      advanced.transport = .imap
      settings.advancedOptions = advanced
      settings.dryRun = true
    }
  }

  private func saveCredential(_ secret: String, for connection: IMAPAppConnection) throws {
    let keychain = APIKeychain(service: connection.credentialService)
    if secret.isEmpty {
      guard try keychain.exists() else { throw KeychainError.missing }
    } else {
      try keychain.save(secret, preserveWhitespace: true)
    }
  }
}

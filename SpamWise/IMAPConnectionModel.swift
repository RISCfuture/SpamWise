import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// The draft and actions behind the app's separate IMAP connection.
@MainActor @Observable final class IMAPConnectionModel {
  var host = ""
  var username = ""
  var port = "993"
  var credential = ""
  var oauthBearer = false
  var accountID = "imap:" + UUID().uuidString
  /// Loading, saving and checking the connection.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private var hasLoaded = false

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  /// Fills the draft from the saved connection once, keeping later edits to the draft.
  func loadIfNeeded() {
    guard !hasLoaded else { return }
    hasLoaded = true
    operation.run(retryable: true) { [self] in
      guard let saved = try await IMAPAppConnection.saved(in: services.requireStore()) else {
        return String(localized: "Configure a separate IMAP connection.")
      }
      host = saved.account.host; username = saved.account.username
      port = String(saved.account.port); accountID = saved.account.id
      oauthBearer = saved.oauthBearer
      return String(localized: "Saved IMAP connection loaded. Check it before use.")
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
      await shared.refresh()
      return String(
        localized:
          "Connection saved. Dry run is enabled; check the connection to validate its mailboxes."
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
        ? String(localized: "Read-only check passed. Inbox and Junk mailboxes are validated.")
        : String(
          localized:
            "Read-only check passed. This server lacks a supported MOVE capability or unique Junk mailbox."
        )
    }
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
      _ = try keychain.read()
    } else {
      try keychain.save(secret, preserveWhitespace: true)
    }
  }
}

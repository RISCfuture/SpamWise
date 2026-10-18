import Foundation
import Observation
import SpamWiseCore
import MailIntegration

@MainActor @Observable final class IMAPConnectionModel {
  private let model: AppModel
  var host = ""
  var username = ""
  var port = "993"
  var credential = ""
  var oauthBearer = false
  var accountID = "imap:" + UUID().uuidString
  var status = String(localized: "Configure a separate IMAP connection.")
  /// True while this or any other app operation is running; IMAP setup shares the app's busy gate.
  var busy: Bool { model.busy }

  init(model: AppModel) { self.model = model }
  func load() async {
    guard let store = model.store else { return }
    do {
      guard let saved = try await IMAPAppConnection.saved(in: store) else { return }
      host = saved.account.host; username = saved.account.username
      port = String(saved.account.port); accountID = saved.account.id
      oauthBearer = saved.oauthBearer
      status = String(localized: "Saved IMAP connection loaded. Check it before use.")
    } catch {
      status = AppModel.describe(error)
    }
  }
  func save() {
    guard let number = UInt16(port), number > 0 else { return report(IMAPSetupError.invalidPort) }
    let connection = connection(port: number)
    let secret = credential
    credential = ""
    perform { [self] in
      guard let store = model.store else { throw IMAPSetupError.storageUnavailable }
      try await save(connection, secret: secret, store: store)
      status = String(
        localized:
          "Connection saved. Dry run is enabled; check the connection to validate its mailboxes."
      )
    }
  }
  func check() {
    perform { [self] in
      guard let store = model.store else { throw IMAPSetupError.storageUnavailable }
      guard let connection = try await IMAPAppConnection.saved(in: store) else {
        throw IMAPSetupError.noSavedConnection
      }
      let result = try await model.configuredIMAPAdapter().validateReadOnly()
      let validated = try await IMAPAccountValidation.record(
        result,
        for: connection.account,
        store: store
      )
      status =
        validated
        ? String(localized: "Read-only check passed. Inbox and Junk mailboxes are validated.")
        : String(
          localized:
            "Read-only check passed. This server lacks a supported MOVE capability or unique Junk mailbox."
        )
    }
  }
}

extension IMAPConnectionModel {
  /// Runs through the app's busy-tracked operation gate and shows any failure's cause here.
  private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
    model.run { [self] in
      do {
        try await operation()
      } catch {
        status = AppModel.describe(error)
        throw error
      }
    }
  }

  private func report(_ error: IMAPSetupError) { status = AppModel.describe(error) }

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

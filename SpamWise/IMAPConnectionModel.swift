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
  var busy = false

  init(model: AppModel) { self.model = model }
  func load() async {
    guard let store = model.store,
      let saved = try? await IMAPAppConnection.load(from: store)
    else { return }
    host = saved.account.host; username = saved.account.username
    port = String(saved.account.port); accountID = saved.account.id; oauthBearer = saved.oauthBearer
    status = String(localized: "Saved IMAP connection loaded. Check it before use.")
  }
  func save() {
    guard let store = model.store, let number = UInt16(port), number > 0 else {
      status = String(localized: "Enter a valid TLS port."); return
    }
    let connection = connection(port: number)
    let secret = credential
    busy = true
    Task {
      defer { busy = false; credential = "" }
      do {
        try await save(connection, secret: secret, store: store)
        await model.refresh()
        status = String(
          localized:
            "Connection saved. Dry run is enabled; check the connection to validate its mailboxes."
        )
      } catch {
        status = String(
          localized: "Could not save the connection. Check the endpoint and Keychain access."
        )
      }
    }
  }
  func check() {
    guard let store = model.store else { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        let adapter = try await model.configuredIMAPAdapter(validateConnection: false)
        let result = try await adapter.validateReadOnly()
        let connection = try await IMAPAppConnection.load(from: store)
        let validated = try await IMAPAccountValidation.record(
          result,
          for: connection.account,
          store: store
        )
        await model.refresh()
        status =
          validated
          ? String(localized: "Read-only check passed. Inbox and Junk mailboxes are validated.")
          : String(
            localized:
              "Read-only check passed. This server lacks a supported MOVE capability or unique Junk mailbox."
          )
      } catch {
        status = String(
          localized:
            "IMAP check failed. Verify the saved endpoint, credentials and server capabilities."
        )
      }
    }
  }
}

extension IMAPConnectionModel {
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
    _ = try JSONDecoder().decode(
      IMAPConfiguration.self,
      from: JSONEncoder().encode(connection.account)
    )
    try saveCredential(secret, for: connection)
    try await store.update(
      IMAPAppConnection.storeKey,
      default: Optional<IMAPAppConnection>.none
    ) { $0 = connection }
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

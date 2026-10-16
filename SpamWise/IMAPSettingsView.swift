import SwiftUI
import SpamWiseCore
import MailIntegration

struct IMAPSettingsView: View {
  @Bindable var model: AppModel
  @State private var host = ""
  @State private var username = ""
  @State private var port = "993"
  @State private var credential = ""
  @State private var oauthBearer = false
  @State private var probeUID = ""
  @State private var accountID = "imap:" + UUID().uuidString
  @State private var status = String(localized: "Configure a separate IMAP connection.")
  @State private var busy = false

  var body: some View {
    Group {
      Section("Incoming transport") {
        Picker("Mail connection", selection: transportBinding) {
          Text("Apple Mail").tag(MailTransport.appleMail)
          Text("IMAP").tag(MailTransport.imap)
        }.accessibilityIdentifier("imap.transport")
      }
      if model.state.settings.advancedOptions.transport == .imap {
        Section("IMAP account") {
          TextField("Server hostname", text: $host).accessibilityIdentifier("imap.host")
          TextField("TLS port", text: $port).accessibilityIdentifier("imap.port")
          TextField("Username", text: $username).accessibilityIdentifier("imap.username")
          Toggle("Use OAuth bearer token", isOn: $oauthBearer).accessibilityIdentifier("imap.oauth")
          SecureField("Password or bearer token", text: $credential).accessibilityIdentifier(
            "imap.credential"
          )
          Text(
            "Credentials are stored only in Keychain. Leave the credential blank to keep the saved value."
          )
          .foregroundStyle(.secondary)
          Button("Save IMAP connection") { save() }.accessibilityIdentifier("imap.save")
          Button("Check read-only connection") { check() }.accessibilityIdentifier("imap.validate")
          Text(
            "Checking the connection reads mailbox roles and Inbox status. It does not enable mail actions."
          )
          .foregroundStyle(.secondary)
        }
        Section("Disposable message test") {
          Text(
            "Place a disposable [SpamWise Probe] message in Inbox. Enter its IMAP UID, not Apple Mail’s message number."
          )
          TextField("Inbox UID", text: $probeUID).accessibilityIdentifier("imap.probeUID")
          Button("Test Junk and restore Inbox") { probe() }.accessibilityIdentifier("imap.probe")
            .disabled(UInt32(probeUID).map { $0 > 0 } != true)
          Text(
            "The test moves to Junk and back. Verified restoration validates the account. Dry run stays unchanged."
          )
          .foregroundStyle(.secondary)
        }
        Text(status).accessibilityIdentifier("imap.status")
        if busy { ProgressView() }
      }
    }
    .disabled(busy || !model.storageReady)
    .task { await load() }
  }

  private var transportBinding: Binding<MailTransport> {
    Binding(
      get: { model.state.settings.advancedOptions.transport },
      set: { value in
        model.editSettings { settings in
          var advanced = settings.advancedOptions
          advanced.transport = value
          settings.advancedOptions = advanced
          settings.dryRun = true
          settings.route = .unverified
        }
      }
    )
  }

  private func load() async {
    guard let store = model.store,
      let saved = try? await store.read(
        IMAPAppConnection.storeKey,
        default: Optional<IMAPAppConnection>.none
      )
    else { return }
    host = saved.account.host; username = saved.account.username
    port = String(saved.account.port); accountID = saved.account.id; oauthBearer = saved.oauthBearer
    status = String(localized: "Saved IMAP connection loaded. Check it before use.")
  }
  private func save() {
    guard let store = model.store, let number = UInt16(port), number > 0 else {
      status = String(localized: "Enter a valid TLS port."); return
    }
    let connection = IMAPAppConnection(
      account: .init(
        id: accountID,
        host: host.trimmingCharacters(in: .whitespacesAndNewlines),
        port: number,
        username: username.trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      oauthBearer: oauthBearer
    )
    let secret = credential
    busy = true
    Task {
      defer { busy = false; credential = "" }
      do {
        _ = try JSONDecoder().decode(
          IMAPConfiguration.self,
          from: JSONEncoder().encode(connection.account)
        )
        if !secret.isEmpty {
          try APIKeychain(service: connection.credentialService).save(
            secret,
            preserveWhitespace: true
          )
        } else {
          _ = try APIKeychain(service: connection.credentialService).read()
        }
        try await store.update(
          IMAPAppConnection.storeKey,
          default: Optional<IMAPAppConnection>.none
        ) { $0 = connection }
        try await StateRepository.editSettings(store) { settings in
          var advanced = settings.advancedOptions; advanced.transport = .imap
          settings.advancedOptions = advanced
          settings.dryRun = true
        }
        await model.refresh()
        status = String(
          localized: "Connection saved. Dry run is enabled; validate the account before actions."
        )
      } catch {
        status = String(
          localized: "Could not save the connection. Check the endpoint and Keychain access."
        )
      }
    }
  }
  private func check() {
    busy = true
    Task {
      defer { busy = false }
      do {
        let adapter = try await model.configuredIMAPAdapter(validateConnection: false)
        let result = try await adapter.validateReadOnly()
        status =
          result.supportsMove && result.junkMailbox != nil
          ? String(
            localized:
              "Read-only check passed. Disposable-message validation is still required for actions."
          )
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
  private func probe() {
    guard let uid = UInt32(probeUID), uid > 0, let store = model.store else { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        guard
          let connection = try await store.read(
            IMAPAppConnection.storeKey,
            default: Optional<IMAPAppConnection>.none
          )
        else {
          throw IMAPError.invalidConfiguration
        }
        let adapter = try await model.configuredIMAPAdapter()
        _ = try await adapter.testDisposableMessage(uid: uid)
        try await IMAPAccountValidation.record(connection.account, store: store)
        await model.refresh()
        status = String(
          localized:
            "Probe restored to Inbox. Account validated; inspect the message before disabling dry run."
        )
      } catch {
        status = String(
          localized:
            "Probe failed or its outcome is uncertain. Inspect the message manually; no uncertain move is retried."
        )
      }
    }
  }
}

struct IMAPAppConnection: Codable, Sendable {
  static let storeKey = "imap-app-connection-v1"
  var account: IMAPConfiguration
  var oauthBearer: Bool
  var credentialService: String { "codes.tim.SpamWise.imap." + stableHash(Data(account.id.utf8)) }
}

extension AppModel {
  func configuredIMAPCorrectionAdapter() async throws -> IMAPCorrectionAdapter {
    IMAPCorrectionAdapter(adapter: try await configuredIMAPAdapter(validateConnection: false))
  }
  func configuredIMAPAdapter(validateConnection: Bool = true) async throws -> IMAPAdapter {
    guard let store,
      let connection = try await store.read(
        IMAPAppConnection.storeKey,
        default: Optional<IMAPAppConnection>.none
      )
    else {
      throw IMAPError.invalidConfiguration
    }
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

#Preview("Transport selection") { Form { IMAPSettingsView(model: PreviewHelper.model()) } }
#Preview("IMAP setup") {
  let model = PreviewHelper.model()
  model.state.settings.advancedOptions.transport = .imap
  return Form { IMAPSettingsView(model: model) }
}

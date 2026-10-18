import SwiftUI
import SpamWiseCore

struct IMAPSettingsView: View {
  @Bindable var model: AppModel
  @State private var connection: IMAPConnectionModel

  private var transportBinding: Binding<MailTransport> {
    Binding(
      get: { model.state.settings.advancedOptions.transport },
      set: { value in
        guard value != model.state.settings.advancedOptions.transport else { return }
        model.editSettings { settings in
          var advanced = settings.advancedOptions
          advanced.transport = value
          settings.advancedOptions = advanced
          settings.dryRun = true
          settings.validatedAccounts = []
        }
      }
    )
  }

  var body: some View {
    @Bindable var connection = connection
    Section("Mail connection") {
      Picker("Connection", selection: transportBinding) {
        Text("Apple Mail").tag(MailTransport.appleMail)
        Text("IMAP").tag(MailTransport.imap)
      }.accessibilityIdentifier("imap.transport")
        .disabled(connection.busy || !model.storageReady)
    }.task { await connection.load() }
    if model.state.settings.advancedOptions.transport == .imap {
      Section("IMAP account") {
        TextField("Server hostname", text: $connection.host).accessibilityIdentifier("imap.host")
        TextField("Username", text: $connection.username).accessibilityIdentifier("imap.username")
        SecureField("Password or bearer token", text: $connection.credential)
          .accessibilityIdentifier("imap.credential")
        Text("Leave the credential blank to keep the saved Keychain value.").foregroundStyle(
          .secondary
        )
        DisclosureGroup("Connection options") {
          TextField("TLS port", text: $connection.port).accessibilityIdentifier("imap.port")
          Toggle("Use OAuth bearer token", isOn: $connection.oauthBearer).accessibilityIdentifier(
            "imap.oauth"
          )
        }
        HStack {
          Button("Save IMAP connection") { connection.save() }.accessibilityIdentifier("imap.save")
          Button("Check read-only connection") { connection.check() }.accessibilityIdentifier(
            "imap.validate"
          )
        }
        Text(connection.status).textSelection(.enabled).accessibilityIdentifier("imap.status")
        if connection.busy { ProgressView() }
      }.disabled(connection.busy || !model.storageReady)
    }
  }

  init(model: AppModel) {
    self.model = model
    _connection = State(initialValue: IMAPConnectionModel(model: model))
  }
}

#Preview("Connection selection") {
  Form { IMAPSettingsView(model: PreviewHelper.model()) }.formStyle(.grouped)
}
#Preview("IMAP setup") {
  Form { IMAPSettingsView(model: PreviewHelper.model(transport: .imap)) }.formStyle(.grouped)
}

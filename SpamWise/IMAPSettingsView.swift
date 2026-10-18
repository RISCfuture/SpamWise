import SwiftUI
import SpamWiseCore

struct IMAPSettingsView: View {
  let settings: SettingsModel
  @Bindable var imap: IMAPConnectionModel
  let storageReady: Bool

  private var transportBinding: Binding<MailTransport> {
    Binding(
      get: { settings.settings.advancedOptions.transport },
      set: { value in
        guard value != settings.settings.advancedOptions.transport else { return }
        settings.editSettings { settings in
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
    Section("Mail connection") {
      Picker("Connection", selection: transportBinding) {
        Text("Apple Mail").tag(MailTransport.appleMail)
        Text("IMAP").tag(MailTransport.imap)
      }.accessibilityIdentifier("imap.transport")
        .disabled(imap.operation.isBusy || !storageReady)
    }.task { imap.loadIfNeeded() }
    if settings.settings.advancedOptions.transport == .imap {
      Section("IMAP account") {
        Group {
          TextField("Server hostname", text: $imap.host).accessibilityIdentifier("imap.host")
          TextField("Username", text: $imap.username).accessibilityIdentifier("imap.username")
          SecureField("Password or bearer token", text: $imap.credential)
            .accessibilityIdentifier("imap.credential")
          Text("Leave the credential blank to keep the saved Keychain value.").foregroundStyle(
            .secondary
          )
          DisclosureGroup("Connection options") {
            TextField("TLS port", text: $imap.port).accessibilityIdentifier("imap.port")
            Toggle("Use OAuth bearer token", isOn: $imap.oauthBearer).accessibilityIdentifier(
              "imap.oauth"
            )
          }
        }.disabled(imap.operation.isBusy)
        HStack {
          Button("Save IMAP connection") { imap.save() }.accessibilityIdentifier("imap.save")
          Button("Check read-only connection") { imap.check() }.accessibilityIdentifier(
            "imap.validate"
          )
          if imap.operation.isBusy { ProgressView().controlSize(.small) }
        }
        OperationStatusView(operation: imap.operation, identifier: "imap.status")
      }.disabled(!storageReady)
    }
  }
}

#Preview("Connection selection") {
  let model = PreviewHelper.model()
  Form { IMAPSettingsView(settings: model.settings, imap: model.imap, storageReady: true) }
    .formStyle(.grouped)
}
#Preview("IMAP setup") {
  let model = PreviewHelper.model(transport: .imap)
  Form { IMAPSettingsView(settings: model.settings, imap: model.imap, storageReady: true) }
    .formStyle(.grouped)
}

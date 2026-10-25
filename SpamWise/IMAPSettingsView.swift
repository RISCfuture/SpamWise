import SwiftUI
import SpamWiseCore

/// The mail connection SpamWise uses, and the IMAP account details when it is IMAP.
struct IMAPSettingsView: View {
  let settings: SettingsModel
  @Bindable var imap: IMAPConnectionModel
  let storageReady: Bool

  var body: some View {
    Section("Mail connection") {
      TransportPicker(settings: settings)
        .disabled(imap.operation.isBusy || !storageReady)
    }.task { imap.loadIfNeeded() }
    if settings.settings.advancedOptions.transport == .imap {
      Section("IMAP account") {
        IMAPAccountFields(imap: imap).disabled(imap.operation.isBusy)
        HStack {
          Button("Save Connection") { imap.save() }
            .disabled(!imap.canSave)
            .accessibilityIdentifier("imap.save")
          Button("Check Connection") { imap.check() }.accessibilityIdentifier("imap.validate")
          if imap.operation.isBusy {
            ProgressView { Text("Working…") }.labelsHidden().controlSize(.small)
          }
          Spacer()
          if imap.hasSavedConnection { ForgetIMAPConnectionButton(imap: imap) }
          HelpButton(page: "imap-connection")
        }
        OperationStatusView(operation: imap.operation, identifier: "imap.status")
      }.disabled(!storageReady)
    }
  }
}

/**
 Chooses Apple Mail or IMAP after confirming, because switching turns dry run on.

 Each connection keeps its own mailbox check, so returning to a checked connection needs no new
 check.
 */
private struct TransportPicker: View {
  let settings: SettingsModel
  @State private var pending: MailTransport?

  private var selection: Binding<MailTransport> {
    Binding(
      get: { settings.settings.advancedOptions.transport },
      set: { if $0 != settings.settings.advancedOptions.transport { pending = $0 } }
    )
  }
  private var confirming: Binding<Bool> {
    Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
  }

  var body: some View {
    Picker("Connection", selection: selection) {
      Text("Apple Mail").tag(MailTransport.appleMail)
      Text("IMAP").tag(MailTransport.imap)
    }
    .accessibilityIdentifier("imap.transport")
    .confirmationDialog(
      "Switch to \(pending?.localizedTitle ?? "")?",
      isPresented: confirming,
      titleVisibility: .visible,
      presenting: pending
    ) { transport in
      Button("Switch to \(transport.localizedTitle)") { select(transport) }
        .accessibilityIdentifier("imap.transport.confirm")
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text(
        """
        Dry run turns on, so mail stays unchanged until you turn it off in General. Automatic \
        checks use the new connection from now on.
        """
      )
    }
  }

  private func select(_ transport: MailTransport) {
    settings.editSettings { settings in
      var advanced = settings.advancedOptions
      advanced.transport = transport
      settings.advancedOptions = advanced
      settings.dryRun = true
    }
  }
}

private struct IMAPAccountFields: View {
  @Bindable var imap: IMAPConnectionModel

  var body: some View {
    TextField("Server", text: $imap.host, prompt: Text("imap.example.com"))
      .accessibilityIdentifier("imap.host")
    TextField("Username", text: $imap.username, prompt: Text("name@example.com"))
      .accessibilityIdentifier("imap.username")
    SecureField(
      "Password or token",
      text: $imap.credential,
      prompt: imap.canKeepSavedCredential ? Text("Saved in Keychain") : Text("Required")
    )
    .accessibilityIdentifier("imap.credential")
    if imap.canKeepSavedCredential {
      Text("Leave the password blank to keep the saved one.").foregroundStyle(.secondary)
    }
    DisclosureGroup("Connection options") {
      TextField("TLS port", text: $imap.port, prompt: Text(IMAPConnectionModel.defaultPort))
        .accessibilityIdentifier("imap.port")
      Toggle("Sign in with an OAuth token", isOn: $imap.oauthBearer)
        .accessibilityIdentifier("imap.oauth")
    }
  }
}

/// Forgets the saved IMAP connection and its password after confirming.
private struct ForgetIMAPConnectionButton: View {
  let imap: IMAPConnectionModel
  @State private var confirming = false

  var body: some View {
    Button("Forget Connection…", role: .destructive) { confirming = true }
      .accessibilityIdentifier("imap.forget")
      .confirmationDialog(
        "Forget this IMAP connection?",
        isPresented: $confirming,
        titleVisibility: .visible
      ) {
        Button("Forget Connection", role: .destructive) { imap.forget() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          """
          SpamWise removes the password from Keychain and switches to Apple Mail with dry run on. \
          Mail on the server stays as it is.
          """
        )
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

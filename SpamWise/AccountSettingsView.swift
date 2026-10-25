import SwiftUI
import SpamWiseCore

/// The Accounts tab: the mail connection, each account's filtering, health and trust, and keys.
struct AccountSettingsView: View {
  let model: AppModel

  private var transport: MailTransport { model.shared.settings.advancedOptions.transport }

  var body: some View {
    Form {
      IMAPSettingsView(
        settings: model.settings,
        imap: model.imap,
        storageReady: model.services.storageReady
      )
      if transport == .appleMail {
        MailConnectionView(mail: model.mail)
        MailAccountsView(model: model)
      } else if model.imap.hasSavedConnection {
        MailAccountSection(
          model: model,
          accountID: model.imap.accountID,
          name: model.imap.accountName
        )
      }
      RelationshipSettingsView(
        relationships: model.relationships,
        settings: model.settings,
        shared: model.shared,
        imap: model.imap
      )
      if transport == .appleMail { MailRuleSetupView(mail: model.mail) }
      CredentialsSettingsView(credentials: model.credentials)
    }
    .formStyle(.grouped)
    .task(id: model.shared.recordsVersion) { await model.trust.refresh() }
  }
}

#Preview("Apple Mail accounts") { AccountSettingsView(model: PreviewHelper.accountsModel()) }
#Preview("Failing account") {
  AccountSettingsView(model: PreviewHelper.accountsModel(failing: true))
}
#Preview("No accounts yet") { AccountSettingsView(model: PreviewHelper.model()) }
#Preview("IMAP account") { AccountSettingsView(model: PreviewHelper.model(transport: .imap)) }

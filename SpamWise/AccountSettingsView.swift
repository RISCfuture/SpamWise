import SwiftUI
import SpamWiseCore

/// The Accounts tab: each account's connection, filtering, health and trust, then keys. With Apple
/// Mail, the choice of another connection follows the Apple Mail sections.
struct AccountSettingsView: View {
  let model: AppModel

  private var transport: MailTransport { model.shared.settings.advancedOptions.transport }

  var body: some View {
    Form {
      if transport == .appleMail {
        MailConnectionView(mail: model.mail)
        MailAccountsView(model: model)
      } else {
        IMAPSettingsView(model: model)
        if model.imap.hasSavedConnection {
          MailAccountSection(
            model: model,
            accountID: model.imap.accountID,
            name: model.imap.accountName
          )
        }
      }
      RelationshipSettingsView(
        relationships: model.relationships,
        settings: model.settings,
        shared: model.shared,
        imap: model.imap
      )
      if transport == .appleMail {
        MailRuleSetupView(mail: model.mail)
        IMAPSettingsView(model: model)
      }
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

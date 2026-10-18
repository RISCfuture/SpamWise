import SwiftUI
import SpamWiseCore

struct MailConnectionView: View {
  @Bindable var model: AppModel

  var body: some View {
    Section("Apple Mail") {
      Text("Allow Automation when asked.")
      Button("Check Mail connection") { model.checkMail() }
        .accessibilityIdentifier("mail.check").disabled(model.busy)
      Text(model.mailStatus).textSelection(.enabled)
        .accessibilityIdentifier(
          model.mailPermissionDenied ? "mail.permissionDenied" : "mail.status"
        )
      LabeledContent(
        "Validated accounts",
        value: model.state.settings.validatedAccounts.count.formatted()
      )
    }
    Section {
      DisclosureGroup("Accounts and scan health") {
        MailHealthView(model: model)
      }
      DisclosureGroup("History and Contacts") {
        Text("Use your correspondence and Contacts to recognize trusted senders.")
        Button("Connect Contacts (optional)") { model.requestContacts() }
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(model.contactsStatus).foregroundStyle(.secondary)
        Toggle(
          "Exclude my own addresses from automatic trust",
          isOn: model.mailBinding(\.excludeOwnAddresses)
        )
        Text(
          "Explicit sender rules still take precedence. Check Mail connection to refresh your account addresses."
        )
        .foregroundStyle(.secondary)
        TrustExclusionsView(model: model)
        Button("Import Inbox and Sent history") { model.importHistory() }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      DisclosureGroup("Mail rule") {
        MailRuleSetupView(model: model)
      }
    }.disabled(model.busy)
  }
}

private struct MailRuleSetupView: View {
  let model: AppModel

  var body: some View {
    Text("Optionally run the bundled script from a Mail rule so new mail is checked as it arrives.")
    HStack {
      Button("Show Mail rule script in Finder") { model.revealRule() }
      Spacer()
      HelpButton(page: "troubleshooting-mail-integration")
    }
  }
}

#Preview("Mail connection") {
  Form { MailConnectionView(model: PreviewHelper.model()) }.formStyle(.grouped)
}
#Preview("Permission denied") {
  let model = PreviewHelper.model()
  model.mailPermissionDenied = true
  model.mailStatus = AppModel.describe(IntegrationError.permissionDenied)
  return Form { MailConnectionView(model: model) }.formStyle(.grouped)
}
#Preview("Mail rule") {
  Form { MailRuleSetupView(model: PreviewHelper.model()) }.formStyle(.grouped)
}

import SwiftUI
import SpamWiseCore

struct MailConnectionView: View {
  let model: AppModel

  private var mail: MailConnectionModel { model.mail }

  var body: some View {
    Section("Apple Mail") {
      Text("Allow Automation when asked.")
      HStack {
        Button("Check Mail connection") { mail.checkConnection() }
          .accessibilityIdentifier("mail.check")
        if mail.check.isBusy { ProgressView().controlSize(.small) }
      }
      MailConnectionStatus(
        mail: mail,
        identifier: mail.permissionDenied ? "mail.permissionDenied" : "mail.status"
      )
      LabeledContent(
        "Validated accounts",
        value: model.shared.settings.validatedAccounts.count.formatted()
      )
    }
    Section {
      DisclosureGroup("Accounts and scan health") {
        MailHealthView(model: model)
      }
      DisclosureGroup("History and Contacts") {
        RelationshipSettingsView(
          relationships: model.relationships,
          settings: model.settings,
          shared: model.shared
        )
      }
      DisclosureGroup("Mail rule") {
        MailRuleSetupView(mail: mail)
      }
    }
  }
}

/// The latest connection check's result, or what to do before the first check.
struct MailConnectionStatus: View {
  let mail: MailConnectionModel
  let identifier: String

  var body: some View {
    if mail.check.isBusy {
      Text("Waiting for Mail Automation permission…").foregroundStyle(.secondary)
        .accessibilityIdentifier(identifier)
    } else if mail.check.status == nil {
      Text("Mail connection not checked").foregroundStyle(.secondary)
        .accessibilityIdentifier(identifier)
    } else {
      OperationStatusView(operation: mail.check, identifier: identifier)
    }
  }
}

private struct RelationshipSettingsView: View {
  let relationships: RelationshipsModel
  let settings: SettingsModel
  let shared: SharedStateModel

  var body: some View {
    Text("Use your correspondence and Contacts to recognize trusted senders.")
    Button("Connect Contacts (optional)") { relationships.connectContacts() }
      .frame(maxWidth: .infinity, alignment: .leading)
    if relationships.contacts.status == nil {
      Text("Contacts optional — not requested").foregroundStyle(.secondary)
    }
    OperationStatusView(operation: relationships.contacts)
    Toggle(
      "Exclude my own addresses from automatic trust",
      isOn: settings.mailBinding(\.excludeOwnAddresses)
    )
    Text(
      "Explicit sender rules still take precedence. Check Mail connection to refresh your account addresses."
    )
    .foregroundStyle(.secondary)
    TrustExclusionsView(relationships: relationships, shared: shared)
    HStack {
      Button("Import Inbox and Sent history") { relationships.importHistory() }
      if relationships.historyImport.isBusy { ProgressView().controlSize(.small) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    OperationStatusView(operation: relationships.historyImport)
  }
}

private struct MailRuleSetupView: View {
  let mail: MailConnectionModel
  @State private var failure: OperationStatus?

  var body: some View {
    Text("Optionally run the bundled script from a Mail rule so new mail is checked as it arrives.")
    HStack {
      Button("Show Mail rule script in Finder") { reveal() }
      Spacer()
      HelpButton(page: "troubleshooting-mail-integration")
    }
    StatusLabel(status: failure)
  }

  private func reveal() {
    do {
      try mail.revealRuleScript()
      failure = nil
    } catch {
      failure = .failure(OperationFailure(error))
    }
  }
}

#Preview("Mail connection") {
  Form { MailConnectionView(model: PreviewHelper.model()) }.formStyle(.grouped)
}
#Preview("Permission denied") {
  let model = PreviewHelper.model()
  model.mail.checkConnection()
  return Form { MailConnectionView(model: model) }.formStyle(.grouped)
}
#Preview("Mail rule") {
  Form { MailRuleSetupView(mail: PreviewHelper.model().mail) }.formStyle(.grouped)
}

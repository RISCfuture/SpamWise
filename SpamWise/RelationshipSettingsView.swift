import SwiftUI
import SpamWiseCore

/// Contacts and correspondence history, which help SpamWise recognize people you know.
struct RelationshipSettingsView: View {
  let relationships: RelationshipsModel
  let settings: SettingsModel
  let shared: SharedStateModel

  var body: some View {
    Section("Contacts and history") {
      Text(
        """
        People in Contacts and people you’ve written to are less likely to be sent to Junk. In \
        accounts with a trusted mail server, their mail goes straight to Inbox.
        """
      )
      .foregroundStyle(.secondary)
      HStack {
        Button("Connect Contacts") { relationships.connectContacts() }
        if relationships.contacts.isBusy { ProgressView().controlSize(.small) }
      }
      if relationships.contacts.status == nil {
        Text("Optional. SpamWise reads only email addresses.").foregroundStyle(.secondary)
      }
      OperationStatusView(operation: relationships.contacts)
      HStack {
        Button("Import Inbox and Sent History") { relationships.importHistory() }
        if relationships.historyImport.isBusy { ProgressView().controlSize(.small) }
      }
      OperationStatusView(operation: relationships.historyImport)
      Toggle(
        "Don’t treat my own addresses as people I know",
        isOn: settings.mailBinding(\.excludeOwnAddresses)
      )
    }
    TrustExclusionsView(relationships: relationships, shared: shared)
  }
}

/// The bundled script a Mail rule can run so new mail is checked as soon as it arrives.
struct MailRuleSetupView: View {
  let mail: MailConnectionModel
  @State private var failure: OperationStatus?

  var body: some View {
    Section("New mail") {
      Text(
        """
        SpamWise checks your Inbox every minute. To check new mail as soon as it arrives, add a \
        Mail rule that runs the SpamWise script.
        """
      )
      .foregroundStyle(.secondary)
      HStack {
        Button("Show Script in Finder") { reveal() }
        Spacer()
        HelpButton(page: "troubleshooting-mail-integration")
      }
      StatusLabel(status: failure)
    }
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

#Preview("Contacts and history") {
  let model = PreviewHelper.model()
  Form {
    RelationshipSettingsView(
      relationships: model.relationships,
      settings: model.settings,
      shared: model.shared
    )
  }
  .formStyle(.grouped)
}
#Preview("Mail rule") {
  Form { MailRuleSetupView(mail: PreviewHelper.model().mail) }.formStyle(.grouped)
}

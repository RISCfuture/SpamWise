import SwiftUI
import SpamWiseCore
import MailIntegration

/// The Inbox and Junk mailboxes Mail reports for an account, which SpamWise moves mail between.
struct MailDestinationView: View {
  let mail: MailConnectionModel
  let shared: SharedStateModel
  let accountID: String
  @State private var destinations: MailDestinations?
  @State private var reading = TrackedOperation()

  var body: some View {
    LabeledContent(
      "Inbox and Junk mailboxes",
      value: shared.settings.validatedAccounts.contains(accountID)
        ? String(localized: "Found") : String(localized: "Not found yet")
    )
    HStack {
      Button("Check Mailboxes") { read() }
      if reading.isBusy { ProgressView().controlSize(.small) }
    }
    if let destinations {
      LabeledContent("Inbox", value: names(destinations.inbox))
      LabeledContent("Junk", value: names(destinations.junk))
      MailboxRoleWarning(destinations: destinations)
    }
    OperationStatusView(operation: reading)
  }

  private func read() {
    destinations = nil
    reading.run(retryable: true) { [mail, accountID] in
      destinations = try await mail.readDestinations(accountID: accountID)
      return nil
    }
  }

  private func names(_ values: [String]) -> String {
    values.isEmpty ? String(localized: "None") : values.joined(separator: ", ")
  }
}

/// Why SpamWise won't move an account's mail, and how to set its mailboxes up in Mail.
private struct MailboxRoleWarning: View {
  let destinations: MailDestinations

  private var missingJunk: Bool { destinations.junk.isEmpty }
  private var duplicateJunk: Bool { destinations.junk.count > 1 }

  var body: some View {
    if missingJunk {
      WarningLabel(
        """
        Mail hasn’t set a Junk mailbox for this account. In Mail, select the account’s junk \
        folder, choose Mailbox › Use This Mailbox For › Junk, then choose Check Mailboxes.
        """
      )
    } else if duplicateJunk {
      WarningLabel(
        """
        Mail shows more than one Junk mailbox for this account. In Mail, keep the Junk role on one \
        folder only, then choose Check Mailboxes.
        """
      )
    } else if !destinations.isUnambiguous {
      WarningLabel(
        """
        Mail doesn’t show exactly one Inbox for this account, so SpamWise won’t move its mail. \
        Check the account in Mail, then choose Check Mailboxes.
        """
      )
    }
  }
}

#Preview("Unchecked mailboxes") {
  let model = PreviewHelper.model()
  Form { MailDestinationView(mail: model.mail, shared: model.shared, accountID: "preview") }
    .formStyle(.grouped)
}

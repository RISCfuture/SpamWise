import SwiftUI
import SpamWiseCore
import MailIntegration

/// The Inbox and Junk mailboxes Mail reports for an account, which SpamWise moves mail between.
struct MailDestinationView: View {
  let mail: MailConnectionModel
  let shared: SharedStateModel
  let accountID: String
  @State private var reading = TrackedOperation()

  private var destinations: MailDestinations? { mail.destinations[accountID] }

  var body: some View {
    LabeledContent(
      "Inbox and Junk mailboxes",
      value: shared.settings.validatedAccounts.contains(accountID)
        ? String(localized: "Found") : String(localized: "Not found yet")
    )
    HStack {
      Button("Check Mailboxes") { read() }
      if reading.isBusy {
        ProgressView { Text("Checking mailboxes…") }.labelsHidden().controlSize(.small)
      }
    }
    if let destinations {
      LabeledContent("Inbox", value: names(destinations.inbox))
      LabeledContent("Junk", value: names(destinations.junk))
      MailboxRoleWarning(destinations: destinations)
    }
    OperationStatusView(operation: reading)
  }

  private func read() {
    reading.run(retryable: true) { [mail, accountID] in
      try await mail.readDestinations(accountID: accountID)
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
    } else if destinations.junkBypassesGmailSpam {
      GmailSpamWarning(destinations: destinations)
    }
  }
}

/// Why a Gmail account's junk misses Gmail's Spam, and how to point Mail's Junk role at it.
struct GmailSpamWarning: View {
  let destinations: MailDestinations
  /// The account's name, for a warning shown outside the account's own section.
  var accountName: String?

  private var junk: String { destinations.junk.first ?? "" }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      WarningLabel { message }
      Spacer()
      HelpButton(page: "gmail-spam")
    }
  }

  @ViewBuilder private var message: some View {
    if let accountName {
      Text(
        """
        For the “\(accountName)” account, Mail uses the Gmail label “\(junk)” as Junk instead of \
        Gmail’s Spam, so Gmail’s own filter doesn’t learn from the mail SpamWise moves there. In \
        Mail, select Spam in the account’s [Gmail] folder, choose Mailbox › Use This Mailbox For › \
        Junk, then choose Check Mail Connection.
        """
      )
    } else {
      Text(
        """
        Mail uses the Gmail label “\(junk)” as this account’s Junk instead of Gmail’s Spam, so \
        Gmail’s own filter doesn’t learn from the mail SpamWise moves there. In Mail, select Spam \
        in the account’s [Gmail] folder, choose Mailbox › Use This Mailbox For › Junk, then choose \
        Check Mailboxes.
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

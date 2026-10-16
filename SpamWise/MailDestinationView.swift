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
      if !destinations.isUnambiguous {
        WarningLabel(
          "Mail doesn’t show exactly one Inbox and one Junk mailbox for this account, so SpamWise won’t move its mail."
        )
      }
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

#Preview("Unchecked mailboxes") {
  let model = PreviewHelper.model()
  Form { MailDestinationView(mail: model.mail, shared: model.shared, accountID: "preview") }
    .formStyle(.grouped)
}

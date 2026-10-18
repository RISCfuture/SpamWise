import SwiftUI
import SpamWiseCore
import MailIntegration

struct MailDestinationView: View {
  let mail: MailConnectionModel
  let shared: SharedStateModel
  let accountID: String
  @State private var destinations: MailDestinations?
  @State private var reading = TrackedOperation()

  var body: some View {
    DisclosureGroup("Mailbox destinations") {
      LabeledContent(
        "Inbox and Junk",
        value: shared.settings.validatedAccounts.contains(accountID)
          ? String(localized: "Validated") : String(localized: "Not validated")
      )
      HStack {
        Button("Read current destinations") { read() }
        if reading.isBusy { ProgressView().controlSize(.small) }
      }
      if let destinations {
        LabeledContent("Inbox", value: names(destinations.inbox))
        LabeledContent("Junk", value: names(destinations.junk))
        if !destinations.isUnambiguous {
          Text("Mailbox roles are missing or ambiguous. Actions remain unavailable.")
        }
      }
      OperationStatusView(operation: reading)
      Text(
        "These are Mail.app roles. Matching names do not prove server labels. Keep dry run on while comparing filters."
      ).foregroundStyle(.secondary)
    }
  }

  private func read() {
    destinations = nil
    reading.run(retryable: true) { [mail, accountID] in
      destinations = try await mail.readDestinations(accountID: accountID)
      return nil
    }
  }

  private func names(_ values: [String]) -> String {
    values.isEmpty ? String(localized: "Unavailable") : values.joined(separator: ", ")
  }
}

#Preview("Unchecked destinations") {
  let model = PreviewHelper.model()
  Form { MailDestinationView(mail: model.mail, shared: model.shared, accountID: "preview") }
}

import SwiftUI
import SpamWiseCore
import MailIntegration

struct MailDestinationView: View {
  let model: AppModel
  let accountID: String
  @State private var destinations: MailDestinations?
  @State private var failure: String?

  var body: some View {
    DisclosureGroup("Mailbox destinations") {
      LabeledContent(
        "Inbox and Junk",
        value: model.state.settings.validatedAccounts.contains(accountID)
          ? String(localized: "Validated") : String(localized: "Not validated")
      )
      Button("Read current destinations") {
        destinations = nil; failure = nil
        model.run {
          do { destinations = try await model.readDestinations(accountID: accountID) } catch {
            failure = AppModel.describe(error)
          }
        }
      }.disabled(model.busy)
      if let destinations {
        LabeledContent("Inbox", value: names(destinations.inbox))
        LabeledContent("Junk", value: names(destinations.junk))
        if !destinations.isUnambiguous {
          Text("Mailbox roles are missing or ambiguous. Actions remain unavailable.")
        }
      }
      if let failure { Text(failure).textSelection(.enabled) }
      Text(
        "These are Mail.app roles. Matching names do not prove server labels. Keep dry run on while comparing filters."
      ).foregroundStyle(.secondary)
    }
  }
  private func names(_ values: [String]) -> String {
    values.isEmpty ? String(localized: "Unavailable") : values.joined(separator: ", ")
  }
}

#Preview("Unchecked destinations") {
  Form { MailDestinationView(model: PreviewHelper.model(), accountID: "preview") }
}

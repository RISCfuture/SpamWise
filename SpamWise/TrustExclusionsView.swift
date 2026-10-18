import SwiftUI
import SpamWiseCore

/// Your own addresses, and addresses that never count as people you know.
struct TrustExclusionsView: View {
  let relationships: RelationshipsModel
  let shared: SharedStateModel
  @State private var addresses = ""

  var body: some View {
    DisclosureGroup("Your addresses and exceptions") {
      if shared.state.ownAddresses.isEmpty {
        Text("Check Mail Connection to find your account addresses.")
          .foregroundStyle(.secondary)
      } else {
        LabeledContent("Your addresses") {
          Text(shared.state.ownAddresses.sorted().joined(separator: "\n"))
            .textSelection(.enabled)
        }
      }
      Text(
        """
        Mail from these addresses never counts as from people you know. It isn’t blocked, and your \
        sender rules still apply. Enter one address per line.
        """
      )
      .foregroundStyle(.secondary)
      TextEditor(text: $addresses).frame(minHeight: 80)
        .accessibilityLabel("Addresses that don’t count as people you know")
      Button("Save Exceptions") { relationships.saveTrustExclusions(addresses) }
      OperationStatusView(operation: relationships.exclusions)
    }.onAppear {
      addresses = shared.settings.mailOptions.trustExclusions.sorted().joined(separator: "\n")
    }
  }
}

#Preview("Trust exclusions") {
  let model = PreviewHelper.model()
  Form { TrustExclusionsView(relationships: model.relationships, shared: model.shared) }
    .formStyle(.grouped)
}
#Preview("Discovered addresses") {
  let model = PreviewHelper.model()
  model.shared.state.ownAddresses = ["me@example.org", "me@icloud.example"]
  return Form { TrustExclusionsView(relationships: model.relationships, shared: model.shared) }
    .formStyle(.grouped)
}

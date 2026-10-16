import SwiftUI
import SpamWiseCore

/**
 Your own addresses, and addresses that never count as people you know.

 Edits save when editing ends. One that can't be saved stays, with the reason, until it is fixed.
 */
struct TrustExclusionsView: View {
  @Bindable var relationships: RelationshipsModel
  let shared: SharedStateModel

  var body: some View {
    Section {
      if shared.state.ownAddresses.isEmpty {
        Text("Check Mail Connection to find your account addresses.")
          .foregroundStyle(.secondary)
      } else {
        LabeledContent("Your addresses") {
          Text(shared.state.ownAddresses.sorted().joined(separator: "\n"))
            .textSelection(.enabled)
        }
      }
      TextEditor(text: $relationships.exclusionsText).frame(minHeight: 80)
        .accessibilityLabel("Addresses that don’t count as people you know")
        .accessibilityIdentifier("relationships.exclusions")
        .commitsEdits { relationships.commitTrustExclusions() }
      OperationStatusView(operation: relationships.exclusions)
    } header: {
      Text("Your addresses and exceptions")
    } footer: {
      Text(
        """
        Mail from these addresses never counts as from people you know. It isn’t blocked, and your \
        sender rules still apply. Enter one address per line.
        """
      )
      .foregroundStyle(.secondary)
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

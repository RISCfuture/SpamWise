import SwiftUI
import SpamWiseCore

struct TrustExclusionsView: View {
  let relationships: RelationshipsModel
  let shared: SharedStateModel
  @State private var addresses = ""

  var body: some View {
    DisclosureGroup("Own addresses and trust exclusions") {
      if !shared.state.ownAddresses.isEmpty {
        Text(shared.state.ownAddresses.sorted().joined(separator: "\n")).textSelection(.enabled)
      } else {
        Text("No account addresses discovered yet.")
      }
      Text(
        "Exclude aliases or other addresses from automatic Contacts and history trust, one per line."
      )
      .foregroundStyle(.secondary)
      TextEditor(text: $addresses).frame(minHeight: 80)
        .accessibilityLabel("Addresses excluded from automatic trust")
      Button("Save trust exclusions") { relationships.saveTrustExclusions(addresses) }
      OperationStatusView(operation: relationships.exclusions)
      Text("These exclusions do not block mail. Explicit address and domain rules still win.")
        .foregroundStyle(.secondary)
    }.onAppear {
      addresses = shared.settings.mailOptions.trustExclusions.sorted().joined(separator: "\n")
    }
  }
}

#Preview("Trust exclusions") {
  let model = PreviewHelper.model()
  Form { TrustExclusionsView(relationships: model.relationships, shared: model.shared) }
}

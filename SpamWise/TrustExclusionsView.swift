import SwiftUI
import SpamWiseCore

struct TrustExclusionsView: View {
  let model: AppModel
  @State private var addresses = ""

  var body: some View {
    DisclosureGroup("Own addresses and trust exclusions") {
      if !model.state.ownAddresses.isEmpty {
        Text(model.state.ownAddresses.sorted().joined(separator: "\n")).textSelection(.enabled)
      } else {
        Text("No account addresses discovered yet.")
      }
      Text(
        "Exclude aliases or other addresses from automatic Contacts and history trust, one per line."
      )
      .foregroundStyle(.secondary)
      TextEditor(text: $addresses).frame(minHeight: 80)
        .accessibilityLabel("Addresses excluded from automatic trust")
      Button("Save trust exclusions") {
        let draft = addresses
        model.run {
          guard let store = model.store else { throw IntegrationError.unavailable }
          try await TrustExclusions.save(draft, store: store)
        }
      }.disabled(model.busy)
      Text("These exclusions do not block mail. Explicit address and domain rules still win.")
        .foregroundStyle(.secondary)
    }.onAppear {
      addresses = model.state.settings.mailOptions.trustExclusions.sorted().joined(separator: "\n")
    }
  }
}

#Preview("Trust exclusions") { Form { TrustExclusionsView(model: PreviewHelper.model()) } }

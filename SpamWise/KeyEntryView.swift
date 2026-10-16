import SwiftUI
import SpamWiseCore

struct KeyEntryView: View {
  @Bindable var model: AppModel
  @State private var key = ""

  var body: some View {
    SecureField("Anthropic API key", text: $key)
      .accessibilityIdentifier("setup.key")
    HStack {
      Button("Verify and save key") {
        model.verifyKey(key); key = ""
      }
      .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
      Spacer()
      Link(
        "Open Claude Console",
        destination: URL(string: "https://console.anthropic.com/settings/keys")!
      )
    }
    Text("Verification sends one synthetic message to Haiku 5.5 and saves your key in Keychain.")
      .foregroundStyle(.secondary)
    if !model.keyStatus.isEmpty {
      Text("API key status: \(model.keyStatus)").textSelection(.enabled)
    }
  }
}

#Preview("API key") { Form { KeyEntryView(model: PreviewHelper.model()) }.formStyle(.grouped) }

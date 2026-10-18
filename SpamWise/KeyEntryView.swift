import SwiftUI
import SpamWiseCore

struct KeyEntryView: View {
  let credentials: CredentialsModel
  @State private var key = ""

  var body: some View {
    SecureField("Anthropic API key", text: $key)
      .accessibilityIdentifier("setup.key")
    HStack {
      Button("Verify and save key") {
        credentials.verifyClaudeKey(key); key = ""
      }
      .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if credentials.claudeKey.isBusy {
        ProgressView().controlSize(.small)
        Text("Verifying Haiku 5.5…").foregroundStyle(.secondary)
      }
      Spacer()
      Link(
        "Open Claude Console",
        destination: URL(string: "https://console.anthropic.com/settings/keys")!
      )
    }
    Text("Verification sends one synthetic message to Haiku 5.5 and saves your key in Keychain.")
      .foregroundStyle(.secondary)
    OperationStatusView(operation: credentials.claudeKey, identifier: "setup.keyStatus")
  }
}

#Preview("API key") {
  Form { KeyEntryView(credentials: PreviewHelper.model().credentials) }.formStyle(.grouped)
}

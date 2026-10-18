import SwiftUI
import SpamWiseCore

/**
 Entry for a cloud provider's API key. A Claude key is verified with one test request before it
 is saved; other providers' keys are saved without a request.

 Return in the field submits the key, and the submit button is the default while a key is typed.
 The typed key clears once it is saved.
 */
struct KeyEntryView: View {
  let credentials: CredentialsModel
  /// The model a Claude key is verified with; its provider chooses the key.
  let model: ModelIdentifier
  @State private var localKey = ""
  private let externalKey: Binding<String>?

  private var key: Binding<String> { externalKey ?? $localKey }
  private var backend: ModelBackend { model.backend }
  private var verifies: Bool { backend == .claude }
  private var operation: TrackedOperation {
    verifies ? credentials.claudeKey : credentials.providerKey
  }
  private var draft: String { key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    SecureField(
      backend.keyFieldTitle,
      text: key,
      prompt: Text(verbatim: backend.keyPrompt)
    )
    .onSubmit(submit)
    .accessibilityIdentifier("setup.key")
    HStack {
      Button(verifies ? "Verify and save key" : "Save key", action: submit)
        .keyboardShortcut(draft.isEmpty ? nil : .defaultAction)
        .disabled(draft.isEmpty || operation.isBusy)
        .accessibilityIdentifier("setup.saveKey")
      if operation.isBusy {
        ProgressView().controlSize(.small)
        if verifies {
          Text("Verifying with \(model.displayName)…").foregroundStyle(.secondary)
        }
      }
      Spacer()
      if let consoleURL = backend.keyConsoleURL {
        Link("Get an API key", destination: consoleURL)
      }
    }
    if credentials.savedKeys.contains(backend), draft.isEmpty {
      Text("A key is saved in Keychain. Enter a new one to replace it.")
        .foregroundStyle(.secondary)
    }
    Text(
      verifies
        ? "SpamWise checks the key with one short test request to \(model.displayName), which may incur a small API charge, then saves it only in Keychain."
        : "The key is saved only in Keychain, without a request. A dry run shows whether it works."
    )
    .foregroundStyle(.secondary)
    OperationStatusView(operation: operation, identifier: "setup.keyStatus")
  }

  /**
   Creates key entry for `model`'s provider.

   - Parameters:
     - credentials: Saves the key.
     - model: The model a Claude key is verified with.
     - key: The typed key, when the caller keeps it across views; otherwise the view keeps it.
   */
  init(
    credentials: CredentialsModel,
    model: ModelIdentifier = .claudeHaiku,
    key: Binding<String>? = nil
  ) {
    self.credentials = credentials
    self.model = model
    externalKey = key
  }

  private func submit() {
    guard !draft.isEmpty, !operation.isBusy else { return }
    let run =
      verifies
      ? credentials.verifyClaudeKey(draft, model: model)
      : credentials.saveProviderKey(draft, for: backend)
    let key = key, operation = operation
    Task {
      await run.value
      if operation.failure == nil { key.wrappedValue = "" }
    }
  }
}

extension ModelBackend {
  fileprivate var keyFieldTitle: LocalizedStringKey {
    switch self {
      case .claude: "Anthropic API key"
      case .openAI: "OpenAI API key"
      case .gemini: "Gemini API key"
      case .onDevice, .privateCloudCompute: "API key"
    }
  }

  /// The start of a key the provider issues, shown in the empty field.
  fileprivate var keyPrompt: String {
    switch self {
      case .claude: "sk-ant-…"
      case .openAI: "sk-…"
      case .gemini: "AIza…"
      case .onDevice, .privateCloudCompute: ""
    }
  }

  fileprivate var keyConsoleURL: URL? {
    switch self {
      case .claude: URL(string: "https://console.anthropic.com/settings/keys")
      case .openAI: URL(string: "https://platform.openai.com/api-keys")
      case .gemini: URL(string: "https://aistudio.google.com/apikey")
      case .onDevice, .privateCloudCompute: nil
    }
  }
}

#Preview("Claude key") {
  Form { KeyEntryView(credentials: PreviewHelper.model().credentials) }.formStyle(.grouped)
}
#Preview("OpenAI key") {
  Form { KeyEntryView(credentials: PreviewHelper.model().credentials, model: .gptMini) }
    .formStyle(.grouped)
}

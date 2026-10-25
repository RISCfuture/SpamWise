import SwiftUI
import SpamWiseCore

/**
 Entry for a cloud provider's API key. A Claude key is verified with one test request before it
 is saved, so it can't be saved while Keep filtering on this Mac is on; other providers' keys are
 saved without a request.

 Return in the field submits the key, and the submit button is the default while a key is typed.
 The typed key clears once it is saved.
 */
struct KeyEntryView: View {
  let credentials: CredentialsModel
  /// The model a Claude key is verified with; its provider chooses the key.
  let model: ModelIdentifier
  /// Whether Keep filtering on this Mac is on, which rules out a verification request.
  let isLocalOnly: Bool
  @State private var localKey = ""
  private let externalKey: Binding<String>?

  private var key: Binding<String> { externalKey ?? $localKey }
  private var backend: ModelBackend { model.backend }
  private var verifies: Bool { backend == .claude }
  private var operation: TrackedOperation {
    verifies ? credentials.claudeKey : credentials.providerKey
  }
  private var draft: String { key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var canSubmit: Bool { !draft.isEmpty && !operation.isBusy && !(verifies && isLocalOnly) }

  var body: some View {
    SecureField(
      backend.keyFieldTitle,
      text: key,
      prompt: Text(verbatim: backend.keyPrompt)
    )
    .onSubmit(submit)
    .accessibilityIdentifier("setup.key")
    HStack {
      Button(verifies ? "Verify and Save Key" : "Save Key", action: submit)
        .keyboardShortcut(canSubmit ? .defaultAction : nil)
        .disabled(!canSubmit)
        .accessibilityIdentifier("setup.saveKey")
      if operation.isBusy {
        ProgressView { Text("Saving the key…") }.labelsHidden().controlSize(.small)
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
      SavedKeyRow(credentials: credentials, backend: backend)
    }
    KeyEntryNote(model: model, isLocalOnly: isLocalOnly)
    OperationStatusView(operation: operation, identifier: "setup.keyStatus")
    OperationStatusView(operation: credentials.storedCredentials)
  }

  /**
   Creates key entry for `model`'s provider.

   - Parameters:
     - credentials: Saves the key.
     - model: The model a Claude key is verified with.
     - isLocalOnly: Whether Keep filtering on this Mac is on, which rules out verification.
     - key: The typed key, when the caller keeps it across views; otherwise the view keeps it.
   */
  init(
    credentials: CredentialsModel,
    model: ModelIdentifier = .claudeHaiku,
    isLocalOnly: Bool,
    key: Binding<String>? = nil
  ) {
    self.credentials = credentials
    self.model = model
    self.isLocalOnly = isLocalOnly
    externalKey = key
  }

  private func submit() {
    guard canSubmit else { return }
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

/// The saved key's note, with Remove Key after confirming.
private struct SavedKeyRow: View {
  let credentials: CredentialsModel
  let backend: ModelBackend
  @State private var confirming = false

  var body: some View {
    HStack {
      Text("A key is saved in Keychain. Enter a new one to replace it.")
        .foregroundStyle(.secondary)
      Spacer()
      Button("Remove Key…", role: .destructive) { confirming = true }
        .disabled(credentials.storedCredentials.isBusy)
        .accessibilityIdentifier("setup.removeKey")
    }
    .confirmationDialog(
      "Remove the \(backend.localizedTitle) API key?",
      isPresented: $confirming,
      titleVisibility: .visible
    ) {
      Button("Remove Key", role: .destructive) { credentials.remove(.provider(backend)) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "SpamWise removes the key from Keychain and can’t use \(backend.localizedTitle) until you enter a key again."
      )
    }
  }
}

/// What saving the key involves, or why a Claude key can't be verified now.
private struct KeyEntryNote: View {
  let model: ModelIdentifier
  let isLocalOnly: Bool

  var body: some View {
    Group {
      if model.backend != .claude {
        Text(
          "The key is saved only in Keychain, without a request. A dry run shows whether it works."
        )
      } else if isLocalOnly {
        Text(
          "Verifying sends a test request to \(model.displayName), so it’s unavailable while Keep filtering on this Mac is on."
        )
      } else {
        Text(
          "SpamWise checks the key with one short test request to \(model.displayName), which may incur a small API charge, then saves it only in Keychain."
        )
      }
    }
    .foregroundStyle(.secondary)
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
  Form { KeyEntryView(credentials: PreviewHelper.model().credentials, isLocalOnly: false) }
    .formStyle(.grouped)
}
#Preview("Claude key, local only") {
  Form { KeyEntryView(credentials: PreviewHelper.model().credentials, isLocalOnly: true) }
    .formStyle(.grouped)
}
#Preview("OpenAI key") {
  Form {
    KeyEntryView(
      credentials: PreviewHelper.model().credentials,
      model: .gptMini,
      isLocalOnly: false
    )
  }
  .formStyle(.grouped)
}

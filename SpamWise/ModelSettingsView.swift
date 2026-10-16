import SwiftUI
import SpamWiseCore

struct ModelSettingsView: View {
  @Bindable var model: AppModel
  @State private var key = ""
  @State private var budget = BudgetLedger()
  var body: some View {
    Section("Classifier") {
      Picker(
        "Provider",
        selection: Binding(
          get: { model.state.settings.advancedOptions.backend },
          set: { backend in
            model.editSettings {
              var advanced = $0.advancedOptions
              advanced.backend = backend; advanced.modelID = nil
              $0.advancedOptions = advanced
            }
          }
        )
      ) {
        Text("Anthropic Claude").tag(ModelBackend.claude)
        Text("Apple on-device").tag(ModelBackend.onDevice)
        Text("Apple Private Cloud Compute").tag(ModelBackend.privateCloudCompute)
        Text("OpenAI").tag(ModelBackend.openAI)
        Text("Google Gemini").tag(ModelBackend.gemini)
      }.accessibilityIdentifier("model.provider")
      LabeledContent(
        "Model",
        value: model.state.settings.advancedOptions.modelID
          ?? model.state.settings.advancedOptions.backend.defaultModelID
      )
      if model.state.settings.advancedOptions.backend == .claude {
        KeyEntryView(model: model)
      } else if [.openAI, .gemini].contains(model.state.settings.advancedOptions.backend) {
        SecureField("Provider API key", text: $key).accessibilityIdentifier("model.key")
        Button("Save provider key") {
          model.saveProviderKey(key); key = ""
        }.disabled(key.isEmpty || model.busy)
        Text(
          "Stored only in Keychain. Saving does not make a paid request; use a dry run to verify."
        ).font(.caption)
      } else {
        Text(
          """
          Availability depends on your Mac and Apple Intelligence settings. Private Cloud Compute \
          also requires an approved entitlement. Refusals leave mail unchanged.
          """
        ).font(.caption)
      }
      Text(
        """
        Messages and preferences go only to the selected provider. An unavailable model never \
        falls back to another provider.
        """
      ).font(.caption)
    }
    Section("Spending limit") {
      LabeledContent("Authorized ceiling", value: budget.limitUSD.formatted(.currency(code: "USD")))
      LabeledContent(
        "Conservative commitments",
        value: budget.committedUSD.formatted(.currency(code: "USD"))
      )
      Text(
        """
        Each paid call reserves an upper bound before it starts. Commitments include failed calls \
        and exceed estimated actual charges. Calls stop when the ceiling would be exceeded.
        """
      ).font(.caption)
      LabeledContent(
        "Month-to-date estimated API cost",
        value: model.monthCost.formatted(.currency(code: "USD"))
      )
    }.task(id: model.busy) {
      if let store = model.store, let ledger = try? await EvaluationBudget.load(store) {
        budget = ledger
      }
    }
  }
}

extension AppModel {
  func saveProviderKey(_ key: String) {
    let backend = state.settings.advancedOptions.backend
    run { [self] in
      let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !credential.isEmpty else { throw ClassificationError.missingCredential }
      try APIKeychain(service: ConfiguredClassifier.credentialService(for: backend)).save(
        credential
      )
      status = String(localized: "Provider key saved in Keychain. Use a dry run to verify.")
    }
  }
  func advancedBinding<T: Sendable>(
    _ key: any WritableKeyPath<AdvancedSettings, T> & Sendable
  ) -> Binding<T> {
    Binding(
      get: { self.state.settings.advancedOptions[keyPath: key] },
      set: { value in
        self.editSettings {
          var advanced = $0.advancedOptions; advanced[keyPath: key] = value
          $0.advancedOptions = advanced
        }
      }
    )
  }
}

#Preview { Form { ModelSettingsView(model: PreviewHelper.model()) } }

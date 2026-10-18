import SwiftUI
import SpamWiseCore

struct ModelSettingsView: View {
  @Bindable var model: AppModel
  @State private var key = ""

  private var backend: ModelBackend { model.state.settings.advancedOptions.backend }
  private var backendBinding: Binding<ModelBackend> {
    Binding(
      get: { backend },
      set: { value in
        model.editSettings {
          var advanced = $0.advancedOptions
          advanced.select(value.defaultModel)
          $0.advancedOptions = advanced
        }
        key = ""
      }
    )
  }

  var body: some View {
    Section("Classifier") {
      Toggle("Keep filtering on this Mac", isOn: model.mailBinding(\.localOnly))
        .accessibilityIdentifier("model.localOnly")
      if model.state.settings.mailOptions.localOnly {
        Text(
          "Requires the on-device provider. Disables external evidence and sidecars. Mail still synchronizes."
        )
        .foregroundStyle(.secondary)
      }
      Picker("Provider", selection: backendBinding) {
        ForEach(ModelBackend.allCases.filter { $0 != .privateCloudCompute }, id: \.self) {
          backend in
          Text(backend.localizedTitle).tag(backend)
        }
      }.accessibilityIdentifier("model.provider")
      if backend == .privateCloudCompute {
        Text("Private Cloud Compute is unavailable. Select another provider.")
      }
      if model.state.settings.mailOptions.localOnly && backend != .onDevice {
        Text("Select On-device to classify. The current provider is blocked by local mode.")
          .accessibilityIdentifier("model.localConflict")
      }
      if backend != .onDevice {
        ProviderConsentView(model: model, backend: backend)
      }
      LabeledContent("Model", value: model.state.settings.advancedOptions.model.displayName)
      if backend == .claude {
        KeyEntryView(model: model)
      } else if [.openAI, .gemini].contains(backend) {
        SecureField("Provider API key", text: $key).accessibilityIdentifier("model.key")
        Button("Save provider key") {
          model.saveProviderKey(key); key = ""
        }
        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
        Text(
          "Stored only in Keychain. Saving does not make a paid request; use a dry run to verify."
        )
        .foregroundStyle(.secondary)
      } else {
        Text(
          backend == .onDevice
            ? "Requires Apple Intelligence on this Mac."
            : "Requires Apple’s Private Cloud Compute entitlement and an eligible distribution."
        )
        .foregroundStyle(.secondary)
      }
    }
    Section {
      DisclosureGroup("Usage and spending") { SpendingSettingsView(model: model) }
    }
  }
}

#Preview("Claude") { Form { ModelSettingsView(model: PreviewHelper.model()) }.formStyle(.grouped) }
#Preview("On-device") {
  Form { ModelSettingsView(model: PreviewHelper.model(backend: .onDevice)) }.formStyle(.grouped)
}
#Preview("OpenAI") {
  Form { ModelSettingsView(model: PreviewHelper.model(backend: .openAI)) }.formStyle(.grouped)
}
#Preview("Gemini") {
  Form { ModelSettingsView(model: PreviewHelper.model(backend: .gemini)) }.formStyle(.grouped)
}
#Preview("Private Cloud Compute") {
  Form { ModelSettingsView(model: PreviewHelper.model(backend: .privateCloudCompute)) }
    .formStyle(.grouped)
}

import SwiftUI
import SpamWiseCore

struct ModelSettingsView: View {
  let settings: SettingsModel
  let shared: SharedStateModel
  let credentials: CredentialsModel
  @State private var key = ""

  private var backend: ModelBackend { settings.settings.advancedOptions.backend }
  private var backendBinding: Binding<ModelBackend> {
    Binding(
      get: { backend },
      set: { value in
        settings.editSettings {
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
      Toggle("Keep filtering on this Mac", isOn: settings.mailBinding(\.localOnly))
        .accessibilityIdentifier("model.localOnly")
      if settings.settings.mailOptions.localOnly {
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
      if settings.settings.mailOptions.localOnly && backend != .onDevice {
        Text("Select On-device to classify. The current provider is blocked by local mode.")
          .accessibilityIdentifier("model.localConflict")
      }
      if backend != .onDevice {
        ProviderConsentView(settings: settings, backend: backend)
      }
      LabeledContent("Model", value: settings.settings.advancedOptions.model.displayName)
      if backend == .claude {
        KeyEntryView(credentials: credentials)
      } else if [.openAI, .gemini].contains(backend) {
        SecureField("Provider API key", text: $key).accessibilityIdentifier("model.key")
        Button("Save provider key") {
          credentials.saveProviderKey(key, for: backend); key = ""
        }
        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        OperationStatusView(operation: credentials.providerKey)
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
      DisclosureGroup("Usage and spending") {
        SpendingSettingsView(settings: settings, shared: shared)
      }
    }
  }
}

#Preview("Claude") { ModelSettingsPreview(backend: .claude) }
#Preview("On-device") { ModelSettingsPreview(backend: .onDevice) }
#Preview("OpenAI") { ModelSettingsPreview(backend: .openAI) }
#Preview("Gemini") { ModelSettingsPreview(backend: .gemini) }
#Preview("Private Cloud Compute") { ModelSettingsPreview(backend: .privateCloudCompute) }

/// The classifier settings over preview models.
private struct ModelSettingsPreview: View {
  let model: AppModel

  var body: some View {
    Form {
      ModelSettingsView(
        settings: model.settings,
        shared: model.shared,
        credentials: model.credentials
      )
    }.formStyle(.grouped)
  }

  init(backend: ModelBackend) { model = PreviewHelper.model(backend: backend) }
}

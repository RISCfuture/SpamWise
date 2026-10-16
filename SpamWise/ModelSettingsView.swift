import SwiftUI
import SpamWiseCore

struct ModelSettingsView: View {
  @Bindable var model: AppModel
  @State private var key = ""
  @State private var budget = BudgetLedger()

  private var backend: ModelBackend { model.state.settings.advancedOptions.backend }
  private var backendBinding: Binding<ModelBackend> {
    Binding(
      get: { backend },
      set: { value in
        model.editSettings {
          var advanced = $0.advancedOptions
          advanced.backend = value
          advanced.modelID = nil
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
        ForEach(ModelBackend.allCases, id: \.self) { backend in
          Text(backend.localizedTitle).tag(backend)
        }
      }.accessibilityIdentifier("model.provider")
      if model.state.settings.mailOptions.localOnly && backend != .onDevice {
        Text("Select On-device to classify. The current provider is blocked by local mode.")
          .accessibilityIdentifier("model.localConflict")
      }
      LabeledContent(
        "Model",
        value: model.state.settings.advancedOptions.modelID ?? backend.defaultModelID
      )
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
      DisclosureGroup("Usage and spending") {
        LabeledContent(
          "Month-to-date estimated API cost",
          value: model.monthCost.formatted(.currency(code: "USD"))
        )
        LabeledContent(
          "Authorized ceiling",
          value: budget.limitUSD.formatted(.currency(code: "USD"))
        )
        LabeledContent(
          "Conservative commitments",
          value: budget.committedUSD.formatted(.currency(code: "USD"))
        )
        HStack(alignment: .top) {
          Text(
            """
            Paid requests reserve a maximum cost before starting. Reservations include failed \
            requests and may exceed actual charges.
            """
          )
          .foregroundStyle(.secondary)
          Spacer()
          HelpButton(page: "what-data-is-sent")
        }
      }
    }.task(id: model.busy) {
      if let store = model.store, let ledger = try? await EvaluationBudget.load(store) {
        budget = ledger
      }
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

import SwiftUI
import SpamWiseCore

/// The Classifier tab: which model classifies mail, what it may receive, its key and its cost.
struct ClassifierSettingsView: View {
  let model: AppModel

  private var backend: ModelBackend { model.settings.settings.advancedOptions.backend }

  var body: some View {
    Form {
      ProviderSection(settings: model.settings)
      if backend.isCloud {
        Section {
          ProviderConsentToggle(settings: model.settings, backend: backend)
        } header: {
          Text("Mail sharing")
        } footer: {
          ProviderSharingSummary(settings: model.settings, backend: backend)
        }
      }
      APIKeySection(
        model: model.settings.settings.advancedOptions.model,
        credentials: model.credentials
      )
      Section {
        SpendingSettingsView(settings: model.settings, shared: model.shared)
      } header: {
        Text("Usage and spending")
      } footer: {
        HStack(alignment: .firstTextBaseline) {
          Text("With a limit set, paid classification pauses until next month once it is reached.")
            .foregroundStyle(.secondary)
          Spacer()
          HelpButton(page: "what-data-is-sent")
        }
      }
    }.formStyle(.grouped)
  }
}

/// Local-only mode, the provider and its model.
private struct ProviderSection: View {
  let settings: SettingsModel
  @State private var confirmsLocalOnly = false

  private var advanced: AdvancedSettings { settings.settings.advancedOptions }
  private var localOnly: Bool { settings.settings.mailOptions.localOnly }
  private var models: [ModelIdentifier] {
    ModelIdentifier.allCases.filter { $0.backend == advanced.backend }
  }
  private var localOnlyBinding: Binding<Bool> {
    Binding(
      get: { localOnly },
      set: { enabled in
        if !enabled {
          settings.allowNetworkProviders()
        } else if advanced.backend.isCloud {
          confirmsLocalOnly = true
        } else {
          settings.keepFilteringOnThisMac()
        }
      }
    )
  }
  private var backendBinding: Binding<ModelBackend> {
    Binding(get: { advanced.backend }, set: { settings.selectBackend($0) })
  }
  private var modelBinding: Binding<ModelIdentifier> {
    Binding(get: { advanced.model }, set: { settings.selectModel($0) })
  }

  var body: some View {
    Section {
      Toggle("Keep filtering on this Mac", isOn: localOnlyBinding)
        .accessibilityIdentifier("model.localOnly")
        .confirmationDialog(
          "Switch to the on-device model?",
          isPresented: $confirmsLocalOnly,
          titleVisibility: .visible
        ) {
          Button("Use On-Device Model") { settings.keepFilteringOnThisMac() }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            "Mail will be classified with Apple Intelligence on this Mac instead of \(advanced.backend.localizedTitle)."
          )
        }
      Picker("Provider", selection: backendBinding) {
        ForEach(ModelBackend.selectable, id: \.self) { backend in
          Text(backend.localizedTitle).tag(backend)
            .disabled(localOnly && backend.isCloud)
        }
      }.accessibilityIdentifier("model.provider")
      if models.count > 1 {
        Picker("Model", selection: modelBinding) {
          ForEach(models, id: \.self) { Text($0.displayName).tag($0) }
        }.accessibilityIdentifier("model.model")
      } else {
        LabeledContent("Model", value: advanced.model.displayName)
      }
      ProviderWarning(settings: settings)
    } header: {
      Text("Provider")
    } footer: {
      ProviderFooter(backend: advanced.backend, localOnly: localOnly)
    }
  }
}

/// A selection that can't classify mail until the user changes it.
private struct ProviderWarning: View {
  let settings: SettingsModel

  var body: some View {
    if settings.settings.advancedOptions.backend == .privateCloudCompute {
      StatusLabel(
        status: .failure(
          OperationFailure(
            message: String(
              localized: "Private Cloud Compute isn’t available. Select another provider."
            )
          )
        )
      )
    } else if settings.hasLocalOnlyConflict {
      StatusLabel(
        status: .failure(
          OperationFailure(
            message: String(
              localized: """
                Mail isn’t classified while this Mac is kept local and a network provider is \
                selected. Select Apple on-device or turn off Keep filtering on this Mac.
                """
            )
          )
        ),
        identifier: "model.localConflict"
      )
    }
  }
}

private struct ProviderFooter: View {
  let backend: ModelBackend
  let localOnly: Bool

  var body: some View {
    Group {
      if localOnly {
        Text(
          """
          Mail is classified with Apple Intelligence on this Mac. Network providers and lookups \
          are off; Mail still syncs as usual.
          """
        )
      } else if backend.isCloud {
        Text(
          "Mail is sent to \(backend.localizedTitle) for classification only after you allow it below."
        )
      } else {
        Text("Mail is classified with Apple Intelligence on this Mac and isn’t sent anywhere.")
      }
    }.foregroundStyle(.secondary)
  }
}

/// The selected provider's API key, saved only in Keychain.
private struct APIKeySection: View {
  let model: ModelIdentifier
  let credentials: CredentialsModel

  var body: some View {
    if model.backend.isCloud {
      Section("API key") {
        MissingProviderKeyBanner(
          credentials: credentials,
          backend: model.backend,
          isAboveKeyField: true
        )
        KeyEntryView(credentials: credentials, model: model).id(model.backend)
      }
    }
  }
}

#Preview("Claude") { ClassifierSettingsView(model: PreviewHelper.model(backend: .claude)) }
#Preview("On-device") { ClassifierSettingsView(model: PreviewHelper.model(backend: .onDevice)) }
#Preview("OpenAI") { ClassifierSettingsView(model: PreviewHelper.model(backend: .openAI)) }
#Preview("Gemini") { ClassifierSettingsView(model: PreviewHelper.model(backend: .gemini)) }
#Preview("Local-only conflict") {
  let model = PreviewHelper.model(backend: .claude)
  model.shared.state.settings.mailOptions.localOnly = true
  return ClassifierSettingsView(model: model)
}
#Preview("Private Cloud Compute") {
  ClassifierSettingsView(model: PreviewHelper.model(backend: .privateCloudCompute))
}

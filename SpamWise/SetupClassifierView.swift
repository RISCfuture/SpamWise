import SwiftUI
import SpamWiseCore

/// Setup's provider step: the provider, then its API key and mail-sharing consent.
struct SetupClassifierView: View {
  let settings: SettingsModel
  let credentials: CredentialsModel
  let readiness: ClassifierReadiness
  /// The API key typed but not yet saved, kept while the user moves between steps.
  @Binding var draftKey: String

  private var advanced: AdvancedSettings { settings.settings.advancedOptions }
  private var provider: Binding<ModelBackend> {
    Binding(
      get: { advanced.backend },
      set: { backend in
        settings.selectBackend(backend)
        draftKey = ""
      }
    )
  }

  var body: some View {
    Section("Choose how SpamWise classifies mail") {
      Text(
        "Your rules and known senders decide most mail. The provider you choose classifies the rest."
      )
      Picker("Provider", selection: provider) {
        ForEach(ModelBackend.selectable, id: \.self) { backend in
          Text(backend.localizedTitle).tag(backend)
        }
      }
      .pickerStyle(.radioGroup)
      .accessibilityIdentifier("setup.provider")
      LabeledContent("Model", value: advanced.model.displayName)
      ProviderDescription(backend: advanced.backend)
      ReadinessNote(readiness: readiness, backend: advanced.backend)
    }
    if advanced.backend.isCloud {
      Section(advanced.backend.localizedTitle) {
        KeyEntryView(
          credentials: credentials,
          model: advanced.model,
          isLocalOnly: settings.settings.mailOptions.localOnly,
          key: $draftKey
        )
        ProviderConsentView(settings: settings, backend: advanced.backend)
      }
    }
  }
}

/// Where the provider classifies mail and what it costs.
private struct ProviderDescription: View {
  let backend: ModelBackend

  var body: some View {
    Group {
      if backend.isCloud {
        Text(
          "Messages your rules can’t decide are sent to \(backend.localizedTitle) with your API key. Your provider account is charged for each one."
        )
      } else {
        Text("Mail stays on this Mac, with no API key or charges. Requires Apple Intelligence.")
      }
    }
    .foregroundStyle(.secondary)
  }
}

/// What the selected provider still needs before it classifies mail.
private struct ReadinessNote: View {
  let readiness: ClassifierReadiness
  let backend: ModelBackend

  var body: some View {
    Group {
      switch readiness {
        case .ready:
          Text("Ready to classify mail.").foregroundStyle(.secondary)
        case .needsKey, .needsConsent:
          Text(
            "To classify mail with \(backend.localizedTitle), save an API key and allow mail sharing below."
          )
        case .blockedByLocalOnly:
          Text(
            "Filtering is set to stay on this Mac, which blocks cloud providers. Choose \(ModelBackend.onDevice.localizedTitle) or change this in Settings."
          )
        case .unavailable where backend == .onDevice:
          Text(
            "Apple Intelligence isn’t available on this Mac. Turn it on in System Settings, or choose another provider."
          )
        case .unavailable:
          Text("This provider isn’t available. Choose another provider.")
      }
    }
    .accessibilityIdentifier("setup.readiness")
  }
}

#Preview("Claude, not set up") { SetupClassifierPreview(backend: .claude) }
#Preview("Claude, ready") { SetupClassifierPreview(backend: .claude, readiness: .ready) }
#Preview("On-device") { SetupClassifierPreview(backend: .onDevice, readiness: .ready) }
#Preview("On-device unavailable") {
  SetupClassifierPreview(backend: .onDevice, readiness: .unavailable)
}
#Preview("Gemini") { SetupClassifierPreview(backend: .gemini) }
#Preview("Blocked by local mode") {
  SetupClassifierPreview(backend: .openAI, readiness: .blockedByLocalOnly)
}

/// The provider step over preview models.
private struct SetupClassifierPreview: View {
  let model: AppModel
  let readiness: ClassifierReadiness
  @State private var draftKey = ""

  var body: some View {
    Form {
      SetupClassifierView(
        settings: model.settings,
        credentials: model.credentials,
        readiness: readiness,
        draftKey: $draftKey
      )
    }
    .formStyle(.grouped)
    .frame(width: 600)
  }

  init(backend: ModelBackend, readiness: ClassifierReadiness = .needsKey) {
    model = PreviewHelper.model(backend: backend)
    self.readiness = readiness
  }
}

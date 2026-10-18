import SwiftUI
import SpamWiseCore

struct EvidenceSettingsView: View {
  @Bindable var model: AppModel
  @State private var configuration = ExternalEvidenceSettings()

  var body: some View {
    Section {
      DisclosureGroup {
        Toggle(
          "Share sender domains with registration services to check domain age",
          isOn: Binding(
            get: { model.state.settings.advancedOptions.domainRegistrationLookup == true },
            set: { enabled in
              model.editSettings { $0.advancedOptions.domainRegistrationLookup = enabled }
            }
          )
        )
        Toggle(
          "Read embedded image text with on-device OCR",
          isOn: model.advancedBinding(\.imageOCR)
        )
        Text("Only embedded images are read. Remote images are never downloaded.").foregroundStyle(
          .secondary
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        Toggle(
          "Read plain-text and HTML attachments locally",
          isOn: Binding(
            get: { model.state.settings.advancedOptions.textAttachments == true },
            set: { enabled in model.editSettings { $0.advancedOptions.textAttachments = enabled } }
          )
        )
        Text(
          "PDF and Office documents remain unread. Attached text is untrusted; scripts and remote resources never run."
        )
        .foregroundStyle(.secondary)
        Toggle(
          "Look up sender and link domains in Spamhaus DBL",
          isOn: $configuration.domainBlocklist
        )
        .accessibilityIdentifier("spamhaus.enabled")
        if configuration.domainBlocklist {
          SpamhausSettingsView(configuration: $configuration)
        }
        Toggle("Local Rspamd scanner", isOn: $configuration.localRspamd)
          .accessibilityIdentifier("rspamd.enabled")
        if configuration.localRspamd {
          Text(
            """
            Sends message data to your scanner at 127.0.0.1:11333. Its configuration may use \
            online services. Disabled in local-only mode.
            """
          )
          .foregroundStyle(.secondary)
        }
        Text("Unavailable or failed evidence never counts as spam.").foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button("Save evidence settings") { save() }
          .accessibilityIdentifier("evidence.save")
          .disabled(configuration.domainBlocklist && !configuration.termsAcknowledged)
          .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text("Optional evidence").accessibilityIdentifier("evidence.disclosure")
      }
    }.onAppear {
      configuration = model.state.settings.advancedOptions.externalEvidence ?? .init()
    }
  }

  private func save() {
    let updated = configuration
    model.editSettings {
      var advanced = $0.advancedOptions
      advanced.externalEvidence = updated
      $0.advancedOptions = advanced
    }
  }
}

#Preview("Evidence") {
  Form { EvidenceSettingsView(model: PreviewHelper.model()) }.formStyle(.grouped)
}

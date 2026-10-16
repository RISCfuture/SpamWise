import SwiftUI
import SpamWiseCore

struct EvidenceSettingsView: View {
  @Bindable var model: AppModel
  @State private var configuration = ExternalEvidenceSettings()
  @State private var path = ""

  var body: some View {
    Section {
      DisclosureGroup("Optional evidence") {
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
        if configuration.domainBlocklist {
          Link(
            "Review Spamhaus usage terms",
            destination: URL(string: "https://www.spamhaus.org/blocklists/dnsbl-fair-use-policy/")!
          )
          Toggle("I meet the lookup service’s usage terms", isOn: $configuration.termsAcknowledged)
          TextField("DNS resolver address", text: $configuration.resolverAddress)
          Text("Queries share domain names with your resolver and the lookup service.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if DistributionCapabilities.externalPrograms {
          TextField("Optional local rspamc path", text: $path)
        }
        Text("Unavailable or failed evidence never counts as spam.").foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button("Save evidence settings") { save() }
          .disabled(configuration.domainBlocklist && !configuration.termsAcknowledged)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }.onAppear {
      configuration = model.state.settings.advancedOptions.externalEvidence ?? .init()
      path = configuration.rspamcPath ?? ""
    }
  }

  private func save() {
    var saved = configuration
    saved.rspamcPath = !DistributionCapabilities.externalPrograms || path.isEmpty ? nil : path
    let updated = saved
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

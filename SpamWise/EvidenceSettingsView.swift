import SwiftUI
import SpamWiseCore

struct EvidenceSettingsView: View {
  @Bindable var model: AppModel
  @State private var configuration = ExternalEvidenceSettings()
  @State private var path = ""
  var body: some View {
    Section("Optional evidence") {
      Toggle("Read embedded image text with on-device OCR", isOn: model.advancedBinding(\.imageOCR))
      Text(
        """
        OCR reads bounded embedded PNG and JPEG images. It never downloads remote images; \
        unavailable text remains unknown.
        """
      ).font(.caption)
      Toggle(
        "Look up sender and link domains in Spamhaus DBL",
        isOn: $configuration.domainBlocklist
      )
      Link(
        "Review Spamhaus usage terms",
        destination: URL(string: "https://www.spamhaus.org/blocklists/dnsbl-fair-use-policy/")!
      )
      Toggle("I meet the lookup service’s usage terms", isOn: $configuration.termsAcknowledged)
      TextField("DNS resolver address", text: $configuration.resolverAddress)
      Text(
        """
        Queries disclose domain names to the resolver and reputation service. Failed, denied, or \
        malformed results remain unknown.
        """
      ).font(.caption)
      TextField("Optional local rspamc path", text: $path)
      Text(
        """
        Rspamd must already be installed locally. The app sandbox may prevent execution; an \
        unavailable sidecar supplies no spam evidence.
        """
      ).font(.caption)
      Button("Save evidence settings") {
        var saved = configuration
        saved.rspamcPath = path.isEmpty ? nil : path
        let updated = saved
        model.editSettings {
          var advanced = $0.advancedOptions; advanced.externalEvidence = updated
          $0.advancedOptions = advanced
        }
      }.disabled(configuration.domainBlocklist && !configuration.termsAcknowledged)
    }.onAppear {
      configuration = model.state.settings.advancedOptions.externalEvidence ?? .init()
      path = configuration.rspamcPath ?? ""
    }
  }
}

#Preview { Form { EvidenceSettingsView(model: PreviewHelper.model()) } }

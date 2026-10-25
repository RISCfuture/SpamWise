import SwiftUI
import SpamWiseCore

/// Optional evidence: what SpamWise reads on this Mac, and what it looks up over the network.
struct EvidenceSettingsView: View {
  let settings: SettingsModel
  let credentials: CredentialsModel

  var body: some View {
    LocalAnalysisSection(settings: settings)
    NetworkLookupsSection(settings: settings)
    if settings.evidence.domainBlocklist {
      SpamhausSettingsView(settings: settings, credentials: credentials)
    }
  }
}

private struct LocalAnalysisSection: View {
  let settings: SettingsModel

  var body: some View {
    Section {
      Toggle(
        "Read embedded image text with on-device OCR",
        isOn: settings.advancedBinding(\.imageOCR)
      )
      Toggle(
        "Read plain-text and HTML attachments locally",
        isOn: settings.advancedBinding(\.textAttachments)
      )
    } header: {
      Text("Local analysis")
    } footer: {
      Text(
        """
        Only images inside the message are read; remote images are never downloaded. PDF and \
        Office attachments aren’t read, and nothing in an attachment ever runs.
        """
      )
      .foregroundStyle(.secondary)
    }
  }
}

private struct NetworkLookupsSection: View {
  let settings: SettingsModel

  private var localOnly: Bool { settings.settings.mailOptions.localOnly }

  var body: some View {
    Section {
      Group {
        Toggle(
          "Share sender domains with registration services to check domain age",
          isOn: settings.advancedBinding(\.domainRegistrationLookup)
        )
        Toggle(
          "Look up sender and link domains in Spamhaus DBL",
          isOn: settings.evidenceBinding(\.domainBlocklist)
        )
        .accessibilityIdentifier("spamhaus.enabled")
        Toggle("Scan with my Rspamd server", isOn: settings.evidenceBinding(\.localRspamd))
          .accessibilityIdentifier("rspamd.enabled")
      }.disabled(localOnly)
    } header: {
      Text("Network lookups")
    } footer: {
      NetworkLookupsFooter(localOnly: localOnly, rspamdEnabled: settings.evidence.localRspamd)
    }
  }
}

/// What the network lookups share, including the whole message while Rspamd is on.
private struct NetworkLookupsFooter: View {
  let localOnly: Bool
  let rspamdEnabled: Bool

  private var rspamdAddress: String {
    let endpoint = RspamdLookup.endpoint
    return [endpoint.host(), endpoint.port.map(String.init)].compactMap(\.self)
      .joined(separator: ":")
  }

  var body: some View {
    VStack(alignment: .leading) {
      if localOnly {
        Text("Unavailable while Keep filtering on this Mac is on in Provider settings.")
      } else {
        Text(
          "Domain-age and Spamhaus lookups share only sender and link domain names, never message content."
        )
        if rspamdEnabled {
          Text(
            """
            Rspamd receives the whole message at \(rspamdAddress), and its own configuration may \
            use online services.
            """
          )
        }
        Text("A lookup that fails never counts against a message.")
      }
    }
    .foregroundStyle(.secondary)
  }
}

#Preview("Evidence") {
  let model = PreviewHelper.model()
  Form { EvidenceSettingsView(settings: model.settings, credentials: model.credentials) }
    .formStyle(.grouped)
}
#Preview("Local only") {
  let model = PreviewHelper.model(backend: .onDevice)
  model.shared.state.settings.mailOptions.localOnly = true
  return Form { EvidenceSettingsView(settings: model.settings, credentials: model.credentials) }
    .formStyle(.grouped)
}

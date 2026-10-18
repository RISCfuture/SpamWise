import SwiftUI
import SpamWiseCore

struct SpamhausSettingsView: View {
  @Binding var configuration: ExternalEvidenceSettings
  @State private var key = ""
  @State private var keyStatus = ""

  private var transport: Binding<SpamhausTransport> {
    Binding(
      get: { configuration.spamhausTransport ?? .publicDNS },
      set: {
        configuration.spamhausTransport = $0
        configuration.termsAcknowledged = false
      }
    )
  }

  var body: some View {
    Picker("Spamhaus service", selection: transport) {
      Text("HTTPS subscription or trial").tag(SpamhausTransport.https)
        .accessibilityIdentifier("spamhaus.transport.https")
      Text("Public DNS mirrors").tag(SpamhausTransport.publicDNS)
        .accessibilityIdentifier("spamhaus.transport.publicDNS")
    }
    .accessibilityIdentifier("spamhaus.transport")
    if configuration.spamhausTransport == .https {
      Link(
        "Review HTTPS access requirements",
        destination: URL(
          string:
            "https://docs.spamhaus.com/datasets/docs/source/70-access-methods/web-query-service/000-intro.html"
        )!
      )
      Text("Requires DNS Blocklists via HTTPS access. Free DNS-query keys may not include it.")
        .foregroundStyle(.secondary)
      SecureField("Spamhaus HTTPS query key", text: $key)
        .accessibilityIdentifier("spamhaus.key")
      Button("Save query key") { saveKey() }
        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("spamhaus.saveKey")
      if !keyStatus.isEmpty {
        Text(keyStatus).foregroundStyle(.secondary)
          .accessibilityIdentifier("spamhaus.keyStatus")
      }
    } else {
      Link(
        "Review Spamhaus usage terms",
        destination: SpamhausConfiguration.termsURL
      )
      TextField("DNS resolver address", text: $configuration.resolverAddress)
    }
    Toggle("I meet the lookup service’s usage terms", isOn: $configuration.termsAcknowledged)
      .accessibilityIdentifier("spamhaus.consent")
    Text("Shares sender and link domains with the selected service. Disabled in local-only mode.")
      .foregroundStyle(.secondary)
      .onAppear { refreshKeyStatus() }
  }

  private func refreshKeyStatus() {
    keyStatus =
      (try? APIKeychain(service: APIKeychain.spamhausService).read()) == nil
      ? String(localized: "No query key saved") : String(localized: "Query key saved in Keychain")
  }

  private func saveKey() {
    do {
      try APIKeychain(service: APIKeychain.spamhausService).save(key)
      key = ""
      refreshKeyStatus()
    } catch {
      key = ""
      keyStatus = String(localized: "Could not save the query key in Keychain")
    }
  }
}

#Preview("HTTPS") {
  @Previewable @State var configuration = PreviewHelper.spamhaus(.https)
  Form { SpamhausSettingsView(configuration: $configuration) }.formStyle(.grouped)
}

#Preview("Public DNS") {
  @Previewable @State var configuration = PreviewHelper.spamhaus(.publicDNS)
  Form { SpamhausSettingsView(configuration: $configuration) }.formStyle(.grouped)
}

import SwiftUI
import SpamWiseCore

/// The Spamhaus service, its terms, and its query key or resolver; lookups wait for the terms.
struct SpamhausSettingsView: View {
  let settings: SettingsModel
  let credentials: CredentialsModel

  private var evidence: ExternalEvidenceSettings { settings.evidence }
  private var transport: Binding<SpamhausTransport> {
    Binding(
      get: { evidence.spamhausTransport ?? .publicDNS },
      set: { settings.selectSpamhausService($0) }
    )
  }

  var body: some View {
    Section {
      Group {
        Picker("Spamhaus service", selection: transport) {
          Text("HTTPS subscription or trial").tag(SpamhausTransport.https)
            .accessibilityIdentifier("spamhaus.transport.https")
          Text("Public DNS mirrors").tag(SpamhausTransport.publicDNS)
            .accessibilityIdentifier("spamhaus.transport.publicDNS")
        }
        .accessibilityIdentifier("spamhaus.transport")
        if evidence.spamhausTransport == .https {
          SpamhausKeyEntry(credentials: credentials)
        } else {
          ResolverAddressField(draft: settings.resolverAddress)
        }
        Toggle(
          "I meet the lookup service’s usage terms",
          isOn: settings.evidenceBinding(\.termsAcknowledged)
        )
        .accessibilityIdentifier("spamhaus.consent")
        if !evidence.termsAcknowledged {
          StatusLabel(
            status: .failure(
              OperationFailure(
                message: String(localized: "No lookups are made until you accept the terms.")
              )
            ),
            identifier: "spamhaus.consentRequired"
          )
        }
      }.disabled(settings.settings.mailOptions.localOnly)
    } header: {
      Text("Spamhaus")
    } footer: {
      SpamhausFooter(usesHTTPS: evidence.spamhausTransport == .https)
    }
  }
}

private struct SpamhausKeyEntry: View {
  let credentials: CredentialsModel
  @State private var key = ""

  var body: some View {
    SecureField("Spamhaus HTTPS query key", text: $key, prompt: Text("Query key"))
      .accessibilityIdentifier("spamhaus.key")
      .onSubmit(save)
    Button("Save query key", action: save)
      .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityIdentifier("spamhaus.saveKey")
    OperationStatusView(operation: credentials.spamhausKey, identifier: "spamhaus.keyStatus")
      .onAppear { credentials.refreshSpamhausKeyStatus() }
  }

  private func save() {
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    credentials.saveSpamhausKey(key)
    key = ""
  }
}

private struct ResolverAddressField: View {
  @Bindable var draft: SettingDraft<String>

  var body: some View {
    TextField(
      "DNS resolver address",
      text: $draft.value,
      prompt: Text(verbatim: ExternalEvidenceSettings().resolverAddress)
    )
    .commitsDraft(draft)
    if !draft.isAcceptable {
      StatusLabel(
        status: .failure(
          OperationFailure(
            message: String(
              localized:
                "Not saved. Enter an IPv4 address, such as \(ExternalEvidenceSettings().resolverAddress)."
            )
          )
        )
      )
    }
  }
}

private struct SpamhausFooter: View {
  private static let accessRequirementsURL = URL(
    string:
      "https://docs.spamhaus.com/datasets/docs/source/70-access-methods/web-query-service/000-intro.html"
  )
  let usesHTTPS: Bool

  var body: some View {
    VStack(alignment: .leading) {
      Text("Sender and link domains are shared with the selected service.")
      if usesHTTPS {
        Text(
          "The HTTPS service needs a subscription or trial key; free DNS keys may not include it."
        )
        if let url = Self.accessRequirementsURL {
          Link("Review HTTPS access requirements", destination: url)
        }
      } else {
        Link("Review Spamhaus usage terms", destination: SpamhausConfiguration.termsURL)
      }
    }
    .foregroundStyle(.secondary)
  }
}

#Preview("HTTPS") {
  let model = PreviewHelper.model()
  model.shared.state.settings.advancedOptions.externalEvidence = PreviewHelper.spamhaus(.https)
  return Form { SpamhausSettingsView(settings: model.settings, credentials: model.credentials) }
    .formStyle(.grouped)
}
#Preview("Public DNS") {
  let model = PreviewHelper.model()
  model.shared.state.settings.advancedOptions.externalEvidence = PreviewHelper.spamhaus(.publicDNS)
  return Form { SpamhausSettingsView(settings: model.settings, credentials: model.credentials) }
    .formStyle(.grouped)
}

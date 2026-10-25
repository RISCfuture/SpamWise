import SwiftUI
import SpamWiseCore

/// Permission for one provider to receive mail context, with what it receives.
struct ProviderConsentView: View {
  let settings: SettingsModel
  let backend: ModelBackend

  var body: some View {
    ProviderConsentToggle(settings: settings, backend: backend)
    ProviderSharingSummary(settings: settings, backend: backend)
  }
}

/// Grants or withdraws one provider's permission to receive mail context.
struct ProviderConsentToggle: View {
  let settings: SettingsModel
  let backend: ModelBackend

  private var permission: Binding<Bool> {
    Binding(
      get: { settings.settings.advancedOptions.mailSharingConsent.contains(backend) },
      set: { settings.setSharingConsent($0, for: backend) }
    )
  }

  var body: some View {
    Toggle("Allow mail context to be sent to \(backend.localizedTitle)", isOn: permission)
      .accessibilityIdentifier("provider.consent")
  }
}

/// What a provider receives with each message, and how to stop it.
struct ProviderSharingSummary: View {
  let settings: SettingsModel
  let backend: ModelBackend

  private var termsURL: URL? {
    switch backend {
      case .claude:
        URL(
          string:
            "https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data"
        )
      case .openAI: URL(string: "https://developers.openai.com/api/docs/guides/your-data")
      case .gemini: URL(string: "https://ai.google.dev/gemini-api/terms")
      case .onDevice, .privateCloudCompute: nil
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      Text(
        """
        Each message’s sender, subject, shortened text and evidence are sent with your policy and \
        up to \(settings.settings.correctionLimit) similar corrections from the same account. Mail \
        can contain sensitive information.
        """
      )
      Text(
        """
        Only new mail is sent automatically; older mail is sent only when you preview it. Turning \
        this off stops future requests, but requests already sent can’t be recalled.
        """
      )
      Text(
        """
        Keys stay in Keychain until you remove them. Forget Connection removes a saved IMAP \
        password.
        """
      )
      if backend == .gemini {
        Text(
          """
          Google’s unpaid-service terms allow model improvement and human review. Do not send \
          personal mail under those terms. Confirm which terms apply to your project and region.
          """
        )
      }
      if let termsURL {
        Link("Provider data and retention terms", destination: termsURL)
          .accessibilityIdentifier("provider.privacyTerms")
      }
    }
    .foregroundStyle(.secondary)
  }
}

#Preview("Mail sharing off") {
  Form { ProviderConsentView(settings: PreviewHelper.model().settings, backend: .claude) }
    .formStyle(.grouped)
}
#Preview("Mail sharing on") {
  let model = PreviewHelper.model(backend: .openAI)
  model.shared.state.settings.advancedOptions.mailSharingConsent = [.openAI]
  return Form { ProviderConsentView(settings: model.settings, backend: .openAI) }
    .formStyle(.grouped)
}
#Preview("Gemini disclosure") {
  Form {
    ProviderConsentView(settings: PreviewHelper.model(backend: .gemini).settings, backend: .gemini)
  }
  .formStyle(.grouped)
  .frame(width: 600)
}

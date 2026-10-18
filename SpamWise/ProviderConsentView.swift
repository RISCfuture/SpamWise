import SwiftUI
import SpamWiseCore

struct ProviderConsentView: View {
  let model: AppModel
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
  private var permission: Binding<Bool> {
    Binding(
      get: { model.state.settings.advancedOptions.mailSharingConsent.contains(backend) },
      set: { granted in
        model.editSettings {
          var consent = $0.advancedOptions.mailSharingConsent
          if granted { consent.insert(backend) } else { consent.remove(backend) }
          $0.advancedOptions.mailSharingConsent = consent
        }
      }
    )
  }
  var body: some View {
    Toggle("Allow mail context to be sent to \(backend.localizedTitle)", isOn: permission)
      .accessibilityIdentifier("provider.consent")
    DisclosureGroup("What is shared") {
      Text(
        """
        Includes the message’s sender, subject, shortened text and evidence, your preferences, and \
        up to \(model.state.settings.correctionLimit, format: .number) similar corrections from \
        the same account, each with its sender domain, subject, a short excerpt and your label. \
        Enabled attachment/OCR text may be included. Mail can contain sensitive information.
        """
      ).foregroundStyle(.secondary)
      Text(
        """
        Automatic filtering covers only mail received after setup. Older mail is sent to your \
        provider only when you preview it.
        """
      ).foregroundStyle(.secondary)
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
      Text(
        """
        Turn this off to stop future requests. Requests already sent cannot be recalled. Provider \
        retention terms apply; keys stay in Keychain.
        """
      ).foregroundStyle(.secondary)
    }
  }
}

#Preview("Mail sharing off") {
  Form { ProviderConsentView(model: PreviewHelper.model(), backend: .claude) }
}
#Preview("Mail sharing on") {
  let model = PreviewHelper.model(backend: .openAI)
  model.state.settings.advancedOptions.mailSharingConsent = [.openAI]
  return Form { ProviderConsentView(model: model, backend: .openAI) }
}
#Preview("Gemini disclosure") {
  Form { ProviderConsentView(model: PreviewHelper.model(backend: .gemini), backend: .gemini) }
    .formStyle(.grouped)
    .frame(width: 600)
}

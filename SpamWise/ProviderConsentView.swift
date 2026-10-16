import SwiftUI
import SpamWiseCore

struct ProviderConsentView: View {
  let model: AppModel
  let backend: ModelBackend

  private var permission: Binding<Bool> {
    Binding(
      get: { model.state.settings.advancedOptions.mailSharingConsent?.contains(backend) == true },
      set: { granted in
        model.editSettings {
          var consent = $0.advancedOptions.mailSharingConsent ?? []
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
        Includes sender, subject, shortened text, evidence, preferences and correction examples. \
        Enabled attachment/OCR text may be included. Mail can contain sensitive information.
        """
      ).foregroundStyle(.secondary)
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

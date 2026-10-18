import SwiftUI
import SpamWiseCore

/**
 A persistent warning while the selected provider needs an API key that Keychain doesn't hold.

 Shows nothing while the key is saved, for providers that need no key, or when Keychain can't
 answer, so a locked Keychain is never reported as a missing key. The app's monitor keeps
 ``CredentialsModel/missingProviderKey`` current.
 */
struct MissingProviderKeyBanner: View {
  let credentials: CredentialsModel
  let backend: ModelBackend

  var body: some View {
    if credentials.missingProviderKey == backend {
      WarningLabel(
        "No API key for \(backend.localizedTitle). New mail isn’t classified until you add one in Settings."
      )
      .accessibilityIdentifier("credentials.missingKey")
    }
  }
}

#Preview("Missing key") {
  let model = PreviewHelper.model(backend: .openAI)
  VStack { MissingProviderKeyBanner(credentials: model.credentials, backend: .openAI) }
    .frame(width: 480, height: 80)
    .task { await model.credentials.checkProviderKeyIfDue(for: .openAI) }
}

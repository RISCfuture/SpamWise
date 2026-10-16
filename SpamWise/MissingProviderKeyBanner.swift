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
  /// Whether the banner sits above the key field, rather than in a window without one.
  var isAboveKeyField = false

  var body: some View {
    if credentials.missingProviderKey == backend {
      Group {
        if isAboveKeyField {
          WarningLabel(
            "No API key for \(backend.localizedTitle). New mail isn’t classified until you add one below."
          )
        } else {
          WarningLabel(
            "No API key for \(backend.localizedTitle). New mail isn’t classified until you add one in Settings."
          )
        }
      }
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
#Preview("Missing key above the key field") {
  let model = PreviewHelper.model(backend: .openAI)
  Form {
    MissingProviderKeyBanner(
      credentials: model.credentials,
      backend: .openAI,
      isAboveKeyField: true
    )
  }
  .formStyle(.grouped)
  .frame(width: 480, height: 120)
  .task { await model.credentials.checkProviderKeyIfDue(for: .openAI) }
}

import SwiftUI
import SpamWiseCore

extension AppModel {
  func mailBinding<T: Sendable>(
    _ key: any WritableKeyPath<MailPreferences, T> & Sendable
  ) -> Binding<T> {
    Binding(
      get: { self.state.settings.mailOptions[keyPath: key] },
      set: { value in
        self.editSettings { $0.mailOptions[keyPath: key] = value }
      }
    )
  }
  func saveProviderKey(_ key: String) {
    let backend = state.settings.advancedOptions.backend
    run { [self] in
      let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !credential.isEmpty else { throw ClassificationError.missingCredential }
      try APIKeychain(service: ConfiguredClassifier.credentialService(for: backend)).save(
        credential
      )
      status = String(localized: "Provider key saved in Keychain. Use a dry run to verify.")
    }
  }
  func advancedBinding<T: Sendable>(
    _ key: any WritableKeyPath<AdvancedSettings, T> & Sendable
  ) -> Binding<T> {
    Binding(
      get: { self.state.settings.advancedOptions[keyPath: key] },
      set: { value in
        self.editSettings {
          var advanced = $0.advancedOptions; advanced[keyPath: key] = value
          $0.advancedOptions = advanced
        }
      }
    )
  }
}

extension AppModel {
  func settingBinding<T: Sendable>(_ key: any WritableKeyPath<SpamWiseCore.Settings, T> & Sendable)
    -> Binding<T>
  {
    Binding(get: { self.state.settings[keyPath: key] }, set: { self.setSetting(key, to: $0) })
  }
}

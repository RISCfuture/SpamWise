import Foundation
import SpamWiseCore

/// A secret SpamWise keeps in the shared Keychain.
enum StoredCredential: Hashable, Identifiable, Sendable {
  /// A paid model provider's API key.
  case provider(ModelBackend)
  /// The Spamhaus HTTPS query key.
  case spamhaus
  /// The saved IMAP connection's password, under its Keychain service.
  case imap(service: String)

  /// Providers whose API keys SpamWise stores.
  static let providers: [ModelBackend] = [.claude, .openAI, .gemini]

  var id: String {
    switch self {
      case .provider(let backend): "provider.\(backend.rawValue)"
      case .spamhaus: "spamhaus"
      case .imap: "imap"
    }
  }

  /// Position in lists: provider keys, then the Spamhaus key, then the IMAP password.
  var displayOrder: Int {
    switch self {
      case .provider(let backend): Self.providers.firstIndex(of: backend) ?? 0
      case .spamhaus: Self.providers.count
      case .imap: Self.providers.count + 1
    }
  }

  /// The Keychain item holding the secret.
  var keychain: APIKeychain? {
    switch self {
      case .provider(let backend): APIKeychain(backend: backend)
      case .spamhaus: APIKeychain(service: APIKeychain.spamhausService)
      case .imap(let service): APIKeychain(service: service)
    }
  }

  var localizedTitle: String {
    switch self {
      case .provider(let backend): String(localized: "\(backend.localizedTitle) API key")
      case .spamhaus: String(localized: "Spamhaus query key")
      case .imap: String(localized: "IMAP password or token")
    }
  }

  /// Whether Keychain holds a credential.
  enum State: Sendable {
    case saved, notSaved
    /// Keychain couldn't answer, such as when it is locked.
    case unknown
  }
}

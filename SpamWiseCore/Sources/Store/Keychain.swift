public import Foundation
public import Classifier
import Security

/// Failures while accessing or storing credentials.
public protocol CredentialFailure: Error {}

/// Credential lookup or update failures.
public enum KeychainError: CredentialFailure, Sendable, LocalizedError {
  /// Keychain returned an unsuccessful status.
  case status(OSStatus)
  /// No nonempty credential is available.
  case missing
  /// General description of the failed credential operation.
  public var errorDescription: String? {
    String(localized: "The credential is unavailable.", bundle: .module)
  }
  /// The credential prerequisite or Keychain status that caused the failure.
  public var failureReason: String? {
    switch self {
      case .missing: String(localized: "No nonempty credential was found.", bundle: .module)
      case .status(let status):
        String(
          localized: "Keychain returned status \(status, format: .number.grouping(.never)).",
          bundle: .module
        )
    }
  }
  /// What the user can do to make the credential available again.
  public var recoverySuggestion: String? {
    switch self {
      case .missing:
        String(localized: "Enter the key or password again in SpamWise Settings.", bundle: .module)
      case .status:
        String(
          localized:
            "Make sure your Mac is unlocked, then try again. If it keeps failing, restart your Mac.",
          bundle: .module
        )
    }
  }
}
/// One credential, such as a model provider or Spamhaus key, in the shared data-protection Keychain group.
public struct APIKeychain: Sendable {
  /// Keychain access group shared by the app and extension.
  public static let accessGroup = "2NFSK2WB24.codes.tim.SpamWise.shared"
  /// Separate credential namespace for the user's Spamhaus HTTPS query key.
  public static let spamhausService = servicePrefix + "spamhaus"
  private static let servicePrefix = "codes.tim.SpamWise."
  private static let account = "user-api-key"
  private let service: String
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: Self.account, kSecAttrAccessGroup as String: Self.accessGroup,
      kSecUseDataProtectionKeychain as String: true
    ]
  }
  /// Accesses the credential stored under an explicit service name.
  public init(service: String) { self.service = service }
  /// Accesses a paid provider's API key; nil for Apple models, which need no credential.
  public init?(backend: ModelBackend) {
    switch backend {
      case .claude: self.init(service: Self.servicePrefix + "anthropic")
      case .openAI: self.init(service: Self.servicePrefix + "openai")
      case .gemini: self.init(service: Self.servicePrefix + "gemini")
      case .onDevice, .privateCloudCompute: return nil
    }
  }
  /// Returns the stored credential, throwing ``KeychainError/missing`` when none is stored or it is empty or unreadable.
  public func read() throws -> String {
    var query = query; query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { throw KeychainError.missing }
    guard status == errSecSuccess else { throw KeychainError.status(status) }
    guard let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
    else { throw KeychainError.missing }
    return key
  }
  /**
   Whether a credential is stored, checked from its attributes without reading the secret.

   - Throws: ``KeychainError/status(_:)`` when Keychain cannot answer, such as a missing
     entitlement or a locked keychain; a missing item returns false.
   */
  public func exists() throws -> Bool {
    var query = query; query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
      case errSecSuccess: return true
      case errSecItemNotFound: return false
      default: throw KeychainError.status(status)
    }
  }
  /// Removes the credential; removing one that is not stored succeeds.
  public func delete() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.status(status)
    }
  }
  /// Writes a nonempty credential, preserving significant password whitespace when explicitly requested.
  public func save(_ key: String, preserveWhitespace: Bool = false) throws {
    let value = Data(
      (preserveWhitespace ? key : key.trimmingCharacters(in: .whitespacesAndNewlines)).utf8
    )
    guard !value.isEmpty else { throw KeychainError.missing }
    let updated = SecItemUpdate(query as CFDictionary, [kSecValueData: value] as CFDictionary)
    if updated == errSecItemNotFound {
      var attributes = query; attributes[kSecValueData as String] = value
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let status = SecItemAdd(attributes as CFDictionary, nil)
      guard status == errSecSuccess else { throw KeychainError.status(status) }
    } else if updated != errSecSuccess {
      throw KeychainError.status(updated)
    }
  }
}

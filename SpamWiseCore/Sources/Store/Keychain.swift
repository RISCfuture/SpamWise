public import Foundation
import Security

/// Failures while accessing or storing credentials.
public protocol CredentialFailure: Error {}

/// Credential lookup or update failures.
public enum KeychainError: CredentialFailure, Sendable, LocalizedError {
  /// Keychain returned an unsuccessful status or unusable credential data.
  case status(OSStatus)
  /// No nonempty credential is available.
  case missing
  /// General description of the failed credential operation.
  public var errorDescription: String? { String(localized: "The credential is unavailable.") }
  /// The credential prerequisite or Keychain status that caused the failure.
  public var failureReason: String? {
    switch self {
      case .missing: String(localized: "No nonempty credential was found.")
      case .status(let status):
        String(localized: "Keychain returned status \(status, format: .number.grouping(.never)).")
    }
  }
}
/// Stores the user's API key in the shared data-protection Keychain group.
public struct APIKeychain: Sendable {
  /// Keychain access group shared by the app and extension.
  public static let accessGroup = "2NFSK2WB24.codes.tim.SpamWise.shared"
  private let service: String
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "user-api-key", kSecAttrAccessGroup as String: Self.accessGroup,
      kSecUseDataProtectionKeychain as String: true
    ]
  }
  /// Creates an APIKeychain with the supplied configuration.
  public init(service: String = "codes.tim.SpamWise.anthropic") { self.service = service }
  /// Reads durable state or credentials, throwing when access is unavailable.
  public func read() throws -> String {
    var query = query; query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { throw KeychainError.missing }
    guard status == errSecSuccess, let data = result as? Data,
      let key = String(data: data, encoding: .utf8)
    else { throw KeychainError.status(status) }
    return key
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

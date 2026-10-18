public import Foundation
public import SpamWiseCore
import Security
import LocalAuthentication

/// A secret reference; JSON configuration never contains the resolved password or bearer token.
public struct IMAPCredentialReference: Codable, Sendable {
  private static let maximumEnvironmentNameBytes = 128
  private static let maximumKeychainReferenceBytes = 256
  /// Name of an explicitly supplied process environment variable.
  public var environment: String?
  /// Exact login Keychain generic-password service when no environment reference is supplied.
  public var keychainService: String?
  /// Exact login Keychain account paired with the service.
  public var keychainAccount: String?
  /// Authentication mechanism; false selects TLS-protected LOGIN.
  public var oauthBearer: Bool
  /// Creates a secret reference with exactly one source.
  public init(
    environment: String? = nil,
    keychainService: String? = nil,
    keychainAccount: String? = nil,
    oauthBearer: Bool = false
  ) {
    self.environment = environment; self.keychainService = keychainService
    self.keychainAccount = keychainAccount; self.oauthBearer = oauthBearer
  }
  /// Decodes references with password authentication as the default.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    environment = try values.decodeIfPresent(String.self, forKey: .environment)
    keychainService = try values.decodeIfPresent(String.self, forKey: .keychainService)
    keychainAccount = try values.decodeIfPresent(String.self, forKey: .keychainAccount)
    oauthBearer = try values.decodeIfPresent(Bool.self, forKey: .oauthBearer) ?? false
    try validate()
  }
  /// Resolves an ephemeral secret without printing or persisting it.
  public func resolve() throws -> IMAPCredential {
    let secret = try resolvedSecret()
    return oauthBearer ? .oauthBearer(secret) : .password(secret)
  }
  /// Reads the referenced secret without requesting interactive Keychain authentication.
  public func resolvedSecret() throws -> String {
    try validate()
    let secret: String
    if let environment {
      guard let value = ProcessInfo.processInfo.environment[environment], !value.isEmpty else {
        throw IMAPError.authenticationFailed
      }
      secret = value
    } else {
      let context = LAContext()
      context.interactionNotAllowed = true
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService ?? "",
        kSecAttrAccount as String: keychainAccount ?? "",
        kSecMatchLimit as String: kSecMatchLimitOne, kSecReturnData as String: true,
        kSecUseAuthenticationContext as String: context
      ]
      var result: CFTypeRef?
      let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
      guard status == errSecSuccess, let data = result as? Data,
        let value = String(data: data, encoding: .utf8), !value.isEmpty
      else {
        throw IMAPError.authenticationFailed
      }
      secret = value
    }
    return secret
  }
  func validate() throws {
    if let environment {
      guard keychainService == nil, keychainAccount == nil, !environment.isEmpty,
        environment.utf8.count <= Self.maximumEnvironmentNameBytes,
        environment.utf8.allSatisfy({
          $0 == 95 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        })
      else {
        throw IMAPError.invalidConfiguration
      }
    } else {
      guard let keychainService, !keychainService.isEmpty, let keychainAccount,
        !keychainAccount.isEmpty,
        keychainService.utf8.count <= Self.maximumKeychainReferenceBytes,
        keychainAccount.utf8.count <= Self.maximumKeychainReferenceBytes
      else { throw IMAPError.invalidConfiguration }
    }
  }
  private enum CodingKeys: String, CodingKey {
    case environment, keychainService, keychainAccount, oauthBearer
  }
}

/// Bounded headless connection configuration with references to secrets and an optional explicit state store.
public struct IMAPDaemonConfiguration: Codable, Sendable {
  private static let maximumConfigurationBytes = 65_536
  private static let maximumStatePathBytes = 4096
  /// Explicit account endpoint and identity.
  public var account: IMAPConfiguration
  /// IMAP password or OAuth secret reference.
  public var credential: IMAPCredentialReference
  /// Optional state path for an unsigned command-line installation; absent uses the signed App Group.
  public var statePath: String?
  /// Explicit paid-provider references keyed by ModelBackend raw value; nil uses shared Keychain.
  public var providerCredentials: [String: IMAPCredentialReference]?
  /// Decodes at most 64 KiB and rejects unknown fields, including accidentally embedded secrets.
  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= maximumConfigurationBytes,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(object.keys).isSubset(of: ["account", "credential", "statePath", "providerCredentials"]),
      let account = object["account"] as? [String: Any],
      Set(account.keys).isSubset(of: ["id", "host", "port", "username", "allowsActions"]),
      let credential = object["credential"] as? [String: Any],
      Set(credential.keys).isSubset(of: [
        "environment", "keychainService", "keychainAccount", "oauthBearer"
      ])
    else {
      throw IMAPError.invalidConfiguration
    }
    if let raw = object["providerCredentials"] {
      guard let providers = raw as? [String: Any],
        Set(providers.keys).isSubset(of: ["claude", "openAI", "gemini"])
      else { throw IMAPError.invalidConfiguration }
      for rawReference in providers.values {
        guard let reference = rawReference as? [String: Any],
          Set(reference.keys).isSubset(of: ["environment", "keychainService", "keychainAccount"])
        else { throw IMAPError.invalidConfiguration }
      }
    }
    let result = try JSONDecoder().decode(Self.self, from: data)
    try result.account.validate(); try result.credential.validate()
    guard result.statePath.map({ !$0.isEmpty && $0.utf8.count <= maximumStatePathBytes }) ?? true
    else {
      throw IMAPError.invalidConfiguration
    }
    return result
  }
}

extension StateRepository {
  /// Records Apple Mail's Inbox and Junk role checks keyed by account.
  ///
  /// Validated accounts Mail no longer reports lose validation; IMAP accounts with saved
  /// validation evidence keep theirs.
  /// - Parameters:
  ///   - unambiguousByAccount: Whether each checked account's roles resolved uniquely.
  ///   - store: The shared state store.
  ///   - reportedAccounts: Every account Apple Mail currently reports.
  public static func recordAppleMailRoles(
    _ unambiguousByAccount: [String: Bool],
    in store: Store,
    reportedAccounts: Set<String>
  ) async throws {
    let imapAccounts = try await IMAPAccountValidation.accountIDs(in: store)
    try await recordMailboxRoles(
      unambiguousByAccount,
      in: store,
      currentAccounts: reportedAccounts.union(imapAccounts)
    )
  }
}

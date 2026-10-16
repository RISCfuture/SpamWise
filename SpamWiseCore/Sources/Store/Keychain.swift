import Foundation
import Security

public enum KeychainError: Error, Sendable { case status(OSStatus), missing }
public struct APIKeychain: Sendable {
    public static let accessGroup = "2NFSK2WB24.codes.tim.SpamWise.shared"
    public init() {}
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "codes.tim.SpamWise.anthropic", kSecAttrAccount as String: "user-api-key", kSecAttrAccessGroup as String: Self.accessGroup, kSecUseDataProtectionKeychain as String: true] }
    public func read() throws -> String {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw KeychainError.missing }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw KeychainError.status(status) }
        return key
    }
    public func save(_ key: String) throws {
        let value = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !value.isEmpty else { throw KeychainError.missing }
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData: value] as CFDictionary)
        if updated == errSecItemNotFound {
            var attributes = query; attributes[kSecValueData as String] = value; attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.status(status) }
        } else if updated != errSecSuccess { throw KeychainError.status(updated) }
    }
}

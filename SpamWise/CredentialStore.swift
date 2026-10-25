import Foundation
import Synchronization
import SpamWiseCore

/// Where SpamWise keeps the secrets that ``StoredCredential`` names.
protocol CredentialStore: Sendable {
  /// The saved secret; throws `KeychainError.missing` when none is saved.
  func read(_ credential: StoredCredential) throws -> String
  /// Whether a secret is saved, checked without reading it.
  func exists(_ credential: StoredCredential) throws -> Bool
  /// Saves a nonempty secret, trimmed of surrounding whitespace.
  func save(_ secret: String, as credential: StoredCredential) throws
  /// Removes the secret; removing one that isn't saved succeeds.
  func delete(_ credential: StoredCredential) throws
}

/// The shared Keychain group, which the app and the Mail extension both read.
struct KeychainCredentialStore: CredentialStore {
  func read(_ credential: StoredCredential) throws -> String {
    guard let keychain = credential.keychain else { throw KeychainError.missing }
    return try keychain.read()
  }

  func exists(_ credential: StoredCredential) throws -> Bool {
    try credential.keychain?.exists() ?? false
  }

  func save(_ secret: String, as credential: StoredCredential) throws {
    guard let keychain = credential.keychain else { throw ClassificationError.configuration }
    try keychain.save(secret)
  }

  func delete(_ credential: StoredCredential) throws {
    try credential.keychain?.delete()
  }
}

/// Secrets held only in memory, so UI tests and previews never read or write the shared Keychain.
final class MemoryCredentialStore: CredentialStore {
  private let secrets = Mutex<[StoredCredential: String]>([:])

  func read(_ credential: StoredCredential) throws -> String {
    guard let secret = secrets.withLock({ $0[credential] }) else { throw KeychainError.missing }
    return secret
  }

  func exists(_ credential: StoredCredential) -> Bool {
    secrets.withLock { $0[credential] != nil }
  }

  func save(_ secret: String, as credential: StoredCredential) throws {
    let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw KeychainError.missing }
    secrets.withLock { $0[credential] = trimmed }
  }

  func delete(_ credential: StoredCredential) {
    secrets.withLock { $0[credential] = nil }
  }
}

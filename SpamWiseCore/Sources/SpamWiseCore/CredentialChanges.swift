import Foundation

/// Credential edits that make mail left unclassified for want of a working key due again.
public enum CredentialChanges {
  /**
   Records that a model provider's API key was saved.

   Mail that failed because the key was missing or rejected stays unclassified until the
   filtering revision changes. Advancing the revision makes it due at the next discovery pass,
   as with any other revision change: classified results stay settled, and dry-run previews made
   earlier are classified again once dry run is off. Nothing is added to the audit trail, which
   records configuration and never credentials.

   - Parameter store: Shared storage whose filtering revision advances.
   */
  public static func recordKeySaved(_ store: Store) async throws {
    try await StateRepository.update(store, loading: StateSlices()) { $0.revision += 1 }
  }
}

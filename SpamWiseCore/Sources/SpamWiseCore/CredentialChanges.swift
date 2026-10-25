import Foundation

/// Credential edits that make mail left unclassified for want of a working key due again.
public enum CredentialChanges {
  /**
   Records that a model provider's API key was saved, together with `record` when given.

   Mail that failed because the key was missing or rejected stays unclassified until the
   filtering revision changes. When `backend` is the selected provider, the revision advances
   in the same transaction that records `record`, making that mail due at the next discovery
   pass. As with any other revision change, classified results stay settled, the latest
   correction can no longer be undone, and dry-run previews made earlier are classified again
   once dry run is off. A key saved for another provider leaves the revision alone: selecting
   that provider changes it. Nothing is added to the audit trail, which records configuration
   and never credentials.

   - Parameters:
     - backend: The provider whose key was saved.
     - store: Shared storage whose filtering revision advances.
     - record: Activity to record with the change, such as the key's verification request.
   */
  public static func recordKeySaved(
    for backend: ModelBackend,
    in store: Store,
    recording record: DecisionRecord? = nil
  ) async throws {
    try await StateRepository.update(store, loading: StateSlices()) { state in
      if state.settings.advancedOptions.backend == backend { state.revision += 1 }
      if let record { state.record(record) }
    }
  }
}

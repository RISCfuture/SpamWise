import Foundation
import Observation
import SpamWiseCore

/// Encrypted backups of rules, policy, corrections and learning.
@MainActor
@Observable
final class BackupModel {
  /// What a successful restore leaves the user to do.
  static var restoredMessage: String {
    String(
      localized:
        "Backup restored. Filtering is paused with dry run on. In Accounts, choose Check Mail Connection, or Check Connection for an IMAP account, then resume."
    )
  }
  /// Exporting and restoring backups.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices

  init(services: AppServices) { self.services = services }

  /// Reads, decrypts and restores the backup at `url` away from the main actor.
  @concurrent
  private static func restore(from url: URL, recoveryKey: String, store: Store) async throws {
    let data = try url.readSecurityScoped(maximumBytes: StateBackup.maximumBytes)
    try await StateBackup.restore(data, recoveryKey: recoveryKey, store: store)
  }

  /// Encrypts a backup with `recoveryKey` and hands it to `save`.
  func export(
    recoveryKey: String,
    includeContent: Bool,
    save: @escaping @MainActor (Data) -> Void
  ) {
    operation.run { [self] in
      save(
        try await StateBackup.export(
          store: services.requireStore(),
          recoveryKey: recoveryKey,
          includeContent: includeContent
        )
      )
      return nil
    }
  }

  /// Replaces rules, policy and learning from the backup at `url`, then pauses filtering.
  func restore(from url: URL, recoveryKey: String) {
    operation.run { [self] in
      try await Self.restore(from: url, recoveryKey: recoveryKey, store: services.requireStore())
      return Self.restoredMessage
    }
  }
}

import Foundation
import Observation
import SpamWiseCore

/// Encrypted backups of rules, policy, corrections and learning.
@MainActor @Observable final class BackupModel {
  private static let maximumBackupBytes = 64 * 1024 * 1024
  /// Exporting and restoring backups.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices

  init(services: AppServices) { self.services = services }

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
      let data = try SecurityScopedFile.read(url, limit: Self.maximumBackupBytes)
      try await StateBackup.restore(data, recoveryKey: recoveryKey, store: services.requireStore())
      return String(
        localized:
          "Backup restored. Filtering is paused; validate accounts before resuming actions."
      )
    }
  }
}

import Foundation
import Observation
import SpamWiseCore

/**
 Resolves SpamWise data that couldn't be read and was set aside: restore an encrypted backup, or
 keep the current state. A copy of the set-aside data can be saved first, for support.
 */
@MainActor
@Observable
final class StorageRecoveryModel {
  /// Saving a copy, restoring a backup or keeping the current state.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel

  /// The set-aside data, newest first.
  var entries: [StateRecovery.Entry] { shared.recoveryEntries.sorted { $0.date > $1.date } }

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  /// Encodes the set-aside data as one JSON file and hands it to `save`.
  func exportPreservedData(save: @escaping @MainActor (Data) -> Void) {
    operation.run { [self] in
      let preserved = try await StateRecovery.preservedData(services.requireStore())
      save(try JSONEncoder.pretty.encode(preserved))
      return nil
    }
  }

  /// Restores the backup at `url` with `recoveryKey`, then discards the set-aside data.
  func restore(from url: URL, recoveryKey: String) {
    operation.run { [self] in
      let data = try url.readSecurityScoped(maximumBytes: StateBackup.maximumBytes)
      try await StateRecovery.restore(
        backup: data,
        recoveryKey: recoveryKey,
        store: services.requireStore()
      )
      return try await resolved(BackupModel.restoredMessage)
    }
  }

  /// Discards the set-aside data and keeps SpamWise's current state.
  func keepCurrentState() {
    operation.run { [self] in
      try await StateRecovery.reset(services.requireStore())
      return try await resolved(nil)
    }
  }

  private func resolved(_ message: String?) async throws -> String? {
    shared.recoveryResolved()
    await shared.refresh()
    return message
  }
}

extension StateRecovery.Entry {
  /// What the set-aside data held, as people know it.
  var localizedSource: String {
    switch StateSlice(rawValue: source) {
      case .policy, .meta: String(localized: "Settings")
      case .rules, .contentRules, .contentRuleHits, .contentRuleSkips:
        String(localized: "Rules")
      case .corrections, .reviewedLabels, .undo: String(localized: "Corrections")
      case .training, .learning: String(localized: "Learning")
      case .records, .retries, .claims: String(localized: "Activity")
      case .contacts, .histories, .authentication:
        String(localized: "Contacts, history and trusted servers")
      case .audit: String(localized: "Configuration history")
      case .mailHealth: String(localized: "Account check progress")
      case nil: String(localized: "Data from an earlier version")
    }
  }
}

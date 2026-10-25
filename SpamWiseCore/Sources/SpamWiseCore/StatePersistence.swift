public import Foundation
import SwiftData
import Synchronization

/// One-time preparation of a store: its schema mark, checked before any other state access.
enum StatePersistence {
  /// Single-document snapshots that builds before the entity schema stored.
  private static let snapshotKeys = ["application-v1", "mail-health-v1"]
  private static let schemaKey = "state.schema"
  private static let entitySchema = 2
  private static let preparedStores = Mutex<Set<URL>>([])

  /**
   Checks the store's schema mark once per process, before any other state access.

   - Throws: ``StoredStateError/newerVersion`` when a newer version marked the entity schema, so
     this version neither reads nor writes that state.
   */
  static func prepared(_ store: Store) async throws {
    guard !preparedStores.withLock({ $0.contains(store.url) }) else { return }
    try await store.transaction { context in
      try markSchema(context)
      try context.save()
    }
    preparedStores.withLock { _ = $0.insert(store.url) }
  }
  /**
   Marks an unmarked store with the entity schema, first setting aside any single-document
   snapshot it holds for recovery, since this version doesn't read that format.
   */
  private static func markSchema(_ context: ModelContext) throws {
    if let mark = try context.document(schemaKey) {
      let schema = try? JSONDecoder().decode(Int.self, from: mark)
      guard let schema, schema <= entitySchema else { throw StoredStateError.newerVersion }
      return
    }
    for key in snapshotKeys {
      guard let snapshot = try context.document(key) else { continue }
      try StateRecovery.quarantine(snapshot, source: key, in: context)
      try context.removeDocument(key)
    }
    try context.setDocument(schemaKey, JSONEncoder().encode(entitySchema))
    try context.markChanged(
      StateSlice.allCases.map(\.rawValue),
      stamp: context.nextChangeStamp()
    )
  }
}

/// What shared storage holds when it opens.
public enum StoredStateCondition: Sendable, Equatable {
  /// Nothing has been saved yet, as on a first run.
  case empty
  /// Saved state that this version reads.
  case readable
  /// Unreadable data was set aside and awaits a recovery decision.
  case needsRecovery([StateRecovery.Entry])
}

/// Shared storage that holds data this version can't use; nothing in it is changed.
public enum StoredStateError: StorageFailure, Sendable, Equatable, LocalizedError {
  /// A newer version of SpamWise saved the data in a format this version doesn't support.
  case newerVersion
  /// The shared database couldn't be opened or read.
  case unreadable
  /// A general description of the storage problem.
  public var errorDescription: String? {
    String(localized: "SpamWise can’t use its saved data.", bundle: .module)
  }
  /// Why the saved data can't be used.
  public var failureReason: String? {
    switch self {
      case .newerVersion:
        String(
          localized: "A newer version of SpamWise saved it in a format this version doesn’t read.",
          bundle: .module
        )
      case .unreadable:
        String(localized: "The shared database couldn’t be opened.", bundle: .module)
    }
  }
  /// What the user can do; the saved data stays as it is.
  public var recoverySuggestion: String? {
    switch self {
      case .newerVersion:
        String(localized: "Install the latest version of SpamWise.", bundle: .module)
      case .unreadable:
        String(
          localized: "Quit and reopen SpamWise. Your saved data is left unchanged.",
          bundle: .module
        )
    }
  }
}

extension StateRepository {
  /**
   Opens shared storage and reports what it holds, so a first run can be told apart from data
   that can't be read.

   Settings and usage totals are decoded first; one that can't be decoded is set aside, and the
   store then needs recovery.

   - Throws: ``StoredStateError`` when the database can't be opened or a newer version wrote
     it, ``StoreError`` while storage is busy or missing, or cancellation.
   */
  public static func condition(_ store: Store) async throws -> StoredStateCondition {
    do {
      let saved = try await transaction(store) { transaction in
        try transaction.context.document(StateTransaction.policyKey) != nil
      }
      let entries = try await StateRecovery.entries(store)
      guard entries.isEmpty else { return .needsRecovery(entries) }
      return saved ? .readable : .empty
    } catch let error as any StorageFailure {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw StoredStateError.unreadable
    }
  }
}

/// Unreadable stored state that was set aside, and the explicit ways to resolve it.
public enum StateRecovery {
  private static let indexKey = "state.quarantine"
  private static let payloadPrefix = "state.quarantine."
  /// Set-aside data awaiting a recovery decision, read without the lock; empty when all is readable.
  public static func entries(_ store: Store) async throws -> [Entry] {
    try await StatePersistence.prepared(store)
    return try await store.snapshot { context in try index(in: context) }
  }
  /// The preserved bytes of each set-aside source, for export or support.
  public static func preservedData(_ store: Store) async throws -> [String: Data] {
    try await store.transaction { context in
      try index(in: context).reduce(into: [:]) { data, entry in
        data[entry.source] = try context.document(payloadPrefix + entry.source)
      }
    }
  }
  /// Restores portable state from an encrypted backup, then discards the set-aside data.
  public static func restore(backup: Data, recoveryKey: String, store: Store) async throws {
    try await StateBackup.restore(backup, recoveryKey: recoveryKey, store: store)
    try await reset(store)
  }
  /// Discards the set-aside data and keeps the current state.
  public static func reset(_ store: Store) async throws {
    try await store.transaction { context in
      for entry in try index(in: context) {
        try context.removeDocument(payloadPrefix + entry.source)
      }
      try context.removeDocument(indexKey)
      try context.save()
    }
  }
  /// Preserves unreadable bytes under their source name; a later failure replaces an earlier one.
  static func quarantine(_ data: Data, source: String, in context: ModelContext) throws {
    var entries = try index(in: context).filter { $0.source != source }
    entries.append(Entry(source: source, date: .now, byteCount: data.count))
    try context.setDocument(payloadPrefix + source, data)
    try context.setDocument(indexKey, JSONEncoder().encode(entries))
  }
  private static func index(in context: ModelContext) throws -> [Entry] {
    try context.document(indexKey).map { try JSONDecoder().decode([Entry].self, from: $0) } ?? []
  }
  /// When and from which slice unreadable data was set aside.
  public struct Entry: Codable, Sendable, Equatable {
    /// Stored slice or single-document key whose data could not be read.
    public let source: String
    /// Time the data was set aside.
    public let date: Date
    /// Size of the preserved data.
    public let byteCount: Int
  }
}

public import Foundation
import SwiftData
import Synchronization

/// One-time preparation of a store: the transactional import of the single-document snapshot.
enum StatePersistence {
  private static let legacyStateKey = "application-v1"
  private static let legacyHealthKey = "mail-health-v1"
  private static let schemaKey = "state.schema"
  private static let entitySchema = 2
  private static let preparedStores = Mutex<Set<URL>>([])

  /// Imports a single-document snapshot once per process, before any other state access.
  static func prepared(_ store: Store) async throws {
    guard !preparedStores.withLock({ $0.contains(store.url) }) else { return }
    try await store.transaction { context in
      try importLegacyState(context)
      try context.save()
    }
    preparedStores.withLock { _ = $0.insert(store.url) }
  }
  /**
   Moves the single-document snapshot into entity rows in one transaction.

   The snapshot is deleted only by the same save that commits its rows, so an interrupted or
   failed import leaves it in place. An unreadable snapshot is set aside for recovery instead
   of being discarded. Once the entity schema is marked, a snapshot written later by an older
   version is never imported over newer state.
   */
  private static func importLegacyState(_ context: ModelContext) throws {
    guard try context.document(schemaKey) == nil else { return }
    if let legacy = try context.document(legacyStateKey) {
      do {
        let state = try JSONDecoder().decode(AppState.self, from: legacy)
        try StateTransaction(importing: state, context: context).stage()
      } catch is DecodingError {
        try StateRecovery.quarantine(legacy, source: legacyStateKey, in: context)
      }
      try context.removeDocument(legacyStateKey)
    }
    if let health = try context.document(legacyHealthKey) {
      if let states = try? JSONDecoder().decode([String: MailScanHealth].self, from: health) {
        for (key, value) in states {
          context.insert(MailHealthRow(key: key, payload: try JSONEncoder().encode(value)))
        }
      } else {
        try StateRecovery.quarantine(health, source: legacyHealthKey, in: context)
      }
      try context.removeDocument(legacyHealthKey)
    }
    try context.setDocument(schemaKey, JSONEncoder().encode(entitySchema))
    try context.markChanged(
      StateSlice.allCases.map(\.rawValue),
      stamp: context.nextChangeStamp()
    )
  }
}

/// Unreadable stored state that was set aside, and the explicit ways to resolve it.
public enum StateRecovery {
  private static let indexKey = "state.quarantine"
  private static let payloadPrefix = "state.quarantine."
  /// Set-aside data awaiting a recovery decision; empty when all state was readable.
  public static func entries(_ store: Store) async throws -> [Entry] {
    try await StatePersistence.prepared(store)
    return try await store.transaction { context in try index(in: context) }
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

import Foundation
import SwiftData
import Classifier
import Decision

/// Typed transactions over the shared application state.
public enum StateRepository {
  /**
   Reads the selected slices; every unselected collection is empty.

   The default reads everything, including the whole Activity log, and is meant for tests,
   exports and other rare whole-state operations.
   */
  public static func load(_ store: Store, _ slices: StateSlices = .everything) async throws
    -> AppState
  {
    try await transaction(store) { transaction in
      try transaction.load(slices)
      return transaction.state
    }
  }
  /// Atomically reads the selected slices, applies `body`, and writes only what changed.
  public static func update<R: Sendable>(
    _ store: Store,
    loading slices: StateSlices = .everything,
    _ body: @Sendable (inout AppState) throws -> R
  ) async throws -> R {
    try await transaction(store) { transaction in
      try transaction.load(slices)
      let result = try body(&transaction.state)
      try transaction.commit()
      return result
    }
  }
  /**
   Runs `body` under the store lock with a transaction that has read only settings.

   Data that reading set aside for recovery is saved even when `body` commits nothing.
   */
  static func transaction<R: Sendable>(
    _ store: Store,
    _ body: @Sendable (StateTransaction) throws -> R
  ) async throws -> R {
    try await StatePersistence.prepared(store)
    return try await store.transaction { context in
      let transaction = try StateTransaction(context: context)
      let result = try body(transaction)
      try transaction.keepSetAsideData()
      return result
    }
  }
}

extension StateRepository {
  /**
   Applies a field-level edit to current preferences.

   Edits to classification or action policy supersede pending work; edits that are checked
   live at dispatch time, or that only change presentation, are saved without invalidation.
   Both are recorded in the audit trail with the names of the changed fields.
   */
  public static func editSettings(
    _ store: Store,
    _ edit: @Sendable (inout Settings) throws -> Void
  ) async throws {
    try await transaction(store) { transaction in
      let previous = transaction.state.settings
      var settings = previous
      try edit(&settings)
      clamp(&settings)
      guard settings != previous else { return }
      let clearsRetainedContent =
        previous.advancedOptions.retainReviewedContent
        && !settings.advancedOptions.retainReviewedContent
      if clearsRetainedContent { try transaction.load(StateSlices(reviewedLabels: .all)) }
      transaction.state.settings = settings
      if clearsRetainedContent {
        transaction.state.reviewedLabels = transaction.state.reviewedLabels.map { label in
          var label = label; label.message = nil; return label
        }
      }
      let change = AuditEvent.Change.settingsChanged(fields: settings.changedFields(from: previous))
      if settings.policyProjection != previous.policyProjection {
        transaction.state.invalidatePendingWork(change)
      } else {
        transaction.state.audit(change)
      }
      try transaction.commit()
    }
  }
  private static func clamp(_ settings: inout Settings) {
    settings.correctionLimit = ClassificationLimits.correctionLimitRange.clamp(
      settings.correctionLimit
    )
    settings.bodyTokenBudget = ClassificationLimits.bodyTokenBudgetRange.clamp(
      settings.bodyTokenBudget
    )
    if settings.validatedAccounts.isEmpty { settings.dryRun = true }
  }
}

extension StateRepository {
  /// Change counters of each slice; a slice whose counter is unchanged has not been written.
  public static func changeTokens(_ store: Store) async throws -> [StateSlice: Int] {
    try await StatePersistence.prepared(store)
    return try await store.changeTokens().reduce(into: [:]) { tokens, entry in
      if let slice = StateSlice(rawValue: entry.key) { tokens[slice] = entry.value }
    }
  }
  /**
   Records written after `stamp`, with the stamp to pass next time.

   Passing zero returns the whole retained log. Records pruned from the log are not reported.
   */
  public static func recordChanges(_ store: Store, after stamp: Int) async throws -> (
    records: [DecisionRecord], stamp: Int
  ) {
    try await StatePersistence.prepared(store)
    return try await store.snapshot { context in
      let rows = try context.fetch(
        FetchDescriptor<RecordRow>(predicate: #Predicate { $0.changeStamp > stamp })
      )
      let decoder = JSONDecoder()
      return (
        rows.compactMap { try? decoder.decode(DecisionRecord.self, from: $0.payload) }
          .sorted { $0.date < $1.date },
        rows.map(\.changeStamp).max() ?? stamp
      )
    }
  }
  /// One page of matching Activity records in the query's order, fetched without reading the whole log.
  public static func activity(
    _ store: Store,
    matching query: ActivityQuery = .init(),
    offset: Int = 0,
    limit: Int
  ) async throws -> [DecisionRecord] {
    try await StatePersistence.prepared(store)
    return try await store.snapshot { context in
      var descriptor = FetchDescriptor(predicate: query.predicate, sortBy: query.sort.descriptors)
      descriptor.fetchOffset = max(0, offset)
      descriptor.fetchLimit = max(0, limit)
      let decoder = JSONDecoder()
      return try context.fetch(descriptor).compactMap {
        try? decoder.decode(DecisionRecord.self, from: $0.payload)
      }
    }
  }
  /// The Activity records of the messages with these identity keys, newest first.
  public static func records(_ store: Store, identityKeys: Set<String>) async throws
    -> [DecisionRecord]
  {
    guard !identityKeys.isEmpty else { return [] }
    let keys = Array(identityKeys)
    try await StatePersistence.prepared(store)
    return try await store.snapshot { context in
      let descriptor = FetchDescriptor<RecordRow>(
        predicate: #Predicate { keys.contains($0.identityKey) },
        sortBy: [SortDescriptor(\.date, order: .reverse)]
      )
      let decoder = JSONDecoder()
      return try context.fetch(descriptor).compactMap {
        try? decoder.decode(DecisionRecord.self, from: $0.payload)
      }
    }
  }
  /// The distinct accounts of retained Activity records, read from their indexed column.
  public static func activityAccountIDs(_ store: Store) async throws -> Set<String> {
    try await StatePersistence.prepared(store)
    return try await store.snapshot { context in
      var descriptor = FetchDescriptor<RecordRow>(predicate: #Predicate { $0.accountID != nil })
      descriptor.propertiesToFetch = [\.accountID]
      return Set(try context.fetch(descriptor).compactMap(\.accountID))
    }
  }
  /// Number of Activity records matching `query`.
  public static func activityCount(_ store: Store, matching query: ActivityQuery = .init())
    async throws -> Int
  {
    try await StatePersistence.prepared(store)
    return try await store.snapshot { context in
      try context.fetchCount(FetchDescriptor(predicate: query.predicate))
    }
  }
  /**
   The redacted support summary of the whole log.

   Outcomes are counted from their column, and reasons from each record's stored decision
   alone, so no record is decoded in full.
   */
  public static func diagnosticSummary(_ store: Store) async throws -> DiagnosticSummary {
    let state = try await load(store, StateSlices(retries: .all))
    let (outcomes, reasons) = try await store.snapshot { context in
      var outcomeColumn = FetchDescriptor<RecordRow>()
      outcomeColumn.propertiesToFetch = [\.outcome]
      var payloadColumn = FetchDescriptor<RecordRow>()
      payloadColumn.propertiesToFetch = [\.payload]
      let decoder = JSONDecoder()
      return (
        Dictionary(grouping: try context.fetch(outcomeColumn), by: \.outcome).mapValues(\.count),
        Dictionary(
          grouping: try context.fetch(payloadColumn).compactMap {
            try? decoder.decode(StoredDecision.self, from: $0.payload).decision.reason
          },
          by: \.diagnosticCategory
        ).mapValues(\.count)
      )
    }
    return DiagnosticSummary(
      settings: state.settings,
      retryCount: state.retries.count,
      outcomes: outcomes,
      reasons: reasons
    )
  }
  /// ``AppState/historyEligibleInbox`` of the whole log, read from indexed columns without decoding it.
  public static func historyEligibleInbox(_ store: Store) async throws
    -> [String: InboxEligibility]
  {
    let pending = try await load(store, StateSlices(retries: .all, reviewedLabels: .all))
    let superseded = ActionOutcome.superseded.rawValue
    let decisions = try await store.snapshot { context in
      try context.fetch(
        FetchDescriptor<RecordRow>(
          predicate: #Predicate { $0.outcome != superseded },
          sortBy: [SortDescriptor(\.date)]
        )
      ).map {
        InboxDecision(
          key: $0.identityKey,
          corrected: $0.correctedLabel.flatMap(MailLabel.init(rawValue:)),
          decided: $0.label.flatMap(MailLabel.init(rawValue:))
        )
      }
    }
    return AppState.historyEligibleInbox(
      decisions: decisions,
      reviewedLabels: pending.reviewedLabels,
      retries: pending.retries
    )
  }
}

/// The decision of a stored record, decoded without the rest of the record.
private struct StoredDecision: Decodable {
  let decision: Decision
}

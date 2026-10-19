public import Foundation

/// Why a processed message produced no classification.
public enum ProcessingFailure: String, Codable, Sendable {
  /// The message could not be parsed; identical content fails the same way.
  case unparseable
  /// A provider, storage or cancellation condition that can clear without a settings change.
  case transient
  /// A failure that persists until the filtering revision changes.
  case persistent
}

/// Compact durable result for one message identity, retained independently of the Activity log.
public struct ProcessedMessage: Codable, Sendable, Equatable {
  private static let initialRetryDelaySec: TimeInterval = 900
  private static let maximumRetryDelaySec: TimeInterval = 43_200
  private static let transientRetryWindowSec: TimeInterval = 3 * 86_400
  /// Policy generation in effect when the message was processed.
  public var revision: Int
  /// Recorded label; nil when the message was not classified.
  public var label: MailLabel?
  /// Observed action outcome.
  public var outcome: ActionOutcome
  /// Time the result was recorded.
  public var date: Date
  /// Failure category for unclassified results.
  public var failure: ProcessingFailure?
  /// Consecutive transient failures.
  public var attempts: Int?
  /// Earliest time a transient failure may be processed again.
  public var retryAfter: Date?
  /// Time of the first of the consecutive transient failures, which bounds how long they are retried.
  public var firstTransientFailure: Date?
  /// Latest time automatic discovery found this result settled; retention counts from here.
  public var lastObserved: Date?

  /// Whether this result was classified with a stable outcome.
  public var isClassified: Bool {
    label != nil && ![.paused, .superseded, .pending, .unclassified].contains(outcome)
  }

  var retainedSince: Date { lastObserved ?? date }
  /// A paused, superseded or pending result never reached an outcome, so discovery revisits it.
  private var neverFinished: Bool { [.paused, .superseded, .pending].contains(outcome) }
  /// Any outcome other than a failure or a dry run, including unavailable integrations.
  private var keepsOutcomeAcrossRevisions: Bool { ![.unclassified, .dryRun].contains(outcome) }
  /// Unparseable content fails the same way on every attempt, whatever the revision.
  private var failsIdentically: Bool { failure == .unparseable }

  /**
   Creates a result for a recorded decision, classifying its failure when unclassified.

   A transient failure is retried with exponential backoff, from 15 minutes up to 12 hours,
   until three days after the first of its consecutive transient failures; it then persists
   until the filtering revision changes.
   */
  public init(
    record: DecisionRecord,
    failure: ProcessingFailure? = nil,
    previous: Self? = nil,
    now: Date = .now
  ) {
    revision = record.revision
    label = record.correctedLabel ?? record.decision.label
    outcome = record.outcome
    date = now
    guard record.outcome == .unclassified else { return }
    self.failure = failure ?? .persistent
    guard self.failure == .transient else { return }
    let transient = previous?.failure == .transient ? previous : nil
    let attempts = (transient?.attempts ?? 0) + 1
    let firstFailure = transient?.firstTransientFailure ?? transient?.date ?? now
    self.attempts = attempts
    firstTransientFailure = firstFailure
    if now.timeIntervalSince(firstFailure) >= Self.transientRetryWindowSec {
      self.failure = .persistent
    } else {
      retryAfter = now.addingTimeInterval(
        min(
          Self.maximumRetryDelaySec,
          Self.initialRetryDelaySec * pow(2, Double(attempts - 1))
        )
      )
    }
  }

  /**
   Whether automatic discovery should leave this message alone.

   A dry-run result stays settled only while discovery is still a dry run under the revision
   that produced it. Once dry run is off or the policy changes, the message is due again, so
   mail previewed during a dry run is acted on when filtering goes live. Other classified results
   stay settled across revisions, including results whose action found no validated
   integration: validating an account later does not act on them. Unparseable messages stay
   settled because identical content fails the same way. Other failures become due again after
   a revision change or, for transient causes, once their backoff elapses.

   - Parameters:
     - current: The current policy revision.
     - dryRun: Whether the pass asking suppresses mail actions, by setting or by request.
     - now: The time of the pass.
   */
  public func isSettled(revision current: Int, dryRun: Bool, now: Date = .now) -> Bool {
    if neverFinished { return false }
    if outcome == .dryRun { return dryRun && revision == current }
    if keepsOutcomeAcrossRevisions { return true }
    return failsIdentically || (revision == current && !isTransientRetryDue(now: now))
  }

  /// A transient failure whose backoff has elapsed; other failures wait for a revision change.
  private func isTransientRetryDue(now: Date) -> Bool {
    failure == .transient && (retryAfter ?? .distantPast) <= now
  }

  func shouldReplace(_ previous: Self) -> Bool {
    isClassified || !previous.isClassified
  }

  func isRetained(at now: Date, for retention: TimeInterval) -> Bool {
    now.timeIntervalSince(retainedSince) < retention
  }
}

/**
 Durable processed-message index keyed by identity, sharded so each transaction reads one
 small bucket instead of the shared application snapshot.
 */
public enum ProcessedMessageRepository {
  private static let keyPrefix = "processed-v1:"
  private static let legacyImportKey = "processed-v1:legacy-activity"
  private static let bucketPrefixLength = 2
  private static let maximumEntriesPerBucket = 250
  private static let retentionSec: TimeInterval = 400 * 86_400
  private static let observationRefreshSec: TimeInterval = 7 * 86_400

  /// Loads recorded results for the supplied identity keys.
  public static func entries(
    for keys: some Sequence<String>,
    in store: Store
  ) async throws -> [String: ProcessedMessage] {
    let keys = Set(keys)
    let buckets = try await store.read(
      Set(keys.map(bucketKey)),
      as: [String: ProcessedMessage].self
    )
    return keys.reduce(into: [:]) { entries, key in
      entries[key] = buckets[bucketKey(for: key)]?[key]
    }
  }

  /**
   Identity keys among `keys` that automatic discovery should skip; see
   ``ProcessedMessage/isSettled(revision:dryRun:now:)``.

   Settled results not observed for a week have their retention renewed, so mail that stays in
   a swept mailbox is not forgotten and classified again. Results recorded only in Activity
   count once ``importLegacyActivity(in:)`` has run.
   */
  public static func settledKeys(
    among keys: some Sequence<String>,
    revision: Int,
    dryRun: Bool,
    now: Date = .now,
    in store: Store
  ) async throws -> Set<String> {
    let settled = try await entries(for: keys, in: store).filter {
      $0.value.isSettled(revision: revision, dryRun: dryRun, now: now)
    }
    try await renewRetention(
      of: settled.filter { !$0.value.isRetained(at: now, for: observationRefreshSec) }.keys,
      now: now,
      in: store
    )
    return Set(settled.keys)
  }

  /// Records a result for the discovered identity key unless it would replace a classified result with an unclassified one.
  public static func record(
    _ record: DecisionRecord,
    key: String,
    failure: ProcessingFailure? = nil,
    in store: Store,
    now: Date = .now
  ) async throws {
    try await store.update(bucketKey(for: key), default: [String: ProcessedMessage]()) { bucket in
      let entry = ProcessedMessage(
        record: record,
        failure: failure,
        previous: bucket[key],
        now: now
      )
      if let previous = bucket[key], !entry.shouldReplace(previous) { return }
      bucket[key] = entry
      prune(&bucket, now: now)
    }
  }

  /// Imports results from the Activity log once per store, before the index is first consulted.
  public static func importLegacyActivity(in store: Store) async throws {
    guard try await store.read(legacyImportKey, default: false) == false else { return }
    let records = try await StateRepository.load(store, StateSlices(records: .all)).records
    var buckets: [String: [String: ProcessedMessage]] = [:]
    for record in records where record.identity.accountID != nil && !record.deferredBySpendingLimit
    {
      let key = record.identity.key
      let entry = ProcessedMessage(record: record, now: record.date)
      if let previous = buckets[bucketKey(for: key)]?[key], !entry.shouldReplace(previous) {
        continue
      }
      buckets[bucketKey(for: key), default: [:]][key] = entry
    }
    let imported = buckets
    if !imported.isEmpty {
      try await store.update(Set(imported.keys), as: [String: ProcessedMessage].self) { current in
        let now = Date.now
        for (bucket, entries) in imported {
          var merged = current[bucket, default: [:]].merging(entries) { existing, _ in existing }
          prune(&merged, now: now)
          current[bucket] = merged
        }
      }
    }
    try await store.update(legacyImportKey, default: false) { $0 = true }
  }

  private static func renewRetention(
    of keys: some Sequence<String>,
    now: Date,
    in store: Store
  ) async throws {
    let grouped = Dictionary(grouping: keys, by: bucketKey)
    guard !grouped.isEmpty else { return }
    try await store.update(Set(grouped.keys), as: [String: ProcessedMessage].self) { buckets in
      for (bucket, keys) in grouped {
        for key in keys { buckets[bucket]?[key]?.lastObserved = now }
      }
    }
  }

  private static func bucketKey(for key: String) -> String {
    keyPrefix + key.prefix(bucketPrefixLength)
  }

  private static func prune(_ bucket: inout [String: ProcessedMessage], now: Date) {
    bucket = bucket.filter { $0.value.isRetained(at: now, for: retentionSec) }
    guard bucket.count > maximumEntriesPerBucket else { return }
    let newest = bucket.sorted { $0.value.retainedSince > $1.value.retainedSince }
      .prefix(maximumEntriesPerBucket)
    bucket = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
  }
}

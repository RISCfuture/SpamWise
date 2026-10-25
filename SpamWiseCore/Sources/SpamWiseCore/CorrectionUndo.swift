public import Foundation

/// Failures while undoing a correction.
public protocol UndoFailure: Error {}

/// Why a correction can no longer be undone; nothing was restored.
public enum UndoError: UndoFailure, Sendable, Equatable, LocalizedError {
  /// A later change superseded the correction, or its label was never recorded.
  case unavailable
  /// A general description of the refused undo.
  public var errorDescription: String? {
    String(localized: "The correction couldn’t be undone.", bundle: .module)
  }
  /// Why the undo is no longer available.
  public var failureReason: String? {
    String(
      localized: "Rules, labels or settings changed after the correction was saved.",
      bundle: .module
    )
  }
}

/**
 One bounded correction undo, valid only while its policy and learning state remain unchanged.

 Any later write to rules, correction examples, learning or reviewed labels that does not
 itself replace the undo discards it, so an undo never restores over a newer change. The
 corrections of one ``CorrectionBatch`` share an undo while no other change comes between them.
 */
public struct CorrectionUndo: Codable, Sendable, Equatable {
  /// Slices that an undo snapshot covers.
  static let slices = StateSlices([.rules, .corrections, .learning, .undo], reviewedLabels: .all)
  /// The latest correction whose rules and examples can be restored.
  public let recordID: UUID
  /// Required current policy generation.
  public let revision: Int
  /// Corrections of the same batch saved before another change, which the undo leaves in place.
  public let retainedCount: Int
  /// Whether the latest correction's reviewed label and learning were recorded after the snapshot.
  var confirmed = false
  fileprivate let snapshot: Snapshot
  /// The corrections the undo reverts, in the order they were saved.
  fileprivate let reversals: [Reversal]
  private let batchID: UUID?
  /// How many corrections the undo reverts together.
  public var correctionCount: Int { reversals.count }
  /// The corrections and the decisions they corrected.
  private var recordIDs: Set<UUID> { Set(reversals.flatMap { [$0.recordID, $0.sourceID] }) }
  /**
   The undo for a correction saved over `state`.

   A correction of `batch` joins the batch's undo while that undo is still available in `state`.
   */
  init(
    state: AppState,
    source: DecisionRecord,
    recordID: UUID,
    revision: Int,
    batch: CorrectionBatch?
  ) {
    let reversal = Reversal(
      recordID: recordID,
      sourceID: source.id,
      priorLabel: source.correctedLabel
    )
    if let batch, let joined = state.correctionUndo, joined.batchID == batch.id,
      joined.isAvailable(in: state)
    {
      snapshot = joined.snapshot
      reversals = joined.reversals + [reversal]
      retainedCount = joined.retainedCount
    } else {
      snapshot = Snapshot(state: state)
      reversals = [reversal]
      retainedCount = batch?.savedCount ?? 0
    }
    batchID = batch?.id
    self.recordID = recordID; self.revision = revision
  }
  /// Decodes an undo, treating a recorded digest as confirmation and a top-level source as its
  /// only correction.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    recordID = try values.decode(UUID.self, forKey: .recordID)
    revision = try values.decode(Int.self, forKey: .revision)
    snapshot = try values.decode(Snapshot.self, forKey: .snapshot)
    reversals =
      try values.decodeIfPresent([Reversal].self, forKey: .reversals) ?? [
        Reversal(
          recordID: recordID,
          sourceID: try values.decode(UUID.self, forKey: .sourceID),
          priorLabel: values.lenient(.priorLabel, default: nil)
        )
      ]
    batchID = values.lenient(.batchID, default: nil)
    retainedCount = values.lenient(.retainedCount, default: 0)
    confirmed =
      values.lenient(.confirmed, default: false)
      || values.lenient(.expectedDigest, default: String?.none) != nil
  }
  /**
   Restores rules and learning atomically without reversing or retrying any Mail action.

   - Returns: The undo that was applied.
   */
  @discardableResult
  public static func apply(store: Store) async throws -> Self {
    try await StateRepository.transaction(store) { transaction in
      try transaction.load(slices)
      guard let undo = transaction.state.correctionUndo,
        undo.isAvailable(in: transaction.state)
      else {
        throw UndoError.unavailable
      }
      try transaction.load(StateSlices(records: .only(undo.recordIDs)))
      transaction.state.restore(undo)
      try transaction.commit()
      return undo
    }
  }
  /// Whether `record` is a correction this undo reverts or a decision one of them corrected.
  public func applies(to record: DecisionRecord) -> Bool {
    reversals.contains { record.id == $0.recordID || record.id == $0.sourceID }
  }
  /// Rejects stale undo after any policy change.
  public func isAvailable(in state: AppState) -> Bool {
    revision == state.revision && confirmed
  }
  /// Encodes the undo and its confirmation.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(recordID, forKey: .recordID)
    try values.encode(revision, forKey: .revision)
    try values.encode(snapshot, forKey: .snapshot)
    try values.encode(reversals, forKey: .reversals)
    try values.encodeIfPresent(batchID, forKey: .batchID)
    try values.encode(retainedCount, forKey: .retainedCount)
    try values.encode(confirmed, forKey: .confirmed)
  }
  private enum CodingKeys: String, CodingKey {
    case recordID, revision, snapshot, reversals, batchID, retainedCount, confirmed
    case sourceID, priorLabel, expectedDigest
  }
  /// One reverted correction and the label its corrected decision had before it.
  fileprivate struct Reversal: Codable, Sendable, Equatable {
    let recordID: UUID
    let sourceID: UUID
    let priorLabel: MailLabel?
  }
  fileprivate struct Snapshot: Codable, Sendable, Equatable {
    var rules: [SenderRule]
    var corrections: [CorrectionExample]
    var learning: LearningState
    var labels: [ReviewedLabel]

    init(state: AppState) {
      rules = state.rules; corrections = state.corrections
      learning = state.learning; labels = state.reviewedLabels
    }
  }
}

extension AppState {
  fileprivate mutating func restore(_ undo: CorrectionUndo) {
    rules = undo.snapshot.rules
    corrections = undo.snapshot.corrections
    learning = undo.snapshot.learning
    reviewedLabels = undo.snapshot.labels
    for reversal in undo.reversals.reversed() {
      if let index = records.firstIndex(where: { $0.id == reversal.sourceID }) {
        records[index].correctedLabel = reversal.priorLabel
      }
      if let index = records.firstIndex(where: { $0.id == reversal.recordID }) {
        records[index].correctionUndone = true
      }
    }
    invalidatePendingWork(.correctionUndone)
  }
}

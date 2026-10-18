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
 itself replace the undo discards it, so an undo never restores over a newer change.
 */
public struct CorrectionUndo: Codable, Sendable, Equatable {
  /// Slices that an undo snapshot covers.
  static let slices = StateSlices([.rules, .corrections, .learning, .undo], reviewedLabels: .all)
  /// Correction whose rules and examples can be restored.
  public let recordID: UUID
  /// Required current policy generation.
  public let revision: Int
  /// Number of sender rules in the restoration preview.
  public var ruleCount: Int { snapshot.rules.count }
  /// Number of quoted examples in the restoration preview.
  public var exampleCount: Int { snapshot.corrections.count }
  /// Whether the correction's reviewed label and learning were recorded after the snapshot.
  var confirmed = false
  fileprivate let snapshot: Snapshot
  fileprivate let sourceID: UUID
  fileprivate let priorLabel: MailLabel?

  init(state: AppState, source: DecisionRecord, recordID: UUID, revision: Int) {
    snapshot = Snapshot(state: state)
    sourceID = source.id; priorLabel = source.correctedLabel
    self.recordID = recordID; self.revision = revision
  }
  /// Decodes an undo, treating a recorded digest as confirmation.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    recordID = try values.decode(UUID.self, forKey: .recordID)
    revision = try values.decode(Int.self, forKey: .revision)
    snapshot = try values.decode(Snapshot.self, forKey: .snapshot)
    sourceID = try values.decode(UUID.self, forKey: .sourceID)
    priorLabel = values.lenient(.priorLabel, default: nil)
    confirmed =
      values.lenient(.confirmed, default: false)
      || values.lenient(.expectedDigest, default: String?.none) != nil
  }
  /// Restores rules and learning atomically without reversing or retrying any Mail action.
  public static func apply(store: Store) async throws {
    try await StateRepository.transaction(store) { transaction in
      try transaction.load(slices)
      guard let undo = transaction.state.correctionUndo,
        undo.isAvailable(in: transaction.state)
      else {
        throw UndoError.unavailable
      }
      try transaction.load(StateSlices(records: .only([undo.sourceID, undo.recordID])))
      transaction.state.restore(undo)
      try transaction.commit()
    }
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
    try values.encode(sourceID, forKey: .sourceID)
    try values.encodeIfPresent(priorLabel, forKey: .priorLabel)
    try values.encode(confirmed, forKey: .confirmed)
  }
  private enum CodingKeys: String, CodingKey {
    case recordID, revision, snapshot, sourceID, priorLabel, confirmed, expectedDigest
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
    if let index = records.firstIndex(where: { $0.id == undo.sourceID }) {
      records[index].correctedLabel = undo.priorLabel
    }
    if let index = records.firstIndex(where: { $0.id == undo.recordID }) {
      records[index].correctionUndone = true
    }
    invalidatePendingWork(.correctionUndone)
  }
}

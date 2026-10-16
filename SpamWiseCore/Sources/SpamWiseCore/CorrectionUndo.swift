public import Foundation

/// One bounded correction undo, valid only while its policy and learning state remain unchanged.
public struct CorrectionUndo: Codable, Sendable {
  /// Correction whose rules and examples can be restored.
  public let recordID: UUID
  /// Required current policy generation.
  public let revision: Int
  /// Number of sender rules in the restoration preview.
  public var ruleCount: Int { snapshot.rules.count }
  /// Number of quoted examples in the restoration preview.
  public var exampleCount: Int { snapshot.corrections.count }
  var expectedDigest: String?
  private let snapshot: Snapshot
  private let sourceID: UUID
  private let priorLabel: MailLabel?

  init(state: AppState, source: DecisionRecord, recordID: UUID, revision: Int) {
    snapshot = Snapshot(state: state)
    sourceID = source.id; priorLabel = source.correctedLabel
    self.recordID = recordID; self.revision = revision
  }
  static func digest(_ state: AppState) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return stableHash(try encoder.encode(Snapshot(state: state)))
  }
  /// Restores rules and learning atomically without reversing or retrying any Mail action.
  public static func apply(store: Store) async throws {
    try await StateRepository.update(store) { state in
      guard let undo = state.correctionUndo, undo.isAvailable(in: state) else {
        throw IntegrationError.staleMessage
      }
      state.rules = undo.snapshot.rules
      state.corrections = undo.snapshot.corrections
      state.learning = undo.snapshot.learning
      state.reviewedLabels = undo.snapshot.labels
      if let index = state.records.firstIndex(where: { $0.id == undo.sourceID }) {
        state.records[index].correctedLabel = undo.priorLabel
      }
      if let index = state.records.firstIndex(where: { $0.id == undo.recordID }) {
        state.records[index].correctionUndone = true
      }
      state.correctionUndo = nil
      state.revision += 1; state.retries = []
      state.audit(
        .undo,
        detail: String(localized: "Undid correction rules and learning; Mail action unchanged")
      )
    }
  }
  /// Rejects stale undo after any policy or derived-learning change.
  public func isAvailable(in state: AppState) -> Bool {
    revision == state.revision && expectedDigest != nil
      && expectedDigest == (try? Self.digest(state))
  }
  private struct Snapshot: Codable, Sendable {
    var rules: [SenderRule]
    var corrections: [CorrectionExample]
    var learning: LearningState?
    var labels: [ReviewedLabel]?
    init(state: AppState) {
      rules = state.rules; corrections = state.corrections
      learning = state.learning; labels = state.reviewedLabels
    }
  }
}

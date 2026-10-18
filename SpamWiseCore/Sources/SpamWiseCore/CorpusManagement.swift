public import Foundation

/// Failures of explicit reviewed-corpus operations.
public protocol CorpusFailure: Error {}

/// Why a reviewed-corpus operation was rejected; nothing was changed.
public enum CorpusError: CorpusFailure, Sendable, Equatable, LocalizedError {
  /// One import holds more messages than the supported batch.
  case batchTooLarge(limit: Int)
  /// Imported labels would exceed the reviewed-label limit.
  case labelLimitReached(limit: Int, remaining: Int)
  /// The reviewed label is no longer retained.
  case labelNotFound
  /// A general description of the rejected operation.
  public var errorDescription: String? {
    String(localized: "The reviewed examples couldn’t be updated.", bundle: .module)
  }
  /// The constraint that rejected the operation.
  public var failureReason: String? {
    switch self {
      case .batchTooLarge(let limit):
        String(
          localized: "Import at most \(limit, format: .number) messages at a time.",
          bundle: .module
        )
      case .labelLimitReached(let limit, let remaining):
        String(
          localized:
            "SpamWise keeps at most \(limit, format: .number) imported labels; \(remaining, format: .number) more can be imported.",
          bundle: .module
        )
      case .labelNotFound:
        String(localized: "The reviewed example is no longer available.", bundle: .module)
    }
  }
  /// The action that makes room for more imported labels.
  public var recoverySuggestion: String? {
    guard case .labelLimitReached = self else { return nil }
    return String(
      localized: "Forget imported examples you no longer need, then import again.",
      bundle: .module
    )
  }
}

/**
 How many reviewed labels are kept, by origin.

 Labels share one limit. A label replaces any label with the same content or sample identity.
 Beyond the limit the oldest correction labels roll off, together with their correction examples
 and learning; imported labels are never evicted, so imports stop at the limit, and a correction
 made while imported labels fill it saves its rule without a label.
 */
public struct ReviewedLabelCapacity: Sendable, Equatable {
  /// The maximum number of reviewed labels.
  public let limit: Int
  /// Labels imported from reviewed messages.
  public let imported: Int
  /// Labels recorded by corrections, which roll off oldest first.
  public let corrections: Int
  /// Imported labels that can still be added.
  public var remainingImports: Int { max(0, limit - imported) }
}

/// Explicit labeled corpus operations that never create sender rules or request mail actions.
public enum CorpusManagement {
  private static let maximumBatch = 20
  private static let slices = StateSlices([.corrections, .learning], reviewedLabels: .all)
  /// Current reviewed-label usage under the shared retention policy.
  public static func capacity(store: Store) async throws -> ReviewedLabelCapacity {
    try await StateRepository.load(store, StateSlices(reviewedLabels: .all)).reviewedLabelCapacity
  }
  /**
   Imports a bounded batch of human-reviewed examples, deduplicating by delivery-independent content.

   Evidence is derived from each complete message before its headers are discarded, so imported
   samples train on the same features as live corrections.

   - Throws: ``CorpusError`` when the batch is too large or would exceed the imported-label limit.
   */
  public static func importMessages(_ messages: [ParsedMessage], label: MailLabel, store: Store)
    async throws
  {
    guard messages.count <= maximumBatch else {
      throw CorpusError.batchTooLarge(limit: maximumBatch)
    }
    let prepared = messages.map(ImportedSample.init)
    try await StateRepository.update(store, loading: slices) { state in
      try state.requireImportCapacity(for: prepared)
      for sample in prepared { state.importLabel(sample, label: label) }
      state.corrections = Array(state.corrections.suffix(RetentionLimits.corrections))
      state.invalidatePendingWork(.corpusImported(count: prepared.count, label: label))
    }
  }
  /// Relabels reviewed content and linked features without creating sender rules or moving mail.
  public static func relabel(id: String, label: MailLabel, store: Store) async throws {
    try await StateRepository.update(store, loading: slices) { state in
      guard var reviewed = state.reviewedLabels.first(where: { $0.id == id }) else {
        throw CorpusError.labelNotFound
      }
      let sampleID = reviewed.linkedSampleID
      reviewed.label = label; reviewed.date = .now
      state.reviewedLabels.removeAll { $0.id == id }
      state.reviewedLabels.append(reviewed)
      state.learning.relabel(sampleID: sampleID, label: label)
      for index in state.corrections.indices where state.corrections[index].sampleID == sampleID {
        state.corrections[index].label = label
      }
      state.invalidatePendingWork(.corpusRelabeled(label: label))
    }
  }
  /// Forgets one label and its linked derived learning, retaining explicit sender rules.
  public static func forget(id: String, store: Store) async throws {
    try await StateRepository.update(store, loading: slices) { state in
      guard let label = state.reviewedLabels.first(where: { $0.id == id }) else {
        throw CorpusError.labelNotFound
      }
      let sampleID = label.linkedSampleID
      state.reviewedLabels.removeAll { $0.id == id || $0.sampleID == sampleID }
      state.forgetLinkedLearning(sampleID: sampleID)
      state.invalidatePendingWork(.corpusForgotten)
    }
  }
  /**
   Rebuilds derived learning and correction examples from the current reviewed labels.

   Learning samples, campaign signatures and correction examples linked to no current label are
   removed, and linked ones take their label's current value. Admitted predictions, sender rules
   and examples saved without a sample identity are kept.
   */
  public static func rebuildLearning(store: Store) async throws {
    try await StateRepository.update(store, loading: slices) { state in
      let labels = Dictionary(
        state.reviewedLabels.map { ($0.linkedSampleID, $0.label) },
        uniquingKeysWith: { _, latest in latest }
      )
      state.learning.retainExplicit(matching: labels)
      state.corrections = state.corrections.compactMap { example in
        guard let sampleID = example.sampleID else { return example }
        guard let label = labels[sampleID] else { return nil }
        var linked = example
        linked.label = label
        return linked
      }
      state.invalidatePendingWork(.learningRebuilt)
    }
  }
}

/// One message prepared for import, with evidence read before its headers are discarded.
private struct ImportedSample: Sendable {
  let message: ParsedMessage
  let evidence: EvidenceBundle
  let sampleID: String
  init(_ message: ParsedMessage) {
    evidence = EvidenceBundle(message: message)
    self.message = message.boundedForRetention()
    sampleID = LearningSample.identity(for: self.message)
  }
}

extension ReviewedLabel {
  /// The sample identity that links this label to its correction examples and learning.
  var linkedSampleID: String { sampleID ?? message.map(LearningSample.identity) ?? id }
}

extension AppState {
  /// Current reviewed-label usage under the shared retention policy.
  public var reviewedLabelCapacity: ReviewedLabelCapacity {
    ReviewedLabelCapacity(
      limit: RetentionLimits.reviewedLabels,
      imported: reviewedLabels.filter { $0.origin == .reviewedImport }.count,
      corrections: reviewedLabels.filter { $0.origin == .correction }.count
    )
  }
  /**
   Adds or replaces `label` under the policy ``ReviewedLabelCapacity`` describes.

   - Returns: Whether `label` is kept; a correction label is not kept when imported labels fill
     the limit.
   */
  @discardableResult mutating func insertReviewedLabel(_ label: ReviewedLabel) -> Bool {
    let sampleID = label.linkedSampleID
    reviewedLabels.removeAll { $0.id == label.id || $0.linkedSampleID == sampleID }
    reviewedLabels.append(label)
    while reviewedLabels.count > RetentionLimits.reviewedLabels,
      let oldest = reviewedLabels.indices.filter({ reviewedLabels[$0].origin == .correction })
        .min(by: { reviewedLabels[$0].date < reviewedLabels[$1].date })
    {
      forgetLinkedLearning(sampleID: reviewedLabels.remove(at: oldest).linkedSampleID)
    }
    return reviewedLabels.contains { $0.id == label.id }
  }
  /// Removes the correction examples and learning derived from one sample.
  mutating func forgetLinkedLearning(sampleID: String) {
    corrections.removeAll { $0.sampleID == sampleID }
    learning.forget(sampleID: sampleID)
  }
  fileprivate func requireImportCapacity(for samples: [ImportedSample]) throws {
    let incoming = Set(samples.map(\.sampleID))
    let identities = Set(samples.map(\.message.hash))
    let kept = reviewedLabels.filter {
      $0.origin == .reviewedImport && !incoming.contains($0.linkedSampleID)
        && !identities.contains($0.id)
    }
    let capacity = reviewedLabelCapacity
    guard kept.count + incoming.count <= capacity.limit else {
      throw CorpusError.labelLimitReached(
        limit: capacity.limit,
        remaining: capacity.remainingImports
      )
    }
  }
  fileprivate mutating func importLabel(_ sample: ImportedSample, label: MailLabel) {
    var reviewed = ReviewedLabel(
      identity: MessageIdentity(accountID: nil, contentHash: sample.message.hash),
      label: label,
      message: settings.advancedOptions.retainReviewedContent ? sample.message : nil,
      sampleID: sample.sampleID
    )
    reviewed.origin = .reviewedImport
    forgetLinkedLearning(sampleID: sample.sampleID)
    insertReviewedLabel(reviewed)
    learning.recordCorrection(
      message: sample.message,
      evidence: sample.evidence,
      label: label,
      sampleID: sample.sampleID
    )
    var example = CorrectionExample(
      sender: sample.message.fromAddress,
      domain: DomainResolver().domain(ofAddress: sample.message.fromAddress),
      subject: sample.message.subject,
      excerpt: sample.message.text,
      label: label,
      promptScope: .everyAccount
    )
    example.sampleID = sample.sampleID
    corrections.append(example)
  }
}

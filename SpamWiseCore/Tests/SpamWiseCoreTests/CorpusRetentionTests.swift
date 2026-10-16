import Foundation
import Testing
import SpamWiseCore

/// One correction label, then imported labels that fill the reviewed-label limit.
@Suite
struct `Reviewed-label retention` {
  private let store: Store
  private let adapter = RecordingAdapter()
  private let pipeline: Pipeline
  private let corrected: ReviewedLabel
  private let message: ParsedMessage
  /// State once the import that reaches the limit has been saved.
  private let full: AppState

  init() async throws {
    store = try testStore()
    pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(verdict: .init(label: .review, confidence: 60, reason: "unsure"))
    )
    let first = await pipeline.process(try envelope(), adapter: adapter)
    _ = try await pipeline.correct(recordID: first.id, label: .junk, adapter: adapter)
    corrected = try #require(try await StateRepository.load(store).reviewedLabels.first)
    try await StateRepository.update(store) { state in
      for index in 1..<RetentionLimits.reviewedLabels {
        let hash = stableHash(Data("imported \(index)".utf8))
        var label = ReviewedLabel(
          identity: .init(accountID: nil, contentHash: hash),
          label: .junk,
          sampleID: hash
        )
        label.origin = .reviewedImport
        state.reviewedLabels.append(label)
      }
    }
    message = try MIMEParser().parse(fixture("personal"))
    try await CorpusManagement.importMessages([message], label: .inbox, store: store)
    full = try await StateRepository.load(store)
  }

  @Test
  func `rolls off the oldest correction label and its example for an import`() {
    #expect(full.reviewedLabelCapacity.imported == RetentionLimits.reviewedLabels)
    #expect(!full.reviewedLabels.contains { $0.id == corrected.id })
    #expect(!full.corrections.contains { $0.sampleID == corrected.sampleID })
  }

  @Test
  func `refuses an import beyond the limit`() async {
    var another = message
    another.subject = "Another reviewed example"
    another.hash = "another"
    await #expect(
      throws: CorpusError.labelLimitReached(limit: RetentionLimits.reviewedLabels, remaining: 0)
    ) {
      try await CorpusManagement.importMessages([another], label: .inbox, store: store)
    }
  }

  @Test
  func `saves a correction without a label while imported labels fill the limit`() async throws {
    let second = await pipeline.process(try envelope("unsolicited-newsletter"), adapter: adapter)
    _ = try await pipeline.correct(recordID: second.id, label: .inbox, adapter: adapter)
    #expect(try await StateRepository.load(store).reviewedLabels == full.reviewedLabels)
  }
}

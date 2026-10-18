import Foundation
import Testing
import SpamWiseCore

@Test func `keeps imported labels at the limit and rolls off the oldest correction labels`()
  async throws
{
  let store = try testStore(), adapter = RecordingAdapter()
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .review, confidence: 60, reason: "unsure"))
  )
  let first = await pipeline.process(try envelope(), adapter: adapter)
  _ = try await pipeline.correct(recordID: first.id, label: .junk, adapter: adapter)
  let corrected = try #require(try await StateRepository.load(store).reviewedLabels.first)
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
  let message = try MIMEParser().parse(fixture("personal"))
  try await CorpusManagement.importMessages([message], label: .inbox, store: store)
  let full = try await StateRepository.load(store)
  #expect(full.reviewedLabelCapacity.imported == RetentionLimits.reviewedLabels)
  #expect(!full.reviewedLabels.contains { $0.id == corrected.id })
  #expect(!full.corrections.contains { $0.sampleID == corrected.sampleID })
  var another = message
  another.subject = "Another reviewed example"
  another.hash = "another"
  await #expect(
    throws: CorpusError.labelLimitReached(limit: RetentionLimits.reviewedLabels, remaining: 0)
  ) {
    try await CorpusManagement.importMessages([another], label: .inbox, store: store)
  }
  let second = await pipeline.process(try envelope("unsolicited-newsletter"), adapter: adapter)
  _ = try await pipeline.correct(recordID: second.id, label: .inbox, adapter: adapter)
  #expect(try await StateRepository.load(store).reviewedLabels == full.reviewedLabels)
}

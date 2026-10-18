import Foundation
import Testing
import SpamWiseCore

@Test func `releases unattempted claims and never adds a failure record after acting`() async throws
{
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "lure"))
  )
  await adapter.deny(with: ActionNotAttempted(cause: IntegrationError.accountUnverified))
  let refused = await pipeline.process(try envelope(), adapter: adapter)
  #expect(refused.outcome == .failed)
  #expect(try await StateRepository.load(store).claimedActions.isEmpty)
  await adapter.allow()
  await adapter.afterEachAction { try blockStorage(store) }
  let moved = await pipeline.process(try envelope(), adapter: adapter)
  try restoreStorage(store)
  #expect(moved.outcome == .applied)
  #expect(await adapter.actions == [.moveToJunk])
  let records = try await StateRepository.load(store).records
  #expect(records.map(\.outcome) == [.failed, .requested])
  #expect(records.last?.id == moved.id)
}
@Test func `restores the corrected label's mail state and overrides conflicting sender rules`()
  async throws
{
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .review, confidence: 60, reason: "unsure"))
  )
  let flagged = await pipeline.process(try envelope(), adapter: adapter)
  let good = try await pipeline.correct(recordID: flagged.id, label: .inbox, adapter: adapter)
  let review = try await pipeline.correct(recordID: good.id, label: .review, adapter: adapter)
  let junk = try await pipeline.correct(recordID: review.id, label: .junk, adapter: adapter)
  #expect(
    await adapter.actions == [
      .orangeFlag, .moveToInbox, .clearOrangeFlag, .moveToInbox, .orangeFlag, .clearOrangeFlag,
      .moveToJunk
    ]
  )
  #expect([good, review, junk].allSatisfy { $0.outcome == .applied })
  let labels = try await StateRepository.load(store).reviewedLabels
  #expect(labels.map(\.sampleID) == [flagged.sampleID])
  let domainGood = try await pipeline.correct(
    recordID: junk.id,
    label: .inbox,
    scope: .domain,
    adapter: adapter
  )
  #expect(try await StateRepository.load(store).rules.map(\.scope) == [.domain])
  #expect(try await pipeline.overridingRule(for: domainGood) == nil)
  let reviewed = try await pipeline.correct(recordID: domainGood.id, label: .review)
  #expect(try await pipeline.overridingRule(for: reviewed)?.scope == .domain)
}

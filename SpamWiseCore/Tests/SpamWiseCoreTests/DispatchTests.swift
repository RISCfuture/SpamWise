import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Junk dispatch claims` {
  let store: Store
  let adapter = RecordingAdapter()
  let pipeline: Pipeline

  init() async throws {
    store = try testStore()
    try await enableActions(store)
    pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "lure"))
    )
  }

  @Test
  func `releases the claim of an action that was never attempted`() async throws {
    await adapter.deny(with: ActionNotAttempted(cause: IntegrationError.accountUnverified))
    let refused = await pipeline.process(try envelope(), adapter: adapter)
    #expect(refused.outcome == .failed)
    #expect(try await StateRepository.load(store).claimedActions.isEmpty)
  }

  @Test
  func `adds no failure record when storage fails after acting`() async throws {
    await adapter.afterEachAction { [store] in try blockStorage(store) }
    let moved = await pipeline.process(try envelope(), adapter: adapter)
    try restoreStorage(store)
    #expect(moved.outcome == .applied)
    #expect(await adapter.actions == [.moveToJunk])
    let records = try await StateRepository.load(store).records
    #expect(records.map(\.outcome) == [.requested])
    #expect(records.last?.id == moved.id)
  }
}

@Suite
struct `Correction dispatch` {
  let store: Store
  let adapter = RecordingAdapter()
  let pipeline: Pipeline
  /// The fixture's Review decision, flagged orange in Mail.
  let flagged: DecisionRecord

  init() async throws {
    store = try testStore()
    try await enableActions(store)
    pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(verdict: .init(label: .review, confidence: 60, reason: "unsure"))
    )
    flagged = await pipeline.process(try envelope(), adapter: adapter)
  }

  /// Corrects the decision to Good, then Review, then Junk, returning the three corrections.
  private func correctToGoodReviewAndJunk() async throws -> [DecisionRecord] {
    let good = try await pipeline.correct(recordID: flagged.id, label: .inbox, adapter: adapter)
    let review = try await pipeline.correct(recordID: good.id, label: .review, adapter: adapter)
    let junk = try await pipeline.correct(recordID: review.id, label: .junk, adapter: adapter)
    return [good, review, junk]
  }

  @Test
  func `restores each corrected label's mail state`() async throws {
    let corrections = try await correctToGoodReviewAndJunk()
    #expect(
      await adapter.actions == [
        .orangeFlag, .moveToInbox, .clearOrangeFlag, .moveToInbox, .orangeFlag, .clearOrangeFlag,
        .moveToJunk
      ]
    )
    #expect(corrections.map(\.outcome) == [.applied, .applied, .applied])
  }

  @Test
  func `keeps one reviewed label for a message corrected repeatedly`() async throws {
    _ = try await correctToGoodReviewAndJunk()
    let labels = try await StateRepository.load(store).reviewedLabels
    #expect(labels.map(\.sampleID) == [flagged.sampleID])
  }

  @Test
  func `replaces the contradicting address rule with a domain correction`() async throws {
    let junk = try #require(try await correctToGoodReviewAndJunk().last)
    let domainGood = try await pipeline.correct(
      recordID: junk.id,
      label: .inbox,
      scope: .domain,
      adapter: adapter
    )
    #expect(try await StateRepository.load(store).rules.map(\.scope) == [.domain])
    #expect(try await pipeline.overridingRule(for: domainGood) == nil)
  }

  @Test
  func `reports a domain rule that overrides a later review correction`() async throws {
    let domainGood = try await pipeline.correct(
      recordID: flagged.id,
      label: .inbox,
      scope: .domain,
      adapter: adapter
    )
    let reviewed = try await pipeline.correct(recordID: domainGood.id, label: .review)
    #expect(try await pipeline.overridingRule(for: reviewed)?.scope == .domain)
  }
}

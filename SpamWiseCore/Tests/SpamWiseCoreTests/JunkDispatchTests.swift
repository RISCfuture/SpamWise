import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Junk dispatch with actions enabled` {
  private let store: Store
  private let adapter = RecordingAdapter()
  private let pipeline: Pipeline
  /// The identity the adapter reports for the message after moving it to Junk.
  private let moved: MessageIdentity

  init() async throws {
    store = try testStore()
    try await enableActions(store)
    await adapter.observe(store)
    var moved = try envelope().identity
    moved.localID = 42; moved.mailboxValidity = 99; moved.mailbox = "Junk"
    await adapter.moveIdentity(to: moved)
    self.moved = moved
    pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(
        verdict: .init(
          label: .junk,
          confidence: 99,
          reason: "lure",
          usage: .init(input: 100, output: 10, estimated: false)
        )
      )
    )
  }

  private func enableMarkingRead() async throws {
    try await StateRepository.editSettings(store) { $0.mailOptions.markJunkRead = true }
  }

  @Test
  func `persists the decision and action claim before acting`() async throws {
    let record = await pipeline.process(try envelope(), adapter: adapter)
    #expect(record.outcome == .applied)
    #expect(await adapter.actions == [.moveToJunk])
    #expect(await adapter.persistedBeforeAction == [true])
  }

  @Test
  func `records the identity Mail reports after the move`() async throws {
    #expect(await pipeline.process(try envelope(), adapter: adapter).identity == moved)
  }

  @Test
  func `charges the measured cost to the decision's month`() async throws {
    let record = await pipeline.process(try envelope(), adapter: adapter)
    let costs = try await StateRepository.load(store).costByMonth
    #expect(costs[AppState.monthKey(record.date)] == record.verdict?.usage.estimatedCost)
  }

  @Test
  func `acts once for a repeated delivery`() async throws {
    let first = await pipeline.process(try envelope(), adapter: adapter)
    let second = await pipeline.process(try envelope(), adapter: adapter)
    #expect(first.id == second.id)
    #expect(await adapter.actions == [.moveToJunk])
  }

  @Test(.timeLimit(.minutes(1)))
  func `acts once when two pipelines classify the same delivery at the same time`()
    async throws
  {
    let latch = ClassificationLatch(), message = try envelope(), adapter = adapter
    let pipelines = (0..<2).map { _ in gatedPipeline(latch) }
    let outcomes = await withTaskGroup(of: DecisionRecord.self) { group in
      for pipeline in pipelines {
        group.addTask { await pipeline.process(message, adapter: adapter) }
      }
      await latch.waitForArrivals(pipelines.count)
      await latch.release()
      return await group.reduce(into: []) { $0.append($1) }
    }
    #expect(outcomes.map(\.outcome).sorted { $0.rawValue < $1.rawValue } == [.applied, .duplicate])
    #expect(await adapter.actions == [.moveToJunk])
    let applied = try #require(outcomes.first { $0.outcome == .applied })
    let claims = try await StateRepository.load(store, StateSlices(claims: .all)).claimedActions
    #expect(claims[message.identity.key] == applied.id)
  }

  @Test(.timeLimit(.minutes(1)))
  func `refuses a second delivery while the first is still being classified`() async throws {
    let latch = ClassificationLatch(), calls = Counter(), message = try envelope()
    let pipeline = gatedPipeline(latch, counting: calls), adapter = adapter
    let first = Task { await pipeline.process(message, adapter: adapter) }
    await latch.waitForArrivals(1)
    let second = await pipeline.process(message, adapter: adapter)
    await latch.release()
    #expect(second.outcome == .duplicate)
    #expect(second.decision.reason == .duplicateCallback)
    #expect(await first.value.outcome == .applied)
    #expect(calls.value == 1)
  }

  /// A pipeline over this suite's store whose Junk verdicts wait at `latch`.
  private func gatedPipeline(_ latch: ClassificationLatch, counting calls: Counter = Counter())
    -> Pipeline
  {
    Pipeline(
      store: store,
      classifier: MockClassifier(operation: { _ in
        calls.increment()
        await latch.arriveAndWait()
        return Verdict(label: .junk, confidence: 99, reason: "lure")
      })
    )
  }

  @Test
  func `previews a processed message without acting or reusing its record`() async throws {
    let first = await pipeline.process(try envelope(), adapter: adapter)
    let preview = await pipeline.process(try envelope(), adapter: adapter, forceDryRun: true)
    #expect(preview.id != first.id)
    #expect(preview.outcome == .dryRun)
    #expect(await adapter.actions == [.moveToJunk])
  }

  @Test
  func `requests read status only once enabled and not again for a repeated delivery`()
    async throws
  {
    _ = await pipeline.process(try envelope(), adapter: adapter)
    #expect(await adapter.readRequests == 0)
    try await enableMarkingRead()
    let corrected = try await pipeline.correct(
      recordID: try #require(await StateRepository.load(store).records.first).id,
      label: .junk,
      adapter: adapter
    )
    _ = await pipeline.process(try envelope(), adapter: adapter)
    #expect(corrected.readStatusOutcome != nil)
    #expect(await adapter.readRequests == 1)
  }

  @Test
  func `marks corrected Junk read as a step of the correction`() async throws {
    try await enableMarkingRead()
    let first = await pipeline.process(try envelope(), adapter: adapter)
    _ = try await pipeline.correct(recordID: first.id, label: .junk, adapter: adapter)
    #expect(await adapter.readRequests == 2)
    #expect(await adapter.correctionReadRequests == 1)
    #expect(await adapter.junkMarkClaimedBeforeRequest.isEmpty)
  }

  @Test(arguments: [
    (JunkMarkChange?.some(.cleared), ActionOutcome.applied), (.absent, .noAction), (nil, .failed)
  ])
  func `clears Mail's junk mark once a Good correction's move to Inbox is confirmed`(
    change: JunkMarkChange?,
    expected: ActionOutcome
  ) async throws {
    let first = await pipeline.process(try envelope(), adapter: adapter)
    await adapter.reportJunkMark(change)
    let correction = try await pipeline.correct(recordID: first.id, label: .inbox, adapter: adapter)
    #expect(correction.outcome == .applied)
    #expect(correction.junkMarkOutcome == expected)
    #expect((correction.junkMarkError == nil) == (change != nil))
    #expect(await adapter.junkMarkClaimedBeforeRequest == [true])
    let saved = try await StateRepository.load(store).records.first { $0.id == correction.id }
    #expect(saved?.junkMarkOutcome == expected)
  }

  @Test(arguments: [false, true])
  func `records Junk read status separately from the correction outcome`(readSucceeds: Bool)
    async throws
  {
    let first = await pipeline.process(try envelope(), adapter: adapter)
    try await enableMarkingRead()
    if readSucceeds { await adapter.allowMarkRead() }
    let correction = try await pipeline.correct(recordID: first.id, label: .junk, adapter: adapter)
    #expect(correction.outcome == .applied)
    #expect(correction.readStatusOutcome == (readSucceeds ? .applied : .failed))
    #expect((correction.readStatusError == nil) == readSucceeds)
    #expect(await adapter.persistedBeforeAction == [true, true])
  }
}

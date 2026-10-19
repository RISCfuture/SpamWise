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

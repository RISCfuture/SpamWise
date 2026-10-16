import Foundation
import Testing
import SpamWiseCore
@Test(arguments: FilteringStrength.allCases) func `decision threshold branches`(
  _ strength: FilteringStrength
) throws {
  #expect(
    try Decision.evaluate(.init(label: .inbox, confidence: 1, reason: "good"), strength: strength)
      .action == .none
  )
  #expect(
    try Decision.evaluate(
      .init(label: .review, confidence: 100, reason: "uncertain"),
      strength: strength
    ).action == .orangeFlag
  )
  #expect(
    try Decision.evaluate(
      .init(label: .review, confidence: 50, reason: "uncertain"),
      review: .orangeBackground
    ).action == .orangeBackground
  )
  #expect(
    try Decision.evaluate(
      .init(label: .junk, confidence: strength.threshold - 1, reason: "spam"),
      strength: strength
    ).label == .review
  )
  #expect(
    try Decision.evaluate(
      .init(label: .junk, confidence: strength.threshold, reason: "spam"),
      strength: strength
    ).action == .moveToJunk
  )
  #expect(throws: ClassificationError.self) {
    try Decision.evaluate(.init(label: .junk, confidence: 999, reason: "invalid"))
  }
}
actor RecordingAdapter: MailClientAdapter {
  var actions: [MailAction] = []
  var fail = false
  func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope? { nil }
  func recentMessages(limit: Int) async throws -> [MailEnvelope] { [] }
  func importHistory() async throws -> [String: HistoryIndex] { [:] }
  func perform(_ action: MailAction, for identity: MessageIdentity) async throws -> ActionReceipt {
    if fail { throw IntegrationError.permissionDenied }
    actions.append(action); return .init(confirmed: true)
  }
  func deny() { fail = true }
}
func testStore() throws -> Store {
  try Store(
    url: FileManager.default.temporaryDirectory.appending(
      path: "SpamWise-tests/\(UUID())/state.store"
    )
  )
}
func envelope(_ name: String = "filler-spam") throws -> MailEnvelope {
  let raw = try fixture(name)
  return MailEnvelope(
    identity: .init(accountID: "account-A", contentHash: stableHash(raw)),
    raw: raw
  )
}
func enableActions(_ store: Store) async throws {
  try await StateRepository.update(store) { state in
    state.settings.dryRun = false; state.settings.route = .mailRule
    state.settings.validatedAccounts = ["account-A"]
  }
}
@Test func `persist before action and never duplicate`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  let pipeline = Pipeline(
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
  let first = await pipeline.process(try envelope(), adapter: adapter)
  let second = await pipeline.process(try envelope(), adapter: adapter)
  let state = try await StateRepository.load(store)
  #expect(state.costByMonth?[AppState.monthKey(first.date)] == first.verdict?.usage.estimatedCost)
  #expect(first.outcome == .applied)
  #expect(first.id == second.id)
  #expect(await adapter.actions == [.moveToJunk])
  #expect(try await StateRepository.load(store).records.first?.verdict?.label == .junk)
}
@Test func `dry run pause and failure do not act`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "lure"))
  )
  #expect(await pipeline.process(try envelope(), adapter: adapter).outcome == .dryRun)
  try await StateRepository.update(store) { $0.settings.paused = true }
  #expect(await pipeline.process(try envelope(), adapter: adapter).outcome == .paused)
  #expect(await adapter.actions.isEmpty)
  let failing = Pipeline(
    store: try testStore(),
    classifier: MockClassifier(operation: { _ in throw ClassificationError.network })
  )
  #expect(await failing.process(try envelope(), adapter: adapter).outcome == .unclassified)
}
@Test func `retry queue is bounded and correction invalidates it`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in throw ClassificationError.rateLimited })
  )
  let failed = await pipeline.process(try envelope(), adapter: adapter)
  let pending = try #require(await StateRepository.load(store).retries.first)
  _ = await pipeline.process(try envelope(), adapter: adapter, forceDryRun: true)
  let afterFailure = try #require(await StateRepository.load(store).retries.first)
  #expect(afterFailure.dryRun == pending.dryRun)
  #expect(afterFailure.due == pending.due)
  let preview = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "preview"))
  )
  _ = await preview.process(try envelope(), adapter: adapter, forceDryRun: true)
  #expect(try await StateRepository.load(store).retries.count == 1)
  _ = try await pipeline.correct(recordID: failed.id, label: .inbox, adapter: adapter)
  let state = try await StateRepository.load(store)
  #expect(state.retries.isEmpty)
  #expect(state.rules.count == 1)
  #expect(state.rules[0].scope == .address)
  #expect(state.corrections.count == 1)
  #expect(await adapter.actions.isEmpty)
}
@Test func `correction during classification supersedes old verdict`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  let initial = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .inbox, confidence: 99, reason: "good"))
  )
  let record = await initial.process(try envelope(), adapter: adapter)
  let delayed = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      try await Task.sleep(for: .milliseconds(150))
      return .init(label: .junk, confidence: 100, reason: "late")
    })
  )
  let task = Task { await delayed.process(try envelope(), adapter: adapter) }
  try await Task.sleep(for: .milliseconds(30))
  _ = try await initial.correct(recordID: record.id, label: .inbox, adapter: adapter)
  #expect(try await task.value.outcome == .superseded)
  #expect(await adapter.actions == [.moveToInbox])
}
@Test func `action failure is separate from verdict`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  await adapter.deny(); try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .review, confidence: 50, reason: "uncertain"))
  )
  let record = await pipeline.process(try envelope(), adapter: adapter)
  #expect(record.verdict?.label == .review)
  #expect(record.outcome == .failed)
  #expect(record.actionError != nil)
}
@Test func `persistence failure prevents action`() async throws {
  let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let store = try Store(url: dir)
  let adapter = RecordingAdapter()
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .junk, confidence: 100, reason: "spam"))
  )
  #expect(await pipeline.process(try envelope(), adapter: adapter).outcome == .unclassified)
  #expect(await adapter.actions.isEmpty)
}

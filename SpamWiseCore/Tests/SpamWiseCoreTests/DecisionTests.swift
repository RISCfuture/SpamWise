import Foundation
import Testing
import SpamWiseCore
@Test(arguments: FilteringStrength.allCases) func `selects actions at each decision threshold`(
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
  var updatedIdentity: MessageIdentity?
  var lookups = 0
  var message: MailEnvelope?
  func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope? {
    lookups += 1
    return message
  }
  func retain(_ envelope: MailEnvelope) { message = envelope }
  func recentMessages(limit: Int) async throws -> [MailEnvelope] { [] }
  func importHistory() async throws -> [String: HistoryIndex] { [:] }
  func perform(_ action: MailAction, for identity: MessageIdentity) async throws -> ActionReceipt {
    if fail { throw IntegrationError.permissionDenied }
    actions.append(action); return .init(confirmed: true, updatedIdentity: updatedIdentity)
  }
  func deny() { fail = true }
  func moveIdentity(to identity: MessageIdentity) { updatedIdentity = identity }
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
@Test func `persists before acting and prevents duplicate actions`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  var moved = try envelope().identity
  moved.localID = 42; moved.mailboxValidity = 99; moved.mailbox = "Junk"
  await adapter.moveIdentity(to: moved)
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
  #expect(first.identity == moved)
  #expect(first.id == second.id)
  #expect(await adapter.actions == [.moveToJunk])
  #expect(try await StateRepository.load(store).records.first?.verdict?.label == .junk)
}
@Test func `prevents actions during dry runs pauses and failures`() async throws {
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
  try await StateRepository.editSettings(store) {
    $0.paused = false
    $0.mailOptions.localOnly = true
  }
  let network = StubRDAP()
  let privatePipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { input in
      #expect(input.evidence.domainAgeDays == nil)
      return Verdict(label: .review, confidence: 10, reason: "unknown")
    }),
    rdap: RDAPLookup(fetcher: network)
  )
  _ = await privatePipeline.process(try envelope(), adapter: adapter)
  #expect(await network.calls == 0)
  let configured = ConfiguredClassifier(
    store: store,
    credential: { _ in
      Issue.record("Local mode must reject cloud classification before reading credentials")
      return "unused"
    }
  )
  await #expect(throws: ClassificationError.configuration) {
    try await configured.classify(
      ClassificationInput(
        message: MIMEParser().parse(fixture("filler-spam")),
        evidence: EvidenceBundle(message: MIMEParser().parse(fixture("filler-spam")))
      )
    )
  }
}

@Test
func `corrects selected mail without classifying and excludes own addresses from implicit trust`()
  async throws
{
  let store = try testStore(), adapter = RecordingAdapter()
  let selected = try envelope()
  let message = try MIMEParser().parse(selected.raw)
  try await StateRepository.update(store) {
    $0.contactAddresses = [message.fromAddress]
    $0.contactsUpdatedAt = .now
    $0.ownAddresses = [message.fromAddress]
  }
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .review, confidence: 50, reason: "unknown"))
  )
  let classified = await pipeline.process(selected)
  #expect(classified.path == "model")
  let correction = try await pipeline.correct(envelope: selected, label: .inbox, adapter: adapter)
  #expect(correction.correctedLabel == .inbox)
  #expect(correction.outcome == .dryRun)
  #expect(await adapter.actions.isEmpty)
  let ruled = await pipeline.process(selected)
  #expect(ruled.path == "gate")
  #expect(ruled.decision.label == .inbox)
}
@Test func `preserves pending retries during previews and invalidates them on correction`()
  async throws
{
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
  let review = try await pipeline.correct(recordID: failed.id, label: .review, adapter: adapter)
  let reviewed = try await StateRepository.load(store)
  #expect(review.decision.action == .orangeFlag)
  #expect(reviewed.rules.isEmpty)
  #expect(reviewed.reviewedLabels?.first?.label == .review)
  #expect(reviewed.corrections.last?.label == .review)
  #expect(await adapter.lookups == 0)
  #expect(reviewed.learning == nil)
  await adapter.retain(try envelope())
  try await StateRepository.update(store) { state in
    var options = state.settings.advancedOptions
    options.retainReviewedContent = true
    state.settings.advanced = options
  }
  _ = try await pipeline.correct(recordID: failed.id, label: .inbox, adapter: adapter)
  let retained = try await StateRepository.load(store)
  #expect(await adapter.lookups == 1)
  #expect(retained.reviewedLabels?.first?.message != nil)
  #expect(retained.learning == nil)
  try await StateRepository.update(store) { state in
    var options = state.settings.advancedOptions
    options.retainReviewedContent = false
    options.bayes = true
    state.settings.advanced = options
  }
  _ = try await pipeline.correct(recordID: failed.id, label: .junk, adapter: adapter)
  let learned = try await StateRepository.load(store)
  #expect(await adapter.lookups == 2)
  #expect(learned.reviewedLabels?.first?.message == nil)
  #expect(learned.reviewedLabels?.first?.sampleID != nil)
  #expect(learned.learning?.samples.count == 1)
}
@Test func `consumes retries only within the selected account`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  let failed = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      throw ClassificationError.rateLimited
    })
  )
  let first = try envelope()
  var second = first; second.identity.accountID = "account-B"
  _ = await failed.process(first, adapter: adapter)
  _ = await failed.process(second, adapter: adapter)
  let due = Date().addingTimeInterval(35)
  let successful = Pipeline(
    store: store,
    classifier: MockClassifier(
      verdict:
        .init(label: .inbox, confidence: 99, reason: "Retry succeeded")
    )
  )
  await successful.retryDue(adapter: adapter, now: due, accountID: "account-A")
  let state = try await StateRepository.load(store)
  #expect(state.retries.map { $0.identity.accountID } == ["account-B"])
  #expect(state.records.last?.identity.accountID == "account-A")
  #expect(state.records.last?.decision.label == .inbox)
  #expect(await adapter.actions.isEmpty)
}
@Test func `supersedes pending verdicts when a correction arrives`() async throws {
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
@Test func `records action failures separately from verdicts`() async throws {
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
@Test func `prevents actions after persistence fails`() async throws {
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

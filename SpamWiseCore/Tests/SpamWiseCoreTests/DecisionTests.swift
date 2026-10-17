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
  #expect(await adapter.readRequests == 0)
  try await StateRepository.editSettings(store) { $0.mailOptions.markJunkRead = true }
  let correction = try await pipeline.correct(recordID: first.id, label: .junk, adapter: adapter)
  #expect(correction.outcome == .applied)
  #expect(correction.readStatusOutcome == .failed)
  #expect(correction.readStatusError != nil)
  _ = await pipeline.process(try envelope(), adapter: adapter)
  #expect(await adapter.readRequests == 1)
  #expect(try await StateRepository.load(store).records.first?.verdict?.label == .junk)
  let preview = await pipeline.process(try envelope(), adapter: adapter, forceDryRun: true)
  #expect(preview.id != first.id)
  #expect(preview.outcome == .dryRun)
  #expect(await adapter.actions == [.moveToJunk, .moveToJunk])
  await adapter.allowMarkRead()
  let markedRead = try await pipeline.correct(recordID: first.id, label: .junk, adapter: adapter)
  #expect(markedRead.readStatusOutcome == .applied)
  #expect(markedRead.outcome == .applied)
  #expect(await adapter.readRequests == 2)
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
  try await StateRepository.editSettings(store) { $0.mailOptions.localOnly = false }
  _ = await privatePipeline.process(try envelope(), adapter: adapter, forceDryRun: true)
  #expect(await network.calls == 0)
  try await StateRepository.editSettings(store) {
    $0.mailOptions.localOnly = true
    $0.advancedOptions.domainRegistrationLookup = true
  }
  _ = await privatePipeline.process(try envelope(), adapter: adapter, forceDryRun: true)
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
  try await TrustExclusions.save(" ALIAS@EXAMPLE.ORG \nfriend@example.org", store: store)
  let excluded = try await StateRepository.load(store)
  #expect(
    excluded.settings.mailOptions.trustExclusions == ["alias@example.org", "friend@example.org"]
  )
  await #expect(throws: RuleManagementError.self) {
    try await TrustExclusions.save("valid@example.org\nnot an address", store: store)
  }
  #expect(try await StateRepository.load(store).revision == excluded.revision)
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
  let reviewedID = try #require(reviewed.reviewedLabels?.first?.id)
  try await CorpusManagement.relabel(id: reviewedID, label: .inbox, store: store)
  #expect(try await StateRepository.load(store).corrections.allSatisfy { $0.label == .inbox })
  try await CorpusManagement.forget(id: reviewedID, store: store)
  #expect(try await StateRepository.load(store).corrections.isEmpty)
  #expect(await adapter.lookups == 0)
  await adapter.retain(try envelope())
  try await StateRepository.editSettings(store) {
    $0.advancedOptions.retainReviewedContent = true
  }
  _ = try await pipeline.correct(recordID: failed.id, label: .inbox, adapter: adapter)
  let retained = try await StateRepository.load(store)
  #expect(await adapter.lookups == 1)
  #expect(retained.reviewedLabels?.first?.message != nil)
  #expect(retained.learning == nil)
  try await StateRepository.editSettings(store) {
    $0.advancedOptions.retainReviewedContent = false
    $0.advancedOptions.bayes = true
  }
  _ = try await pipeline.correct(recordID: failed.id, label: .junk, adapter: adapter)
  let learned = try await StateRepository.load(store)
  #expect(await adapter.lookups == 2)
  #expect(learned.reviewedLabels?.first?.message == nil)
  #expect(learned.reviewedLabels?.first?.sampleID != nil)
  #expect(learned.learning?.samples.count == 1)
  #expect(try #require(learned.correctionUndo).isAvailable(in: learned))
  try await CorrectionUndo.apply(store: store)
  let undone = try await StateRepository.load(store)
  #expect(undone.rules == retained.rules)
  #expect(undone.learning == retained.learning)
  #expect(undone.corrections == retained.corrections)
  #expect(undone.records.last?.correctionUndone == true)
  #expect(await adapter.actions.isEmpty)
  _ = try await pipeline.correct(recordID: failed.id, label: .junk, adapter: adapter)
  try await StateRepository.editSettings(store) { $0.paused = true }
  await #expect(throws: IntegrationError.staleMessage) {
    try await CorrectionUndo.apply(store: store)
  }
  try await StateRepository.editSettings(store) { $0.advanced?.bayes = false }
  _ = try await pipeline.correct(recordID: failed.id, label: .inbox, adapter: adapter)
  let beforeForget = try await StateRepository.load(store)
  try await CorpusManagement.forget(id: reviewedID, store: store)
  let forgotten = try await StateRepository.load(store)
  #expect(forgotten.corrections.isEmpty)
  #expect(forgotten.learning?.samples.isEmpty == true)
  #expect(forgotten.rules == beforeForget.rules)
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
  let (started, signalStarted) = AsyncStream<Void>.makeStream()
  let (released, release) = AsyncStream<Void>.makeStream()
  let delayed = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      signalStarted.yield(())
      signalStarted.finish()
      for await _ in released { break }
      try Task.checkCancellation()
      return .init(label: .junk, confidence: 100, reason: "late")
    })
  )
  let message = try envelope()
  let task = Task {
    let result = await delayed.process(message, adapter: adapter)
    signalStarted.finish()
    return result
  }
  defer {
    signalStarted.finish()
    release.finish()
    task.cancel()
  }
  var starts = started.makeAsyncIterator()
  try #require(await starts.next() != nil)
  _ = try await initial.correct(recordID: record.id, label: .inbox, adapter: adapter)
  release.yield(())
  release.finish()
  #expect(await task.value.outcome == .superseded)
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

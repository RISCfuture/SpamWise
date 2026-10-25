import Foundation
import Testing
@testable import SpamWiseCore

@Suite
struct `Processed-message index` {
  private let store: Store
  private let adapter = RecordingAdapter()
  private let calls = Counter()
  private let pipeline: Pipeline
  private let previewed: MailEnvelope
  private let transient: MailEnvelope
  private let unparseable: MailEnvelope
  private let keyless: MailEnvelope
  private var batch: [MailEnvelope] { [previewed, transient, unparseable] }

  init() throws {
    store = try testStore()
    let calls = calls
    pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(operation: { input in
        calls.increment()
        if input.message.subject.contains("cart") { throw ClassificationError.network }
        if input.message.subject.contains("Dinner") { throw ClassificationError.missingCredential }
        return Verdict(label: .junk, confidence: 99, reason: "lure")
      })
    )
    previewed = try envelope()
    transient = try envelope("stranger-cart")
    var unparseable = transient
    unparseable.raw = Data(repeating: 65, count: 2_100_000)
    unparseable.identity.contentHash = stableHash(unparseable.raw)
    self.unparseable = unparseable
    keyless = try envelope("personal")
  }

  /// Runs automatic discovery over `envelopes`, returning how many it processed.
  @discardableResult
  private func sweep(_ envelopes: [MailEnvelope], dryRun: Bool) async throws -> Int {
    try await pipeline.processBatch(envelopes, adapter: adapter, dryRun: dryRun, skipsSettled: true)
      .count
  }

  private func settled(_ envelopes: [MailEnvelope], dryRun: Bool, now: Date = .now) async throws
    -> Set<String>
  {
    try await ProcessedMessageRepository.settledKeys(
      among: envelopes.map(\.identity.key),
      revision: StateRepository.load(store, StateSlices()).revision,
      dryRun: dryRun,
      now: now,
      in: store
    )
  }

  /// Turns on live actions and changes the policy, which starts a new revision.
  private func goLiveWithNewPolicy() async throws {
    try await enableActions(store)
    try await StateRepository.editSettings(store) { $0.strength = .aggressive }
  }

  @Test
  func `records why discovery could not classify a message`() async throws {
    #expect(try await sweep(batch, dryRun: true) == 3)
    #expect(calls.value == 2)
    let reasons = try await StateRepository.load(store).records.map(\.decision.reason)
    #expect(reasons.contains(.classificationFailed(.network)))
    #expect(reasons.contains(.messageUnreadable))
  }

  @Test
  func `skips mail already settled in the same dry run`() async throws {
    try await sweep(batch, dryRun: true)
    #expect(try await sweep(batch, dryRun: true) == 0)
    #expect(calls.value == 2)
  }

  @Test
  func `retries a transient failure but not unparseable mail after a policy change`()
    async throws
  {
    try await sweep([transient, unparseable], dryRun: true)
    try await goLiveWithNewPolicy()
    #expect(try await sweep([transient, unparseable], dryRun: false) == 1)
    #expect(calls.value == 2)
    #expect(try await sweep([transient, unparseable], dryRun: false) == 0)
  }

  @Test
  func `retries a transient failure once its backoff elapses`() async throws {
    try await sweep([transient, unparseable], dryRun: true)
    let later = Date.now.addingTimeInterval(3600)
    #expect(
      try await settled([transient, unparseable], dryRun: true, now: later)
        == [unparseable.identity.key]
    )
  }

  @Test(arguments: [(saved: ModelBackend.claude, retried: true), (.openAI, false)])
  func `retries mail that failed for want of a key once the selected provider's key is saved`(
    saved: ModelBackend,
    retried: Bool
  ) async throws {
    try await sweep([keyless], dryRun: true)
    #expect(try await settled([keyless], dryRun: true) == [keyless.identity.key])
    try await CredentialChanges.recordKeySaved(for: saved, in: store)
    #expect(try await settled([keyless], dryRun: true).isEmpty == retried)
  }

  @Test(arguments: [
    (dryRun: true, policyChanged: false, settled: true),
    (false, false, false),
    (true, true, true),
    (false, true, false)
  ])
  func `settles a dry-run result only while dry run stays on, whatever the policy`(
    dryRun: Bool,
    policyChanged: Bool,
    settled: Bool
  ) {
    let record = DecisionRecord(
      identity: .init(accountID: "account-A", contentHash: "previewed"),
      decision: .init(label: .junk, action: .moveToJunk, reason: .model("lure")),
      outcome: .dryRun,
      revision: 4
    )
    let result = ProcessedMessage(record: record)
    #expect(result.isSettled(revision: policyChanged ? 5 : 4, dryRun: dryRun) == settled)
  }

  @Test
  func `backs off a live failure of mail previewed under an earlier policy`() async throws {
    let identity = MessageIdentity(accountID: "account-A", contentHash: "previewed")
    let preview = DecisionRecord(
      identity: identity,
      decision: .init(label: .junk, action: .moveToJunk, reason: .model("lure")),
      outcome: .dryRun,
      revision: 4
    )
    var failure = preview
    failure.decision = .init(label: nil, action: .none, reason: .classificationFailed(.network))
    failure.outcome = .unclassified
    failure.revision = 5
    let now = Date.now
    for (record, kind) in [(preview, nil), (failure, ProcessingFailure.transient)] {
      try await ProcessedMessageRepository.record(
        record,
        key: identity.key,
        failure: kind,
        in: store,
        now: now
      )
    }
    let entry = try #require(
      try await ProcessedMessageRepository.entries(for: [identity.key], in: store)[identity.key]
    )
    let retryAfter = try #require(entry.retryAfter)
    #expect(entry.failure == .transient)
    #expect(entry.isSettled(revision: 5, dryRun: false, now: now))
    #expect(!entry.isSettled(revision: 5, dryRun: false, now: retryAfter))
  }

  @Test
  func `acts on mail previewed during a dry run once dry run is off, without classifying it again`()
    async throws
  {
    try await sweep([previewed], dryRun: true)
    try await enableActions(store)
    #expect(try await sweep([previewed], dryRun: false) == 1)
    #expect(await adapter.actions == [.moveToJunk])
    #expect(calls.value == 1)
    #expect(try await StateRepository.load(store).records.map(\.outcome) == [.applied])
    #expect(try await sweep([previewed], dryRun: false) == 0)
    #expect(await adapter.actions == [.moveToJunk])
  }

  @Test
  func `keeps previewed mail settled when the policy changes during a dry run`() async throws {
    try await sweep([previewed], dryRun: true)
    try await StateRepository.editSettings(store) { $0.strength = .aggressive }
    #expect(try await sweep([previewed], dryRun: true) == 0)
    #expect(calls.value == 1)
  }

  @Test
  func `classifies mail previewed under an earlier policy again when it goes live`()
    async throws
  {
    try await sweep([previewed], dryRun: true)
    try await goLiveWithNewPolicy()
    #expect(try await sweep([previewed], dryRun: false) == 1)
    #expect(calls.value == 2)
    #expect(await adapter.actions == [.moveToJunk])
  }

  @Test
  func `keeps a preview applied while discovery moves it to where the message now is`()
    async throws
  {
    try await sweep([previewed], dryRun: true)
    try await enableActions(store)
    let stale = try #require(try await StateRepository.load(store).records.first)
    _ = try await pipeline.applyPreview(recordID: stale.id, adapter: adapter)
    var moved = previewed.identity
    moved.localID = 7
    let adopted = try await pipeline.adoptPreview(stale.id, discoveredAs: moved)
    #expect(adopted?.outcome == .applied)
    #expect(try await StateRepository.load(store).records.map(\.outcome) == [.applied])
  }

  @Test
  func `keeps a dry-run result settled for forced dry runs while filtering is live`()
    async throws
  {
    try await enableActions(store)
    try await sweep([previewed], dryRun: true)
    #expect(try await sweep([previewed], dryRun: true) == 0)
    #expect(calls.value == 1)
    #expect(await adapter.actions.isEmpty)
  }

  @Test
  func `classifies a message polled twice in a dry run once`() async throws {
    let polled = try envelope("order-confirmation")
    for _ in 1...2 { try await sweep([polled], dryRun: true) }
    #expect(calls.value == 1)
  }

  @Test
  func `acts on a manual preview when filtering is live without classifying it again`()
    async throws
  {
    try await enableActions(store)
    let fresh = try envelope("unsolicited-newsletter")
    try await pipeline.processBatch([fresh], adapter: adapter, dryRun: true, skipsSettled: false)
    #expect(await adapter.actions.isEmpty)
    try await sweep([fresh], dryRun: false)
    #expect(await adapter.actions == [.moveToJunk])
    #expect(calls.value == 1)
  }

  @Test
  func `renews the retention of settled mail that stays in a mailbox`() async throws {
    try await sweep([previewed], dryRun: true)
    let observed = Date.now.addingTimeInterval(300 * 86_400)
    let pruned = observed.addingTimeInterval(200 * 86_400)
    #expect(try await settled([previewed], dryRun: true, now: observed) == [previewed.identity.key])
    let neighbor = try #require(try await StateRepository.load(store).records.first)
    try await ProcessedMessageRepository.record(
      neighbor,
      key: previewed.identity.key.prefix(2) + "-neighbor",
      in: store,
      now: pruned
    )
    #expect(try await settled([previewed], dryRun: true, now: pruned) == [previewed.identity.key])
  }

  @Test
  func `classifies mail again under a new policy after shared storage was unavailable`()
    async throws
  {
    try blockStorage(store)
    #expect(await pipeline.process(previewed, discovered: true).outcome == .unclassified)
    try restoreStorage(store)
    try await StateRepository.editSettings(store) { $0.strength = .aggressive }
    #expect(try await sweep([previewed], dryRun: true) == 1)
    #expect(calls.value == 1)
  }
}

@Suite
struct `Transient processing failures` {
  private let store: Store
  private let fresh: MailEnvelope

  init() throws {
    store = try testStore()
    fresh = try envelope("unsolicited-newsletter")
  }

  /// Processes `fresh` while shared storage is unavailable, then records the result once it returns.
  private func processDuringOutage() async throws -> DecisionRecord {
    let pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(operation: { _ in throw ClassificationError.network })
    )
    try blockStorage(store)
    let unavailable = await pipeline.process(fresh, discovered: true)
    try restoreStorage(store)
    try await pipeline.processBatch(
      [],
      adapter: RecordingAdapter(),
      dryRun: true,
      skipsSettled: true
    )
    return unavailable
  }

  @Test
  func `records unavailable shared storage as a transient failure`() async throws {
    let unavailable = try await processDuringOutage()
    #expect(unavailable.decision.reason == .storageUnavailable)
    let entry = try await ProcessedMessageRepository.entries(for: [fresh.identity.key], in: store)
    #expect(entry[fresh.identity.key]?.failure == .transient)
  }

  @Test
  func `retries consecutive transient failures for three days`() async throws {
    let unavailable = try await processDuringOutage()
    let entry = try await ProcessedMessageRepository.entries(for: [fresh.identity.key], in: store)
    let transient = try #require(entry[fresh.identity.key])
    let start = try #require(transient.firstTransientFailure)
    let retried = ProcessedMessage(
      record: unavailable,
      failure: .transient,
      previous: transient,
      now: start.addingTimeInterval(2 * 86_400)
    )
    #expect(retried.failure == .transient && retried.firstTransientFailure == start)
    let expired = ProcessedMessage(
      record: unavailable,
      failure: .transient,
      previous: retried,
      now: start.addingTimeInterval(3 * 86_400)
    )
    #expect(expired.failure == .persistent)
  }

  @Test
  func `settles mail classified again from Activity`() async throws {
    let outage = await Pipeline(
      store: store,
      classifier: MockClassifier(operation: { _ in throw ClassificationError.network })
    ).process(fresh, discovered: true)
    let adapter = RecordingAdapter()
    await adapter.retain(fresh)
    let recovered = Pipeline(store: store, classifier: junkClassifier)
    let retry = try await recovered.retryUnclassified(recordID: outage.id, adapter: adapter)
    #expect(retry.outcome == .dryRun)
    await #expect(throws: DecisionRecordError.notUnclassified) {
      try await recovered.retryUnclassified(recordID: retry.id, adapter: adapter)
    }
    let settled = try await ProcessedMessageRepository.settledKeys(
      among: [fresh.identity.key],
      revision: retry.revision,
      dryRun: true,
      in: store
    )
    #expect(settled == [fresh.identity.key])
  }
}

@Test
func `keeps evicted action claims without classifying again`() async throws {
  let store = try testStore(), adapter = RecordingAdapter(), calls = Counter()
  try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      calls.increment()
      return Verdict(label: .junk, confidence: 99, reason: "lure")
    })
  )
  #expect(await pipeline.process(try envelope(), adapter: adapter).outcome == .applied)
  try await StateRepository.update(store) { $0.records.removeAll() }
  let evicted = await pipeline.process(try envelope(), adapter: adapter)
  #expect(evicted.outcome == .duplicate)
  #expect(evicted.decision.label == .junk)
  #expect(calls.value == 1)
  #expect(await adapter.actions == [.moveToJunk])
  #expect(try await StateRepository.load(store).records.isEmpty)
}

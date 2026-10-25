import Foundation
import Testing
import SpamWiseCore

@Test(arguments: FilteringStrength.allCases)
func `selects actions at each decision threshold`(
  _ strength: FilteringStrength
) throws {
  func action(_ label: MailLabel, _ confidence: Int) throws -> Decision {
    try Decision.evaluate(
      .init(label: label, confidence: confidence, reason: "fixture"),
      strength: strength
    )
  }
  #expect(try action(.inbox, 1).action == .none)
  #expect(try action(.review, 100).action == .orangeFlag)
  #expect(try action(.junk, strength.threshold - 1).label == .review)
  #expect(try action(.junk, strength.threshold).action == .moveToJunk)
}

@Test(arguments: FilteringStrength.allCases)
func `bounds a graymail verdict by the user's preference for its category`(
  _ strength: FilteringStrength
) throws {
  func label(_ label: MailLabel, _ preference: GraymailPreference, confidence: Int = 100) throws
    -> MailLabel?
  {
    try Decision.evaluate(
      .init(label: label, category: .promotion, confidence: confidence, reason: "fixture"),
      strength: strength,
      preference: preference
    ).label
  }
  #expect(try label(.junk, .keep) == .review)
  #expect(try label(.inbox, .keep) == .inbox)
  #expect(try label(.inbox, .review) == .review)
  #expect(try label(.junk, .review) == .review)
  #expect(try label(.inbox, .junk) == .review)
  #expect(try label(.junk, .junk) == .junk)
  #expect(try label(.junk, .junk, confidence: strength.threshold - 1) == .review)
}

@Test
func `applies a category preference only to model verdicts`() async throws {
  let store = try testStore()
  try await StateRepository.update(store) {
    $0.settings.categoryPreferences[.promotion] = .keep
    $0.rules = [SenderRule(scope: .address, value: "reward@courtesy-kit.lat", disposition: .block)]
  }
  let verdict = Verdict(label: .junk, category: .promotion, confidence: 100, reason: "sale")
  let pipeline = Pipeline(store: store, classifier: MockClassifier(verdict: verdict))
  let ruled = await pipeline.process(try envelope(), adapter: RecordingAdapter())
  #expect(ruled.decision.label == .junk && ruled.decision.preference == nil)
  let modeled = await pipeline.process(try envelope("stranger-cart"), adapter: RecordingAdapter())
  #expect(modeled.decision.label == .review && modeled.decision.preference == .keep)
}

@Test
func `annotates Review with the chosen treatment`() throws {
  let verdict = Verdict(label: .review, confidence: 50, reason: "uncertain")
  #expect(try Decision.evaluate(verdict, review: .orangeBackground).action == .orangeBackground)
}

@Test
func `rejects confidence outside 0 through 100`() {
  #expect(throws: ClassificationError.self) {
    try Decision.evaluate(.init(label: .junk, confidence: 999, reason: "invalid"))
  }
}

@Test
func `records a dry run without acting by default`() async throws {
  let adapter = RecordingAdapter()
  let pipeline = Pipeline(store: try testStore(), classifier: junkClassifier)
  #expect(await pipeline.process(try envelope(), adapter: adapter).outcome == .dryRun)
  #expect(await adapter.actions.isEmpty)
}

@Test
func `records a pause without acting`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  try await StateRepository.update(store) { $0.settings.paused = true }
  let pipeline = Pipeline(store: store, classifier: junkClassifier)
  #expect(await pipeline.process(try envelope(), adapter: adapter).outcome == .paused)
  #expect(await adapter.actions.isEmpty)
}

@Test(arguments: [ClassificationError.network, .contextExceeded])
func `leaves mail unclassified without acting when classification fails`(
  failure: ClassificationError
) async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in throw failure })
  )
  #expect(await pipeline.process(try envelope(), adapter: adapter).outcome == .unclassified)
  #expect(await adapter.actions.isEmpty)
}

@Test
func `sends mail whose evidence alone exceeds the prompt limit to Review`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in throw ClassificationError.evidenceExceedsPrompt })
  )
  let record = await pipeline.process(try envelope(), adapter: adapter)
  #expect(record.decision.label == .review)
  #expect(record.path == .model)
  #expect(await adapter.actions == [.orangeFlag])
}

@Test(arguments: [(localOnly: true, lookups: false), (false, false), (true, true)])
func `makes no evidence lookups in local-only mode or with lookups off`(
  localOnly: Bool,
  lookups: Bool
) async throws {
  let store = try testStore(), network = StubRDAP()
  try await StateRepository.editSettings(store) { settings in
    settings.mailOptions.localOnly = localOnly
    if lookups {
      settings.advancedOptions.domainRegistrationLookup = true
      enableSpamhausEvidence(in: &settings)
    }
  }
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { input in
      #expect(input.evidence.domainAgeDays == nil)
      #expect(input.evidence.auxiliaryFindings == nil)
      return Verdict(label: .review, confidence: 10, reason: "unknown")
    }),
    rdap: RDAPLookup(fetcher: network)
  )
  #expect(await pipeline.process(try envelope()).path == .model)
  #expect(await network.calls == 0)
}

@Test
func `rejects cloud classification in local-only mode before reading credentials`()
  async throws
{
  let store = try testStore()
  try await StateRepository.editSettings(store) { $0.mailOptions.localOnly = true }
  let configured = ConfiguredClassifier(
    store: store,
    credential: { _ in
      Issue.record("Local mode must reject cloud classification before reading credentials")
      return "unused"
    }
  )
  let message = try MIMEParser().parse(fixture("filler-spam"))
  await #expect(throws: ClassificationError.configuration) {
    try await configured.classify(
      ClassificationInput(message: message, evidence: EvidenceBundle(message: message))
    )
  }
}

@Test
func `supersedes pending verdicts when a correction arrives`() async throws {
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

@Test
func `prevents actions after persistence fails`() async throws {
  let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let store = try Store(url: dir)
  let adapter = RecordingAdapter()
  let pipeline = Pipeline(store: store, classifier: junkClassifier)
  #expect(await pipeline.process(try envelope(), adapter: adapter).outcome == .unclassified)
  #expect(await adapter.actions.isEmpty)
}

import Foundation
import Testing
import SpamWiseCore

@Test func `migrates legacy settings and excludes corrected mail from the Review digest`() throws {
  let encoded = try JSONEncoder().encode(AppState())
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  object.removeValue(forKey: "learning"); object.removeValue(forKey: "reviewedLabels")
  var settings = try #require(object["settings"] as? [String: Any])
  settings.removeValue(forKey: "advanced"); settings["paused"] = true
  settings.removeValue(forKey: "mailPreferences")
  object["settings"] = settings
  let decoded = try JSONDecoder().decode(
    AppState.self,
    from: JSONSerialization.data(withJSONObject: object)
  )
  #expect(decoded.settings.paused)
  #expect(decoded.settings.advancedOptions.backend == .claude)
  #expect(!decoded.settings.advancedOptions.fingerprints)
  #expect(!decoded.settings.mailOptions.localOnly)
  var state = decoded
  let identity = MessageIdentity(accountID: "account", contentHash: "digest")
  var review = DecisionRecord(
    identity: identity,
    sender: "person@example.com",
    subject: "Review",
    decision: .init(label: .review, action: .orangeFlag, reason: "uncertain"),
    outcome: .dryRun,
    path: "model",
    revision: 0
  )
  state.records = [review]
  #expect(ReviewDigest(state: state).records.count == 1)
  review.correctedLabel = .inbox; state.records = [review]
  #expect(ReviewDigest(state: state).records.isEmpty)
  var query = ActivityQuery()
  query.text = "PERSON"
  #expect(query.apply(to: state.records).count == 1)
  query.accountID = "other"
  #expect(query.apply(to: state.records).isEmpty)
  review.verdict = .init(label: .review, confidence: 50, reason: "uncertain")
  review.outcome = .failed
  let statistics = ActivityStatistics(records: [review])
  #expect(statistics.reviewedDecisions == 1)
  #expect(statistics.reviewedMistakes == 1)
  #expect(statistics.unresolvedReview == 0)
  #expect(statistics.actionFailures == 1)
  var uncertain = review
  uncertain.outcome = .noAction; uncertain.correctedLabel = nil
  uncertain.verdict = .init(label: .review, confidence: 1, reason: "unknown")
  #expect(ReviewPriority.precedes(review, uncertain))
  let diagnostic = try JSONEncoder().encode(DiagnosticSummary(state: state))
  #expect(!String(decoding: diagnostic, as: UTF8.self).contains("person@example.com"))
}

@Test func `restores authenticated backups while preserving spending and disabling actions`()
  async throws
{
  let store = try testStore()
  try await enableActions(store)
  try await RuleManagement.save(
    scope: .address,
    value: "friend@example.org",
    disposition: .allow,
    store: store
  )
  try await EvaluationBudget.reserve(upperBoundUSD: 1, store: store)
  let before = try await StateRepository.load(store)
  let key = StateBackup.recoveryKey()
  let archive = try StateBackup.export(before, recoveryKey: key)
  #expect(!String(decoding: archive, as: UTF8.self).contains("friend@example.org"))
  await #expect(throws: BackupError.self) {
    try await StateBackup.restore(archive, recoveryKey: StateBackup.recoveryKey(), store: store)
  }
  #expect(try await StateRepository.load(store).revision == before.revision)
  var damaged = archive; damaged[0] ^= 1
  await #expect(throws: BackupError.self) {
    try await StateBackup.restore(damaged, recoveryKey: key, store: store)
  }
  try await StateBackup.restore(archive, recoveryKey: key, store: store)
  let restored = try await StateRepository.load(store)
  #expect(restored.rules == before.rules)
  #expect(restored.settings.paused && restored.settings.dryRun)
  #expect(restored.settings.validatedAccounts.isEmpty)
  #expect(restored.settings.route == .unverified)
  #expect(try await EvaluationBudget.load(store).committedUSD == 1)
}

@Test func `imports rules atomically and invalidates stale work after explicit edits`() async throws
{
  let store = try testStore()
  try await RuleManagement.save(
    scope: .address,
    value: "Person@Example.com",
    disposition: .allow,
    store: store
  )
  let before = try await StateRepository.load(store)
  #expect(before.rules.first?.value == "person@example.com")
  let invalid = Data(
    #"{"version":1,"rules":[{"scope":"domain","value":"com","disposition":"block","updatedAt":0}]}"#
      .utf8
  )
  await #expect(throws: RuleManagementError.self) {
    try await RuleManagement.importRules(invalid, store: store)
  }
  #expect(try await StateRepository.load(store).rules == before.rules)
  #expect(try await StateRepository.load(store).auditEvents?.count == before.auditEvents?.count)
  let exported = try RuleManagement.exportRules(before.rules)
  let other = try testStore()
  try await RuleManagement.importRules(exported, store: other)
  #expect(try await StateRepository.load(other).rules.map(\.id) == before.rules.map(\.id))
  try await RuleManagement.save(
    scope: .address,
    value: "person@example.com",
    disposition: .block,
    store: store
  )
  let changed = try await StateRepository.load(store)
  #expect(changed.rules.count == 1)
  #expect(changed.rules.first?.disposition == .block)
  #expect(changed.revision > before.revision)
  #expect(changed.auditEvents?.last?.kind == .senderRule)
  var content = ContentRule(); content.pattern = "newsletter"
  let contentArchive = try ContentRuleManagement.exportRules([content])
  try await ContentRuleManagement.importRules(contentArchive, store: store)
  try await ContentRuleManagement.importRules(contentArchive, store: store)
  #expect(try await StateRepository.load(store).contentRules?.count == 1)
  content.pattern = "["; content.operation = .regularExpression
  #expect(throws: ContentRuleError.invalid) { try ContentRuleManagement.exportRules([content]) }
}

@Test func `imports deduplicated corpus labels without rules and forgets linked learning`()
  async throws
{
  let store = try testStore()
  try await RuleManagement.save(
    scope: .address,
    value: "friend@example.org",
    disposition: .allow,
    store: store
  )
  let message = try MIMEParser().parse(fixture("filler-spam"))
  var examples = (0..<20).map { index in
    var sample = message
    sample.subject = "Corpus example \(index)"
    sample.hash = stableHash(Data(sample.subject.utf8))
    return sample
  }
  try await CorpusManagement.importMessages(examples, label: .junk, store: store)
  examples[0].hash = "different delivery"
  try await CorpusManagement.importMessages([examples[0]], label: .inbox, store: store)
  let state = try await StateRepository.load(store)
  let labels = try #require(state.reviewedLabels)
  #expect(labels.count == 20)
  #expect(state.rules.count == 1)
  #expect(state.records.isEmpty)
  let heldOut = labels.filter(\.heldOut)
  #expect(!heldOut.isEmpty)
  #expect(
    heldOut.allSatisfy { label in !state.corrections.contains { $0.sampleID == label.sampleID } }
  )
  #expect(state.learning?.samples.allSatisfy { $0.partition == .training } == true)
  let last = try #require(labels.last)
  #expect(last.label == .inbox)
  #expect(last.message == nil)
  try await CorpusManagement.relabel(id: last.id, label: .review, store: store)
  #expect(try await StateRepository.load(store).reviewedLabels?.last?.label == .review)
  try await CorpusManagement.forget(id: last.id, store: store)
  let forgotten = try await StateRepository.load(store)
  #expect(forgotten.reviewedLabels?.count == 19)
  #expect(!forgotten.corrections.contains { $0.sampleID == last.sampleID })
  #expect(forgotten.learning?.samples.contains { $0.id == last.sampleID } == false)
  #expect(forgotten.rules == state.rules)
}

@Test func `bounds concurrent budget reservations by the configured cap`() async throws {
  let store = try testStore()
  try await EvaluationBudget.configure(limitUSD: 0.20, store: store)
  let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
    for _ in 0..<8 {
      group.addTask {
        (try? await EvaluationBudget.reserve(upperBoundUSD: 0.10, store: store)) != nil
      }
    }
    var count = 0
    for await success in group where success { count += 1 }
    return count
  }
  #expect(successes <= 2)
  #expect(successes > 0)
  #expect(try await EvaluationBudget.load(store).committedUSD <= 0.20)
  await #expect(throws: BudgetError.self) {
    try await EvaluationBudget.reserve(upperBoundUSD: .nan, store: store)
  }
}

@Test
func `batches private notifications across restarts while honoring quiet time and corrections`()
  async throws
{
  let store = try testStore()
  let now = Date(timeIntervalSince1970: 1_800_014_400)
  var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  var preferences = NotificationPreferences()
  preferences.enabledSince = now.addingTimeInterval(-3600)
  preferences.quietStartHour = 0; preferences.quietEndHour = 0
  let configured = preferences
  try await StateRepository.update(store) { state in
    state.settings.dryRun = false
    state.settings.mailOptions.notifications = configured
    var record = DecisionRecord(
      identity: .init(accountID: "a", contentHash: "review"),
      sender: "private@example.org",
      subject: "Private subject",
      decision: .init(label: .review, action: .orangeFlag, reason: "uncertain"),
      outcome: .applied,
      path: "model",
      revision: 0
    )
    record.date = now.addingTimeInterval(-60)
    state.records = [record]
  }
  preferences.quietStartHour = 22; preferences.quietEndHour = 8
  let night = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now)!
  let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now)!
  #expect(preferences.isQuiet(at: night, calendar: calendar))
  #expect(preferences.isQuiet(at: morning, calendar: calendar))
  #expect(
    !preferences.isQuiet(
      at: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!,
      calendar: calendar
    )
  )
  let first = try #require(
    await NotificationPlanning.claim(store: store, now: now, calendar: calendar)
  )
  #expect(first.review == 1 && first.good == 0)
  let reopened = try await Store(url: store.url)
  #expect(
    try await NotificationPlanning.claim(
      store: reopened,
      now: now.addingTimeInterval(4000),
      calendar: calendar
    ) == nil
  )
  try await StateRepository.update(store) { state in
    var record = state.records[0]
    record.id = UUID(); record.identity.contentHash = "corrected"; record.correctedLabel = .inbox
    state.records.append(record)
  }
  #expect(
    try await NotificationPlanning.claim(
      store: store,
      now: now.addingTimeInterval(5000),
      calendar: calendar
    ) == nil
  )
}

@Test func `replays automation receipts without repeating classification or corrections`()
  async throws
{
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "lure"))
  )
  let selected = try envelope(), requestID = UUID()
  let first = try await pipeline.execute(
    .preview,
    requestID: requestID,
    envelope: selected,
    adapter: adapter
  )
  #expect(first.outcome == .dryRun)
  #expect(
    try await pipeline.execute(.preview, requestID: requestID, envelope: selected, adapter: adapter)
      == first
  )
  #expect(try await StateRepository.load(store).records.count == 1)
  await #expect(throws: IntegrationError.staleMessage) {
    try await pipeline.execute(
      .correct(.junk),
      requestID: requestID,
      envelope: selected,
      adapter: adapter
    )
  }
  let correctionID = UUID()
  let corrected = try await pipeline.execute(
    .correct(.inbox),
    requestID: correctionID,
    envelope: selected,
    adapter: adapter
  )
  #expect(corrected.outcome == .applied)
  #expect(
    try await pipeline.execute(
      .correct(.inbox),
      requestID: correctionID,
      envelope: selected,
      adapter: adapter
    ) == corrected
  )
  #expect(await adapter.actions == [.moveToInbox])
  #expect(try await StateRepository.load(store).corrections.count == 1)
}

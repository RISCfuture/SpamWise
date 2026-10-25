import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Correction of a message whose classification failed` {
  private let store: Store
  private let adapter = RecordingAdapter()
  private let pipeline: Pipeline
  /// The unclassified record, which also queued a retry.
  private let failed: DecisionRecord

  init() async throws {
    store = try testStore()
    pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(operation: { _ in throw ClassificationError.rateLimited })
    )
    failed = await pipeline.process(try envelope(), adapter: adapter)
  }

  private func state() async throws -> AppState { try await StateRepository.load(store) }

  @discardableResult
  private func correct(_ label: MailLabel) async throws -> DecisionRecord {
    try await pipeline.correct(recordID: failed.id, label: label, adapter: adapter)
  }

  /// Corrects the failed record as Junk, running `interruption` once between saving the
  /// correction and claiming its mail steps.
  private func correctJunk(interruptedBy interruption: @escaping @Sendable () async throws -> Void)
    async throws -> DecisionRecord
  {
    let checks = Counter()
    await adapter.beforeEachSupportCheck {
      checks.increment()
      if checks.value == 1 { try? await interruption() }
    }
    return try await correct(.junk)
  }

  private func edit(_ body: @escaping @Sendable (inout AdvancedSettings) -> Void) async throws {
    try await StateRepository.editSettings(store) { body(&$0.advancedOptions) }
  }

  private func reviewedLabelID() async throws -> String {
    try #require(await state().reviewedLabels.first?.id)
  }

  @Test(arguments: [false, true])
  func `keeps a pending retry unchanged during previews`(previewSucceeds: Bool) async throws {
    let pending = try #require(await state().retries.first)
    let preview =
      previewSucceeds
      ? Pipeline(
        store: store,
        classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "preview"))
      ) : pipeline
    _ = await preview.process(try envelope(), adapter: adapter, forceDryRun: true)
    #expect(try await state().retries == [pending])
  }

  @Test(arguments: [false, true])
  func `keeps a correction in force when other mail or the policy changes before it claims`(
    editsPolicy: Bool
  ) async throws {
    let other = try envelope("authentic-contact")
    let pipeline = pipeline, adapter = adapter, store = store
    let correction = try await correctJunk {
      if editsPolicy {
        try await StateRepository.editSettings(store) { $0.strength = .aggressive }
      } else {
        _ = try await pipeline.correct(envelope: other, label: .inbox, adapter: adapter)
      }
    }
    #expect(correction.outcome == .dryRun)
    let current = try await state()
    #expect(current.records.count(where: { $0.path == .correction }) == (editsPolicy ? 1 : 2))
    #expect(current.revision == correction.revision + 1)
  }

  @Test
  func `lets a newer correction of the same message replace an older one`() async throws {
    let pipeline = pipeline, adapter = adapter, failed = failed
    let older = try await correctJunk {
      _ = try await pipeline.correct(recordID: failed.id, label: .inbox, adapter: adapter)
    }
    #expect(older.outcome == .superseded)
    let newer = try #require(
      await state().records.first { $0.path == .correction && $0.correctedLabel == .inbox }
    )
    #expect(newer.outcome == .dryRun)
  }

  @Test
  func `discards pending retries and saves an account-scoped address rule`() async throws {
    try await correct(.inbox)
    let corrected = try await state()
    #expect(corrected.retries.isEmpty)
    #expect(corrected.rules.map(\.scope) == [.address])
    #expect(corrected.corrections.map(\.promptScope) == [.account("account-A")])
    #expect(await adapter.actions.isEmpty)
  }

  @Test
  func `records a Review correction with an excerpt but no rule, content or learning`()
    async throws
  {
    await adapter.retain(try envelope())
    let review = try await correct(.review)
    let reviewed = try await state()
    #expect(review.decision.action == .orangeFlag)
    #expect(reviewed.rules.isEmpty)
    #expect(reviewed.reviewedLabels.map(\.label) == [.review])
    #expect(reviewed.reviewedLabels.allSatisfy { $0.message == nil })
    #expect(reviewed.corrections.last?.label == .review)
    #expect(reviewed.corrections.last?.excerpt.isEmpty == false)
    #expect(reviewed.learning == LearningState())
  }

  @Test
  func `relabels the linked correction examples`() async throws {
    try await correct(.review)
    try await CorpusManagement.relabel(id: reviewedLabelID(), label: .inbox, store: store)
    let corrections = try await state().corrections
    #expect(!corrections.isEmpty && corrections.allSatisfy { $0.label == .inbox })
  }

  @Test
  func `forgets the linked correction examples without reading mail`() async throws {
    try await correct(.review)
    let lookups = await adapter.lookups
    try await CorpusManagement.forget(id: reviewedLabelID(), store: store)
    #expect(try await state().corrections.isEmpty)
    #expect(await adapter.lookups == lookups)
  }

  @Test
  func `retains reviewed content without learning when retention is enabled`() async throws {
    await adapter.retain(try envelope())
    try await edit { $0.retainReviewedContent = true }
    try await correct(.inbox)
    let retained = try await state()
    #expect(await adapter.lookups == 1)
    #expect(retained.reviewedLabels.first?.message != nil)
    #expect(retained.corrections.last?.excerpt.isEmpty == false)
    #expect(retained.learning == LearningState())
  }

  @Test
  func `learns from a correction without retaining its content`() async throws {
    await adapter.retain(try envelope())
    try await edit { $0.bayes = true }
    try await correct(.junk)
    let learned = try await state()
    #expect(await adapter.lookups == 1)
    #expect(learned.reviewedLabels.first?.message == nil)
    #expect(learned.reviewedLabels.first?.sampleID != nil)
    #expect(learned.learning.samples.count == 1)
  }

  @Test
  func `undoes the latest correction's rules, learning and examples`() async throws {
    await adapter.retain(try envelope())
    try await correct(.inbox)
    let before = try await state()
    try await edit { $0.bayes = true }
    try await correct(.junk)
    let learned = try await state()
    #expect(try #require(learned.correctionUndo).isAvailable(in: learned))
    try await CorrectionUndo.apply(store: store)
    let undone = try await state()
    #expect(undone.rules == before.rules)
    #expect(undone.learning == before.learning)
    #expect(undone.corrections == before.corrections)
    #expect(undone.records.last?.correctionUndone == true)
    #expect(await adapter.actions.isEmpty)
  }

  @Test
  func `refuses undo after a later settings change`() async throws {
    try await correct(.junk)
    let corrected = try await state()
    #expect(try #require(corrected.correctionUndo).isAvailable(in: corrected))
    try await StateRepository.editSettings(store) { $0.strength = .conservative }
    await #expect(throws: UndoError.unavailable) {
      try await CorrectionUndo.apply(store: store)
    }
  }

  @Test
  func `forgets learning while retaining sender rules`() async throws {
    await adapter.retain(try envelope())
    try await edit { $0.bayes = true }
    try await correct(.junk)
    try await edit { $0.bayes = false }
    try await correct(.inbox)
    let before = try await state()
    #expect(!before.learning.samples.isEmpty)
    try await CorpusManagement.forget(id: reviewedLabelID(), store: store)
    let forgotten = try await state()
    #expect(forgotten.corrections.isEmpty)
    #expect(forgotten.learning.samples.isEmpty)
    #expect(forgotten.rules == before.rules && !forgotten.rules.isEmpty)
  }
}

@Suite
struct `Correction of selected mail` {
  private let store: Store
  private let adapter = RecordingAdapter()
  private let selected: MailEnvelope
  private let pipeline: Pipeline

  /// Stores the selected message's sender as both a contact and one of the user's own addresses.
  init() async throws {
    store = try testStore()
    selected = try envelope("authentic-contact")
    let sender = try MIMEParser().parse(selected.raw).fromAddress
    try await StateRepository.update(store) {
      $0.contactAddresses = [sender]
      $0.contactsUpdatedAt = .now
      $0.ownAddresses = [sender]
    }
    try await AuthenticationTrust.save(["mx.example"], accountID: "account-A", store: store)
    pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(verdict: .init(label: .review, confidence: 50, reason: "unknown"))
    )
  }

  @Test
  func `classifies the user's own address instead of trusting it as a contact`() async {
    #expect(await pipeline.process(selected).path == .model)
  }

  @Test
  func `saves no record of a selected message whose correction fails`() async throws {
    await #expect(throws: CorrectionError.reviewRequiresAddressScope) {
      try await pipeline.correct(envelope: selected, label: .review, scope: .domain)
    }
    await #expect(throws: TrainingFolderError.planInactive) {
      try await pipeline.correct(envelope: selected, label: .junk, trainingPlanID: "missing")
    }
    #expect(try await StateRepository.load(store).records.isEmpty)
  }

  @Test
  func `corrects in dry run and decides later deliveries by the new rule`() async throws {
    let correction = try await pipeline.correct(envelope: selected, label: .inbox, adapter: adapter)
    #expect(correction.correctedLabel == .inbox)
    #expect(correction.outcome == .dryRun)
    #expect(await adapter.actions.isEmpty)
    let ruled = await pipeline.process(selected)
    #expect(ruled.path == .gate)
    #expect(ruled.decision.label == .inbox)
  }

  @Test
  func `undoes a batch together, except corrections saved before another change`() async throws {
    let batch = CorrectionBatch()
    let retained = try await pipeline.correct(envelope: selected, label: .junk, batch: batch)
    try await StateRepository.editSettings(store) { $0.strength = .conservative }
    let before = try await StateRepository.load(store)
    var undone: [DecisionRecord] = []
    for name in ["filler-spam", "stranger-cart"] {
      undone.append(
        try await pipeline.correct(envelope: envelope(name), label: .junk, batch: batch)
      )
    }
    let undo = try await CorrectionUndo.apply(store: store)
    #expect(undo.correctionCount == 2 && undo.retainedCount == 1)
    let after = try await StateRepository.load(store)
    #expect(after.rules == before.rules && after.rules.count == 1)
    let records = Dictionary(uniqueKeysWithValues: after.records.map { ($0.id, $0) })
    #expect(undone.allSatisfy { records[$0.id]?.correctionUndone == true })
    #expect(records[retained.id]?.correctionUndone == false)
  }
}

@Test
func `normalizes saved trust exclusions`() async throws {
  let store = try testStore()
  try await TrustExclusions.save(" ALIAS@EXAMPLE.ORG \nfriend@example.org", store: store)
  #expect(
    try await StateRepository.load(store).settings.mailOptions.trustExclusions
      == ["alias@example.org", "friend@example.org"]
  )
}

@Test
func `rejects trust exclusions containing an invalid address without saving`() async throws {
  let store = try testStore()
  let before = try await StateRepository.load(store)
  await #expect(throws: TrustExclusionError.invalidAddress("not an address")) {
    try await TrustExclusions.save("valid@example.org\nnot an address", store: store)
  }
  #expect(try await StateRepository.load(store).revision == before.revision)
}

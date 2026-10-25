import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Training folder corrections` {
  private let store: Store
  private let adapter = RecordingAdapter()
  private let pipeline: Pipeline
  /// A message placed in the Train Good folder.
  private let selected: MailEnvelope
  private let plan: MailFolderPlan

  /// Saves an enabled Train Good plan whose baseline is validated.
  init() async throws {
    store = try testStore()
    var selected = try envelope()
    selected.identity.mailbox = "SpamWise Train Good"
    self.selected = selected
    var plan = MailFolderPlan(
      folder: .init(accountID: "account-A", path: ["SpamWise Train Good"]),
      purpose: .trainGood
    )
    plan.enabled = true
    plan.trainingBaselineValidated = true
    self.plan = plan
    pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(operation: { _ in
        Issue.record("Deliberate training must not classify first")
        throw ClassificationError.configuration
      })
    )
    try await save(plan)
  }

  private func save(_ plan: MailFolderPlan) async throws {
    try await StateRepository.editSettings(store) { $0.mailOptions.folderPlans = [plan] }
  }

  @discardableResult
  private func correct() async throws -> DecisionRecord {
    try await pipeline.correct(
      envelope: selected,
      label: .inbox,
      adapter: adapter,
      trainingPlanID: plan.id
    )
  }

  @discardableResult
  private func observe(
    _ identities: [MessageIdentity] = [],
    sweepComplete: Bool = true,
    canReleaseClaims: Bool = true,
    settling: Set<UUID> = []
  ) async throws -> Bool {
    try await TrainingFolders.observe(
      identities,
      planID: plan.id,
      sweepComplete: sweepComplete,
      canReleaseClaims: canReleaseClaims,
      settling: settling,
      store: store
    )
  }

  private func setOutcome(_ outcome: ActionOutcome, of record: DecisionRecord) async throws {
    try await StateRepository.update(store) { state in
      if let index = state.records.firstIndex(where: { $0.id == record.id }) {
        state.records[index].outcome = outcome
      }
    }
  }

  /// Identities of `count` other messages in the training folder.
  private func otherPlacements(_ count: Int) -> [MessageIdentity] {
    (0..<count).map { index in
      var identity = selected.identity
      identity.messageID = "<other-\(index)@example.org>"
      return identity
    }
  }

  private func state() async throws -> AppState { try await StateRepository.load(store) }

  @Test
  func `refuses corrections from a folder whose baseline is unvalidated`() async throws {
    var unvalidated = plan
    unvalidated.trainingBaselineValidated = false
    try await save(unvalidated)
    await #expect(throws: TrainingFolderError.planInactive) { try await correct() }
  }

  @Test
  func `corrects each placement once in dry run without classifying or moving it`()
    async throws
  {
    try await correct()
    await #expect(throws: TrainingFolderError.alreadyClaimed) { try await correct() }
    #expect(try await state().corrections.count == 1)
    #expect(await adapter.actions.isEmpty)
  }

  @Test
  func `keeps claims but not observations a sweep cannot release, and forgets both with the plan`()
    async throws
  {
    try await correct()
    try await observe(canReleaseClaims: false)
    let incomplete = try await state()
    #expect(incomplete.trainingClaims.count == 1)
    #expect(incomplete.trainingObservations[plan.id]?.isEmpty == true)
    try await observe([selected.identity], canReleaseClaims: false)
    #expect(try await state().trainingObservations[plan.id]?.isEmpty == true)
    try await FolderPlans.remove(planID: plan.id, in: store)
    let removed = try await state()
    #expect(removed.trainingClaims.isEmpty)
    #expect(removed.trainingObservations[plan.id] == nil)
  }

  @Test
  func `releases the claim once a complete sweep no longer finds the message`() async throws {
    let first = try await correct()
    try await observe()
    #expect(try await state().trainingClaims.isEmpty)
    #expect(try await correct().id != first.id)
  }

  @Test(arguments: [ActionOutcome.pending, .requested, .failed])
  func `keeps the claim of a placement awaiting dispatch or whose move is unconfirmed`(
    outcome: ActionOutcome
  ) async throws {
    let record = try await correct()
    try await setOutcome(outcome, of: record)
    try await observe()
    #expect(try await state().trainingClaims.count == 1)
  }

  @Test
  func `releases an applied placement's claim once its move recheck is done`() async throws {
    let record = try await correct()
    try await setOutcome(.applied, of: record)
    try await observe(settling: [record.id])
    #expect(try await state().trainingClaims.count == 1)
    try await observe()
    #expect(try await state().trainingClaims.isEmpty)
  }

  @Test
  func `finishes a traversal larger than it tracks without releasing its claims`() async throws {
    try await correct()
    let others = otherPlacements(RetentionLimits.trainingObservations + 1)
    #expect(try await observe(others, sweepComplete: false))
    let partial = try await state()
    #expect(partial.trainingObservations[plan.id]?.count == RetentionLimits.trainingObservations)
    #expect(try await observe())
    let finished = try await state()
    #expect(finished.trainingClaims.count == 1)
    #expect(finished.trainingObservations[plan.id]?.isEmpty == true)
    #expect(try await !observe())
    #expect(try await state().trainingClaims.isEmpty)
  }
}

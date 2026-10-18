import Foundation
import Testing
import SpamWiseCore

@Suite
// swiftlint:disable:next type_name
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

  @discardableResult private func correct() async throws -> DecisionRecord {
    try await pipeline.correct(
      envelope: selected,
      label: .inbox,
      adapter: adapter,
      trainingPlanID: plan.id
    )
  }

  private func observe(_ identities: [MessageIdentity] = [], canReleaseClaims: Bool = true)
    async throws
  {
    try await TrainingFolders.observe(
      identities,
      planID: plan.id,
      sweepComplete: true,
      canReleaseClaims: canReleaseClaims,
      store: store
    )
  }

  private func state() async throws -> AppState { try await StateRepository.load(store) }

  @Test func `refuses corrections from a folder whose baseline is unvalidated`() async throws {
    var unvalidated = plan
    unvalidated.trainingBaselineValidated = false
    try await save(unvalidated)
    await #expect(throws: TrainingFolderError.planInactive) { try await correct() }
  }

  @Test func `corrects each placement once in dry run without classifying or moving it`()
    async throws
  {
    try await correct()
    await #expect(throws: TrainingFolderError.alreadyClaimed) { try await correct() }
    #expect(try await state().corrections.count == 1)
    #expect(await adapter.actions.isEmpty)
  }

  @Test func `keeps claims and discards observations when a sweep cannot release them`()
    async throws
  {
    try await correct()
    try await observe(canReleaseClaims: false)
    let incomplete = try await state()
    #expect(incomplete.trainingClaims.count == 1)
    #expect(incomplete.trainingObservations[plan.id]?.isEmpty == true)
    try await observe([selected.identity], canReleaseClaims: false)
    #expect(try await state().trainingObservations[plan.id]?.isEmpty == true)
  }

  @Test func `releases the claim once a complete sweep no longer finds the message`() async throws {
    let first = try await correct()
    try await observe()
    #expect(try await state().trainingClaims.isEmpty)
    #expect(try await correct().id != first.id)
  }

  @Test func `keeps the claim when the training correction's move failed`() async throws {
    let record = try await correct()
    try await StateRepository.update(store) { state in
      if let index = state.records.firstIndex(where: { $0.id == record.id }) {
        state.records[index].outcome = .failed
      }
    }
    try await observe()
    #expect(try await state().trainingClaims.count == 1)
  }
}

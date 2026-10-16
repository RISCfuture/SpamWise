import Foundation
import Testing
import SpamWiseCore

@Test func `legacy state keeps settings and reviewed digest excludes corrected mail`() throws {
  let encoded = try JSONEncoder().encode(AppState())
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  object.removeValue(forKey: "learning"); object.removeValue(forKey: "reviewedLabels")
  var settings = try #require(object["settings"] as? [String: Any])
  settings.removeValue(forKey: "advanced"); settings["paused"] = true
  object["settings"] = settings
  let decoded = try JSONDecoder().decode(
    AppState.self,
    from: JSONSerialization.data(withJSONObject: object)
  )
  #expect(decoded.settings.paused)
  #expect(decoded.settings.advancedOptions.backend == .claude)
  #expect(!decoded.settings.advancedOptions.fingerprints)
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
}

@Test func `rule import is atomic and explicit edits invalidate stale work`() async throws {
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
}

@Test func `budget reservations cannot exceed cap across concurrent consumers`() async throws {
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

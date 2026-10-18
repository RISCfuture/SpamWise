import Foundation
import Testing
import SpamWiseCore

/// A dry-run Review decision for `person@example.com` in `account`.
private func reviewRecord(
  outcome: ActionOutcome = .dryRun,
  confidence: Int = 50,
  correctedLabel: MailLabel? = nil
) -> DecisionRecord {
  var record = DecisionRecord(
    identity: MessageIdentity(accountID: "account", contentHash: "digest"),
    sender: "person@example.com",
    subject: "Review",
    verdict: .init(label: .review, confidence: confidence, reason: "uncertain"),
    decision: .init(label: .review, action: .orangeFlag, reason: .model("uncertain")),
    outcome: outcome,
    path: .model
  )
  record.correctedLabel = correctedLabel
  return record
}

@Test func `excludes corrected mail from the Review digest`() {
  var state = AppState()
  state.records = [reviewRecord()]
  #expect(ReviewDigest(state: state).records.count == 1)
  state.records = [reviewRecord(correctedLabel: .inbox)]
  #expect(ReviewDigest(state: state).records.isEmpty)
}

@Test(arguments: [
  (text: "PERSON", accountID: String?.none, matches: true), ("PERSON", "account", true),
  ("PERSON", "other", false), ("nobody", nil, false)
])
func `filters Activity by case-insensitive text and exact account`(
  text: String,
  accountID: String?,
  matches: Bool
) {
  var query = ActivityQuery()
  query.text = text; query.accountID = accountID
  #expect(query.apply(to: [reviewRecord()]).isEmpty != matches)
}

@Test func `counts corrected decisions as mistakes and failed actions separately`() {
  let statistics = ActivityStatistics(records: [
    reviewRecord(outcome: .failed, correctedLabel: .inbox)
  ])
  #expect(statistics.reviewedDecisions == 1)
  #expect(statistics.reviewedMistakes == 1)
  #expect(statistics.unresolvedReview == 0)
  #expect(statistics.actionFailures == 1)
  #expect(statistics.reviewedMistakeUpperBound == 1)
  #expect(statistics.accountDailyCounts["account"]?.values.reduce(0, +) == 1)
}

@Test func `bounds the reviewed disagreement rate above the observed share`() throws {
  let statistics = ActivityStatistics(
    records: [reviewRecord(correctedLabel: .inbox)]
      + (1...9).map { _ in reviewRecord(correctedLabel: .review) }
  )
  let bound = try #require(statistics.reviewedMistakeUpperBound)
  #expect(bound > 0.1 && bound < 0.5)
}

@Test func `pages Activity in the requested order with newest first among ties`() async throws {
  let store = try testStore()
  let senders = ["carol@example.com", "alice@example.com", "bob@example.com", "alice@example.com"]
  let records = senders.enumerated().map { index, sender in
    var record = reviewRecord()
    record.sender = sender
    record.date = Date(timeIntervalSince1970: TimeInterval(index))
    return record
  }
  try await StateRepository.update(store) { state in records.forEach { state.record($0) } }
  var query = ActivityQuery()
  query.sort = ActivitySort(key: .sender, ascending: true)
  let page = try await StateRepository.activity(store, matching: query, limit: 3)
  #expect(page.map(\.id) == [records[3].id, records[1].id, records[2].id])
  #expect(query.apply(to: records).prefix(3).map(\.id) == page.map(\.id))
}

@Test func `ranks failed Mail actions ahead of less confident Review`() {
  let failed = reviewRecord(outcome: .failed, confidence: 50)
  let uncertain = reviewRecord(outcome: .noAction, confidence: 1)
  #expect(ReviewPriority.precedes(failed, uncertain))
  #expect(!ReviewPriority.precedes(uncertain, failed))
}

@Test func `summarizes diagnostic reasons without sender or explanation text`() throws {
  var unconsented = reviewRecord()
  unconsented.decision.reason = .classificationFailed(.consentRequired)
  var state = AppState()
  state.records = [reviewRecord(), unconsented]
  let summary = DiagnosticSummary(state: state)
  #expect(summary.reasons == ["model": 1, "unclassified: consentRequired": 1])
  let diagnostic = String(decoding: try JSONEncoder().encode(summary), as: UTF8.self)
  #expect(!diagnostic.contains("person@example.com"))
  #expect(!diagnostic.contains("uncertain"))
}

@Test func `reads the records of chosen messages newest first`() async throws {
  let store = try testStore()
  let older = reviewRecord()
  var newer = reviewRecord(outcome: .applied)
  newer.date = older.date.addingTimeInterval(1)
  let other = DecisionRecord(
    identity: MessageIdentity(accountID: "account", contentHash: "other"),
    decision: .init(label: nil, action: .none, reason: .selectedForCorrection),
    outcome: .noAction
  )
  let recorded = [older, other, newer]
  try await StateRepository.update(store, loading: StateSlices()) { state in
    for record in recorded { state.record(record) }
  }
  let records = try await StateRepository.records(store, identityKeys: [older.identity.key])
  #expect(records.map(\.id) == [newer.id, older.id])
}

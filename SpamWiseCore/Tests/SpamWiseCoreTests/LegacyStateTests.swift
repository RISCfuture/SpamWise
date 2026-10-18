import Foundation
import Testing
import SpamWiseCore

@Test func `loads legacy Activity records with typed reasons and without stored placeholders`()
  async throws
{
  let encoded = try JSONEncoder().encode(AppState())
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  let contentRuleID = UUID()
  let legacy: [(label: String?, reason: String)] = [
    ("junk", "gate: user domain block rule"),
    (nil, "unclassified: spending limit reached; no provider request was made"),
    (nil, "unclassified: consentRequired"),
    ("inbox", "gate: user content rule \(contentRuleID.uuidString)"),
    ("review", "Looks like a newsletter")
  ]
  object["records"] =
    legacy.map {
      legacyRecord(label: $0, reason: $1, sender: "Unknown", subject: "Unclassified message")
    } + [
      legacyRecord(
        label: "inbox",
        reason: ["classificationFailed": ["_0": "retired"]],
        path: "model",
        sender: "person@example.com",
        subject: "(No subject)"
      )
    ]
  let stored = try JSONDecoder().decode(
    AppState.self,
    from: JSONSerialization.data(withJSONObject: object)
  )
  let store = try testStore()
  try await store.update(StateRepository.key, default: AppState()) { $0 = stored }
  let decoded = try await StateRepository.load(store)
  #expect(
    decoded.records.map(\.decision.reason) == [
      .gate(.senderRule(scope: .domain, disposition: .block)), .spendingLimitReached,
      .classificationFailed(.consentRequired),
      .gate(.contentRule(id: contentRuleID, disposition: .allow, note: nil)),
      .legacy("Looks like a newsletter"), .unrecognized
    ]
  )
  #expect(decoded.records.map(\.path) == Array(repeating: .error, count: 5) + [.model])
  #expect(decoded.records.map(\.sender) == Array(repeating: nil, count: 5) + ["person@example.com"])
  #expect(decoded.records.allSatisfy { $0.subject == nil })
  #expect(
    decoded.records.map(\.deferredBySpendingLimit) == [false, true, false, false, false, false]
  )
  #expect(
    decoded.records.prefix(3).map(\.decision.reason.localizedDescription) == [
      "Blocked by your rule for this sender’s domain",
      "Not classified: the monthly spending limit was reached, so nothing was sent to the provider.",
      "Not classified: Allow mail sharing with the selected provider in Account settings first."
    ]
  )
  var legacySearch = ActivityQuery()
  legacySearch.text = "RULE FOR THIS SENDER"
  #expect(legacySearch.apply(to: decoded.records).map(\.decision.label) == [.junk])
}

/// A record in the untyped form that earlier versions stored.
private func legacyRecord(
  label: String?,
  reason: Any,
  path: String = "retired",
  sender: String,
  subject: String
) -> [String: Any] {
  var decision: [String: Any] = ["action": "none", "reason": reason]
  decision["label"] = label
  return [
    "id": UUID().uuidString, "date": 0,
    "identity": ["accountID": "account", "contentHash": UUID().uuidString], "sender": sender,
    "subject": subject, "decision": decision, "outcome": "unclassified", "path": path,
    "latency": 0, "revision": 0
  ]
}

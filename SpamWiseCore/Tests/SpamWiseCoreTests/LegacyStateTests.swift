import Foundation
import SwiftData
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
    legacy.enumerated().map {
      legacyRecord(
        label: $1.label,
        reason: $1.reason,
        date: $0,
        sender: "Unknown",
        subject: "Unclassified message"
      )
    } + [
      legacyRecord(
        label: "inbox",
        reason: ["classificationFailed": ["_0": "retired"]],
        path: "model",
        date: legacy.count,
        sender: "person@example.com",
        subject: "(No subject)"
      )
    ]
  object["auditEvents"] = [
    [
      "id": UUID().uuidString, "date": 0, "revision": 2, "kind": "senderRule",
      "detail": "Saved domain:shop.example: block"
    ]
  ]
  object["rules"] = [
    ["scope": "domain", "value": "Bücher.example", "disposition": "block", "updatedAt": 0]
  ]
  let stored = try JSONDecoder().decode(
    AppState.self,
    from: JSONSerialization.data(withJSONObject: object)
  )
  let store = try testStore()
  try await store.update("application-v1", default: AppState()) { $0 = stored }
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
  #expect(decoded.auditEvents.map(\.change) == [.recorded("Saved domain:shop.example: block")])
  #expect(decoded.rules.map(\.value) == ["xn--bcher-kva.example"])
  var legacySearch = ActivityQuery()
  legacySearch.text = "RULE FOR THIS SENDER"
  #expect(legacySearch.apply(to: decoded.records).map(\.decision.label) == [.junk])
}

/// A record in the untyped form that earlier versions stored.
private func legacyRecord(
  label: String?,
  reason: Any,
  path: String = "retired",
  date: Int,
  sender: String,
  subject: String
) -> [String: Any] {
  var decision: [String: Any] = ["action": "none", "reason": reason]
  decision["label"] = label
  return [
    "id": UUID().uuidString, "date": date,
    "identity": ["accountID": "account", "contentHash": UUID().uuidString], "sender": sender,
    "subject": subject, "decision": decision, "outcome": "unclassified", "path": path,
    "latency": 0, "revision": 0
  ]
}

@Test func `imports a single-document store once and sets aside an unreadable one`() async throws {
  let identity = MessageIdentity(accountID: "account", contentHash: "digest")
  var legacy = AppState()
  legacy.settings.paused = true
  legacy.rules = [.init(scope: .address, value: "friend@example.org", disposition: .allow)]
  legacy.claimedActions = [identity.key: UUID()]
  legacy.records = [
    DecisionRecord(
      identity: identity,
      sender: "person@example.com",
      subject: "Weekly news",
      verdict: .init(label: .review, confidence: 60, reason: "uncertain"),
      decision: .init(label: .review, action: .orangeFlag, reason: .model("uncertain")),
      outcome: .applied,
      path: .model
    )
  ]
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
  )
  var records = try #require(object["records"] as? [[String: Any]])
  records[0]["outcome"] = "deferred"
  object["records"] = records
  object.removeValue(forKey: "learning"); object.removeValue(forKey: "costByMonth")
  let store = try legacyStore(JSONSerialization.data(withJSONObject: object))
  let imported = try await StateRepository.load(store)
  #expect(imported.settings.paused)
  #expect(imported.rules == legacy.rules)
  #expect(imported.claimedActions == legacy.claimedActions)
  #expect(imported.records.map(\.outcome) == [.requested])
  #expect(try await store.read("application-v1", default: Data()).isEmpty)
  #expect(try await StateRecovery.entries(store).isEmpty)
  var query = ActivityQuery(); query.text = "weekly"
  #expect(try await StateRepository.activity(store, matching: query, limit: 10).count == 1)
  let unreadable = try legacyStore(Data("not json".utf8))
  #expect(try await StateRepository.load(unreadable).rules.isEmpty)
  #expect(try await StateRecovery.entries(unreadable).map(\.source) == ["application-v1"])
  #expect(
    try await StateRecovery.preservedData(unreadable)["application-v1"] == Data("not json".utf8)
  )
  try await StateRecovery.reset(unreadable)
  #expect(try await StateRecovery.entries(unreadable).isEmpty)
}

@Test func `decodes legacy settings with defaults for options they lack`() throws {
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as? [String: Any]
  )
  object.removeValue(forKey: "learning"); object.removeValue(forKey: "reviewedLabels")
  var settings = try #require(object["settings"] as? [String: Any])
  settings.removeValue(forKey: "advanced"); settings["paused"] = true
  settings.removeValue(forKey: "mailPreferences"); settings["route"] = "mailKit"
  object["settings"] = settings
  let decoded = try JSONDecoder().decode(
    AppState.self,
    from: JSONSerialization.data(withJSONObject: object)
  )
  #expect(decoded.settings.paused)
  #expect(decoded.settings.advancedOptions.backend == .claude)
  #expect(!decoded.settings.advancedOptions.fingerprints)
  #expect(!decoded.settings.mailOptions.localOnly)
  #expect(decoded.settings.incomingRoute == .mailRule)
}

/// Writes `snapshot` into an unversioned single-document store.
private func legacyStore(_ snapshot: Data) throws -> Store {
  let store = try testStore()
  let container = try ModelContainer(
    for: Unversioned.StoredValue.self,
    configurations: ModelConfiguration(url: store.url, cloudKitDatabase: .none)
  )
  let context = ModelContext(container)
  context.insert(Unversioned.StoredValue(key: "application-v1", payload: snapshot))
  try context.save()
  return store
}

private enum Unversioned {
  @Model final class StoredValue {
    @Attribute(.unique) var key: String
    var payload: Data
    init(key: String, payload: Data) { self.key = key; self.payload = payload }
  }
}

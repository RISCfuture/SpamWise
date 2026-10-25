import Foundation
import SwiftData
import Testing
import SpamWiseCore

/// Activity, audit and rules stored in the untyped forms of earlier versions.
@Suite
struct `Legacy Activity records` {
  private let contentRuleID = UUID()
  private let decoded: AppState

  init() async throws {
    let encoded = try JSONEncoder().encode(AppState())
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
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
    decoded = try await StateRepository.load(store)
  }

  @Test
  func `types the reasons earlier versions stored as text`() {
    #expect(
      decoded.records.map(\.decision.reason) == [
        .gate(.senderRule(scope: .domain, disposition: .block)), .spendingLimitReached,
        .classificationFailed(.consentRequired),
        .gate(.contentRule(id: contentRuleID, disposition: .allow, note: nil)),
        .legacy("Looks like a newsletter"), .unrecognized
      ]
    )
  }

  @Test
  func `records untyped paths as errors and keeps only real senders`() {
    #expect(decoded.records.map(\.path) == Array(repeating: .error, count: 5) + [.model])
    #expect(
      decoded.records.map(\.sender) == Array(repeating: nil, count: 5) + ["person@example.com"]
    )
  }

  @Test
  func `drops stored placeholder subjects`() {
    #expect(decoded.records.allSatisfy { $0.subject == nil })
  }

  @Test
  func `marks spending-limit deferrals`() {
    #expect(
      decoded.records.map(\.deferredBySpendingLimit) == [false, true, false, false, false, false]
    )
  }

  @Test
  func `describes typed legacy reasons in prose`() {
    #expect(
      decoded.records.prefix(3).map(\.decision.reason.localizedDescription) == [
        "Blocked by your rule for this sender’s domain",
        "Not classified: the monthly spending limit was reached, so nothing was sent to the provider.",
        "Not classified: Allow mail sharing with the selected provider in Settings → Classifier first."
      ]
    )
  }

  @Test
  func `keeps legacy audit details and stores domain rules in ASCII form`() {
    #expect(decoded.auditEvents.map(\.change) == [.recorded("Saved domain:shop.example: block")])
    #expect(decoded.rules.map(\.value) == ["xn--bcher-kva.example"])
  }

  @Test
  func `finds legacy rule decisions by their description`() {
    var search = ActivityQuery()
    search.text = "RULE FOR THIS SENDER"
    #expect(search.apply(to: decoded.records).map(\.decision.label) == [.junk])
  }
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

@Suite
struct `Single-document import` {
  private let identity = MessageIdentity(accountID: "account", contentHash: "digest")
  private let legacy: AppState

  init() {
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
    self.legacy = legacy
  }

  /// A store holding the legacy snapshot with an outcome and fields a different version wrote.
  private func importedStore() throws -> Store {
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
    )
    var records = try #require(object["records"] as? [[String: Any]])
    records[0]["outcome"] = "deferred"
    object["records"] = records
    object.removeValue(forKey: "learning"); object.removeValue(forKey: "costByMonth")
    return try legacyStore(JSONSerialization.data(withJSONObject: object))
  }

  @Test
  func `imports settings, rules and claims from a single-document store`() async throws {
    let imported = try await StateRepository.load(importedStore())
    #expect(imported.settings.paused)
    #expect(imported.rules == legacy.rules)
    #expect(imported.claimedActions == legacy.claimedActions)
  }

  @Test
  func `imports an unknown outcome as requested`() async throws {
    #expect(try await StateRepository.load(importedStore()).records.map(\.outcome) == [.requested])
  }

  @Test
  func `removes the snapshot once imported and finds its Activity`() async throws {
    let store = try importedStore()
    _ = try await StateRepository.load(store)
    #expect(try await store.read("application-v1", default: Data()).isEmpty)
    #expect(try await StateRecovery.entries(store).isEmpty)
    var query = ActivityQuery(); query.text = "weekly"
    #expect(try await StateRepository.activity(store, matching: query, limit: 10).count == 1)
  }

  @Test
  func `sets aside an unreadable snapshot until recovery is resolved`() async throws {
    let unreadable = try legacyStore(Data("not json".utf8))
    #expect(try await StateRepository.load(unreadable).rules.isEmpty)
    #expect(try await StateRecovery.entries(unreadable).map(\.source) == ["application-v1"])
    #expect(
      try await StateRecovery.preservedData(unreadable)["application-v1"] == Data("not json".utf8)
    )
    try await StateRecovery.reset(unreadable)
    #expect(try await StateRecovery.entries(unreadable).isEmpty)
  }
}

@Suite
struct `Stored state condition` {
  private let store: Store

  init() throws { store = try testStore() }

  @Test
  func `reports an empty store as a first run until settings are saved`() async throws {
    #expect(try await StateRepository.condition(store) == .empty)
    try await StateRepository.editSettings(store) { $0.paused = true }
    #expect(try await StateRepository.condition(store) == .readable)
  }

  @Test
  func `reports set-aside data as needing recovery`() async throws {
    let unreadable = try legacyStore(Data("not json".utf8))
    guard case .needsRecovery(let entries) = try await StateRepository.condition(unreadable)
    else {
      Issue.record("Set-aside data was not reported")
      return
    }
    #expect(entries.map(\.source) == ["application-v1"])
  }

  @Test
  func `sets aside settings it can't decode and asks for recovery`() async throws {
    try await store.update("state.policy", default: "not settings") { _ in }
    guard case .needsRecovery(let entries) = try await StateRepository.condition(store) else {
      Issue.record("Undecodable settings were reported as readable")
      return
    }
    #expect(entries.map(\.source) == ["policy"])
    #expect(try await StateRecovery.preservedData(store)["policy"] != nil)
  }

  @Test
  func `keeps settings that a read set aside`() async throws {
    try await store.update("state.policy", default: "not settings") { _ in }
    _ = try await StateRepository.load(store, StateSlices())
    #expect(try await StateRecovery.entries(store).map(\.source) == ["policy"])
  }

  @Test
  func `refuses state a newer version saved without changing it`() async throws {
    try await store.update("state.schema", default: 0) { $0 = 3 }
    await #expect(throws: StoredStateError.newerVersion) {
      try await StateRepository.condition(store)
    }
    await #expect(throws: StoredStateError.newerVersion) {
      try await StateRepository.editSettings(store) { $0.paused = true }
    }
    #expect(try await store.read("state.schema", default: 0) == 3)
  }

  @Test
  func `reports a database that can't be opened as unreadable`() async throws {
    try Data("not a database".utf8).write(to: store.url)
    await #expect(throws: StoredStateError.unreadable) {
      try await StateRepository.condition(store)
    }
  }
}

@Test
func `decodes legacy settings with defaults for options they lack`() throws {
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as? [String: Any]
  )
  object.removeValue(forKey: "learning"); object.removeValue(forKey: "reviewedLabels")
  var settings = try #require(object["settings"] as? [String: Any])
  settings.removeValue(forKey: "advanced"); settings["paused"] = true
  settings.removeValue(forKey: "mailPreferences"); settings["route"] = "mailKit"
  settings.removeValue(forKey: "categoryPreferences")
  settings["policy"] = PromptBuilder.formerDefaultPolicies.sorted()[0]
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
  #expect(decoded.settings.policy == PromptBuilder.defaultPolicy)
  #expect(decoded.settings.categoryPreferences == .defaults)
}

@Test
func `reads unreadable privacy preferences as their restrictive values`() throws {
  let preferences = try JSONDecoder().decode(
    MailPreferences.self,
    from: Data(#"{"localOnly": "yes", "accountIDs": 7}"#.utf8)
  )
  #expect(preferences.localOnly)
  #expect(preferences.accountIDs?.isEmpty == true)
}

@Test
func `reads absent privacy preferences as their defaults`() throws {
  let preferences = try JSONDecoder().decode(MailPreferences.self, from: Data("{}".utf8))
  #expect(!preferences.localOnly)
  #expect(preferences.accountIDs == nil)
}

@Test
func `reads unreadable Mail preferences and consent in settings as restrictive`() throws {
  let settings = try JSONDecoder().decode(
    Settings.self,
    from: Data(#"{"mailPreferences": 5, "advanced": {"mailSharingConsent": "claude"}}"#.utf8)
  )
  #expect(settings.mailOptions.localOnly)
  #expect(settings.mailOptions.accountIDs?.isEmpty == true)
  #expect(settings.advancedOptions.mailSharingConsent.isEmpty)
}

@Test
func `keeps the stored names of camel-case enum cases`() {
  let pinned: [(any RawRepresentable<String>, String)] = [
    (AppleModelBackend.onDevice, "onDevice"),
    (AppleModelBackend.privateCloudCompute, "privateCloudCompute"),
    (ModelBackend.onDevice, "onDevice"),
    (ModelBackend.privateCloudCompute, "privateCloudCompute"),
    (ModelBackend.openAI, "openAI"),
    (ThreatStatus.notDetected, "notDetected"),
    (ClassificationError.missingCredential, "missingCredential"),
    (ClassificationError.consentRequired, "consentRequired"),
    (ClassificationError.rateLimited, "rateLimited"),
    (ClassificationError.contextExceeded, "contextExceeded"),
    (ClassificationError.invalidOutput, "invalidOutput"),
    (ReviewTreatment.orangeFlag, "orangeFlag"),
    (ReviewTreatment.orangeBackground, "orangeBackground"),
    (MailAction.orangeFlag, "orangeFlag"),
    (MailAction.orangeBackground, "orangeBackground"),
    (MailAction.moveToJunk, "moveToJunk"),
    (MailAction.moveToInbox, "moveToInbox"),
    (MailAction.clearOrangeFlag, "clearOrangeFlag"),
    (MailAction.clearOrangeBackground, "clearOrangeBackground"),
    (ActionOutcome.noAction, "noAction"),
    (ActionOutcome.dryRun, "dryRun"),
    (ActionOutcome.integrationUnavailable, "integrationUnavailable"),
    (LearningPartition.heldOut, "heldOut"),
    (LearningProvenance.explicitCorrection, "explicitCorrection"),
    (LearningProvenance.highConfidencePrediction, "highConfidencePrediction"),
    (DecodingIssue.invalidCharacters, "invalidCharacters"),
    (DecodingIssue.unknownCharset, "unknownCharset"),
    (DecodingIssue.invalidQuotedPrintable, "invalidQuotedPrintable"),
    (DecodingIssue.invalidEncodedWord, "invalidEncodedWord"),
    (DecodingIssue.unknownTransferEncoding, "unknownTransferEncoding"),
    (DecodingIssue.malformedPartHeaders, "malformedPartHeaders"),
    (DecodingIssue.ambiguousPartHeaders, "ambiguousPartHeaders"),
    (DecodingIssue.malformedMessageHeaders, "malformedMessageHeaders"),
    (DecodingIssue.incompleteMultipart, "incompleteMultipart"),
    (DecodingIssue.invalidMultipartBoundary, "invalidMultipartBoundary"),
    (DecodingIssue.partLimitExceeded, "partLimitExceeded"),
    (ContentRuleField.listID, "listID"),
    (ContentRuleField.replyTo, "replyTo"),
    (ContentRuleField.contentType, "contentType"),
    (ContentRuleField.attachmentNames, "attachmentNames"),
    (ContentRuleField.attachmentTypes, "attachmentTypes"),
    (ContentRuleOperator.regularExpression, "regularExpression"),
    (ExternalEvidenceStatus.notListed, "notListed"),
    (SpamhausTransport.publicDNS, "publicDNS"),
    (MailTransport.appleMail, "appleMail"),
    (ReviewedLabel.Origin.reviewedImport, "reviewedImport"),
    (AuditEvent.Kind.senderRule, "senderRule"),
    (AuditEvent.Kind.contentRule, "contentRule"),
    (AuditEvent.Kind.backupRestore, "backupRestore"),
    (AuditEvent.Kind.corpusImport, "corpusImport"),
    (AuditEvent.Kind.corpusForget, "corpusForget"),
    (MailFolderPurpose.trainGood, "trainGood"),
    (MailFolderPurpose.trainJunk, "trainJunk"),
    (IncomingRoute.mailRule, "mailRule"),
    (DecisionPath.unreadableSender, "unreadableSender")
  ]
  for (value, name) in pinned { #expect(value.rawValue == name) }
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
  @Model
  final class StoredValue {
    @Attribute(.unique)
    var key: String
    var payload: Data

    init(key: String, payload: Data) { self.key = key; self.payload = payload }
  }
}

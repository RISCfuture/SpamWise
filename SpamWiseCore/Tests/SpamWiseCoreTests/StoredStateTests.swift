import Foundation
import SwiftData
import Testing
import SpamWiseCore

@Test
func `reads record fields this version can't decode as their fallbacks`() throws {
  let record = DecisionRecord(
    identity: MessageIdentity(accountID: "account", contentHash: "digest"),
    decision: .init(label: .inbox, action: .none, reason: .paused),
    outcome: .applied,
    path: .model
  )
  let encoded = try JSONEncoder().encode(record)
  for reason: Any in ["Looks like a newsletter", ["classificationFailed": ["_0": "retired"]]] {
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var decision = try #require(object["decision"] as? [String: Any])
    decision["reason"] = reason
    object["decision"] = decision
    object["outcome"] = "deferred"; object["path"] = "retired"
    let decoded = try JSONDecoder().decode(
      DecisionRecord.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(decoded.decision.reason == .unrecognized)
    #expect(decoded.outcome == .requested)
    #expect(decoded.path == .error)
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
  func `sets aside a snapshot from a build before the entity schema`() async throws {
    let snapshot = try JSONEncoder().encode(AppState())
    let early = try singleDocumentStore(snapshot)
    guard case .needsRecovery(let entries) = try await StateRepository.condition(early) else {
      Issue.record("The snapshot was not set aside")
      return
    }
    #expect(entries.map(\.source) == ["application-v1"])
    #expect(try await StateRecovery.preservedData(early)["application-v1"] == snapshot)
    try await StateRecovery.reset(early)
    #expect(try await StateRepository.condition(early) == .empty)
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
func `decodes settings with defaults for options they lack`() throws {
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
private func singleDocumentStore(_ snapshot: Data) throws -> Store {
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

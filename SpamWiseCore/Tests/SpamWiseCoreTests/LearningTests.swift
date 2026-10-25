import Classifier
import Foundation
import Learning
import MessageModel
import Signals
import Testing
import SpamWiseCore

@Suite
struct `Correction retrieval` {
  let message: ParsedMessage
  let relevant = correction("observatory telescope shipment", date: 1)
  let irrelevant = correction(
    "casino lucky jackpot prize",
    sender: "prize@casino.example",
    date: 2
  )

  init() throws {
    message = try learningMessage("Your observatory telescope shipment has arrived")
  }

  @Test
  func `retrieves related older corrections before unrelated recent examples`() {
    let results = CorrectionRetrieval.examples(for: message, from: [irrelevant, relevant], limit: 1)
    #expect(results.map(\.id) == [relevant.id])
  }

  @Test
  func `retrieves nothing when the limit is zero`() {
    #expect(CorrectionRetrieval.examples(for: message, from: [relevant], limit: 0).isEmpty)
  }

  @Test
  func `retrieves the same examples whatever their stored order`() {
    #expect(
      CorrectionRetrieval.examples(for: message, from: [relevant, irrelevant], limit: 2)
        == CorrectionRetrieval.examples(for: message, from: [irrelevant, relevant], limit: 2)
    )
  }
}

/// Corrections that must not produce a domain rule suggestion.
enum UnsuggestedCorrections: CaseIterable, Sendable {
  case contradictedByGood, oneExampleRepeated, sharedProviderDomains, alreadyDecidedByRule

  var examples: [CorrectionExample] {
    switch self {
      case .contradictedByGood:
        repeatedShopJunk
          + [correction("receipt", sender: "orders@shop.example", label: .inbox, date: 5)]
      case .oneExampleRepeated: Array(repeating: repeatedShopJunk[0], count: 8)
      case .sharedProviderDomains: friendsAtSharedProviders
      case .alreadyDecidedByRule: repeatedShopJunk
    }
  }

  var rules: [SenderRule] {
    self == .alreadyDecidedByRule
      ? [SenderRule(scope: .domain, value: "shop.example", disposition: .allow)] : []
  }
}

@Suite
struct `Policy suggestions` {
  @Test
  func `suggests a rule for a domain corrected the same way by several senders`() throws {
    let suggestions = PolicyDistiller.suggestions(from: repeatedShopJunk, rules: [])
    let suggestion = try #require(suggestions.first)
    #expect(suggestions.count == 1)
    #expect(suggestion.domain == "shop.example")
    #expect(suggestion.label == .junk)
  }

  @Test(arguments: UnsuggestedCorrections.allCases)
  func `makes no suggestion for corrections that don't agree independently`(
    _ corrections: UnsuggestedCorrections
  ) {
    #expect(
      PolicyDistiller.suggestions(from: corrections.examples, rules: corrections.rules).isEmpty
    )
  }

  @Test
  func `suggests a category preference only when corrections across senders agree`() throws {
    func promotion(_ sender: String, _ label: MailLabel, date: Double) -> CorrectionExample {
      var example = correction("sale \(sender)", sender: sender, label: label, date: date)
      example.category = .promotion
      return example
    }
    let junked = [
      promotion("deals@a.example", .junk, date: 1), promotion("deals@b.example", .junk, date: 2),
      promotion("deals@c.example", .junk, date: 3)
    ]
    let suggestion = try #require(
      PolicyDistiller.categorySuggestions(from: junked, preferences: .defaults).first
    )
    #expect(suggestion.category == .promotion && suggestion.preference == .junk)
    #expect(suggestion.domainCount == 3)
    let kept = junked + [promotion("deals@d.example", .inbox, date: 4)]
    #expect(PolicyDistiller.categorySuggestions(from: kept, preferences: .defaults).isEmpty)
    var preferences = CategoryPreferences.defaults
    preferences[.promotion] = .junk
    #expect(PolicyDistiller.categorySuggestions(from: junked, preferences: preferences).isEmpty)
  }

  @Test
  func `counts known senders at a domain from corrections and records`() {
    var state = AppState()
    state.corrections = repeatedShopJunk + friendsAtSharedProviders
    state.record(
      .init(
        identity: .init(accountID: "account", contentHash: "news"),
        sender: "news@shop.example",
        decision: .init(label: .junk, action: .none, reason: .model("Unwanted")),
        outcome: .dryRun
      )
    )
    #expect(state.knownSenderCounts(atDomains: ["shop.example"]) == ["shop.example": 4])
  }
}

@Suite
struct `Campaign fingerprints` {
  let message: ParsedMessage

  init() throws { message = try learningMessage(campaignText, authenticated: true) }

  private func junkCampaign() -> LearningState {
    var state = LearningState()
    state.recordCorrection(message: message, evidence: authenticatedEvidence(message), label: .junk)
    return state
  }

  @Test
  func `learns no campaign from a correction without trusted authentication`() {
    var state = LearningState()
    state.recordCorrection(message: message, evidence: .init(message: message), label: .junk)
    #expect(state.campaignMatch(for: message, evidence: authenticatedEvidence(message)) == nil)
  }

  @Test
  func `matches an authenticated junk campaign only for authenticated mail`() {
    let state = junkCampaign()
    #expect(state.campaignMatch(for: message, evidence: authenticatedEvidence(message)) != nil)
    #expect(state.campaignMatch(for: message, evidence: .init(message: message)) == nil)
  }

  @Test
  func `matches no campaign for the same text from a different sender`() throws {
    let unrelatedSender = try learningMessage(
      campaignText,
      sender: "different@unrelated.example",
      authenticated: true
    )
    #expect(
      junkCampaign().campaignMatch(
        for: unrelatedSender,
        evidence: authenticatedEvidence(unrelatedSender)
      ) == nil
    )
  }

  @Test
  func `forgets a campaign after an explicit good correction`() {
    var state = junkCampaign()
    state.recordCorrection(
      message: message,
      evidence: authenticatedEvidence(message),
      label: .inbox
    )
    #expect(state.campaignMatch(for: message, evidence: authenticatedEvidence(message)) == nil)
    #expect(state.samples.map(\.label) == [.inbox])
  }

  @Test
  func `learns no campaign from generic boilerplate`() throws {
    let generic = try learningMessage(
      "Thank you\nUnsubscribe privacy policy manage preferences contact us",
      authenticated: true
    )
    var state = LearningState()
    state.recordCorrection(message: generic, evidence: authenticatedEvidence(generic), label: .junk)
    #expect(state.campaignMatch(for: generic, evidence: authenticatedEvidence(generic)) == nil)
  }

  @Test
  func `lets a later junk correction override an earlier good campaign signature`() throws {
    let issues = try (0..<3).map {
      try learningMessage(campaignText + " issue\($0)", id: "\($0)", authenticated: true)
    }
    var state = LearningState()
    state.recordCorrection(
      message: issues[0],
      evidence: authenticatedEvidence(issues[0]),
      label: .inbox
    )
    state.recordCorrection(
      message: issues[1],
      evidence: authenticatedEvidence(issues[1]),
      label: .junk
    )
    #expect(state.fingerprints.map(\.label) == [.junk])
    #expect(state.campaignMatch(for: issues[2], evidence: authenticatedEvidence(issues[2])) != nil)
  }
}

@Suite
struct `Bounded learning state` {
  /// Five junk corrections recorded into room for three samples and two fingerprints.
  let state: LearningState

  init() throws {
    var state = LearningState(maximumSamples: 3, maximumFingerprints: 2)
    for index in 0..<5 {
      let message = try learningMessage(campaignText + " unique\(index)", id: "\(index)")
      state.recordCorrection(
        message: message,
        evidence: .init(message: message),
        label: .junk,
        date: Date(timeIntervalSince1970: Double(index))
      )
    }
    self.state = state
  }

  @Test
  func `keeps the newest samples and fingerprints within their limits`() {
    #expect(state.samples.count == 3)
    #expect(state.samples.first?.date == Date(timeIntervalSince1970: 4))
    #expect(state.fingerprints.count <= 2)
  }

  @Test
  func `round-trips its samples through JSON`() throws {
    let restored = try JSONDecoder().decode(LearningState.self, from: JSONEncoder().encode(state))
    #expect(restored.samples == state.samples)
  }

  @Test
  func `decodes an empty document as an empty state`() throws {
    let empty = try JSONDecoder().decode(LearningState.self, from: Data("{}".utf8))
    #expect(empty.samples.isEmpty)
  }

  @Test
  func `migrates legacy sample features to the current schema`() throws {
    let legacy = try JSONDecoder().decode(
      LearningState.self,
      from: Data(legacySampleJSON(id: try #require(state.samples.first?.id)).utf8)
    )
    let migrated = try #require(legacy.samples.first?.features)
    #expect(migrated.version < LearningFeatures.schemaVersion)
    #expect(migrated.abuseHeavyTLD == 1)
    #expect(migrated.unknownDomainAge == 1)
    #expect(migrated.linkDomainDensity == 0.5)
  }
}

@Suite
struct `Statistical training` {
  private static let junkVerdict = Verdict(label: .junk, confidence: 99, reason: "classifier")
  let query: ParsedMessage

  init() throws {
    query = try learningMessage("casino jackpot lottery prize lucky winner claim reward")
  }

  /// Evidence for the query whose only learned signal is whether its TLD is abuse-heavy.
  private func evidence(abuseHeavyTLD: Bool) -> EvidenceBundle {
    var evidence = EvidenceBundle(message: query)
    evidence.tldIsAbuseHeavy = abuseHeavyTLD
    return evidence
  }

  private func trained() throws -> LearningState {
    var state = LearningState()
    try trainLearningState(&state)
    return state
  }

  @Test
  func `has no statistical estimate before training`() {
    let estimate = LearningState().estimate(message: query, evidence: .init(message: query))
    #expect(estimate.bayesLogOdds == nil)
    #expect(estimate.logisticMargin == nil)
  }

  @Test
  func `estimates junk odds after training on every explicit label`() throws {
    let state = try trained()
    let estimate = state.estimate(message: query, evidence: .init(message: query))
    #expect((estimate.bayesLogOdds ?? 0) > 0)
    #expect(estimate.logisticMargin != nil)
    #expect(estimate.trainingCount == state.samples.count)
  }

  @Test(arguments: [(confidence: 99, hasContradiction: true), (98, false)])
  func `refuses self training from a contradicted or less confident verdict`(
    confidence: Int,
    hasContradiction: Bool
  ) throws {
    var state = try trained()
    let admitted = state.admitPrediction(
      message: query,
      evidence: evidence(abuseHeavyTLD: true),
      verdict: .init(label: .junk, confidence: confidence, reason: "classifier"),
      hasContradiction: hasContradiction
    )
    #expect(!admitted)
  }

  @Test
  func `admits a confident consistent prediction once`() throws {
    var state = try trained()
    let first = state.admitPrediction(
      message: query,
      evidence: evidence(abuseHeavyTLD: true),
      verdict: Self.junkVerdict,
      hasContradiction: false
    )
    let duplicate = state.admitPrediction(
      message: query,
      evidence: .init(message: query),
      verdict: Self.junkVerdict,
      hasContradiction: false
    )
    #expect(first)
    #expect(!duplicate)
  }

  @Test
  func `keeps an explicit good label over a self-trained prediction`() throws {
    var state = try trained()
    _ = state.admitPrediction(
      message: query,
      evidence: evidence(abuseHeavyTLD: true),
      verdict: Self.junkVerdict,
      hasContradiction: false
    )
    state.recordCorrection(message: query, evidence: .init(message: query), label: .inbox)
    let overridingGood = state.admitPrediction(
      message: query,
      evidence: .init(message: query),
      verdict: Self.junkVerdict,
      hasContradiction: false
    )
    #expect(!overridingGood)
    #expect(
      state.samples.filter { $0.id == LearningSample.identity(for: query) }.map(\.label) == [.inbox]
    )
  }

  @Test
  func `learns directional regularized weights from evidence`() throws {
    let state = try trained()
    let junk = state.estimate(message: query, evidence: evidence(abuseHeavyTLD: true))
    let good = state.estimate(message: query, evidence: evidence(abuseHeavyTLD: false))
    #expect((junk.logisticMargin ?? 0) > 0)
    #expect((good.logisticMargin ?? 0) < 0)
  }

  @Test
  func `refuses self training that the learned weights contradict`() throws {
    var state = try trained()
    let inconsistent = state.admitPrediction(
      message: query,
      evidence: evidence(abuseHeavyTLD: false),
      verdict: .init(label: .junk, confidence: 100, reason: "model"),
      hasContradiction: false
    )
    #expect(!inconsistent)
  }

  @Test
  func `infers learned weights from the pipeline's enriched evidence`() async throws {
    let fixture = try await enrichedInferenceFixture()
    let enrichedEvidence = try #require(fixture.record.evidence)
    #expect(enrichedEvidence.domainAgeDays != nil)
    let expected = try #require(
      fixture.learning.estimate(message: fixture.message, evidence: enrichedEvidence).logisticMargin
    )
    #expect(enrichedEvidence.learnedMargin == expected)
  }
}

/// Junk corrections from three senders at one shop domain.
private let repeatedShopJunk = (0..<3).map {
  correction("advertisement \($0)", sender: "sender\($0)@shop.example", date: Double($0))
}

/// Good corrections from friends at two shared mail-provider domains.
private let friendsAtSharedProviders = (0..<3).flatMap { index in
  ["gmail.com", "outlook.co.uk"].map {
    correction(
      "dinner \(index)",
      sender: "friend\(index)@\($0)",
      label: .inbox,
      date: Double(index)
    )
  }
}

private struct EnrichedInferenceFixture {
  let learning: LearningState
  let message: ParsedMessage
  let record: DecisionRecord
}

private func enrichedInferenceFixture() async throws -> EnrichedInferenceFixture {
  var learning = LearningState()
  for index in 0..<200 {
    let message = try learningMessage("A bounded training sample \(index)")
    let junk = index.isMultiple(of: 2)
    learning.recordCorrection(
      message: message,
      evidence: .init(message: message, domainAgeDays: junk ? 1 : 1000),
      label: junk ? .junk : .inbox
    )
  }
  let store = try testStore(), trained = learning
  try await StateRepository.update(store) {
    $0.learning = trained
    var options = $0.settings.advancedOptions; options.learnedWeights = true
    options.domainRegistrationLookup = true
    $0.settings.advancedOptions = options
  }
  let message = try learningMessage("A new sample", sender: "sender@example.com")
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(
      verdict:
        .init(label: .review, confidence: 50, reason: "Inspect evidence")
    ),
    rdap: RDAPLookup(fetcher: StubRDAP())
  )
  let record = await pipeline.process(
    message,
    identity: .init(accountID: "eval", contentHash: message.hash)
  )
  return EnrichedInferenceFixture(learning: trained, message: message, record: record)
}

private let campaignText =
  "Exclusive observatory telescope liquidation warehouse discount savings "
  + "premium optical lenses astronomy equipment limited inventory clearance purchase checkout "
  + "voucher celestial imaging accessories binoculars mount tripod promotion delivery today"

private func trainLearningState(_ state: inout LearningState) throws {
  for index in 0..<200 {
    let junk = index.isMultiple(of: 2)
    let text =
      junk
      ? "casino jackpot lottery prize lucky winner claim reward"
      : "observatory telescope meeting research colleague agenda discussion"
    let message = try learningMessage(text + " item\(index)", id: "\(index)")
    var evidence = EvidenceBundle(message: message)
    evidence.tldIsAbuseHeavy = junk
    state.recordCorrection(
      message: message,
      evidence: evidence,
      label: junk ? .junk : .inbox,
      date: Date(timeIntervalSince1970: Double(index))
    )
  }
}

private func correction(
  _ text: String,
  sender: String = "sender@shop.example",
  label: MailLabel = .junk,
  date: Double
) -> CorrectionExample {
  var example = CorrectionExample(
    sender: sender,
    domain: DomainResolver().domain(ofAddress: sender),
    subject: text,
    excerpt: text,
    label: label,
    promptScope: .everyAccount
  )
  example.date = Date(timeIntervalSince1970: date)
  return example
}

private let trustedAuthServer = "mx.example"

private func learningMessage(
  _ text: String,
  sender: String = "sender@shop.example",
  id: String = "sample",
  authenticated: Bool = false
) throws -> ParsedMessage {
  let subject = text.prefix(80).replacingOccurrences(of: "\n", with: " ")
  let authentication =
    authenticated ? "Authentication-Results: \(trustedAuthServer); dmarc=pass\r\n" : ""
  return try MIMEParser().parse(
    Data(
      "From: \(sender)\r\nSubject: \(subject)\r\nMessage-ID: <\(id)>\r\n\(authentication)\r\n\(text)"
        .utf8
    )
  )
}

private func authenticatedEvidence(_ message: ParsedMessage) -> EvidenceBundle {
  EvidenceBundle(message: message, trustedAuthServers: [trustedAuthServer])
}

private func legacySampleJSON(id: String) -> String {
  """
  {"samples": [{"id": "\(id)", "date": 0, "label": "junk", "provenance": "explicitCorrection", \
  "partition": "training", "tokens": ["casino"], "features": [1, 1, 0, 1, 0, 0, 0, 0.5]}]}
  """
}

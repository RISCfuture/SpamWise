import Classifier
import Foundation
import Learning
import MessageModel
import Signals
import Testing
import SpamWiseCore

@Suite
// swiftlint:disable:next type_name
struct `learns from bounded corrections` {
  @Test func `retrieves related older corrections before unrelated recent examples`() throws {
    let message = try learningMessage("Your observatory telescope shipment has arrived")
    let relevant = correction("observatory telescope shipment", date: 1)
    let irrelevant = correction(
      "casino lucky jackpot prize",
      sender: "prize@casino.example",
      date: 2
    )
    let results = CorrectionRetrieval.examples(for: message, from: [irrelevant, relevant], limit: 1)
    #expect(results.map(\.id) == [relevant.id])
    #expect(CorrectionRetrieval.examples(for: message, from: [relevant], limit: 0).isEmpty)
    #expect(
      CorrectionRetrieval.examples(for: message, from: [relevant, irrelevant], limit: 2)
        == CorrectionRetrieval.examples(for: message, from: [irrelevant, relevant], limit: 2)
    )
  }

  @Test func `distills only repeated noncontradictory domain corrections`() {
    let examples = (0..<3).map {
      correction("advertisement \($0)", sender: "sender\($0)@shop.example", date: Double($0))
    }
    let suggestions = PolicyDistiller.suggestions(from: examples)
    #expect(suggestions.count == 1)
    #expect(suggestions.first?.domain == "shop.example")
    #expect(suggestions.first?.label == .junk)
    let good = correction("receipt", sender: "orders@shop.example", label: .inbox, date: 5)
    #expect(PolicyDistiller.suggestions(from: examples + [good]).isEmpty)
    #expect(PolicyDistiller.suggestions(from: Array(repeating: examples[0], count: 8)).isEmpty)
  }

  @Test func `matches anchored campaigns and invalidates them after explicit good`() throws {
    let message = try learningMessage(campaignText)
    var state = LearningState()
    state.recordCorrection(message: message, evidence: .init(message: message), label: .junk)
    #expect(state.campaignMatch(for: message) != nil)
    let unrelatedSender = try learningMessage(campaignText, sender: "different@unrelated.example")
    #expect(state.campaignMatch(for: unrelatedSender) == nil)
    state.recordCorrection(message: message, evidence: .init(message: message), label: .inbox)
    #expect(state.campaignMatch(for: message) == nil)
    #expect(state.samples.count == 1)
    #expect(state.samples.first?.label == .inbox)
    let generic = try learningMessage(
      "Thank you\nUnsubscribe privacy policy manage preferences contact us"
    )
    state.recordCorrection(message: generic, evidence: .init(message: generic), label: .junk)
    #expect(state.campaignMatch(for: generic) == nil)
  }

  @Test func `retains bounded records and restores safe limits when decoding`() throws {
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
    #expect(state.samples.count == 3)
    #expect(state.samples.first?.date == Date(timeIntervalSince1970: 4))
    #expect(state.fingerprints.count <= 2)
    let restored = try JSONDecoder().decode(LearningState.self, from: JSONEncoder().encode(state))
    #expect(restored.samples == state.samples)
    let empty = try JSONDecoder().decode(LearningState.self, from: Data("{}".utf8))
    #expect(empty.samples.isEmpty)
  }

  @Test func `excludes heldout examples and refuses contradictory self training`() throws {
    var state = LearningState()
    let query = try learningMessage("casino jackpot lottery prize lucky winner claim reward")
    #expect(state.estimate(message: query, evidence: .init(message: query)).bayesLogOdds == nil)
    #expect(state.estimate(message: query, evidence: .init(message: query)).logisticMargin == nil)
    try trainLearningState(&state)
    let estimate = state.estimate(message: query, evidence: .init(message: query))
    #expect((estimate.bayesLogOdds ?? 0) > 0)
    #expect(estimate.logisticMargin != nil)
    #expect(estimate.trainingCount + estimate.heldOutCount == state.samples.count)
    #expect(estimate.heldOutCount > 0)
    let high = Verdict(label: .junk, confidence: 99, reason: "classifier")
    var junkEvidence = EvidenceBundle(message: query)
    junkEvidence.tldIsAbuseHeavy = true
    let contradictory = state.admitPrediction(
      message: query,
      evidence: .init(message: query),
      verdict: high,
      hasContradiction: true
    )
    let lowConfidence = state.admitPrediction(
      message: query,
      evidence: .init(message: query),
      verdict: .init(label: .junk, confidence: 98, reason: "classifier"),
      hasContradiction: false
    )
    let admitted = state.admitPrediction(
      message: query,
      evidence: junkEvidence,
      verdict: high,
      hasContradiction: false
    )
    let duplicate = state.admitPrediction(
      message: query,
      evidence: .init(message: query),
      verdict: high,
      hasContradiction: false
    )
    #expect(!contradictory)
    #expect(!lowConfidence)
    #expect(admitted)
    #expect(!duplicate)
    state.recordCorrection(message: query, evidence: .init(message: query), label: .inbox)
    let overridingGood = state.admitPrediction(
      message: query,
      evidence: .init(message: query),
      verdict: high,
      hasContradiction: false
    )
    #expect(!overridingGood)
    #expect(
      state.samples.filter { $0.id == LearningSample.identity(for: query) }.map(\.label) == [.inbox]
    )
    let heldOut = try #require(state.samples.first { $0.partition == .heldOut })
    #expect(!state.trainingSamples.contains { $0.id == heldOut.id })
  }

  @Test func `learns directional regularized weights without heldout leakage`() async throws {
    var state = LearningState(), changedHoldout = LearningState()
    try trainLearningState(&state)
    try trainLearningState(&changedHoldout, reverseHeldOutLabels: true)
    let query = try learningMessage("casino jackpot lottery prize lucky winner claim reward")
    var evidence = EvidenceBundle(message: query)
    evidence.tldIsAbuseHeavy = true
    let junk = state.estimate(message: query, evidence: evidence)
    #expect((junk.logisticMargin ?? 0) > 0)
    #expect(junk == changedHoldout.estimate(message: query, evidence: evidence))
    evidence.tldIsAbuseHeavy = false
    #expect((state.estimate(message: query, evidence: evidence).logisticMargin ?? 0) < 0)
    let inconsistent = state.admitPrediction(
      message: query,
      evidence: evidence,
      verdict: .init(label: .junk, confidence: 100, reason: "model"),
      hasContradiction: false
    )
    #expect(!inconsistent)
    let fixture = try await enrichedInferenceFixture()
    let enrichedEvidence = try #require(fixture.record.evidence)
    #expect(enrichedEvidence.domainAgeDays != nil)
    let expected = try #require(
      fixture.learning.estimate(message: fixture.message, evidence: enrichedEvidence).logisticMargin
    )
    #expect(enrichedEvidence.learnedMargin == expected)
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

private func trainLearningState(_ state: inout LearningState, reverseHeldOutLabels: Bool = false)
  throws
{
  for index in 0..<200 {
    let junk = index.isMultiple(of: 2)
    let text =
      junk
      ? "casino jackpot lottery prize lucky winner claim reward"
      : "observatory telescope meeting research colleague agenda discussion"
    let message = try learningMessage(text + " item\(index)", id: "\(index)")
    var evidence = EvidenceBundle(message: message)
    evidence.tldIsAbuseHeavy = junk
    var label: MailLabel = junk ? .junk : .inbox
    if reverseHeldOutLabels {
      var partitionProbe = LearningState()
      partitionProbe.recordCorrection(message: message, evidence: evidence, label: label)
      if partitionProbe.samples.first?.partition == .heldOut { label = junk ? .inbox : .junk }
    }
    state.recordCorrection(
      message: message,
      evidence: evidence,
      label: label,
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
    domain: "shop.example",
    subject: text,
    gist: text,
    label: label
  )
  example.date = Date(timeIntervalSince1970: date)
  return example
}

private func learningMessage(
  _ text: String,
  sender: String = "sender@shop.example",
  id: String = "sample"
) throws -> ParsedMessage {
  let subject = text.prefix(80).replacingOccurrences(of: "\n", with: " ")
  return try MIMEParser().parse(
    Data("From: \(sender)\r\nSubject: \(subject)\r\nMessage-ID: <\(id)>\r\n\r\n\(text)".utf8)
  )
}

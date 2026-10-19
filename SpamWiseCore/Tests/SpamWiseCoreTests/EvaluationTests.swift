import Foundation
import Testing
import SpamWiseCore
@testable import Evaluation

@Test
func `separates graymail and failures from binary calibration`() throws {
  let observations = [
    EvaluationObservation(
      file: "good/a",
      truth: .good,
      label: .junk,
      confidence: 96,
      path: .model,
      reason: "wrong"
    ),
    EvaluationObservation(
      file: "good/b",
      truth: .good,
      label: nil,
      confidence: nil,
      path: .error,
      reason: "timeout"
    ),
    EvaluationObservation(
      file: "junk/a",
      truth: .junk,
      label: .junk,
      confidence: 99,
      path: .model,
      reason: "lure"
    ),
    EvaluationObservation(
      file: "graymail/a",
      truth: .graymail,
      label: .junk,
      confidence: 99,
      path: .model,
      reason: "bulk"
    )
  ]
  let report = EvaluationReport(observations: observations)
  #expect(report.binary.good == 2)
  #expect(report.binary.falsePositives == 1)
  #expect(report.binary.junkPrecision == 0.5)
  #expect(report.unclassified == 1)
  #expect(report.misclassifications.count == 3)
  #expect(report.perPath[.model]?.falsePositives == 1)
  let calibration = ThresholdCalibration(observations: observations)
  #expect(calibration.curve.first?.modelJunkVerdicts == 2)
  let strict = try #require(calibration.curve.first { $0.threshold == 97 })
  #expect(strict.modelJunkVerdicts == 1 && strict.cumulativePrecision == 1)
  #expect(strict.metrics.falsePositives == 0 && strict.metrics.truePositives == 1)
  #expect(try #require(BinomialBound.upper95(errors: 0, trials: 1500)) <= 0.002)
  #expect(try #require(BinomialBound.upper95(errors: 1, trials: 2)) > 0.97)
  #expect(BinomialBound.upper95(errors: 0, trials: 0) == nil)
}

@Test
func `caches model responses while recomputing threshold decisions`() async throws {
  let message = try MIMEParser().parse(fixture("filler-spam"))
  let input = ClassificationInput(message: message, evidence: .init(message: message))
  let calls = Counter()
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let cached = try CachedClassifier(
    directory: directory,
    model: "test-v1",
    underlying: MockClassifier(operation: { _ in
      calls.increment()
      return Verdict(
        label: .junk,
        confidence: 96,
        reason: "lure",
        usage: .init(input: 100, output: 10, estimated: false)
      )
    })
  )
  let first = try await cached.classify(input)
  let second = try await cached.classify(input)
  #expect(calls.value == 1)
  #expect(try Decision.evaluate(first, strength: .conservative).label == .review)
  #expect(try Decision.evaluate(second, strength: .balanced).label == .junk)
  #expect(await cached.hits == 1)
  var changed = input
  changed.policy = "A different policy"
  _ = try await cached.classify(changed)
  #expect(calls.value == 2)
  let other = try CachedClassifier(
    directory: directory,
    model: "test-v2",
    underlying: MockClassifier(operation: { _ in
      calls.increment()
      return first
    })
  )
  _ = try await other.classify(input)
  #expect(calls.value == 3)
}

@Test
func `partitions reviewed content and reports missing retained messages`() throws {
  let message = try MIMEParser().parse(fixture("personal"))
  let identity = MessageIdentity(
    accountID: "fixture",
    contentHash: String(repeating: "0", count: 64)
  )
  let label = ReviewedLabel(identity: identity, label: .review, message: message)
  let missing = ReviewedLabel(
    identity: .init(accountID: "fixture", contentHash: "missing"),
    label: .inbox
  )
  let corpus = try ReviewedCorpus(labels: [label, missing], partition: .all)
  #expect(corpus.summary.totalLabels == 2)
  #expect(corpus.summary.missingContent == 1)
  #expect(corpus.entries.count == 1)
  #expect(corpus.entries.first?.truth == .graymail)
  #expect(corpus.entries.first?.message == message)
  let partition = LearningSample.partition(for: LearningSample.identity(for: message))
  let heldOut = try ReviewedCorpus(labels: [label, missing])
  #expect(heldOut.entries.count == (partition == .heldOut ? 1 : 0))
  #expect(heldOut.summary.excludedPartition == (partition == .training ? 1 : 0))
  var cleared = label
  cleared.message = nil
  #expect(cleared.heldOut == label.heldOut)
  #expect(label.heldOut == (partition == .heldOut))
  var legacy = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(label)) as? [String: Any]
  )
  legacy.removeValue(forKey: "sampleID")
  var migrated = try JSONDecoder().decode(
    ReviewedLabel.self,
    from: JSONSerialization.data(withJSONObject: legacy)
  )
  migrated.message = nil
  #expect(migrated.sampleID == LearningSample.identity(for: message))
  #expect(migrated.heldOut == label.heldOut)
}

@Test
func `collapses redelivered reviewed content and rejects conflicting labels`() throws {
  let original = try MIMEParser().parse(fixture("personal"))
  var redelivered = original
  redelivered.headers["received"] = ["another delivery route"]
  redelivered.hash = "another-raw-hash"
  let labels = [original, redelivered].map {
    ReviewedLabel(
      identity: .init(accountID: "fixture", contentHash: $0.hash),
      label: .inbox,
      message: $0
    )
  }
  #expect(try ReviewedCorpus(labels: labels, partition: .all).entries.count == 1)
  var conflicting = labels
  conflicting[1].label = .junk
  #expect(
    throws: ReviewedCorpusError.conflictingLabels([LearningSample.identity(for: original)])
  ) {
    try ReviewedCorpus(labels: conflicting, partition: .all)
  }
}

@Test
func `compares identical frozen cohorts and rejects leakage or missing results`() throws {
  let url = try #require(
    Bundle.module.url(forResource: "comparison", withExtension: "json", subdirectory: "Fixtures")
  )
  let data = try Data(contentsOf: url)
  let report = try ComparisonReport(data: data)
  #expect(report.systems[0].metrics.binary.falsePositives == 0)
  #expect(report.systems[1].metrics.binary.falsePositives == 1)
  #expect(report.systems[1].metrics.binary.falseNegatives == 1)
  #expect(report.systems[0].latencyP50Sec == 2)
  #expect(report.systems[0].latencyP95Sec == 3)
  #expect(report.systems[1].latencyP50Sec == nil)
  #expect(report.systems[0].reviewMinPerThousand == 12.0 / 60 * 1000 / 3)
  #expect(report.systems[1].reviewMinPerThousand == nil)
  #expect(report.systems[0].messagesPerSec == 0.5)
  #expect(!report.eligibleForBoundedComparison)
  #expect(report.sourceCounts["spamsieve"] == 1)
  let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  var leaked = original
  leaked["trainingCampaigns"] = ["fraud"]
  #expect(throws: ComparisonManifestError.trainingCampaign("fraud")) {
    try ComparisonReport(data: JSONSerialization.data(withJSONObject: leaked))
  }
  var missing = original
  var runs = try #require(missing["runs"] as? [[String: Any]])
  var results = try #require(runs[0]["results"] as? [[String: Any]])
  results.removeLast(); runs[0]["results"] = results; missing["runs"] = runs
  #expect(
    throws: ComparisonManifestError.missingResult(system: "Synthetic A", messageID: "newsletter")
  ) {
    try ComparisonReport(data: JSONSerialization.data(withJSONObject: missing))
  }
}

@Test
func `invalidates threat cache across account evidence policy and enriched text`()
  async throws
{
  let message = try MIMEParser().parse(fixture("personal")), calls = Counter()
  var preferenceEvidence = EvidenceBundle(message: message)
  preferenceEvidence.bayesLogOdds = 7
  preferenceEvidence.learnedMargin = 5
  let independent = ThreatInput(
    message: message,
    accountID: "account-A",
    evidence: preferenceEvidence
  )
  #expect(independent.evidence.bayesLogOdds == nil)
  #expect(independent.evidence.learnedMargin == nil)
  var input = ThreatInput(
    message: message,
    accountID: "account-A",
    evidence: .init(message: message)
  )
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let operation: @Sendable (ThreatInput) async throws -> [ThreatFinding] = { _ in
    calls.increment()
    return [
      .init(kind: .spam, status: .notDetected, reason: "Synthetic negative", coverage: "Text")
    ]
  }
  let cached = try CachedThreatDetector(
    directory: directory,
    underlying: FixtureThreatDetector(operation: operation)
  )
  _ = try await cached.assess(input)
  let reused = try await cached.assess(input)
  #expect(calls.value == 1)
  #expect(reused.first { $0.kind == .phishing }?.status == .unknown)
  input.accountID = "account-B"
  _ = try await cached.assess(input)
  input.evidence.contact = true
  _ = try await cached.assess(input)
  input.message.text += "\nUntrusted OCR addition"
  _ = try await cached.assess(input)
  let changed = try CachedThreatDetector(
    directory: directory,
    underlying: FixtureThreatDetector(policy: "fixture-policy-v2", operation: operation)
  )
  _ = try await changed.assess(input)
  #expect(calls.value == 5)
  #expect(await cached.hits == 1)
}

@Test
func `keeps threat truth and unknown coverage separate across objectives and languages`()
  throws
{
  let message = try MIMEParser().parse(fixture("personal"))
  let input = ThreatInput(message: message, accountID: nil, evidence: .init(message: message))
  let assessment = try ThreatAssessment(
    input: input,
    detector: FixtureThreatDetector { _ in [] }.identity,
    findings: [
      .init(
        kind: .spam,
        status: .detected,
        score: 0.7,
        reason: "Synthetic result",
        coverage: "English text only"
      )
    ]
  )
  let rows = [
    ThreatEvaluationObservation(
      sampleID: "a",
      language: "en",
      truth: [.spam: false],
      assessment: assessment
    ),
    ThreatEvaluationObservation(
      sampleID: "b",
      language: "es",
      truth: [.spam: false],
      assessment: nil
    ),
    ThreatEvaluationObservation(
      sampleID: "c",
      language: "fr",
      truth: [.phishing: true],
      assessment: nil
    )
  ]
  let report = try ThreatEvaluationReport(observations: rows)
  #expect(report.objectives[.spam]?.falsePositives == 1)
  #expect(report.objectives[.spam]?.assessedNegatives == 1)
  #expect(report.objectives[.spam]?.unassessed == 1)
  #expect(report.objectives[.phishing]?.negatives == 0)
  #expect(report.objectives[.phishing]?.unlabeled == 2)
  #expect(report.objectives[.phishing]?.recall == 0)
  #expect(report.objectives[.phishing]?.falsePositiveUpper95 == nil)
  #expect(report.languages["es"]?[.spam]?.assessedNegatives == 0)
  #expect(throws: ThreatReportError.duplicateSample("a")) {
    try ThreatEvaluationReport(observations: rows + [rows[0]])
  }
}

@Test
func `refuses evaluation spending without an explicit ledger and ceiling and stops at it`()
  async throws
{
  let url = FileManager.default.temporaryDirectory.appending(
    path: "SpamWise-tests/\(UUID())/budget.store"
  )
  await #expect(throws: BudgetError.missingStore) {
    _ = try await EvaluationBudget.ledgerStore(at: nil, limitUSD: 0.5)
  }
  await #expect(throws: BudgetError.unconfigured) {
    _ = try await EvaluationBudget.ledgerStore(at: url, limitUSD: nil)
  }
  let store = try Store(url: url)
  await #expect(throws: BudgetError.unconfigured) {
    try await EvaluationBudget.reserve(upperBoundUSD: 0.25, store: store)
  }
  #expect(try await EvaluationBudget.load(store) == nil)
  _ = try await EvaluationBudget.ledgerStore(at: url, limitUSD: 0.5)
  for _ in 0..<2 { try await EvaluationBudget.reserve(upperBoundUSD: 0.25, store: store) }
  await #expect(throws: BudgetError.self) {
    try await EvaluationBudget.reserve(upperBoundUSD: 0.25, store: store)
  }
  let ledger = try #require(try await EvaluationBudget.load(store))
  #expect(ledger.committedUSD == 0.5 && ledger.calls == 2)
  let message = try MIMEParser().parse(fixture("filler-spam"))
  let calls = Counter()
  let cached = try CachedClassifier(
    directory: url.deletingLastPathComponent().appending(path: "cache"),
    model: "budgeted",
    underlying: BudgetedClassifier(
      MockClassifier { _ in
        calls.increment()
        return Verdict(label: .junk, confidence: 99, reason: "lure")
      },
      store: store,
      upperBoundUSD: 0.25
    )
  )
  await #expect(throws: BudgetError.exhausted) {
    _ = try await cached.classify(.init(message: message, evidence: .init(message: message)))
  }
  #expect(calls.value == 0)
  #expect(await cached.providerCalls == 0)
  #expect(await cached.refusal is BudgetError)
}

@Test
func `selects the lowest threshold meeting each target on training data and validates it`() {
  let training =
    rows(3000, truth: .good, label: .inbox, partition: .training)
    + rows(2, truth: .good, label: .junk, confidence: 92, partition: .training)
    + rows(10, truth: .junk, label: .junk, confidence: 95, partition: .training)
  let heldOut =
    rows(3000, truth: .good, label: .inbox, partition: .heldOut)
    + rows(1, truth: .good, label: .junk, confidence: 96, partition: .heldOut)
  let calibration = ThresholdCalibration(observations: training + heldOut)
  let selected = Dictionary(
    uniqueKeysWithValues: calibration.strengths.map { ($0.strength, $0) }
  )
  #expect(selected[.aggressive]?.selectedThreshold == 85)
  #expect(selected[.balanced]?.selectedThreshold == 93)
  #expect(selected[.conservative]?.selectedThreshold == 93)
  #expect(selected[.balanced]?.validated == true)
  #expect(selected[.conservative]?.validated == false)
  #expect(selected[.balanced]?.current.falsePositives == 1)
  #expect(calibration.curve.first { $0.threshold == 93 }?.cumulativePrecision == 10.0 / 11)
}

@Test
func `seeds receipt history for the order-confirmation fixture sender`() throws {
  let url = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "../../../eval/fixture-state.json").standardized
  let state = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
  let message = try MIMEParser().parse(
    Data(
      contentsOf: url.deletingLastPathComponent().appending(
        path: "fixtures/good/order-confirmation.eml"
      )
    )
  )
  let history = try #require(state.histories["eval"]).summary(
    address: message.fromAddress,
    domain: DomainResolver().domain(ofAddress: message.fromAddress)
  )
  #expect(history.receiptCount > 0)
  #expect((history.authenticatedReceiptCount ?? 0) > 0)
}

private func rows(
  _ count: Int,
  truth: EvaluationTruth,
  label: MailLabel,
  confidence: Int = 90,
  partition: LearningPartition
) -> [EvaluationObservation] {
  (0..<count).map {
    EvaluationObservation(
      file: "\(truth.rawValue)/\(partition.rawValue)/\($0)",
      truth: truth,
      label: label,
      confidence: confidence,
      path: .model,
      reason: "synthetic",
      partition: partition
    )
  }
}

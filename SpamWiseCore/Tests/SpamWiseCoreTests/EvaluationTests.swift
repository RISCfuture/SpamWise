import Foundation
import Testing
import SpamWiseCore
@testable import Evaluation

@Suite
struct `Evaluation report` {
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

  @Test
  func `separates graymail and failures from binary metrics`() {
    let report = EvaluationReport(observations: observations)
    #expect(report.binary.good == 2)
    #expect(report.binary.falsePositives == 1)
    #expect(report.binary.junkPrecision == 0.5)
    #expect(report.unclassified == 1)
    #expect(report.misclassifications.count == 3)
    #expect(report.perPath[.model]?.falsePositives == 1)
  }

  @Test
  func `calibrates thresholds on binary model verdicts only`() throws {
    let calibration = ThresholdCalibration(observations: observations)
    #expect(calibration.curve.first?.modelJunkVerdicts == 2)
    let strict = try #require(calibration.curve.first { $0.threshold == 97 })
    #expect(strict.modelJunkVerdicts == 1 && strict.cumulativePrecision == 1)
    #expect(strict.metrics.falsePositives == 0 && strict.metrics.truePositives == 1)
  }

  @Test
  func `computes one-sided 95 percent binomial upper bounds`() throws {
    #expect(try #require(BinomialBound.upper95(errors: 0, trials: 1500)) <= 0.002)
    #expect(try #require(BinomialBound.upper95(errors: 1, trials: 2)) > 0.97)
    #expect(BinomialBound.upper95(errors: 0, trials: 0) == nil)
  }
}

/// A cached classifier's inputs, which change the cache key one at a time.
enum ClassificationChange: CaseIterable, Sendable {
  case policy, model
}

@Suite
final class `Cached classification` {
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  let calls = Counter()
  let input: ClassificationInput

  init() throws {
    let message = try MIMEParser().parse(fixture("filler-spam"))
    input = ClassificationInput(message: message, evidence: .init(message: message))
  }

  private func classifier(model: String = "test-v1") throws -> CachedClassifier {
    try CachedClassifier(
      directory: directory,
      model: model,
      underlying: MockClassifier(operation: { [calls] _ in
        calls.increment()
        return Verdict(
          label: .junk,
          confidence: 96,
          reason: "lure",
          usage: .init(input: 100, output: 10, estimated: false)
        )
      })
    )
  }

  @Test
  func `reuses a cached response while recomputing threshold decisions`() async throws {
    let cached = try classifier()
    let first = try await cached.classify(input)
    let second = try await cached.classify(input)
    #expect(calls.value == 1)
    #expect(await cached.hits == 1)
    #expect(try Decision.evaluate(first, strength: .conservative).label == .review)
    #expect(try Decision.evaluate(second, strength: .balanced).label == .junk)
  }

  @Test(arguments: ClassificationChange.allCases)
  func `calls the provider again when an input changes`(_ change: ClassificationChange)
    async throws
  {
    _ = try await classifier().classify(input)
    switch change {
      case .policy:
        var changed = input
        changed.policy = "A different policy"
        _ = try await classifier().classify(changed)
      case .model:
        _ = try await classifier(model: "test-v2").classify(input)
    }
    #expect(calls.value == 2)
  }

  deinit { try? FileManager.default.removeItem(at: directory) }
}

@Suite
struct `Reviewed corpus` {
  let message: ParsedMessage
  let label: ReviewedLabel
  let missing = ReviewedLabel(
    identity: .init(accountID: "fixture", contentHash: "missing"),
    label: .inbox
  )
  let partition: LearningPartition

  init() throws {
    message = try MIMEParser().parse(fixture("personal"))
    label = ReviewedLabel(
      identity: MessageIdentity(
        accountID: "fixture",
        contentHash: String(repeating: "0", count: 64)
      ),
      label: .review,
      message: message
    )
    partition = LearningSample.partition(for: LearningSample.identity(for: message))
  }

  @Test
  func `reports labels whose retained message is missing`() throws {
    let corpus = try ReviewedCorpus(labels: [label, missing], partition: .all)
    #expect(corpus.summary.totalLabels == 2)
    #expect(corpus.summary.missingContent == 1)
    #expect(corpus.entries.count == 1)
    #expect(corpus.entries.first?.truth == .graymail)
    #expect(corpus.entries.first?.message == message)
  }

  @Test
  func `keeps only held-out content by default`() throws {
    let heldOut = try ReviewedCorpus(labels: [label, missing])
    #expect(heldOut.entries.count == (partition == .heldOut ? 1 : 0))
    #expect(heldOut.summary.excludedPartition == (partition == .training ? 1 : 0))
  }

  @Test
  func `keeps a label's partition after its message is cleared`() {
    var cleared = label
    cleared.message = nil
    #expect(cleared.heldOut == label.heldOut)
    #expect(label.heldOut == (partition == .heldOut))
  }

  @Test
  func `migrates a legacy label without a sample identity`() throws {
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
}

@Suite
struct `Redelivered reviewed content` {
  let original: ParsedMessage
  let labels: [ReviewedLabel]

  init() throws {
    original = try MIMEParser().parse(fixture("personal"))
    var redelivered = original
    redelivered.headers["received"] = ["another delivery route"]
    redelivered.hash = "another-raw-hash"
    labels = [original, redelivered].map {
      ReviewedLabel(
        identity: .init(accountID: "fixture", contentHash: $0.hash),
        label: .inbox,
        message: $0
      )
    }
  }

  @Test
  func `collapses redelivered copies of one message`() throws {
    #expect(try ReviewedCorpus(labels: labels, partition: .all).entries.count == 1)
  }

  @Test
  func `rejects redelivered copies with conflicting labels`() {
    var conflicting = labels
    conflicting[1].label = .junk
    #expect(
      throws: ReviewedCorpusError.conflictingLabels([LearningSample.identity(for: original)])
    ) {
      try ReviewedCorpus(labels: conflicting, partition: .all)
    }
  }
}

@Suite
struct `Frozen cohort comparison` {
  let data: Data
  let manifest: [String: Any]

  init() throws {
    let url = try #require(
      Bundle.module.url(forResource: "comparison", withExtension: "json", subdirectory: "Fixtures")
    )
    data = try Data(contentsOf: url)
    manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test
  func `compares systems on an identical frozen cohort`() throws {
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
  }

  @Test
  func `rejects a cohort that leaks a training campaign`() {
    var leaked = manifest
    leaked["trainingCampaigns"] = ["fraud"]
    #expect(throws: ComparisonManifestError.trainingCampaign("fraud")) {
      try ComparisonReport(data: JSONSerialization.data(withJSONObject: leaked))
    }
  }

  @Test
  func `rejects a run with a missing result`() throws {
    var missing = manifest
    var runs = try #require(missing["runs"] as? [[String: Any]])
    var results = try #require(runs[0]["results"] as? [[String: Any]])
    results.removeLast(); runs[0]["results"] = results; missing["runs"] = runs
    #expect(
      throws: ComparisonManifestError.missingResult(system: "Synthetic A", messageID: "newsletter")
    ) {
      try ComparisonReport(data: JSONSerialization.data(withJSONObject: missing))
    }
  }
}

/// A threat-detection input that changes the cache key.
enum ThreatInputChange: CaseIterable, Sendable {
  case account, evidence, enrichedText, detectorPolicy
}

@Suite
final class `Cached threat detection` {
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  let calls = Counter()
  let message: ParsedMessage
  let input: ThreatInput

  init() throws {
    message = try MIMEParser().parse(fixture("personal"))
    input = ThreatInput(message: message, accountID: "account-A", evidence: .init(message: message))
  }

  private func detector(policy: String? = nil) throws -> CachedThreatDetector {
    let operation: @Sendable (ThreatInput) async throws -> [ThreatFinding] = { [calls] _ in
      calls.increment()
      return [
        .init(kind: .spam, status: .notDetected, reason: "Synthetic negative", coverage: "Text")
      ]
    }
    let underlying =
      policy.map { FixtureThreatDetector(policy: $0, operation: operation) }
      ?? FixtureThreatDetector(operation: operation)
    return try CachedThreatDetector(directory: directory, underlying: underlying)
  }

  @Test
  func `drops preference-derived scores from threat input`() {
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
  }

  @Test
  func `reuses a cached assessment and reports unchecked kinds as unknown`() async throws {
    let cached = try detector()
    _ = try await cached.assess(input)
    let reused = try await cached.assess(input)
    #expect(calls.value == 1)
    #expect(await cached.hits == 1)
    #expect(reused.first { $0.kind == .phishing }?.status == .unknown)
  }

  @Test(arguments: ThreatInputChange.allCases)
  func `assesses again when an input changes`(_ change: ThreatInputChange) async throws {
    _ = try await detector().assess(input)
    var changed = input
    switch change {
      case .account: changed.accountID = "account-B"
      case .evidence: changed.evidence.contact = true
      case .enrichedText: changed.message.text += "\nUntrusted OCR addition"
      case .detectorPolicy: break
    }
    let policy = change == .detectorPolicy ? "fixture-policy-v2" : nil
    _ = try await detector(policy: policy).assess(changed)
    #expect(calls.value == 2)
  }

  deinit { try? FileManager.default.removeItem(at: directory) }
}

@Suite
struct `Threat evaluation report` {
  let rows: [ThreatEvaluationObservation]

  init() throws {
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
    rows = [
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
  }

  @Test
  func `counts false positives separately from unassessed negatives`() throws {
    let spam = try #require(try ThreatEvaluationReport(observations: rows).objectives[.spam])
    #expect(spam.falsePositives == 1)
    #expect(spam.assessedNegatives == 1)
    #expect(spam.unassessed == 1)
  }

  @Test
  func `reports no bound for an objective without assessed negatives`() throws {
    let phishing = try #require(
      try ThreatEvaluationReport(observations: rows).objectives[.phishing]
    )
    #expect(phishing.negatives == 0)
    #expect(phishing.unlabeled == 2)
    #expect(phishing.recall == 0)
    #expect(phishing.falsePositiveUpper95 == nil)
  }

  @Test
  func `breaks objectives down by language`() throws {
    let report = try ThreatEvaluationReport(observations: rows)
    #expect(report.languages["es"]?[.spam]?.assessedNegatives == 0)
  }

  @Test
  func `rejects a duplicate sample`() {
    #expect(throws: ThreatReportError.duplicateSample("a")) {
      try ThreatEvaluationReport(observations: rows + [rows[0]])
    }
  }
}

@Suite
struct `Evaluation budget` {
  private static let limitUSD = 0.5
  private static let callUSD = 0.25
  let url = FileManager.default.temporaryDirectory.appending(
    path: "SpamWise-tests/\(UUID())/budget.store"
  )

  /// A store whose ledger allows exactly two calls, both already reserved.
  private func exhaustedStore() async throws -> Store {
    let store = try Store(url: url)
    _ = try await EvaluationBudget.ledgerStore(at: url, limitUSD: Self.limitUSD)
    for _ in 0..<2 { try await EvaluationBudget.reserve(upperBoundUSD: Self.callUSD, store: store) }
    return store
  }

  @Test
  func `refuses a ledger without a store`() async {
    await #expect(throws: BudgetError.missingStore) {
      _ = try await EvaluationBudget.ledgerStore(at: nil, limitUSD: Self.limitUSD)
    }
  }

  @Test
  func `refuses a ledger without a ceiling`() async {
    await #expect(throws: BudgetError.unconfigured) {
      _ = try await EvaluationBudget.ledgerStore(at: url, limitUSD: nil)
    }
  }

  @Test
  func `refuses reservations before a ledger is configured`() async throws {
    let store = try Store(url: url)
    await #expect(throws: BudgetError.unconfigured) {
      try await EvaluationBudget.reserve(upperBoundUSD: Self.callUSD, store: store)
    }
    #expect(try await EvaluationBudget.load(store) == nil)
  }

  @Test
  func `stops reserving at the ceiling`() async throws {
    let store = try await exhaustedStore()
    await #expect(throws: BudgetError.self) {
      try await EvaluationBudget.reserve(upperBoundUSD: Self.callUSD, store: store)
    }
    let ledger = try #require(try await EvaluationBudget.load(store))
    #expect(ledger.committedUSD == Self.limitUSD && ledger.calls == 2)
  }

  @Test
  func `refuses an exhausted budgeted call without contacting the provider`() async throws {
    let store = try await exhaustedStore()
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
        upperBoundUSD: Self.callUSD
      )
    )
    await #expect(throws: BudgetError.exhausted) {
      _ = try await cached.classify(.init(message: message, evidence: .init(message: message)))
    }
    #expect(calls.value == 0)
    #expect(await cached.providerCalls == 0)
    #expect(await cached.refusal is BudgetError)
  }
}

@Suite
struct `Threshold selection` {
  let calibration: ThresholdCalibration

  init() {
    let training =
      rows(3000, truth: .good, label: .inbox, partition: .training)
      + rows(2, truth: .good, label: .junk, confidence: 92, partition: .training)
      + rows(10, truth: .junk, label: .junk, confidence: 95, partition: .training)
    let heldOut =
      rows(3000, truth: .good, label: .inbox, partition: .heldOut)
      + rows(1, truth: .good, label: .junk, confidence: 96, partition: .heldOut)
    calibration = ThresholdCalibration(observations: training + heldOut)
  }

  private func selection(_ strength: FilteringStrength) throws -> StrengthCalibration {
    try #require(calibration.strengths.first { $0.strength == strength })
  }

  @Test(arguments: [
    (FilteringStrength.aggressive, 85), (.balanced, 93), (.conservative, 93)
  ])
  func `selects the lowest training threshold meeting each target`(
    strength: FilteringStrength,
    threshold: Int
  ) throws {
    #expect(try selection(strength).selectedThreshold == threshold)
  }

  @Test(arguments: [(FilteringStrength.balanced, true), (.conservative, false)])
  func `validates each selected threshold on held-out data`(
    strength: FilteringStrength,
    validated: Bool
  ) throws {
    #expect(try selection(strength).validated == validated)
  }

  @Test
  func `reports held-out false positives at the current threshold`() throws {
    #expect(try selection(.balanced).current.falsePositives == 1)
    #expect(calibration.curve.first { $0.threshold == 93 }?.cumulativePrecision == 10.0 / 11)
  }
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

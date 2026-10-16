import Foundation
import Testing
import SpamWiseCore
@testable import Evaluation

@Test func `separates graymail and failures from binary calibration`() throws {
  let observations = [
    EvaluationObservation(
      file: "good/a",
      truth: .good,
      label: .junk,
      confidence: 96,
      path: "model",
      reason: "wrong"
    ),
    EvaluationObservation(
      file: "good/b",
      truth: .good,
      label: nil,
      confidence: nil,
      path: "error",
      reason: "timeout"
    ),
    EvaluationObservation(
      file: "junk/a",
      truth: .junk,
      label: .junk,
      confidence: 99,
      path: "model",
      reason: "lure"
    ),
    EvaluationObservation(
      file: "graymail/a",
      truth: .graymail,
      label: .junk,
      confidence: 99,
      path: "model",
      reason: "bulk"
    )
  ]
  let report = EvaluationReport(observations: observations)
  #expect(report.binary.good == 2)
  #expect(report.binary.falsePositives == 1)
  #expect(report.binary.junkPrecision == 0.5)
  #expect(report.unclassified == 1)
  #expect(report.calibration.reduce(0) { $0 + $1.count } == 2)
  #expect(report.misclassifications.count == 3)
  #expect(try #require(BinomialBound.upper95(errors: 0, trials: 1500)) <= 0.002)
  #expect(try #require(BinomialBound.upper95(errors: 1, trials: 2)) > 0.97)
  #expect(BinomialBound.upper95(errors: 0, trials: 0) == nil)
}

@Test func `caches model responses while recomputing threshold decisions`() async throws {
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

@Test func `partitions reviewed content and reports missing retained messages`() throws {
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

@Test func `rejects duplicate reviewed content despite changed delivery headers`() throws {
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
  #expect(throws: ReviewedCorpusError.duplicateContent) {
    try ReviewedCorpus(labels: labels, partition: .all)
  }
}

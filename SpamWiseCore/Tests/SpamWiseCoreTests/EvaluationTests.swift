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
  #expect(BinomialBound.upper95(errors: 0, trials: 1500)! <= 0.002)
  #expect(BinomialBound.upper95(errors: 1, trials: 2)! > 0.97)
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

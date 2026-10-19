import Classifier
import Foundation
import MessageModel
import Signals

enum StatisticalLearning {
  private static let regularization = 0.1
  private static let iterations = 120
  private static let learningRate = 0.5
  private static let minimumBayesSamplesPerClass = 20
  private static let reviewedSamplesPerPrediction = 4
  private static let predictionWeight = 0.1
  private static let minimumMatchingTokens = 3
  private static let maximumLogOdds = 12.0
  private static let maximumLogisticSamples = 2000
  private static let minimumLogisticSamples = 100
  private static let minimumLogisticSamplesPerClass = 30

  static func hasMinimumClasses(_ samples: [LearningSample], perClass: Int) -> Bool {
    samples.filter { $0.label == .junk }.count >= perClass
      && samples.filter { $0.label == .inbox }.count >= perClass
  }

  static func bayes(
    message: ParsedMessage,
    reviewed: [LearningSample],
    predictions: [LearningSample]
  ) -> Double? {
    guard hasMinimumClasses(reviewed, perClass: minimumBayesSamplesPerClass) else { return nil }
    var junk: [String: Double] = [:], good: [String: Double] = [:]
    for sample in reviewed + predictions.prefix(reviewed.count / reviewedSamplesPerPrediction) {
      let weight = sample.provenance == .explicitCorrection ? 1.0 : predictionWeight
      for token in sample.tokens {
        if sample.label == .junk { junk[token, default: 0] += weight }
        if sample.label == .inbox { good[token, default: 0] += weight }
      }
    }
    let vocabulary = Set(junk.keys).union(good.keys)
    let tokens = Set(LearningSample.tokens(for: message)).intersection(vocabulary).sorted()
    guard tokens.count >= minimumMatchingTokens else { return nil }
    let junkTotal =
      junk.keys.sorted().reduce(0) { $0 + junk[$1, default: 0] } + Double(vocabulary.count)
    let goodTotal =
      good.keys.sorted().reduce(0) { $0 + good[$1, default: 0] } + Double(vocabulary.count)
    let logOdds = tokens.reduce(0.0) {
      $0 + log((junk[$1, default: 0] + 1) / junkTotal) - log((good[$1, default: 0] + 1) / goodTotal)
    }
    return max(-maximumLogOdds, min(maximumLogOdds, logOdds))
  }

  /**
   The logit of a model fitted to `reviewed`, evaluated for `evidence`.

   The features that depend on a receiving account are left out while any training sample lacks
   that context, so the model cannot learn where its samples came from.
   */
  static func logistic(evidence: EvidenceBundle, reviewed: [LearningSample]) -> Double? {
    let training = Array(reviewed.prefix(maximumLogisticSamples))
    guard training.count >= minimumLogisticSamples,
      hasMinimumClasses(training, perClass: minimumLogisticSamplesPerClass)
    else { return nil }
    let context = training.allSatisfy(\.features.hasAccountContext)
    let query = LearningFeatures(evidence).vector(accountContext: context)
    let vectors = training.map { $0.features.vector(accountContext: context) }
    var weights = Array(repeating: 0.0, count: query.count)
    for _ in 0..<iterations {
      var gradient = Array(repeating: 0.0, count: query.count)
      for (sample, vector) in zip(training, vectors) {
        let prediction = 1 / (1 + exp(-dot(weights, vector)))
        let error = prediction - (sample.label == .junk ? 1 : 0)
        for index in weights.indices { gradient[index] += error * vector[index] }
      }
      for index in weights.indices {
        let penalty = index == LearningFeatures.biasIndex ? 0 : regularization * weights[index]
        weights[index] -= learningRate * (gradient[index] / Double(training.count) + penalty)
      }
    }
    return dot(weights, query)
  }

  private static func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
  }
}

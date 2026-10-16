import Classifier
import Foundation
import MessageModel
import Signals

enum StatisticalLearning {
  static let featureCount = 8
  private static let regularization = 0.1
  private static let iterations = 120
  private static let learningRate = 0.5
  private static let youngDomainAgeDays = 30
  private static let saturatedLinkDomainCount = 10.0
  private static let minimumBayesSamplesPerClass = 20
  private static let reviewedSamplesPerPrediction = 4
  private static let predictionWeight = 0.1
  private static let minimumMatchingTokens = 3
  private static let maximumLogOdds = 12.0
  private static let maximumLogisticSamples = 2000
  private static let minimumLogisticSamples = 100
  private static let minimumLogisticSamplesPerClass = 30

  static func features(_ evidence: EvidenceBundle) -> [Double] {
    [
      1,
      evidence.tldIsAbuseHeavy ? 1 : 0,
      evidence.domainAgeDays.map { $0 >= 0 && $0 < youngDomainAgeDays ? 1 : 0 } ?? 0,
      evidence.domainAgeDays == nil ? 1 : 0,
      evidence.authResults.contains { $0.trusted && ["fail", "softfail"].contains($0.result) }
        ? 1 : 0,
      evidence.replyToDomain != nil && evidence.fromDomain != nil
        && evidence.replyToDomain != evidence.fromDomain ? 1 : 0,
      evidence.listUnsubscribePresent ? 1 : 0,
      min(1, Double(evidence.linkDomains.count) / saturatedLinkDomainCount)
    ]
  }

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
    let tokens = Set(LearningText.tokens(message.subject + " " + message.text)).intersection(
      vocabulary
    ).sorted()
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

  static func logistic(evidence: EvidenceBundle, reviewed: [LearningSample]) -> Double? {
    let training = Array(reviewed.prefix(maximumLogisticSamples))
    guard training.count >= minimumLogisticSamples,
      hasMinimumClasses(training, perClass: minimumLogisticSamplesPerClass)
    else { return nil }
    var weights = Array(repeating: 0.0, count: featureCount)
    for _ in 0..<iterations {
      var gradient = Array(repeating: 0.0, count: featureCount)
      for sample in training {
        let prediction = 1 / (1 + exp(-dot(weights, sample.features)))
        let error = prediction - (sample.label == .junk ? 1 : 0)
        for index in weights.indices { gradient[index] += error * sample.features[index] }
      }
      for index in weights.indices {
        let penalty = index == 0 ? 0 : regularization * weights[index]
        weights[index] -= learningRate * (gradient[index] / Double(training.count) + penalty)
      }
    }
    return dot(weights, features(evidence))
  }

  private static func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
  }
}

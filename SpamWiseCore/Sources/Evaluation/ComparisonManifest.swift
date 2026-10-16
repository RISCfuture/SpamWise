import Foundation
import SpamWiseCore

/// A frozen paired-comparison input, validated by named checks before any metric is computed.
struct ComparisonManifest: Decodable {
  /// Decodes ISO 8601 timestamps with or without fractional seconds.
  static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      guard let date = timestamp(try container.decode(String.self)) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Expected an ISO 8601 date and time."
        )
      }
      return date
    }
    return decoder
  }

  let schema: Int
  let holdoutID: String
  let frozenAt: Date
  let humanReviewed: Bool
  let trainingCampaigns: Set<String>
  let messages: [ComparisonMessage]
  let runs: [ComparisonRun]

  private static func timestamp(_ text: String) -> Date? {
    let whole = Date.ISO8601FormatStyle()
    let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    return (try? whole.parse(text)) ?? (try? fractional.parse(text))
  }

  func validate() throws {
    try requireSupportedHeader()
    try requireDisjointCohort()
    try requireDistinctFrozenRuns()
  }

  private func requireSupportedHeader() throws {
    guard schema == ComparisonReport.schema else {
      throw ComparisonManifestError.unsupportedSchema(schema)
    }
    guard humanReviewed else { throw ComparisonManifestError.notHumanReviewed }
    guard !holdoutID.isEmpty else { throw ComparisonManifestError.missingHoldoutID }
  }

  private func requireDisjointCohort() throws {
    guard ComparisonReport.messageCounts.contains(messages.count) else {
      throw ComparisonManifestError.messageCount(
        messages.count,
        allowed: ComparisonReport.messageCounts
      )
    }
    var ids: Set<String> = [], campaigns: Set<String> = []
    for message in messages {
      try message.requireIdentity()
      guard ids.insert(message.id).inserted else {
        throw ComparisonManifestError.duplicateMessage(message.id)
      }
      guard campaigns.insert(message.campaign).inserted else {
        throw ComparisonManifestError.duplicateCampaign(message.campaign)
      }
      guard !trainingCampaigns.contains(message.campaign) else {
        throw ComparisonManifestError.trainingCampaign(message.campaign)
      }
    }
  }

  private func requireDistinctFrozenRuns() throws {
    guard ComparisonReport.runCounts.contains(runs.count) else {
      throw ComparisonManifestError.runCount(runs.count, allowed: ComparisonReport.runCounts)
    }
    var systems: Set<String> = []
    for run in runs {
      try run.requireFrozenIdentity()
      guard systems.insert(run.system).inserted else {
        throw ComparisonManifestError.duplicateSystem(run.system)
      }
    }
  }
}

/// One human-labeled holdout message.
struct ComparisonMessage: Decodable {
  let id: String
  let campaign: String
  let truth: EvaluationTruth
  let source: Source

  func requireIdentity() throws {
    guard !id.isEmpty else { throw ComparisonManifestError.blankMessageID }
    guard !campaign.isEmpty else { throw ComparisonManifestError.blankCampaign(messageID: id) }
  }

  /// The folder or filter that proposed the message, independent of its truth label.
  enum Source: String, Decodable { case spamsieve, server, unknown, other }
}

/// One system's frozen results and measurements over the whole cohort.
struct ComparisonRun: Decodable {
  let system: String
  let configurationID: String
  let learningFrozen: Bool
  let priorExposure: PriorExposure
  let elapsedSec: Double
  let cpuSec: Double?
  let peakMemoryBytes: UInt64?
  let costUSD: Double?
  let costBasis: CostBasis?
  let results: [Result]

  private static func isValidMeasurement(_ value: Double) -> Bool { value.isFinite && value >= 0 }

  func requireFrozenIdentity() throws {
    guard !system.isEmpty else { throw ComparisonManifestError.blankSystem }
    guard !configurationID.isEmpty else {
      throw ComparisonManifestError.blankConfigurationID(system: system)
    }
    guard learningFrozen else { throw ComparisonManifestError.learningNotFrozen(system: system) }
  }

  func validate(against messages: [ComparisonMessage]) throws {
    try requireOneResultPerMessage(messages)
    try requireValidMeasurements()
    guard costUSD == nil || costBasis != nil else {
      throw ComparisonManifestError.missingCostBasis(system: system)
    }
  }

  private func requireOneResultPerMessage(_ messages: [ComparisonMessage]) throws {
    var ids: Set<String> = []
    for result in results where !ids.insert(result.id).inserted {
      throw ComparisonManifestError.duplicateResult(system: system, messageID: result.id)
    }
    let expected = Set(messages.map(\.id))
    if let unknown = ids.subtracting(expected).min() {
      throw ComparisonManifestError.unknownResult(system: system, messageID: unknown)
    }
    if let missing = expected.subtracting(ids).min() {
      throw ComparisonManifestError.missingResult(system: system, messageID: missing)
    }
  }

  private func requireValidMeasurements() throws {
    guard elapsedSec.isFinite, elapsedSec > 0 else {
      throw ComparisonManifestError.invalidMeasurement(system: system, field: "elapsedSec")
    }
    let measurements =
      [("cpuSec", cpuSec), ("costUSD", costUSD)]
      + results.flatMap { result in
        [("latencySec", result.latencySec), ("reviewSec", result.reviewSec)]
      }
    for case let (field, value?) in measurements where !Self.isValidMeasurement(value) {
      throw ComparisonManifestError.invalidMeasurement(system: system, field: field)
    }
  }

  /// One message's result; `label` must be present, with null recording an abstention.
  struct Result: Decodable {
    let id: String
    let label: MailLabel?
    let latencySec: Double?
    let reviewSec: Double?
    let corrections: UInt?
    let reason: String?

    init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      id = try values.decode(String.self, forKey: .id)
      label = try values.decode(MailLabel?.self, forKey: .label)
      latencySec = try values.decodeIfPresent(Double.self, forKey: .latencySec)
      reviewSec = try values.decodeIfPresent(Double.self, forKey: .reviewSec)
      corrections = try values.decodeIfPresent(UInt.self, forKey: .corrections)
      reason = try values.decodeIfPresent(String.self, forKey: .reason)
    }

    private enum CodingKeys: String, CodingKey {
      case id, label, latencySec, reviewSec, corrections, reason
    }
  }
}

import Foundation
public import MessageModel
public import Signals

/// Independent detection objectives, separate from personal mail preferences and actions.
public enum ThreatKind: String, Codable, Sendable, CaseIterable {
  /// Unsolicited bulk abuse.
  case spam
  /// Deceptive requests for credentials, money, or harmful interaction.
  case phishing
  /// Phishing with evidence of recipient-specific targeting.
  case spearphishing
  /// Deceptive financial or other scam activity.
  case fraud
  /// Malicious payload delivery, requiring dedicated inspection coverage.
  case malware
}

/// A detector's finding within its declared coverage, never a guarantee of safety.
public enum ThreatStatus: String, Codable, Sendable {
  /// Evidence supports the objective.
  case detected
  /// The covered analysis did not detect the objective.
  case notDetected
  /// The objective could not be assessed.
  case unknown
}

/// Reproducible identity for a detector's complete inference configuration.
public struct ThreatDetectorIdentity: Codable, Sendable, Equatable {
  /// Detector implementation and version.
  public var implementation: String
  /// Explicit model or rule-set revision; no implicit fallback.
  public var model: String
  /// Tokenizer and text preprocessing revision.
  public var preprocessing: String
  /// Prompt and evidence policy revision, including any threshold policy.
  public var policy: String
  /// Whether this detector can send data off the Mac.
  public var usesNetwork: Bool

  /// Captures identities needed to reproduce inference and invalidate cached responses.
  public init(
    implementation: String,
    model: String,
    preprocessing: String,
    policy: String,
    usesNetwork: Bool = false
  ) {
    self.implementation = implementation; self.model = model
    self.preprocessing = preprocessing; self.policy = policy; self.usesNetwork = usesNetwork
  }
}

/// One independent finding with explicit coverage and uncalibrated score provenance.
public struct ThreatFinding: Codable, Sendable, Equatable {
  /// Detection objective.
  public var kind: ThreatKind
  /// Finding within the declared inspection coverage.
  public var status: ThreatStatus
  /// Optional uncalibrated score between zero and one; unknown findings have no score.
  public var score: Double?
  /// Short explanation grounded in evidence, or why assessment is unavailable.
  public var reason: String
  /// What was inspected, including language, truncation and attachment limitations.
  public var coverage: String

  /// Creates a finding that must be validated before persistence or cache reuse.
  public init(
    kind: ThreatKind,
    status: ThreatStatus,
    score: Double? = nil,
    reason: String,
    coverage: String
  ) {
    self.kind = kind; self.status = status; self.score = score
    self.reason = reason; self.coverage = coverage
  }
}

/// Account-scoped detector input without personal preference labels or action rules.
public struct ThreatInput: Codable, Sendable {
  /// Parsed untrusted content; detectors must bound their own text and attachment processing.
  public var message: ParsedMessage
  /// Account identity prevents cross-account context reuse.
  public var accountID: String?
  /// Relationship and authentication evidence; unavailable history stays unknown.
  public var evidence: EvidenceBundle

  /// Captures message content and the evidence actually available to this assessment.
  public init(message: ParsedMessage, accountID: String?, evidence: EvidenceBundle) {
    self.message = message; self.accountID = accountID; self.evidence = evidence
    self.evidence.bayesLogOdds = nil
    self.evidence.learnedMargin = nil
  }

  /// Hashes effective content, account and evidence, including enriched text beyond the raw hash.
  public func fingerprint() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return stableHash(try encoder.encode(self))
  }
}

/// A bounded independent detector; implementations must honor cancellation and declared networking.
public protocol ThreatDetector: Sendable {
  /// Versioned inference identity used for provenance and cache invalidation.
  var identity: ThreatDetectorIdentity { get }
  /// Returns supported findings only; omitted objectives remain unknown.
  func assess(_ input: ThreatInput) async throws -> [ThreatFinding]
}

/// Persisted threat evidence that cannot prescribe a Mail action.
public struct ThreatAssessment: Codable, Sendable, Equatable {
  private static let maximumExplanationCharacters = 512
  /// Assessment schema identity included in cache keys.
  public static let schemaID = "spamwise-threat-assessment-v1"
  /// Actual detector configuration; nil when no detector ran.
  public var detector: ThreatDetectorIdentity?
  /// Hash of effective message, account and evidence.
  public var inputFingerprint: String
  /// Independent findings; omitted or historical objectives are unknown.
  public var findings: [ThreatFinding]

  /// Validates and completes a detector response without deriving labels from Inbox/Junk decisions.
  public init(
    input: ThreatInput,
    detector: ThreatDetectorIdentity?,
    findings: [ThreatFinding]
  ) throws {
    self.detector = detector
    inputFingerprint = try input.fingerprint()
    self.findings = findings
    try validate()
    for kind in ThreatKind.allCases where !self.findings.contains(where: { $0.kind == kind }) {
      self.findings.append(
        .init(kind: kind, status: .unknown, reason: "Objective not assessed", coverage: "None")
      )
    }
  }

  /// Records a bounded unavailable state without inventing negative findings.
  public static func unavailable(
    input: ThreatInput,
    reason: String,
    detector: ThreatDetectorIdentity? = nil
  ) throws -> ThreatAssessment {
    try .init(
      input: input,
      detector: detector,
      findings: ThreatKind.allCases.map {
        .init(kind: $0, status: .unknown, reason: reason, coverage: "None")
      }
    )
  }

  /// Finds one objective without treating a missing finding as a negative result.
  public func finding(for kind: ThreatKind) -> ThreatFinding? {
    findings.first { $0.kind == kind }
  }

  /// Rejects malformed findings, unsupported scores and incomplete detector provenance.
  public func validate() throws {
    guard findings.count <= ThreatKind.allCases.count,
      Set(findings.map(\.kind)).count == findings.count,
      findings.allSatisfy({ finding in
        !finding.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && !finding.coverage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && finding.reason.count <= Self.maximumExplanationCharacters
          && finding.coverage.count <= Self.maximumExplanationCharacters
          && (finding.score.map { $0.isFinite && (0...1).contains($0) } ?? true)
          && (finding.status != .unknown || finding.score == nil)
          && (finding.status == .unknown || detector != nil)
      })
    else { throw ClassificationError.invalidOutput }
    if let detector {
      guard
        [detector.implementation, detector.model, detector.preprocessing, detector.policy]
          .allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
      else { throw ClassificationError.invalidOutput }
    }
  }

}

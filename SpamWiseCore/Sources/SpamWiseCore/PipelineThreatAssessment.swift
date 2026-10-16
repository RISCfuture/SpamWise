import Foundation

extension Pipeline {
  private static let maximumThreatAssessmentTimeSec = 2.0
  private static let threatBudgetFraction = 0.25

  func assessThreats(
    message: ParsedMessage,
    identity: MessageIdentity,
    evidence: EvidenceBundle,
    localOnly: Bool,
    remainingTimeSec: Double
  ) async throws -> ThreatAssessment {
    let input = ThreatInput(message: message, accountID: identity.accountID, evidence: evidence)
    guard let threatDetector else {
      return try .unavailable(input: input, reason: "No independent threat detector configured")
    }
    guard !localOnly || !threatDetector.identity.usesNetwork else {
      return try .unavailable(input: input, reason: "Local mode excludes this network detector")
    }
    guard remainingTimeSec > 0 else {
      return try .unavailable(input: input, reason: "No remaining threat assessment budget")
    }
    do {
      let findings = try await withDeadline(
        seconds: min(
          Self.maximumThreatAssessmentTimeSec,
          remainingTimeSec * Self.threatBudgetFraction
        )
      ) {
        try await threatDetector.assess(input)
      }
      try Task.checkCancellation()
      return try ThreatAssessment(
        input: input,
        detector: threatDetector.identity,
        findings: findings
      )
    } catch {
      try Task.checkCancellation()
      return try .unavailable(
        input: input,
        reason: "Independent threat assessment unavailable",
        detector: threatDetector.identity
      )
    }
  }
}

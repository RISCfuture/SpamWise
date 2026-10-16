public import Foundation

/// Supported explicit automation operations; preview never requests mail actions.
public enum AutomationOperation: Codable, Sendable {
  case preview
  case correct(MailLabel)
}

/// A durable automation reply separate from any subsequently edited Activity row.
public struct AutomationReply: Codable, Sendable, Equatable {
  /// Activity identifier for inspecting the full explanation.
  public let recordID: UUID
  /// Resulting decision label, absent for unclassified mail.
  public let label: MailLabel?
  /// Intended action; previews still record what would have happened.
  public let action: MailAction
  /// Observed action status; callers must not infer success from the label.
  public let outcome: ActionOutcome
  /// Bounded explanation from the decision pipeline.
  public let reason: String
}

extension Pipeline {
  private static let automationKey = "automation-requests-v1"
  private static let maximumAutomationClaims = 10_000
  private static let maximumAutomationReasonCharacters = 500
  /// Claims a caller-supplied UUID before work; reuse returns its saved result or refuses uncertain replay.
  public func execute(
    _ operation: AutomationOperation,
    requestID: UUID,
    envelope: MailEnvelope,
    adapter: any MailClientAdapter
  ) async throws -> AutomationReply {
    try Task.checkCancellation()
    guard envelope.identity.accountID != nil,
      stableHash(envelope.raw) == envelope.identity.contentHash
    else {
      throw IntegrationError.staleMessage
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let fingerprint = stableHash(
      try encoder.encode(RequestIdentity(operation: operation, identity: envelope.identity.key))
    )
    let saved = try await store.update(Self.automationKey, default: [UUID: Claim]()) {
      claims -> AutomationReply? in
      if let existing = claims[requestID] {
        guard existing.fingerprint == fingerprint, let reply = existing.reply else {
          throw IntegrationError.staleMessage
        }
        return reply
      }
      guard claims.count < Self.maximumAutomationClaims else { throw IntegrationError.unavailable }
      claims[requestID] = Claim(fingerprint: fingerprint)
      return nil
    }
    if let saved { return saved }
    try Task.checkCancellation()
    let record: DecisionRecord
    switch operation {
      case .preview: record = await process(envelope, adapter: adapter, forceDryRun: true)
      case .correct(let label):
        record = try await correct(envelope: envelope, label: label, adapter: adapter)
    }
    let reply = AutomationReply(
      recordID: record.id,
      label: record.decision.label,
      action: record.decision.action,
      outcome: record.outcome,
      reason: String(record.decision.reason.prefix(Self.maximumAutomationReasonCharacters))
    )
    try await store.update(Self.automationKey, default: [UUID: Claim]()) { claims in
      guard claims[requestID]?.fingerprint == fingerprint else {
        throw IntegrationError.staleMessage
      }
      claims[requestID]?.reply = reply
    }
    return reply
  }
  private struct RequestIdentity: Encodable {
    let operation: AutomationOperation; let identity: String
  }
  private struct Claim: Codable, Sendable { let fingerprint: String; var reply: AutomationReply? }
}

public import Foundation

/// Failures of an explicit automation request.
public protocol AutomationFailure: Error {}

/// Why an automation request was refused before or after its work.
public enum AutomationError: AutomationFailure, Sendable, Equatable, LocalizedError {
  /// The supplied message has no account or its content no longer matches its identity.
  case messageChanged
  /// The request identifier was already used for different work.
  case requestReused
  /// The request identifier was claimed earlier but its result was never saved, so replaying it is unsafe.
  case resultUnknown
  /// The store holds the maximum number of remembered automation requests.
  case tooManyRequests(limit: Int)
  /// A general description of the refused request.
  public var errorDescription: String? {
    String(localized: "The automation request couldn’t be completed.")
  }
  /// The condition that refused the request.
  public var failureReason: String? {
    switch self {
      case .messageChanged:
        String(localized: "The message has no account or changed since it was selected.")
      case .requestReused:
        String(localized: "This request identifier was already used for a different request.")
      case .resultUnknown:
        String(
          localized:
            "An earlier attempt with this request identifier did not finish, so it was not repeated."
        )
      case .tooManyRequests(let limit):
        String(
          localized: "SpamWise remembers at most \(limit, format: .number) automation requests."
        )
    }
  }
}

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
  /// Bounded explanation from the decision pipeline, in the user's language.
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
      throw AutomationError.messageChanged
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let fingerprint = stableHash(
      try encoder.encode(RequestIdentity(operation: operation, identity: envelope.identity.key))
    )
    let saved = try await store.update(Self.automationKey, default: [UUID: Claim]()) {
      claims -> AutomationReply? in
      if let existing = claims[requestID] {
        guard existing.fingerprint == fingerprint else { throw AutomationError.requestReused }
        guard let reply = existing.reply else { throw AutomationError.resultUnknown }
        return reply
      }
      guard claims.count < Self.maximumAutomationClaims else {
        throw AutomationError.tooManyRequests(limit: Self.maximumAutomationClaims)
      }
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
      reason: String(
        record.decision.reason.localizedDescription.prefix(Self.maximumAutomationReasonCharacters)
      )
    )
    try await store.update(Self.automationKey, default: [UUID: Claim]()) { claims in
      guard claims[requestID]?.fingerprint == fingerprint else {
        throw AutomationError.requestReused
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

public import Foundation
import MessageModel

/// The address or registrable domain affected by a persisted sender rule.
public enum RuleScope: String, Codable, Sendable, CaseIterable { case address, domain }
/// An explicit allow or block instruction.
public enum RuleDisposition: String, Codable, Sendable { case allow, block }
/// The latest correction for one sender address or domain.
public struct SenderRule: Codable, Sendable, Equatable, Identifiable {
  /// The explicit address or domain scope.
  public var scope: RuleScope
  /// Normalized address or domain matched by this rule.
  public var value: String
  /// Whether the matching sender is allowed or blocked.
  public var disposition: RuleDisposition
  /// Timestamp of the latest stored update.
  public var updatedAt: Date
  /// Stable identity used for persistence and presentation.
  public var id: String { scope.rawValue + ":" + value }
  /// Creates a SenderRule with the supplied configuration.
  public init(scope: RuleScope, value: String, disposition: RuleDisposition, updatedAt: Date = .now)
  {
    self.scope = scope; self.value = value.lowercased(); self.disposition = disposition
    self.updatedAt = updatedAt
  }
}
/// How much correspondence history is known.
public enum HistoryAvailability: String, Codable, Sendable { case unavailable, partial, complete }
/// Relationship evidence that distinguishes missing history from observed absence.
public struct SenderHistory: Codable, Sendable, Equatable {
  /// The completeness of the available history.
  public var availability: HistoryAvailability = .unavailable
  /// Number of distinct imported messages from this sender's domain, or from this exact address
  /// at a shared mailbox provider.
  public var receivedCount: Int = 0
  /// Number of imported replies sent to this address.
  public var replyCount: Int = 0
  /// Number of eligible imported receipts from this exact address, used only as model evidence.
  public var receiptCount: Int = 0
  /// Number of those receipts that the user confirmed and trusted servers authenticated for the
  /// From domain; nil means none.
  public var authenticatedReceiptCount: Int?
  /// Timestamp of the most recent known receipt, when available.
  public var lastReceipt: Date?
  /// Human-readable history with unknown and partial states preserved.
  public var summary: String {
    if replyCount > 0 { return "User replied to this sender \(replyCount) times" }
    if receiptCount > 0 { return "\(receiptCount) order confirmations from this sender" }
    if availability == .unavailable { return "History unavailable; relationship unknown" }
    if receivedCount > 0 {
      return "\(receivedCount) prior messages; no confirmed reply or order in imported history"
    }
    return availability == .complete
      ? "No prior mail in the completely imported history window"
      : "No match in partial history; relationship unknown"
  }
  /// Creates a SenderHistory with the supplied configuration.
  public init(
    availability: HistoryAvailability = .unavailable,
    receivedCount: Int = 0,
    replyCount: Int = 0,
    receiptCount: Int = 0,
    authenticatedReceiptCount: Int? = nil
  ) {
    self.availability = availability; self.receivedCount = receivedCount
    self.replyCount = replyCount; self.receiptCount = receiptCount
    self.authenticatedReceiptCount = authenticatedReceiptCount
  }
}
/// The rule or relationship that decided a deterministic gate.
public enum GateReason: Codable, Sendable, Equatable {
  /// The user's address or domain rule.
  case senderRule(scope: RuleScope, disposition: RuleDisposition)
  /// The user's header or body rule, with the rule's note when it has one.
  case contentRule(id: UUID, disposition: RuleDisposition, note: String?)
  /// The sender is in the user's Contacts.
  case contact
  /// The user has replied to the sender.
  case priorCorrespondence
  /// The sender previously sent authenticated order mail.
  case orderHistory

  /// Stable English form for logs, reports and model correction examples.
  public var diagnosticDescription: String {
    switch self {
      case let .senderRule(scope, disposition):
        "gate: user \(scope.rawValue) \(disposition.rawValue) rule"
      case let .contentRule(id, _, _): "gate: user content rule \(id.uuidString)"
      case .contact: "gate: contact"
      case .priorCorrespondence: "gate: prior correspondence"
      case .orderHistory: "gate: order history"
    }
  }
}
/// A deterministic rule or trusted-relationship decision.
public struct GateResult: Codable, Sendable, Equatable {
  /// Whether the matching sender is allowed or blocked.
  public var disposition: RuleDisposition
  /// The rule or relationship behind this result.
  public var reason: GateReason
  /// Creates a GateResult with the supplied configuration.
  public init(_ disposition: RuleDisposition, _ reason: GateReason) {
    self.disposition = disposition; self.reason = reason
  }
}
/// Resolves address rules, domain rules, then authenticated relationships in that order.
public enum Gates {
  /**
   Applies deterministic policy without requesting a mail action.

   The From address can be forged, so anything that allows a sender decides the message only
   when trusted authentication confirms the From domain: an Allow rule, a Contacts match, reply
   history and receipt history. Otherwise the caller passes the relationship to the classifier
   as evidence. Block rules apply whether or not the sender is authenticated. The most specific
   matching rule ends the evaluation, so an unconfirmed address Allow rule never falls through to
   a domain Block rule or to relationships.

   Receipt history allows only a sender outside the shared mailbox providers, and only on the
   strength of receipts that were themselves authenticated. One such receipt is enough: it is
   keyed to the exact address and confirmed by the user, and both it and the current message
   must pass aligned trusted authentication, which together stand in for a count threshold.
   */
  public static func evaluate(
    address: String,
    domain: String?,
    rules: [SenderRule],
    contact: Bool?,
    history: SenderHistory,
    authentication: SenderAuthentication = .unverified
  ) -> GateResult? {
    let confirmed = authentication == .alignedPass
    if let rule = matchingRule(address: address, domain: domain, rules: rules) {
      guard rule.disposition == .block || confirmed else { return nil }
      return GateResult(
        rule.disposition,
        .senderRule(scope: rule.scope, disposition: rule.disposition)
      )
    }
    guard confirmed else { return nil }
    if contact == true { return GateResult(.allow, .contact) }
    if history.replyCount > 0 { return GateResult(.allow, .priorCorrespondence) }
    if (history.authenticatedReceiptCount ?? 0) > 0, let domain,
      !SharedMailboxDomains.contains(domain)
    {
      return GateResult(.allow, .orderHistory)
    }
    return nil
  }
  /// The latest rule for the address, otherwise the latest rule for the domain.
  public static func matchingRule(address: String, domain: String?, rules: [SenderRule])
    -> SenderRule?
  {
    let address = address.lowercased(), domain = domain?.lowercased()
    return [RuleScope.address, .domain].lazy.compactMap { scope in
      let value = scope == .address ? address : domain
      return rules.filter { $0.scope == scope && $0.value == value }
        .max { $0.updatedAt < $1.updatedAt }
    }.first
  }
  /// Replaces any conflicting rule at the same scope and normalized value.
  public static func replacing(_ rule: SenderRule, in rules: [SenderRule]) -> [SenderRule] {
    rules.filter { $0.id != rule.id } + [rule]
  }
}

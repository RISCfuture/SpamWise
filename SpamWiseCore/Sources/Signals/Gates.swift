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
  /// Number of distinct imported messages from this sender domain.
  public var receivedCount: Int = 0
  /// Number of imported replies sent to this address.
  public var replyCount: Int = 0
  /// Number of imported messages matching the receipt heuristic.
  public var receiptCount: Int = 0
  /// Timestamp of the most recent known receipt, when available.
  public var lastReceipt: Date?
  /// Creates a SenderHistory with the supplied configuration.
  public init(
    availability: HistoryAvailability = .unavailable,
    receivedCount: Int = 0,
    replyCount: Int = 0,
    receiptCount: Int = 0
  ) {
    self.availability = availability; self.receivedCount = receivedCount
    self.replyCount = replyCount; self.receiptCount = receiptCount
  }
  /// Human-readable history with unknown and partial states preserved.
  public var summary: String {
    if replyCount > 0 { return "User replied to this sender \(replyCount) times" }
    if receiptCount > 0 { return "\(receiptCount) order confirmations from this domain" }
    if availability == .unavailable { return "History unavailable; relationship unknown" }
    if receivedCount > 0 {
      return "\(receivedCount) prior messages; no confirmed reply or order in imported history"
    }
    return availability == .complete
      ? "No prior mail in the completely imported history window"
      : "No match in partial history; relationship unknown"
  }
}
/// A deterministic rule or trusted-relationship decision.
public struct GateResult: Codable, Sendable, Equatable {
  /// Whether the matching sender is allowed or blocked.
  public var disposition: RuleDisposition
  /// Short explanation of the evidence or policy behind this result.
  public var reason: String
  /// Creates a GateResult with the supplied configuration.
  public init(_ disposition: RuleDisposition, _ reason: String) {
    self.disposition = disposition; self.reason = reason
  }
}
/// Resolves address rules, domain rules, then trusted relationships in that order.
public enum Gates {
  /// Applies deterministic policy without requesting a mail action.
  public static func evaluate(
    address: String,
    domain: String?,
    rules: [SenderRule],
    contact: Bool?,
    history: SenderHistory
  ) -> GateResult? {
    let normalized = address.lowercased()
    for scope in [RuleScope.address, .domain] {
      let value = scope == .address ? normalized : domain?.lowercased()
      if let rule = rules.filter({ $0.scope == scope && $0.value == value }).max(by: {
        $0.updatedAt < $1.updatedAt
      }) {
        return GateResult(
          rule.disposition,
          "gate: user \(scope.rawValue) \(rule.disposition.rawValue) rule"
        )
      }
    }
    if contact == true { return GateResult(.allow, "gate: contact") }
    if history.replyCount > 0 { return GateResult(.allow, "gate: prior correspondence") }
    if history.receiptCount > 0 { return GateResult(.allow, "gate: order history") }
    return nil
  }
  /// Replaces any conflicting rule at the same scope and normalized value.
  public static func replacing(_ rule: SenderRule, in rules: [SenderRule]) -> [SenderRule] {
    rules.filter { $0.id != rule.id } + [rule]
  }
}

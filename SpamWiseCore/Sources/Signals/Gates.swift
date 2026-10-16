import Foundation
import MessageModel

public enum RuleScope: String, Codable, Sendable, CaseIterable { case address, domain }
public enum RuleDisposition: String, Codable, Sendable { case allow, block }
public struct SenderRule: Codable, Sendable, Equatable, Identifiable {
    public var scope: RuleScope
    public var value: String
    public var disposition: RuleDisposition
    public var updatedAt: Date
    public var id: String { scope.rawValue + ":" + value }
    public init(scope: RuleScope, value: String, disposition: RuleDisposition, updatedAt: Date = .now) {
        self.scope = scope; self.value = value.lowercased(); self.disposition = disposition; self.updatedAt = updatedAt
    }
}
public enum HistoryAvailability: String, Codable, Sendable { case unavailable, partial, complete }
public struct SenderHistory: Codable, Sendable, Equatable {
    public var availability: HistoryAvailability = .unavailable
    public var receivedCount: Int = 0
    public var replyCount: Int = 0
    public var receiptCount: Int = 0
    public var lastReceipt: Date?
    public init(availability: HistoryAvailability = .unavailable, receivedCount: Int = 0, replyCount: Int = 0, receiptCount: Int = 0) {
        self.availability = availability; self.receivedCount = receivedCount; self.replyCount = replyCount; self.receiptCount = receiptCount
    }
    public var summary: String {
        if replyCount > 0 { return "User replied to this sender \(replyCount) times" }
        if receiptCount > 0 { return "\(receiptCount) order confirmations from this domain" }
        if availability == .unavailable { return "History unavailable; relationship unknown" }
        if receivedCount > 0 { return "\(receivedCount) prior messages; no confirmed reply or order in imported history" }
        return availability == .complete ? "No prior mail in the completely imported history window" : "No match in partial history; relationship unknown"
    }
}
public struct GateResult: Codable, Sendable, Equatable {
    public var disposition: RuleDisposition
    public var reason: String
    public init(_ disposition: RuleDisposition, _ reason: String) { self.disposition = disposition; self.reason = reason }
}
public enum Gates {
    public static func evaluate(address: String, domain: String?, rules: [SenderRule], contact: Bool?, history: SenderHistory) -> GateResult? {
        let normalized = address.lowercased()
        for scope in [RuleScope.address, .domain] {
            let value = scope == .address ? normalized : domain?.lowercased()
            if let rule = rules.filter({ $0.scope == scope && $0.value == value }).max(by: { $0.updatedAt < $1.updatedAt }) {
                return GateResult(rule.disposition, "gate: user \(scope.rawValue) \(rule.disposition.rawValue) rule")
            }
        }
        if contact == true { return GateResult(.allow, "gate: contact") }
        if history.replyCount > 0 { return GateResult(.allow, "gate: prior correspondence") }
        if history.receiptCount > 0 { return GateResult(.allow, "gate: order history") }
        return nil
    }
    public static func replacing(_ rule: SenderRule, in rules: [SenderRule]) -> [SenderRule] { rules.filter { $0.id != rule.id } + [rule] }
}

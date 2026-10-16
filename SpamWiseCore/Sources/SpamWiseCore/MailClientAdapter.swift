import Foundation
public struct MailEnvelope: Sendable {
    public var identity: MessageIdentity
    public var raw: Data
    public init(identity: MessageIdentity, raw: Data) { self.identity = identity; self.raw = raw }
}
public struct ActionReceipt: Sendable {
    public var confirmed: Bool
    public init(confirmed: Bool) { self.confirmed = confirmed }
}
public protocol MailClientAdapter: Sendable {
    func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope?
    func recentMessages(limit: Int) async throws -> [MailEnvelope]
    func importHistory() async throws -> [String: HistoryIndex]
    func perform(_ action: MailAction, for identity: MessageIdentity) async throws -> ActionReceipt
}
public enum IntegrationError: String, Error, LocalizedError, Sendable {
    case permissionDenied, unavailable, ambiguous, staleMessage, accountUnverified, scriptFailed
    public var errorDescription: String? { "Mail action unavailable: \(rawValue)." }
}

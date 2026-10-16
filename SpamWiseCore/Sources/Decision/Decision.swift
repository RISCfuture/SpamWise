import Foundation
import Classifier

public enum FilteringStrength: String, Codable, Sendable, CaseIterable {
    case conservative, balanced, aggressive
    public var threshold: Int { switch self { case .conservative: 99; case .balanced: 95; case .aggressive: 90 } }
}
public enum ReviewTreatment: String, Codable, Sendable, CaseIterable { case orangeFlag, orangeBackground }
/// The supported action vocabulary deliberately contains no deletion or Trash operation.
public enum MailAction: String, Codable, Sendable { case none, orangeFlag, orangeBackground, moveToJunk, moveToInbox }
public enum ActionOutcome: String, Codable, Sendable { case noAction, dryRun, paused, pending, requested, applied, failed, unclassified, superseded, duplicate, integrationUnavailable }
public struct Decision: Codable, Sendable, Equatable {
    public var label: MailLabel?
    public var action: MailAction
    public var reason: String
    public init(label: MailLabel?, action: MailAction, reason: String) { self.label = label; self.action = action; self.reason = reason }
    public static func evaluate(_ verdict: Verdict, strength: FilteringStrength = .balanced, review: ReviewTreatment = .orangeFlag) throws -> Decision {
        _ = try verdict.validated()
        let label = verdict.label == .junk && verdict.confidence < strength.threshold ? MailLabel.review : verdict.label
        let action: MailAction
        switch label {
        case .inbox: action = .none
        case .review: action = review == .orangeFlag ? .orangeFlag : .orangeBackground
        case .junk: action = .moveToJunk
        }
        return .init(label: label, action: action, reason: verdict.reason)
    }
}

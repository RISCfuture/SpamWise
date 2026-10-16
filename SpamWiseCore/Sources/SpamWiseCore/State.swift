import Foundation

public enum IncomingRoute: String, Codable, Sendable, CaseIterable { case unverified, mailKit, mailRule }
public struct Settings: Codable, Sendable, Equatable {
    public var strength: FilteringStrength = .balanced
    public var review: ReviewTreatment = .orangeFlag
    public var dryRun = true
    public var paused = false
    public var policy = PromptBuilder.defaultPolicy
    public var correctionLimit = 40
    public var bodyTokenBudget = 1500
    public var onboardingComplete = false
    public var route: IncomingRoute = .unverified
    public var validatedAccounts: Set<String> = []
    public var callbackDeadline: Double = 10
    public init() {}
}
public struct DecisionRecord: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var identity: MessageIdentity
    public var sender: String
    public var subject: String
    public var evidence: EvidenceBundle?
    public var verdict: Verdict?
    public var decision: Decision
    public var outcome: ActionOutcome
    public var actionError: String?
    public var path: String
    public var latency: Double
    public var revision: Int
    public var correctedLabel: MailLabel?
    public init(identity: MessageIdentity, sender: String = "Unknown", subject: String = "Unclassified message", evidence: EvidenceBundle? = nil, verdict: Verdict? = nil, decision: Decision, outcome: ActionOutcome, path: String = "error", latency: Double = 0, revision: Int = 0) {
        self.identity = identity; self.sender = sender; self.subject = subject; self.evidence = evidence; self.verdict = verdict
        self.decision = decision; self.outcome = outcome; self.path = path; self.latency = latency; self.revision = revision
    }
}
public struct RetryJob: Codable, Sendable, Identifiable {
    public var id: String { identity.key }
    public var identity: MessageIdentity
    public var message: ParsedMessage
    public var revision: Int
    public var attempt: Int
    public var due: Date
    public var expires: Date
    public var dryRun: Bool
}
public struct HistoryIndex: Codable, Sendable {
    public var availability: HistoryAvailability = .unavailable
    public var received: [String: Int] = [:]
    public var replied: [String: Int] = [:]
    public var receipts: [String: Int] = [:]
    public var importedIDs: Set<String> = []
    public var updatedAt: Date?
    public init() {}
    public func summary(address: String, domain: String?) -> SenderHistory {
        .init(availability: availability, receivedCount: received[domain ?? address, default: 0], replyCount: replied[address, default: 0], receiptCount: receipts[domain ?? "", default: 0])
    }
}
public struct AppState: Codable, Sendable {
    public var schemaVersion = 1
    public var revision = 0
    public var settings = Settings()
    public var rules: [SenderRule] = []
    public var corrections: [CorrectionExample] = []
    public var records: [DecisionRecord] = []
    public var retries: [RetryJob] = []
    public var histories: [String: HistoryIndex] = [:]
    public var claimedActions: [String: UUID] = [:]
    public var contactAddresses: Set<String>?
    public var contactsUpdatedAt: Date?
    public var lastExtensionCallback: Date?
    public var lastBodyCallback: Date?
    public init() {}
}
public enum StateRepository {
    public static let key = "application-v1"
    public static func load(_ store: Store) async throws -> AppState { try await store.read(key, default: AppState()) }
    public static func update<R: Sendable>(_ store: Store, _ body: @Sendable (inout AppState) throws -> R) async throws -> R {
        try await store.update(key, default: AppState(), body)
    }
}

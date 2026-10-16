public import Foundation

/// The explicitly validated incoming-mail integration route.
public enum IncomingRoute: String, Codable, Sendable, CaseIterable {
  /// No incoming-message integration has been validated.
  case unverified
  /// Uses the MailKit extension callback.
  case mailKit
  /// Uses the validated Apple Mail automation route.
  case mailRule
  /// Uses an explicitly configured IMAP account.
  case imap
}
/// Persisted filtering preferences with dry run enabled by default.
public struct Settings: Codable, Sendable, Equatable {
  /// Selected provisional Junk confidence threshold.
  public var strength: FilteringStrength = .balanced
  /// Annotation used for Review messages.
  public var review: ReviewTreatment = .orangeFlag
  /// Whether mail actions must be suppressed.
  public var dryRun = true
  /// Whether classification and actions are paused.
  public var paused = false
  /// The user's bounded plain-English filtering preferences.
  public var policy = PromptBuilder.defaultPolicy
  /// Maximum number of correction examples included in a prompt.
  public var correctionLimit = 40
  /// Approximate body budget, using four characters per token.
  public var bodyTokenBudget = 1500
  /// Whether the user completed the setup flow.
  public var onboardingComplete = false
  /// The recorded incoming-message integration route.
  public var route: IncomingRoute = .unverified
  /// Accounts that passed the explicit disposable-message action probe.
  public var validatedAccounts: Set<String> = []
  /// Provisional callback budget in seconds; requires runtime calibration.
  public var callbackDeadline: Double = 10
  /// Optional advanced preferences; absent in Phase 1 stores.
  public var advanced: AdvancedSettings?
  /// Backward-compatible defaults for optional capabilities.
  public var advancedOptions: AdvancedSettings {
    get { advanced ?? AdvancedSettings() }
    set { advanced = newValue }
  }
  /// Creates a Settings with the supplied configuration.
  public init() {}
}
/// A durable explanation and the independently recorded action outcome.
public struct DecisionRecord: Codable, Sendable, Equatable, Identifiable {
  /// Stable identity used for persistence and presentation.
  public var id = UUID()
  /// Timestamp when this record was created.
  public var date = Date()
  /// Account and content identity used to resolve this message safely.
  public var identity: MessageIdentity
  /// Sender address retained for corrections and activity display.
  public var sender: String
  /// Decoded message subject.
  public var subject: String
  /// Signals available when the decision was made.
  public var evidence: EvidenceBundle?
  /// Model output, absent for errors or explicit corrections.
  public var verdict: Verdict?
  /// Intended action, kept separate from the observed outcome.
  public var decision: Decision
  /// Observed action status, including dry run and integration failure.
  public var outcome: ActionOutcome
  /// Sanitized action failure separate from the classification explanation.
  public var actionError: String?
  /// Decision source, such as gate, model, correction, or error.
  public var path: String
  /// Elapsed decision time in seconds.
  public var latency: Double
  /// Policy generation used to invalidate stale work after corrections.
  public var revision: Int
  /// The user's explicit replacement label, if corrected.
  public var correctedLabel: MailLabel?
  /// Creates a DecisionRecord with the supplied configuration.
  public init(
    identity: MessageIdentity,
    sender: String = "Unknown",
    subject: String = "Unclassified message",
    evidence: EvidenceBundle? = nil,
    verdict: Verdict? = nil,
    decision: Decision,
    outcome: ActionOutcome,
    path: String = "error",
    latency: Double = 0,
    revision: Int = 0
  ) {
    self.identity = identity; self.sender = sender; self.subject = subject
    self.evidence = evidence; self.verdict = verdict
    self.decision = decision; self.outcome = outcome; self.path = path; self.latency = latency
    self.revision = revision
  }
}
/// A bounded, revision-specific classification retry.
public struct RetryJob: Codable, Sendable, Identifiable {
  /// Stable identity used for persistence and presentation.
  public var id: String { identity.key }
  /// Account and content identity used to resolve this message safely.
  public var identity: MessageIdentity
  /// Parsed message supplied to this operation.
  public var message: ParsedMessage
  /// Policy generation used to invalidate stale work after corrections.
  public var revision: Int
  /// Retry attempt number; the pipeline permits at most three retries.
  public var attempt: Int
  /// Earliest time the retry can run.
  public var due: Date
  /// Time after which this queued retry must be discarded.
  public var expires: Date
  /// Whether mail actions must be suppressed.
  public var dryRun: Bool
}
/// Account-scoped, deduplicated correspondence and receipt history.
public struct HistoryIndex: Codable, Sendable {
  /// The completeness of the available history.
  public var availability: HistoryAvailability = .unavailable
  /// Distinct received-message counts by registrable domain.
  public var received: [String: Int] = [:]
  /// Reply counts by recipient address.
  public var replied: [String: Int] = [:]
  /// Heuristic receipt counts by registrable domain.
  public var receipts: [String: Int] = [:]
  /// Account-scoped identities already included in this history snapshot.
  public var importedIDs: Set<String> = []
  /// Timestamp of the latest stored update.
  public var updatedAt: Date?
  /// Creates a HistoryIndex with the supplied configuration.
  public init() {}
  /// Human-readable history with unknown and partial states preserved.
  public func summary(address: String, domain: String?) -> SenderHistory {
    .init(
      availability: availability,
      receivedCount: received[domain ?? address, default: 0],
      replyCount: replied[address, default: 0],
      receiptCount: receipts[domain ?? "", default: 0]
    )
  }
}
/// Durable application state shared by the app and Mail extension.
public struct AppState: Codable, Sendable {
  private static let maximumActivityRecords = 5000
  /// Version of the persisted application state.
  public var schemaVersion = 1
  /// Policy generation used to invalidate stale work after corrections.
  public var revision = 0
  /// Current filtering and integration preferences.
  public var settings = Settings()
  /// Persisted address and explicitly scoped domain rules.
  public var rules: [SenderRule] = []
  /// Recent explicit user corrections used as quoted examples.
  public var corrections: [CorrectionExample] = []
  /// Bounded Activity log of decisions and outcomes.
  public var records: [DecisionRecord] = []
  /// Bounded queue of transient classification failures.
  public var retries: [RetryJob] = []
  /// Correspondence snapshots keyed by Mail account identifier.
  public var histories: [String: HistoryIndex] = [:]
  /// Durable at-most-once action claims retained beyond log truncation.
  public var claimedActions: [String: UUID] = [:]
  /// Cached contact addresses; nil means unavailable.
  public var contactAddresses: Set<String>?
  /// Time the cached Contacts snapshot was refreshed.
  public var contactsUpdatedAt: Date?
  /// Last observed extension callback heartbeat.
  public var lastExtensionCallback: Date?
  /// Last callback in which raw message bytes were available.
  public var lastBodyCallback: Date?
  /// Estimated charges retained independently of the bounded activity log.
  public var costByMonth: [String: Double]?
  /// Bounded derived learning data from explicit corrections and eligible predictions.
  public var learning: LearningState?
  /// Explicit labels retained independently of the Activity display window.
  public var reviewedLabels: [ReviewedLabel]?
  /// Last calendar week whose local Review digest was presented.
  public var lastDigestWeek: String?
  /// Creates an AppState with the supplied configuration.
  public init() {}
}
extension AppState {
  /// Calendar month used for the usage ledger and footer.
  public static func monthKey(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month], from: date)
    return "\(components.year ?? 0)-\(components.month ?? 0)"
  }
  /// Inserts or updates activity without charging twice for outcome updates.
  public mutating func record(_ record: DecisionRecord) {
    if costByMonth == nil {
      costByMonth = [:]
      for previous in records {
        costByMonth?[Self.monthKey(previous.date), default: 0] +=
          previous.verdict?.usage.estimatedCost ?? 0
      }
    }
    if let index = records.firstIndex(where: { $0.id == record.id }) {
      records[index] = record
    } else {
      records.append(record)
      costByMonth?[Self.monthKey(record.date), default: 0] +=
        record.verdict?.usage.estimatedCost ?? 0
    }
    records = Array(records.suffix(Self.maximumActivityRecords))
  }
}
/// Typed transactions for the shared application snapshot.
public enum StateRepository {
  private static let correctionLimitRange = 0...100
  private static let bodyTokenBudgetRange = 100...4000
  /// Stable storage or deduplication key.
  public static let key = "application-v1"
  /// Reads the current shared application snapshot.
  public static func load(_ store: Store) async throws -> AppState {
    try await store.read(key, default: AppState())
  }
  /// Applies a field-level edit to current preferences and invalidates stale classification work.
  public static func editSettings(
    _ store: Store,
    _ edit: @Sendable (inout Settings) -> Void
  ) async throws {
    try await update(store) { state in
      edit(&state.settings)
      state.settings.correctionLimit = min(
        correctionLimitRange.upperBound,
        max(correctionLimitRange.lowerBound, state.settings.correctionLimit)
      )
      state.settings.bodyTokenBudget = min(
        bodyTokenBudgetRange.upperBound,
        max(bodyTokenBudgetRange.lowerBound, state.settings.bodyTokenBudget)
      )
      if !state.settings.advancedOptions.retainReviewedContent {
        state.reviewedLabels = state.reviewedLabels?.map { label in
          var label = label; label.message = nil; return label
        }
      }
      if state.settings.validatedAccounts.isEmpty { state.settings.dryRun = true }
      state.revision += 1
      state.retries.removeAll()
    }
  }
  /// Atomically reads, modifies, and commits a shared value.
  public static func update<R: Sendable>(
    _ store: Store,
    _ body: @Sendable (inout AppState) throws -> R
  ) async throws -> R {
    try await store.update(key, default: AppState(), body)
  }
}

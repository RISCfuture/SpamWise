public import Foundation

/// How SpamWise receives incoming mail.
public enum IncomingRoute: String, Codable, Sendable, CaseIterable {
  /// Previews incoming Apple Mail through the MailKit extension, which has no account identity.
  case mailKit
  /// Checks each included Apple Mail account's Inbox through Automation.
  case mailRule
  /// Checks an explicitly configured IMAP account.
  case imap

  /// Decodes values this version does not recognize as the default Automation route.
  public init(from decoder: any Decoder) throws {
    self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .mailRule
  }
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
  /// The Apple Mail route the user chose; ``incomingRoute`` also accounts for the transport.
  public var route: IncomingRoute = .mailRule
  /// Accounts whose Inbox and Junk mailboxes resolved uniquely in a read-only check.
  public var validatedAccounts: Set<String> = []
  /// Optional advanced preferences; absent in Phase 1 stores.
  public var advanced: AdvancedSettings?
  /// Mail.app workflow preferences, with defaults for existing stores.
  public var mailPreferences: MailPreferences?
  /// Effective Mail.app workflow preferences.
  public var mailOptions: MailPreferences {
    get { mailPreferences ?? MailPreferences() }
    set { mailPreferences = newValue }
  }
  /// Backward-compatible defaults for optional capabilities.
  public var advancedOptions: AdvancedSettings {
    get { advanced ?? AdvancedSettings() }
    set { advanced = newValue }
  }
  /// The effective route: IMAP for the IMAP transport, otherwise the chosen Apple Mail route.
  public var incomingRoute: IncomingRoute {
    if advancedOptions.transport == .imap { return .imap }
    return route == .mailKit ? .mailKit : .mailRule
  }
  /// Creates a Settings with the supplied configuration.
  public init() {}
}
/// What produced a decision record.
public enum DecisionPath: String, Codable, Sendable, CaseIterable {
  /// A sender rule, content rule or trusted relationship.
  case gate
  /// A match to a campaign the user marked as junk.
  case fingerprint
  /// The classifier.
  case model
  /// An explicit user correction.
  case correction
  /// A message the user selected in Mail for correction.
  case selection
  /// A provider connection check.
  case verification
  /// A message without one readable sender, flagged for Review instead of classified.
  case unreadableSender
  /// A failure that left the message unclassified.
  case error

  /// Decodes values this version does not recognize as ``error``.
  public init(from decoder: any Decoder) throws {
    self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .error
  }
}
/// A durable explanation and the independently recorded action outcome.
public struct DecisionRecord: Codable, Sendable, Equatable, Identifiable {
  /// Stable identity used for persistence and presentation.
  public var id = UUID()
  /// Timestamp when this record was created.
  public var date = Date()
  /// Account and content identity used to resolve this message safely.
  public var identity: MessageIdentity
  /// Sender address retained for corrections and activity display; nil when unknown.
  public var sender: String?
  /// Decoded message subject; nil when the message has none or could not be read.
  public var subject: String?
  /// Signals available when the decision was made.
  public var evidence: EvidenceBundle?
  /// Model output, absent for errors or explicit corrections.
  public var verdict: Verdict?
  /// Independent threat coverage; nil on historical, paused, or failed classification records.
  public var threats: ThreatAssessment?
  /// Intended action, kept separate from the observed outcome.
  public var decision: Decision
  /// Observed action status, including dry run and integration failure.
  public var outcome: ActionOutcome
  /// Sanitized action failure separate from the classification explanation.
  public var actionError: String?
  /// What produced the decision.
  public var path: DecisionPath
  /// Elapsed decision time in seconds.
  public var latency: Double
  /// Policy generation used to invalidate stale work after corrections.
  public var revision: Int
  /// The user's explicit replacement label, if corrected.
  public var correctedLabel: MailLabel?
  /// Whether a later explicit undo restored this correction's rules and learning only.
  public var correctionUndone: Bool?
  /// Separately recorded read-status follow-up after a confirmed Junk move.
  public var readStatusOutcome: ActionOutcome?
  /// Failure of optional mark-as-read, independent of the already completed move.
  public var readStatusError: String?
  /// Creates a DecisionRecord with the supplied configuration; an empty subject is stored as nil.
  public init(
    identity: MessageIdentity,
    sender: String? = nil,
    subject: String? = nil,
    evidence: EvidenceBundle? = nil,
    verdict: Verdict? = nil,
    threats: ThreatAssessment? = nil,
    decision: Decision,
    outcome: ActionOutcome,
    path: DecisionPath = .error,
    latency: Double = 0,
    revision: Int = 0
  ) {
    self.identity = identity; self.sender = sender
    self.subject = subject?.isEmpty == false ? subject : nil
    self.evidence = evidence; self.verdict = verdict
    self.threats = threats
    self.decision = decision; self.outcome = outcome; self.path = path; self.latency = latency
    self.revision = revision
  }
}
extension DecisionRecord {
  private static let legacyUnknownSender = "Unknown"
  private static let legacyUnreadableSubject = "Unclassified message"
  private static let legacyMissingSubject = "(No subject)"

  /// Whether the monthly spending limit refused this message before any provider request.
  public var deferredBySpendingLimit: Bool {
    outcome == .unclassified && correctedLabel == nil && decision.reason == .spendingLimitReached
  }

  /// Clears English placeholder text that earlier versions stored for a missing sender or subject.
  mutating func clearLegacyPlaceholders() {
    if subject == Self.legacyMissingSubject { subject = nil }
    guard path == .error else { return }
    if sender == Self.legacyUnknownSender { sender = nil }
    if subject == Self.legacyUnreadableSubject { subject = nil }
  }
}
extension DecisionReason {
  /// The reason recorded when processing fails with `error`.
  init(failure error: any Error) {
    self =
      switch error {
        case is any BudgetFailure: .spendingLimitReached
        case let error as ClassificationError: .classificationFailed(error)
        case is CancellationError: .classificationFailed(.cancelled)
        case is any MessageParsingError: .messageUnreadable
        case is any StorageFailure, is DecodingError, is EncodingError: .storageUnavailable
        default: .processingFailed
      }
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
  /// Distinct received-message counts by registrable domain, or by exact address for shared
  /// mailbox providers.
  public var received: [String: Int] = [:]
  /// Reply counts by recipient address.
  public var replied: [String: Int] = [:]
  /// Eligible receipt counts by exact sender address; nil before any receipt.
  public var senderReceipts: [String: Int]?
  /// User-confirmed receipts that trusted servers authenticated, by exact sender address.
  public var authenticatedSenderReceipts: [String: Int]?
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
      receivedCount: received[Self.receivedKey(address: address, domain: domain), default: 0],
      replyCount: replied[address, default: 0],
      receiptCount: senderReceipts?[address] ?? 0,
      authenticatedReceiptCount: authenticatedSenderReceipts?[address]
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
  /// Optional user-authored header and body rules.
  public var contentRules: [ContentRule]?
  /// Counts of winning content rules, independent of Activity retention.
  public var contentRuleHits: [UUID: Int]?
  /// Per-rule counts of messages where the rule was invalid or timed out, since its last save.
  public var contentRuleSkips: [UUID: Int]?
  /// At-most-once corrections for observed placements in dedicated training folders.
  public var trainingClaims: [String: UUID]?
  /// Identities observed during an unfinished training-folder sweep.
  public var trainingObservations: [String: Set<String>]?
  /// Bounded settings, rule and correction revision trail.
  public var auditEvents: [AuditEvent]?
  /// The latest unchanged correction's bounded undo snapshot.
  public var correctionUndo: CorrectionUndo?
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
  /// Own addresses discovered through Mail.app, used only to exclude implicit trust.
  public var ownAddresses: Set<String>?
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
  mutating func clearLegacyPlaceholders() {
    records.indices.forEach { records[$0].clearLegacyPlaceholders() }
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
    var state = try await store.read(key, default: AppState())
    state.clearLegacyPlaceholders()
    return state
  }
  /// Applies a field-level edit to current preferences and invalidates stale classification work.
  public static func editSettings(
    _ store: Store,
    _ edit: @Sendable (inout Settings) throws -> Void
  ) async throws {
    try await update(store) { state in
      try edit(&state.settings)
      state.correctionUndo = nil
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
      state.audit(.settings, detail: String(localized: "Filtering or integration settings changed"))
    }
  }
  /// Atomically reads, modifies, and commits a shared value.
  public static func update<R: Sendable>(
    _ store: Store,
    _ body: @Sendable (inout AppState) throws -> R
  ) async throws -> R {
    try await store.update(key, default: AppState()) { state in
      state.clearLegacyPlaceholders()
      return try body(&state)
    }
  }
}

public import Foundation

/// How SpamWise receives incoming mail.
public enum IncomingRoute: String, Codable, Sendable, CaseIterable, FallbackDecodable {
  /// Checks each included Apple Mail account's Inbox through Automation.
  case mailRule = "mailRule"
  /// Checks an explicitly configured IMAP account.
  case imap
  /// An unrecognized route uses the default Automation route.
  public static var fallback: Self { .mailRule }
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
  /// How the user wants each kind of graymail handled.
  public var categoryPreferences = CategoryPreferences.defaults
  /// The user's bounded plain-English instructions beyond their category preferences.
  public var policy = PromptBuilder.defaultPolicy
  /// Maximum number of correction examples included in a prompt.
  public var correctionLimit = 5
  /// Approximate body budget, using four characters per token.
  public var bodyTokenBudget = 1500
  /// Whether the user completed the setup flow.
  public var onboardingComplete = false
  /// Accounts whose Inbox and Junk mailboxes resolved uniquely in a read-only check.
  public var validatedAccounts: Set<String> = []
  /// Optional capabilities and the selected model provider.
  public var advancedOptions = AdvancedSettings()
  /// Mail.app workflow preferences.
  public var mailOptions = MailPreferences()
  /// The effective route: IMAP for the IMAP transport, otherwise Apple Mail Automation checks.
  public var incomingRoute: IncomingRoute {
    advancedOptions.transport == .imap ? .imap : .mailRule
  }
  /// Creates default settings: dry run on, not paused, balanced strength and no validated accounts.
  public init() {}
  /**
   Decodes each field independently, using its default when absent or unreadable.

   Unreadable Mail preferences take ``MailPreferences``' restrictive values instead, so they
   never widen the account scope or allow external processing. A policy that an earlier version
   installed by default becomes empty, because category preferences carry those defaults.
   */
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self()
    strength = values.lenient(.strength, default: defaults.strength)
    review = values.lenient(.review, default: defaults.review)
    dryRun = values.lenient(.dryRun, default: defaults.dryRun)
    paused = values.lenient(.paused, default: defaults.paused)
    categoryPreferences = values.lenient(
      .categoryPreferences,
      default: defaults.categoryPreferences
    )
    policy = values.lenient(.policy, default: defaults.policy)
    if PromptBuilder.formerDefaultPolicies.contains(policy) { policy = defaults.policy }
    correctionLimit = values.lenient(.correctionLimit, default: defaults.correctionLimit)
    bodyTokenBudget = values.lenient(.bodyTokenBudget, default: defaults.bodyTokenBudget)
    onboardingComplete = values.lenient(.onboardingComplete, default: defaults.onboardingComplete)
    validatedAccounts = values.lenient(.validatedAccounts, default: defaults.validatedAccounts)
    advancedOptions = values.lenient(.advancedOptions, default: defaults.advancedOptions)
    mailOptions = values.lenient(
      .mailOptions,
      default: defaults.mailOptions,
      unreadable: .restrictive
    )
  }
  private enum CodingKeys: String, CodingKey {
    case strength, review, dryRun, paused, categoryPreferences, policy, correctionLimit
    case bodyTokenBudget
    case onboardingComplete, validatedAccounts
    case advancedOptions = "advanced"
    case mailOptions = "mailPreferences"
  }
}
/// What produced a decision record.
public enum DecisionPath: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
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
  case unreadableSender = "unreadableSender"
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
  /// Independent threat coverage; nil when no detector ran, including historical and failed records.
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
  public var correctionUndone = false
  /// Separately recorded read-status follow-up after a confirmed Junk move; nil when not attempted.
  public var readStatusOutcome: ActionOutcome?
  /// Failure of optional mark-as-read, independent of the already completed move.
  public var readStatusError: String?
  /// Learning identity of the text that was classified, so corrections replace its sample.
  public var sampleID: String?
  /// Creates a record with a new ID and the current date, storing an empty subject as nil.
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
  /// Requires identity, decision and outcome; every other field falls back to its default.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      identity: try values.decode(MessageIdentity.self, forKey: .identity),
      decision: try values.decode(Decision.self, forKey: .decision),
      outcome: try values.decode(ActionOutcome.self, forKey: .outcome)
    )
    id = try values.decode(UUID.self, forKey: .id)
    date = values.lenient(.date, default: date)
    sender = values.lenient(.sender, default: sender)
    subject = values.lenient(.subject, default: subject)
    evidence = values.lenient(.evidence, default: nil)
    verdict = values.lenient(.verdict, default: nil)
    threats = values.lenient(.threats, default: nil)
    actionError = values.lenient(.actionError, default: nil)
    path = values.lenient(.path, default: path)
    latency = values.lenient(.latency, default: latency)
    revision = values.lenient(.revision, default: revision)
    correctedLabel = values.lenient(.correctedLabel, default: nil)
    correctionUndone = values.lenient(.correctionUndone, default: false)
    readStatusOutcome = values.lenient(.readStatusOutcome, default: nil)
    readStatusError = values.lenient(.readStatusError, default: nil)
    sampleID = values.lenient(.sampleID, default: nil)
    clearLegacyPlaceholders()
  }
  private enum CodingKeys: String, CodingKey {
    case id, date, identity, sender, subject, evidence, verdict, threats, decision, outcome
    case actionError, path, latency, revision, correctedLabel, correctionUndone
    case readStatusOutcome, readStatusError, sampleID
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
  private mutating func clearLegacyPlaceholders() {
    if subject == Self.legacyMissingSubject { subject = nil }
    guard path == .error else { return }
    if sender == Self.legacyUnknownSender { sender = nil }
    if subject == Self.legacyUnreadableSubject { subject = nil }
  }
}
/// A bounded, revision-specific classification retry.
public struct RetryJob: Codable, Sendable, Equatable, Identifiable {
  /// The message's identity key, so each message has at most one queued retry.
  public var id: String { identity.key }
  /// Account and content identity of the message to classify again.
  public var identity: MessageIdentity
  /// The parsed message to classify again, so the retry needs no Mail lookup.
  public var message: ParsedMessage
  /// Policy revision when the retry was queued; the retry is discarded once the revision changes.
  public var revision: Int
  /// Retry attempt number; the pipeline permits at most three retries.
  public var attempt: Int
  /// Earliest time the retry can run.
  public var due: Date
  /// Time after which this queued retry must be discarded.
  public var expires: Date
  /// Whether the retry runs as a forced dry run; previews never queue retries, so queued jobs store false.
  public var dryRun: Bool
}
/// Account-scoped, deduplicated correspondence and receipt history.
public struct HistoryIndex: Codable, Sendable, Equatable {
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
  /// Account-scoped identities already counted, bounded to the most recent imports.
  public var importedIDs = RollingIdentitySet(capacity: RetentionLimits.historyImportIdentities)
  /// Timestamp of the latest stored update.
  public var updatedAt: Date?
  /// Creates an empty index whose history is unavailable, so every relationship stays unknown.
  public init() {}
  /// Decodes each field independently, using its default when absent or unreadable.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    availability = values.lenient(.availability, default: .unavailable)
    received = values.lenient(.received, default: [:])
    replied = values.lenient(.replied, default: [:])
    senderReceipts = values.lenient(.senderReceipts, default: nil)
    authenticatedSenderReceipts = values.lenient(.authenticatedSenderReceipts, default: nil)
    importedIDs = RollingIdentitySet(
      capacity: RetentionLimits.historyImportIdentities,
      values.lenient(.importedIDs, default: [])
    )
    updatedAt = values.lenient(.updatedAt, default: nil)
  }
  /**
   Returns the counts recorded for one sender, with this index's availability.

   Received mail is counted by `domain`, or by the exact `address` at shared mailbox providers
   or when the domain is unknown; replies and receipts are counted by `address`.
   */
  public func summary(address: String, domain: String?) -> SenderHistory {
    .init(
      availability: availability,
      receivedCount: received[Self.receivedKey(address: address, domain: domain), default: 0],
      replyCount: replied[address, default: 0],
      receiptCount: senderReceipts?[address] ?? 0,
      authenticatedReceiptCount: authenticatedSenderReceipts?[address]
    )
  }
  private enum CodingKeys: String, CodingKey {
    case availability, received, replied, senderReceipts, authenticatedSenderReceipts
    case importedIDs, updatedAt
  }
}
/// Durable application state shared by the app and Mail extension.
public struct AppState: Codable, Sendable, Equatable {
  /// Policy generation used to invalidate stale work after corrections.
  public var revision = 0
  /// Current filtering and integration preferences.
  public var settings = Settings()
  /// Persisted address and explicitly scoped domain rules.
  public var rules: [SenderRule] = []
  /// User-authored header and body rules.
  public var contentRules: [ContentRule] = []
  /// Counts of winning content rules, independent of Activity retention.
  public var contentRuleHits: [UUID: Int] = [:]
  /// Per-rule counts of messages where the rule was invalid or timed out, since its last save.
  public var contentRuleSkips: [UUID: Int] = [:]
  /// At-most-once corrections for observed placements in dedicated training folders.
  public var trainingClaims: [String: UUID] = [:]
  /// Identities observed during an unfinished training-folder sweep.
  public var trainingObservations: [String: Set<String>] = [:]
  /// Bounded settings, rule and correction revision trail.
  public var auditEvents: [AuditEvent] = []
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
  public var ownAddresses: Set<String> = []
  /// Receiving-server identifiers observed in each account's mail, by account identifier.
  public var authServerObservations: [String: AuthServerObservations] = [:]
  /// Estimated charges retained independently of the bounded activity log.
  public var costByMonth: [String: Double] = [:]
  /// Bounded derived learning data from explicit corrections and eligible predictions.
  public var learning = LearningState()
  /// Explicit labels retained independently of the Activity display window.
  public var reviewedLabels: [ReviewedLabel] = []
  /// Last calendar week whose local Review digest was presented.
  public var lastDigestWeek: String?
  /// Whether this transaction invalidated retries and undo that it did not load.
  var invalidatedPendingWork = false
  /// Creates empty state with default settings, which keep dry run on.
  public init() {}
  /// Decodes each field independently, using its default when absent or unreadable.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    revision = values.lenient(.revision, default: 0)
    settings = values.lenient(.settings, default: Settings())
    rules = values.lenient(.rules, default: [])
    contentRules = values.lenient(.contentRules, default: [])
    contentRuleHits = values.lenient(.contentRuleHits, default: [:])
    contentRuleSkips = values.lenient(.contentRuleSkips, default: [:])
    trainingClaims = values.lenient(.trainingClaims, default: [:])
    trainingObservations = values.lenient(.trainingObservations, default: [:])
    auditEvents = values.lenient(.auditEvents, default: [])
    correctionUndo = values.lenient(.correctionUndo, default: nil)
    corrections = values.lenient(.corrections, default: [])
    records = values.lenient(.records, default: [])
    retries = values.lenient(.retries, default: [])
    histories = values.lenient(.histories, default: [:])
    claimedActions = values.lenient(.claimedActions, default: [:])
    contactAddresses = values.lenient(.contactAddresses, default: nil)
    contactsUpdatedAt = values.lenient(.contactsUpdatedAt, default: nil)
    ownAddresses = values.lenient(.ownAddresses, default: [])
    authServerObservations = values.lenient(.authServerObservations, default: [:])
    costByMonth = values.lenient(.costByMonth, default: Self.costs(of: records))
    learning = values.lenient(.learning, default: LearningState())
    reviewedLabels = values.lenient(.reviewedLabels, default: [])
    lastDigestWeek = values.lenient(.lastDigestWeek, default: nil)
  }
  private enum CodingKeys: String, CodingKey {
    case revision, settings, rules, contentRules, contentRuleHits, contentRuleSkips, trainingClaims
    case trainingObservations, auditEvents, correctionUndo, corrections, records, retries
    case histories, claimedActions, contactAddresses, contactsUpdatedAt, ownAddresses
    case costByMonth, learning, reviewedLabels, lastDigestWeek, authServerObservations
  }
}
extension AppState {
  /// Calendar month used for the usage ledger and footer.
  public static func monthKey(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month], from: date)
    return "\(components.year ?? 0)-\(components.month ?? 0)"
  }
  private static func costs(of records: [DecisionRecord]) -> [String: Double] {
    records.reduce(into: [:]) { costs, record in
      costs[monthKey(record.date), default: 0] += record.verdict?.usage.estimatedCost ?? 0
    }
  }
  /**
   Inserts or updates activity without charging twice for outcome updates.

   A transaction that may update an existing record must load it, so that the update is not
   charged as a new decision.
   */
  public mutating func record(_ record: DecisionRecord) {
    if let index = records.firstIndex(where: { $0.id == record.id }) {
      records[index] = record
    } else {
      records.append(record)
      costByMonth[Self.monthKey(record.date), default: 0] +=
        record.verdict?.usage.estimatedCost ?? 0
    }
  }
  /**
   Supersedes all queued classification work after a policy change.

   Bumps the revision so in-flight decisions cannot act, discards every retry and the
   correction undo snapshot, and records `change` in the audit trail.
   */
  public mutating func invalidatePendingWork(_ change: AuditEvent.Change) {
    revision += 1
    retries = []
    correctionUndo = nil
    invalidatedPendingWork = true
    audit(change)
  }
}

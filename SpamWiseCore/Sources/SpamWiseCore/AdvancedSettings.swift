public import Foundation

/// Explicit classifier selection; unavailable backends never fall back to another provider.
public enum ModelBackend: String, Codable, Sendable, CaseIterable {
  /// Uses the explicitly selected Claude model.
  case claude
  /// Uses Apple’s available on-device model.
  case onDevice
  /// Uses Apple’s explicitly authorized Private Cloud Compute model.
  case privateCloudCompute
  /// Uses the supported OpenAI Responses model.
  case openAI
  /// Uses the supported Gemini model.
  case gemini
  /// Default explicit model identity for a newly selected provider.
  public var defaultModelID: String {
    switch self {
      case .claude: "claude-haiku-5-5"
      case .onDevice: "apple-on-device"
      case .privateCloudCompute: "apple-private-cloud-compute"
      case .openAI: "gpt-5.4-mini"
      case .gemini: "gemini-3.8-flash"
    }
  }
}
/// Incoming integration chosen independently of the classifier provider.
public enum MailTransport: String, Codable, Sendable, CaseIterable {
  /// Accesses mail through the Apple Mail integration.
  case appleMail
  /// Accesses an explicitly configured account through IMAP.
  case imap
}

/// Optional capabilities with conservative defaults.
public struct AdvancedSettings: Codable, Sendable, Equatable {
  /// Explicit model provider.
  public var backend: ModelBackend = .claude
  /// Providers explicitly allowed to receive mail context; missing consent grants no access.
  public var mailSharingConsent: Set<ModelBackend>?
  /// Opt-in sender-domain disclosure to registration-data services.
  public var domainRegistrationLookup: Bool?
  /// Explicit override for providers that support selectable model identities.
  public var modelID: String?
  /// Account access method; IMAP requires separate credentials and validation.
  public var transport: MailTransport = .appleMail
  /// Selects similar reviewed examples instead of a purely chronological window.
  public var retrieveExamples = false
  /// Enables anchored signatures derived from explicit Junk corrections.
  public var fingerprints = false
  /// Enables sufficiently trained Bayes weak evidence.
  public var bayes = false
  /// Enables sufficiently trained regularized evidence weights as weak evidence.
  public var learnedWeights = false
  /// Enables bounded on-device OCR for embedded image parts.
  public var imageOCR = false
  /// Opt-in local extraction of bounded text/plain and text/html attachments.
  public var textAttachments: Bool?
  /// Explicit external evidence configuration; absent disables all lookups and subprocesses.
  public var externalEvidence: ExternalEvidenceSettings?
  /// Presents a local weekly digest of still-unreviewed Review decisions.
  public var weeklyDigest = false
  /// Retains bounded reviewed text locally to support later labeled export.
  public var retainReviewedContent = false
  /// Creates disabled optional capabilities with Claude as the default provider.
  public init() {}
}

/// Opt-in network reputation and local sidecar configuration.
public struct ExternalEvidenceSettings: Codable, Sendable, Equatable {
  /// Queries sender and extracted link domains against Spamhaus DBL.
  public var domainBlocklist = false
  /// Records the user's acknowledgement of the provider's usage terms.
  public var termsAcknowledged = false
  /// Explicit local DNS resolver address meeting the provider's service terms.
  public var resolverAddress = "127.0.0.1"
  /// Explicit Spamhaus service; absent values retain public DNS for existing configurations.
  public var spamhausTransport: SpamhausTransport?
  /// Explicit scanner transport; absent values retain a configured executable path.
  public var rspamdTransport: RspamdTransport?
  /// Absolute path to a separately installed local rspamc executable.
  public var rspamcPath: String?
  /// Resolves an explicit transport or a legacy executable configuration.
  public var selectedRspamdTransport: RspamdTransport? {
    rspamdTransport ?? (rspamcPath == nil ? nil : .executable)
  }
  /// Creates disabled external evidence.
  public init() {}
}

/// An explicit user label; automatic mailbox placement is not ground truth.
public struct ReviewedLabel: Codable, Sendable, Identifiable {
  /// Human action that supplied the label; legacy labels came from corrections.
  public var origin: Origin?
  /// Original account-scoped message identity.
  public var identity: MessageIdentity
  /// Human-selected label, including graymail represented as Review.
  public var label: MailLabel
  /// Time of the latest explicit correction.
  public var date: Date
  /// Optional bounded text retained only under the local sample setting.
  public var message: ParsedMessage?
  /// Delivery-independent content identity retained even when local message text is cleared.
  public var sampleID: String?
  /// Deduplication identity independent of label changes.
  public var id: String { identity.contentHash }
  /// Stable hold-out split, independent of label and correction date.
  public var heldOut: Bool {
    LearningSample.partition(for: sampleID ?? message.map(LearningSample.identity) ?? id)
      == .heldOut
  }
  /// Records an explicit label without requiring message retention.
  public init(
    identity: MessageIdentity,
    label: MailLabel,
    date: Date = .now,
    message: ParsedMessage? = nil,
    sampleID: String? = nil
  ) {
    self.identity = identity; self.label = label; self.date = date; self.message = message
    self.sampleID = sampleID ?? message.map(LearningSample.identity)
  }
  /// Migrates retained messages to stable content identities before their text can be cleared.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      identity: try values.decode(MessageIdentity.self, forKey: .identity),
      label: try values.decode(MailLabel.self, forKey: .label),
      date: try values.decode(Date.self, forKey: .date),
      message: try values.decodeIfPresent(ParsedMessage.self, forKey: .message),
      sampleID: try values.decodeIfPresent(String.self, forKey: .sampleID)
    )
    origin = try values.decodeIfPresent(Origin.self, forKey: .origin)
  }
  /// Explicit human label sources; predictions have separate learning provenance.
  public enum Origin: String, Codable, Sendable { case correction, reviewedImport }
  private enum CodingKeys: String, CodingKey {
    case identity, label, date, message, sampleID, origin
  }
}

/// Local weekly summary; it never sends mail or changes message state.
public struct ReviewDigest: Sendable {
  private static let lookbackDays = 7
  /// Calendar week identity used to avoid repeated automatic presentation.
  public let week: String
  /// Latest still-unreviewed decisions in the preceding seven days.
  public let records: [DecisionRecord]
  /// Builds a digest from persisted outcomes without reclassifying mail.
  public init(state: AppState, now: Date = .now, calendar: Calendar = .current) {
    let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
    week = "\(parts.yearForWeekOfYear ?? 0)-\(parts.weekOfYear ?? 0)"
    let cutoff = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: now) ?? now
    let latest = Dictionary(grouping: state.records, by: { $0.identity.key }).compactMap {
      $0.value.max { $0.date < $1.date }
    }
    records = latest.filter {
      $0.date >= cutoff && $0.date <= now && $0.decision.label == .review
        && $0.correctedLabel == nil && $0.outcome != .superseded
    }.sorted(by: ReviewPriority.precedes)
  }
}

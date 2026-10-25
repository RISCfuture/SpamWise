public import Foundation

/// Incoming integration chosen independently of the classifier provider.
public enum MailTransport: String, Codable, Sendable, CaseIterable {
  /// Accesses mail through the Apple Mail integration.
  case appleMail = "appleMail"
  /// Accesses an explicitly configured account through IMAP.
  case imap

  /// The prefix of the identifiers SpamWise gives IMAP accounts; Apple Mail's identifiers lack it.
  public static let imapAccountPrefix = "imap:"

  /// The transport whose accounts `accountID` identifies.
  public init(accountID: String) {
    self = accountID.hasPrefix(Self.imapAccountPrefix) ? .imap : .appleMail
  }
}

/// Optional capabilities with conservative defaults.
public struct AdvancedSettings: Codable, Sendable, Equatable {
  /// Explicit model provider.
  public var backend: ModelBackend = .claude
  /// Providers explicitly allowed to receive mail context; an absent provider has no access.
  public var mailSharingConsent: Set<ModelBackend> = []
  /// Opt-in sender-domain disclosure to registration-data services.
  public var domainRegistrationLookup = false
  /// Persisted model identity, parsed leniently by ``model``.
  private var modelID: String?
  /// Account access method; IMAP requires separate credentials and validation.
  public var transport: MailTransport = .appleMail
  /// Enables anchored signatures derived from explicit Junk corrections.
  public var fingerprints = false
  /// Enables sufficiently trained Bayes weak evidence.
  public var bayes = false
  /// Enables sufficiently trained regularized evidence weights as weak evidence.
  public var learnedWeights = false
  /// Enables bounded on-device OCR for embedded image parts.
  public var imageOCR = false
  /// Opt-in local extraction of bounded text/plain and text/html attachments.
  public var textAttachments = false
  /// Explicit external evidence configuration; absent disables all lookups and scans.
  public var externalEvidence: ExternalEvidenceSettings?
  /// Presents a local weekly digest of still-unreviewed Review decisions.
  public var weeklyDigest = false
  /// Retains bounded reviewed text locally to support later labeled export.
  public var retainReviewedContent = false
  /// The selected model, or the provider default when the stored identity is unknown or foreign.
  public var model: ModelIdentifier {
    guard let stored = modelID.flatMap(ModelIdentifier.init(rawValue:)), stored.backend == backend
    else { return backend.defaultModel }
    return stored
  }
  /// Creates disabled optional capabilities with Claude as the default provider.
  public init() {}
  /// Decodes each field independently, using its default when absent or unreadable.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self()
    backend = values.lenient(.backend, default: defaults.backend)
    mailSharingConsent = values.lenient(.mailSharingConsent, default: defaults.mailSharingConsent)
    domainRegistrationLookup = values.lenient(
      .domainRegistrationLookup,
      default: defaults.domainRegistrationLookup
    )
    modelID = values.lenient(.modelID, default: defaults.modelID)
    transport = values.lenient(.transport, default: defaults.transport)
    fingerprints = values.lenient(.fingerprints, default: defaults.fingerprints)
    bayes = values.lenient(.bayes, default: defaults.bayes)
    learnedWeights = values.lenient(.learnedWeights, default: defaults.learnedWeights)
    imageOCR = values.lenient(.imageOCR, default: defaults.imageOCR)
    textAttachments = values.lenient(.textAttachments, default: defaults.textAttachments)
    externalEvidence = values.lenient(.externalEvidence, default: defaults.externalEvidence)
    weeklyDigest = values.lenient(.weeklyDigest, default: defaults.weeklyDigest)
    retainReviewedContent = values.lenient(
      .retainReviewedContent,
      default: defaults.retainReviewedContent
    )
  }
  /// Selects `model` together with the provider that serves it.
  public mutating func select(_ model: ModelIdentifier) {
    backend = model.backend; modelID = model.rawValue
  }
  private enum CodingKeys: String, CodingKey {
    case backend, mailSharingConsent, domainRegistrationLookup, modelID, transport
    case fingerprints, bayes, learnedWeights, imageOCR, textAttachments, externalEvidence
    case weeklyDigest, retainReviewedContent
  }
}

/// Opt-in network reputation and local sidecar configuration.
public struct ExternalEvidenceSettings: Codable, Sendable, Equatable {
  private static let loopbackScanner = "loopbackHTTP"
  /// Queries sender and extracted link domains against Spamhaus DBL.
  public var domainBlocklist = false
  /// Records the user's acknowledgement of the provider's usage terms.
  public var termsAcknowledged = false
  /// Explicit local DNS resolver address meeting the provider's service terms.
  public var resolverAddress = "127.0.0.1"
  /// Explicit Spamhaus service; absent values retain public DNS for existing configurations.
  public var spamhausTransport: SpamhausTransport?
  /// Scans messages with the user's Rspamd service on the IPv4 loopback interface.
  public var localRspamd = false
  /// Creates disabled external evidence.
  public init() {}

  /// Decodes saved settings; any stored scanner selection other than the loopback service is off.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    domainBlocklist = try values.decode(Bool.self, forKey: .domainBlocklist)
    termsAcknowledged = try values.decode(Bool.self, forKey: .termsAcknowledged)
    resolverAddress = try values.decode(String.self, forKey: .resolverAddress)
    spamhausTransport = try values.decodeIfPresent(
      SpamhausTransport.self,
      forKey: .spamhausTransport
    )
    localRspamd =
      (try? values.decodeIfPresent(String.self, forKey: .rspamdTransport)) == Self.loopbackScanner
  }

  /// Encodes an enabled scanner as `rspamdTransport: "loopbackHTTP"`.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(domainBlocklist, forKey: .domainBlocklist)
    try values.encode(termsAcknowledged, forKey: .termsAcknowledged)
    try values.encode(resolverAddress, forKey: .resolverAddress)
    try values.encodeIfPresent(spamhausTransport, forKey: .spamhausTransport)
    if localRspamd { try values.encode(Self.loopbackScanner, forKey: .rspamdTransport) }
  }

  private enum CodingKeys: String, CodingKey {
    case domainBlocklist, termsAcknowledged, resolverAddress, spamhausTransport, rspamdTransport
  }
}

/// An explicit user label; automatic mailbox placement is not ground truth.
public struct ReviewedLabel: Codable, Sendable, Equatable, Identifiable {
  /// Human action that supplied the label.
  public var origin: Origin = .correction
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
  /// Derives a stable content identity from a retained message when none was stored.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      identity: try values.decode(MessageIdentity.self, forKey: .identity),
      label: try values.decode(MailLabel.self, forKey: .label),
      date: values.lenient(.date, default: .now),
      message: values.lenient(.message, default: nil),
      sampleID: values.lenient(.sampleID, default: nil)
    )
    origin = values.lenient(.origin, default: .correction)
  }
  /// Explicit human label sources; predictions have separate learning provenance.
  public enum Origin: String, Codable, Sendable, FallbackDecodable {
    case correction
    case reviewedImport = "reviewedImport"
    /// An unrecognized source is treated as an explicit correction.
    public static var fallback: Self { .correction }
  }
  private enum CodingKeys: String, CodingKey {
    case identity, label, date, message, sampleID, origin
  }
}

/// Local weekly summary; it never sends mail or changes message state.
public struct ReviewDigest: Sendable {
  /// Days of Activity the digest covers.
  public static let lookbackDays = 7
  /// Calendar week identity used to avoid repeated automatic presentation.
  public let week: String
  /// Latest still-unreviewed decisions in the preceding ``lookbackDays`` days.
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

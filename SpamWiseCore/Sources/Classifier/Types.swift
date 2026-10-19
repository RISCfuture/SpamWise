public import Foundation
public import MessageModel
public import Signals

/// The classifier vocabulary: Inbox, Review, or Junk.
public enum MailLabel: String, Codable, Sendable, CaseIterable {
  /// Wanted mail that belongs in Inbox.
  case inbox
  /// Uncertain mail requiring user review.
  case review
  /// Unwanted mail eligible for Junk policy evaluation.
  case junk
}
/// Token counts and their measurement provenance.
public struct TokenUsage: Codable, Sendable, Equatable {
  private static let tokensPerPricingUnit = 1_000_000.0
  /// Total input token count, including cached input.
  public var input: Int
  /// Generated output token count.
  public var output: Int
  /// Input tokens served from provider cache.
  public var cached: Int
  /// Whether token counts are estimates rather than provider measurements.
  public var estimated: Bool
  /// Explicit model identity; absent on historical Haiku records.
  public var modelID: String?
  /// Rates captured when this usage was measured.
  public var pricing: ModelTokenPricing?
  /// Estimated USD from captured rates; historical records without a model identity use Haiku rates.
  public var estimatedCost: Double {
    let rates = pricing ?? .legacyHaiku
    return
      (Double(input - cached) * rates.input + Double(cached) * rates.cached
      + Double(output) * rates.output) / Self.tokensPerPricingUnit
  }
  /// Creates token counts, raising negative counts to zero and limiting cached input to `input`.
  public init(
    input: Int = 0,
    output: Int = 0,
    cached: Int = 0,
    estimated: Bool = true,
    modelID: String? = nil,
    pricing: ModelTokenPricing? = nil
  ) {
    self.input = max(0, input); self.output = max(0, output)
    self.cached = min(max(0, cached), max(0, input)); self.estimated = estimated
    self.modelID = modelID; self.pricing = pricing
  }
}
/// Model output kept separate from action policy and integration outcomes.
public struct Verdict: Codable, Sendable, Equatable {
  private static let oversizedContextConfidence = 50
  /**
   The Review verdict for a message whose context exceeds every prompt limit.

   Senders control that size, so it is weak Junk evidence: the message reaches Review rather
   than staying unclassified.
   */
  public static var oversizedContext: Self {
    Self(
      label: .review,
      confidence: oversizedContextConfidence,
      reason: String(
        localized: "The message is too large to classify, which is weak junk evidence.",
        bundle: .module
      )
    )
  }
  /// The explicit Inbox, Review, or Junk label.
  public var label: MailLabel
  /// Uncalibrated model confidence on the integer scale 0 through 100.
  public var confidence: Int
  /// Short explanation of the evidence or policy behind this result.
  public var reason: String
  /// Provider token counts with explicit measurement provenance.
  public var usage: TokenUsage
  /// Creates a verdict, truncating `reason` to 240 characters; ``validated()`` checks the result.
  public init(label: MailLabel, confidence: Int, reason: String, usage: TokenUsage = .init()) {
    self.label = label; self.confidence = confidence
    self.reason = String(reason.prefix(ClassificationLimits.maximumReasonCharacters))
    self.usage = usage
  }

  /// Rejects confidence outside 0 through 100 and empty explanations.
  public func validated() throws -> Self {
    guard ClassificationLimits.confidenceRange.contains(confidence),
      !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw ClassificationError.invalidOutput }
    return self
  }
}
/// A bounded quotation of an explicit user correction.
public struct CorrectionExample: Codable, Sendable, Equatable, Identifiable {
  private static let maximumSenderScalars = 254
  private static let maximumSubjectScalars = 100
  private static let maximumExcerptScalars = 160
  /// Stable identity used for persistence and presentation.
  public var id = UUID()
  /// Timestamp when this record was created.
  public var date: Date = .now
  /// Sender address used for local retrieval and rules; prompts carry only its domain.
  public var sender: String
  /// Registrable sender domain quoted in this correction.
  public var domain: String?
  /// Decoded message subject.
  public var subject: String
  /// Bounded excerpt of the corrected message's text; empty when the text was unavailable.
  public private(set) var excerpt: String
  /// The explicit Inbox, Review, or Junk label.
  public var label: MailLabel
  /// Content identity for forgetting an explicitly linked training example.
  public var sampleID: String?
  /// Mail whose prompts may quote this example; nil examples are never quoted.
  public var promptScope: PromptScope?
  /// Creates a correction example, bounding the quoted sender, subject and excerpt.
  public init(
    sender: String,
    domain: String?,
    subject: String,
    excerpt: String,
    label: MailLabel,
    promptScope: PromptScope?
  ) {
    self.sender = sender.prefix(unicodeScalars: Self.maximumSenderScalars); self.domain = domain
    self.subject = subject.prefix(unicodeScalars: Self.maximumSubjectScalars)
    self.excerpt = excerpt.prefix(unicodeScalars: Self.maximumExcerptScalars); self.label = label
    self.promptScope = promptScope
  }
  /// Replaces the excerpt with the bounded start of the corrected message's text.
  public mutating func quote(_ text: String) {
    excerpt = text.prefix(unicodeScalars: Self.maximumExcerptScalars)
  }
  /// Whether a prompt for mail in `accountID` may quote this example.
  public func isQuotable(inAccount accountID: String?) -> Bool {
    switch promptScope {
      case .everyAccount: true
      case .account(let scope): scope == accountID
      case nil: false
    }
  }
  /// The mail whose classification prompts may quote a correction example.
  public enum PromptScope: Codable, Sendable, Equatable {
    /// Only mail from the account in which the correction was made.
    case account(String)
    /// Mail from any account, for explicitly imported reviewed examples.
    case everyAccount
  }
  private enum CodingKeys: String, CodingKey {
    case id, date, sender, domain, subject, label, sampleID, promptScope
    case excerpt = "gist"
  }
}
/// Message, evidence, preferences, and resource limits for one classification.
public struct ClassificationInput: Sendable {
  /// Parsed message supplied to this operation.
  public var message: ParsedMessage
  /// Signals available when the decision was made.
  public var evidence: EvidenceBundle
  /// The user's bounded plain-English filtering preferences.
  public var policy: String
  /// Explicit user corrections, most relevant first, quoted as examples.
  public var corrections: [CorrectionExample]
  /// Maximum number of correction examples included in a prompt.
  public var correctionLimit: Int
  /// Approximate body budget, using four characters per token.
  public var bodyTokenBudget: Int
  /// Maximum operation duration in seconds.
  public var timeout: TimeInterval
  /**
   Creates classification input, clamping each limit to its supported range.

   `correctionLimit` is clamped to 0 through 20 examples, `bodyTokenBudget` to 100 through 4,000
   tokens and `timeout` to 0.01 through 15 seconds.
   */
  public init(
    message: ParsedMessage,
    evidence: EvidenceBundle,
    policy: String = PromptBuilder.defaultPolicy,
    corrections: [CorrectionExample] = [],
    correctionLimit: Int = 5,
    bodyTokenBudget: Int = 1500,
    timeout: TimeInterval = 15
  ) {
    self.message = message; self.evidence = evidence; self.policy = policy
    self.corrections = corrections
    self.correctionLimit = ClassificationLimits.correctionLimitRange.clamp(correctionLimit)
    self.bodyTokenBudget = ClassificationLimits.bodyTokenBudgetRange.clamp(bodyTokenBudget)
    self.timeout = ClassificationLimits.timeoutRange.clamp(timeout)
  }
}
/// Asynchronous classification contract shared by live and offline backends.
public protocol Classifier: Sendable {
  /// Produces a verdict from bounded message context without performing a mail action.
  func classify(_ input: ClassificationInput) async throws -> Verdict
}
/// Deterministic or injected classification behavior for offline verification.
public struct MockClassifier: Classifier {
  private let operation: @Sendable (ClassificationInput) async throws -> Verdict
  /// Creates a classifier that returns `verdict` for every input, validating it on each call.
  public init(verdict: Verdict) { operation = { _ in verdict } }
  /// Creates a classifier that runs `operation` for each input and validates the verdict it returns.
  public init(operation: @escaping @Sendable (ClassificationInput) async throws -> Verdict) {
    self.operation = operation
  }
  /// Produces a validated verdict or throws without requesting a mail action.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    try await operation(input).validated()
  }
}
/// Failures while preparing or executing a classification request.
public protocol ClassificationFailure: Error {}

/// A classification failure that leaves the message unchanged.
public enum ClassificationError: String, ClassificationFailure, Codable, Sendable, LocalizedError {
  /// No acceptable provider credential is available.
  case missingCredential = "missingCredential"
  /// The selected provider or model configuration is unavailable.
  case configuration
  /// The user has not allowed this provider to receive private mail context.
  case consentRequired = "consentRequired"
  /// The provider refused a request because of a rate limit.
  case rateLimited = "rateLimited"
  /// The operation exceeded its deadline.
  case timeout
  /// The provider could not be reached.
  case network
  /// The bounded prompt or model context limit was exceeded.
  case contextExceeded = "contextExceeded"
  /// The provider declined to generate a classification.
  case refused
  /// The provider response did not satisfy the verdict contract.
  case invalidOutput = "invalidOutput"
  /// The caller cancelled classification.
  case cancelled
  /// Whether a transient classification failure is eligible for bounded retry.
  public var retryable: Bool { [.rateLimited, .timeout, .network].contains(self) }
  /// A non-sensitive description suitable for presentation.
  public var errorDescription: String? {
    String(localized: "Classification is unavailable. Mail was left unchanged.", bundle: .module)
  }
  /// The non-sensitive cause of the failed classification.
  public var failureReason: String? {
    switch self {
      case .missingCredential:
        String(localized: "The provider credential is missing or invalid.", bundle: .module)
      case .configuration:
        String(localized: "The selected model configuration is unavailable.", bundle: .module)
      case .consentRequired:
        String(
          localized:
            "Allow mail sharing with the selected provider in Settings → Classifier first.",
          bundle: .module
        )
      case .rateLimited:
        String(localized: "The provider’s request limit was reached.", bundle: .module)
      case .timeout: String(localized: "The classification deadline expired.", bundle: .module)
      case .network: String(localized: "The provider could not be reached.", bundle: .module)
      case .contextExceeded:
        String(localized: "The message context exceeds the classification limit.", bundle: .module)
      case .refused:
        String(localized: "The provider declined to classify the message.", bundle: .module)
      case .invalidOutput:
        String(localized: "The provider returned an invalid classification.", bundle: .module)
      case .cancelled: String(localized: "Classification was cancelled.", bundle: .module)
    }
  }
}

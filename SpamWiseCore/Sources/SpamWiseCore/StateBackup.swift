public import Foundation
import CryptoKit

/// Failures while authenticating or validating a portable backup.
public protocol BackupFailure: Error {}

/// Invalid or unsupported backup data, including a mismatched recovery key.
public enum BackupError: BackupFailure, LocalizedError, Sendable {
  /// The archive, recovery key or schema cannot be accepted.
  case invalidArchive
  /// General explanation without leaking decrypted content.
  public var errorDescription: String? {
    String(localized: "The backup could not be opened.", bundle: .module)
  }
  /// Describes the authentication or format requirement.
  public var failureReason: String? {
    String(
      localized: "Use the matching recovery key and a supported SpamWise backup.",
      bundle: .module
    )
  }
}

/// Encrypted portable learning state; excludes credentials, action claims and account validation.
public enum StateBackup {
  /// The largest backup file, in bytes, that ``restore(_:recoveryKey:store:)`` reads.
  public static let maximumBytes = 64 * 1024 * 1024
  private static let keyBytes = 32
  private static let readableVersions = 1...Payload.currentVersion
  private static let slices = StateSlices(
    [.rules, .contentRules, .corrections, .learning, .undo],
    reviewedLabels: .all
  )
  private static let authentication = Data("SpamWise-backup-v1".utf8)

  /// Generates an independent recovery key to keep separately from the backup file.
  public static func recoveryKey() -> String {
    unsafe SymmetricKey(size: .bits256).withUnsafeBytes { bytes in
      unsafe Data(bytes).base64EncodedString()
    }
  }
  /// Reads the portable state from `store` and encrypts it.
  public static func export(store: Store, recoveryKey: String, includeContent: Bool = false)
    async throws -> Data
  {
    try export(
      await StateRepository.load(store, slices),
      recoveryKey: recoveryKey,
      includeContent: includeContent
    )
  }
  /**
   Encrypts settings and learning, with retained message text and correction excerpts only when
   `includeContent` is set.
   */
  public static func export(_ state: AppState, recoveryKey: String, includeContent: Bool = false)
    throws -> Data
  {
    let options = state.settings.advancedOptions
    let payload = Payload(
      policy: state.settings.policy,
      categoryPreferences: state.settings.categoryPreferences,
      strength: state.settings.strength,
      review: state.settings.review,
      rules: state.rules,
      corrections: includeContent ? state.corrections : state.corrections.map(withoutExcerpt),
      labels: includeContent ? state.reviewedLabels : state.reviewedLabels.map(withoutMessage),
      learning: state.learning,
      contentRules: state.contentRules,
      trustExclusions: state.settings.mailOptions.trustExclusions,
      learningOptions: LearningOptions(
        fingerprints: options.fingerprints,
        bayes: options.bayes,
        learnedWeights: options.learnedWeights
      )
    )
    let data = try JSONEncoder().encode(payload)
    guard data.count <= maximumBytes else { throw BackupError.invalidArchive }
    return try AES.GCM.seal(data, using: key(recoveryKey), authenticating: authentication).combined!
  }
  /**
   Authenticates and validates the whole archive before replacing portable state atomically.

   This Mac keeps its choice of whether to retain reviewed message text, so the backup's text is
   restored only while that setting is on. A version-one backup has no trust exclusions or
   learning options, so restoring one keeps this Mac's.
   */
  public static func restore(_ data: Data, recoveryKey: String, store: Store) async throws {
    let payload: Payload
    do {
      guard data.count <= maximumBytes else { throw BackupError.invalidArchive }
      let plain = try AES.GCM.open(
        AES.GCM.SealedBox(combined: data),
        using: key(recoveryKey),
        authenticating: authentication
      )
      payload = try JSONDecoder().decode(Payload.self, from: plain)
      try validate(payload)
    } catch { throw BackupError.invalidArchive }
    try await StateRepository.update(store, loading: slices) { state in
      state.rules = payload.rules
      state.contentRules = payload.contentRules ?? []
      let ruleIDs = Set(state.contentRules.map(\.id))
      state.contentRuleHits = state.contentRuleHits.filter { ruleIDs.contains($0.key) }
      state.contentRuleSkips = state.contentRuleSkips.filter { ruleIDs.contains($0.key) }
      state.corrections = payload.corrections
      state.learning = payload.learning ?? LearningState()
      state.reviewedLabels =
        state.settings.advancedOptions.retainReviewedContent
        ? payload.labels : payload.labels.map(withoutMessage)
      state.settings.policy =
        PromptBuilder.formerDefaultPolicies.contains(payload.policy)
        ? PromptBuilder.defaultPolicy : payload.policy
      state.settings.categoryPreferences = payload.categoryPreferences ?? .defaults
      state.settings.strength = payload.strength
      state.settings.review = payload.review
      if let exclusions = payload.trustExclusions {
        state.settings.mailOptions.trustExclusions = exclusions
      }
      payload.learningOptions?.apply(to: &state.settings.advancedOptions)
      state.settings.paused = true
      state.settings.dryRun = true
      state.settings.validatedAccounts = []
      state.invalidatePendingWork(.backupRestored)
    }
  }
  private static func key(_ encoded: String) throws -> SymmetricKey {
    guard let bytes = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
      bytes.count == keyBytes
    else {
      throw BackupError.invalidArchive
    }
    return SymmetricKey(data: bytes)
  }
  private static func validate(_ payload: Payload) throws {
    guard readableVersions.contains(payload.version),
      payload.rules.count <= RetentionLimits.senderRules,
      payload.corrections.count <= RetentionLimits.corrections,
      payload.labels.count <= RetentionLimits.reviewedLabels,
      payload.policy.count <= RetentionLimits.policyCharacters,
      Set(payload.rules.map(\.id)).count == payload.rules.count,
      Set(payload.corrections.map(\.id)).count == payload.corrections.count,
      Set(payload.labels.map(\.id)).count == payload.labels.count,
      payload.trustExclusions.map(TrustExclusions.isValid) ?? true
    else { throw BackupError.invalidArchive }
    for rule in payload.rules {
      guard try RuleManagement.normalized(rule.value, scope: rule.scope) == rule.value else {
        throw BackupError.invalidArchive
      }
    }
    try ContentRuleManagement.validate(payload.contentRules ?? [])
    try validate(payload.corrections, labels: payload.labels)
    for label in payload.labels {
      if let message = label.message {
        guard message == message.boundedForRetention(),
          label.sampleID == LearningSample.identity(for: message)
        else { throw BackupError.invalidArchive }
      }
    }
  }
  /// Requires bounded corrections, quoting every account's mail only for a restored reviewed label.
  private static func validate(_ corrections: [CorrectionExample], labels: [ReviewedLabel]) throws {
    let sampleIDs = Set(labels.map(\.linkedSampleID))
    for correction in corrections {
      guard correction.isBounded else { throw BackupError.invalidArchive }
      if correction.promptScope == .everyAccount {
        guard let sampleID = correction.sampleID, sampleIDs.contains(sampleID) else {
          throw BackupError.invalidArchive
        }
      }
    }
  }
  private static func withoutMessage(_ label: ReviewedLabel) -> ReviewedLabel {
    var label = label
    label.message = nil
    return label
  }
  private static func withoutExcerpt(_ correction: CorrectionExample) -> CorrectionExample {
    var correction = correction
    correction.quote("")
    return correction
  }
  private struct Payload: Codable {
    static let currentVersion = 2
    var version = currentVersion
    var policy: String
    var categoryPreferences: CategoryPreferences?
    var strength: FilteringStrength
    var review: ReviewTreatment
    var rules: [SenderRule]
    var corrections: [CorrectionExample]
    var labels: [ReviewedLabel]
    var learning: LearningState?
    var contentRules: [ContentRule]?
    /// Addresses excluded from relationship trust; absent from version-one backups.
    var trustExclusions: Set<String>?
    /// Which learned signals are enabled; absent from version-one backups.
    var learningOptions: LearningOptions?
  }
  /// The optional learned signals a backup turns on or off.
  private struct LearningOptions: Codable {
    var fingerprints: Bool
    var bayes: Bool
    var learnedWeights: Bool

    func apply(to options: inout AdvancedSettings) {
      options.fingerprints = fingerprints; options.bayes = bayes
      options.learnedWeights = learnedWeights
    }
  }
}

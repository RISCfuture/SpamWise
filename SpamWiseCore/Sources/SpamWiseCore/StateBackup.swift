public import Foundation
import CryptoKit

/// Failures while authenticating or validating a portable backup.
public protocol BackupFailure: Error {}

/// Invalid or unsupported backup data, including a mismatched recovery key.
public enum BackupError: BackupFailure, LocalizedError, Sendable {
  /// The archive, recovery key or schema cannot be accepted.
  case invalidArchive
  /// General explanation without leaking decrypted content.
  public var errorDescription: String? { String(localized: "The backup could not be opened.") }
  /// Describes the authentication or format requirement.
  public var failureReason: String? {
    String(localized: "Use the matching recovery key and a supported SpamWise backup.")
  }
}

/// Encrypted portable learning state; excludes credentials, action claims and account validation.
public enum StateBackup {
  private static let maximumBytes = 64 * 1024 * 1024
  private static let keyBytes = 32
  private static let maximumRules = 10_000
  private static let maximumCorrections = 200
  private static let maximumLabels = 500
  private static let maximumPolicyCharacters = 8000
  private static let maximumMessageCharacters = 16_000
  private static let authentication = Data("SpamWise-backup-v1".utf8)

  /// Generates an independent recovery key to keep separately from the backup file.
  public static func recoveryKey() -> String {
    unsafe SymmetricKey(size: .bits256).withUnsafeBytes { bytes in
      unsafe Data(bytes).base64EncodedString()
    }
  }
  /// Encrypts settings and learning with optional explicitly retained message content.
  public static func export(_ state: AppState, recoveryKey: String, includeContent: Bool = false)
    throws -> Data
  {
    var labels = state.reviewedLabels ?? []
    if !includeContent {
      labels = labels.map {
        var label = $0; label.message = nil; return label
      }
    }
    let payload = Payload(
      policy: state.settings.policy,
      strength: state.settings.strength,
      review: state.settings.review,
      rules: state.rules,
      corrections: state.corrections,
      labels: labels,
      learning: state.learning,
      contentRules: state.contentRules
    )
    let data = try JSONEncoder().encode(payload)
    guard data.count <= maximumBytes else { throw BackupError.invalidArchive }
    return try AES.GCM.seal(data, using: key(recoveryKey), authenticating: authentication).combined!
  }
  /// Authenticates and validates the whole archive before replacing portable state atomically.
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
    try await StateRepository.update(store) { state in
      state.rules = payload.rules
      state.contentRules = payload.contentRules
      state.corrections = payload.corrections
      state.learning = payload.learning
      state.reviewedLabels = payload.labels
      state.settings.policy = payload.policy
      state.settings.strength = payload.strength
      state.settings.review = payload.review
      state.settings.advancedOptions.retainReviewedContent = payload.labels.contains {
        $0.message != nil
      }
      state.settings.paused = true
      state.settings.dryRun = true
      state.settings.validatedAccounts = []
      state.settings.route = .unverified
      state.retries = []
      state.revision += 1
    }
  }
  private static func key(_ encoded: String) throws -> SymmetricKey {
    guard let bytes = Data(base64Encoded: encoded), bytes.count == keyBytes else {
      throw BackupError.invalidArchive
    }
    return SymmetricKey(data: bytes)
  }
  private static func validate(_ payload: Payload) throws {
    guard payload.version == 1, payload.rules.count <= maximumRules,
      payload.corrections.count <= maximumCorrections, payload.labels.count <= maximumLabels,
      payload.policy.count <= maximumPolicyCharacters,
      Set(payload.rules.map(\.id)).count == payload.rules.count,
      Set(payload.labels.map(\.id)).count == payload.labels.count
    else { throw BackupError.invalidArchive }
    for rule in payload.rules {
      guard try RuleManagement.normalized(rule.value, scope: rule.scope) == rule.value else {
        throw BackupError.invalidArchive
      }
    }
    guard (payload.contentRules?.count ?? 0) <= 100 else { throw BackupError.invalidArchive }
    for rule in payload.contentRules ?? [] { try ContentRules.validate(rule) }
    for label in payload.labels {
      if let message = label.message {
        guard message.text.count <= maximumMessageCharacters,
          label.sampleID == LearningSample.identity(for: message)
        else { throw BackupError.invalidArchive }
      }
    }
  }
  private struct Payload: Codable {
    var version = 1
    var policy: String
    var strength: FilteringStrength
    var review: ReviewTreatment
    var rules: [SenderRule]
    var corrections: [CorrectionExample]
    var labels: [ReviewedLabel]
    var learning: LearningState?
    var contentRules: [ContentRule]?
  }
}

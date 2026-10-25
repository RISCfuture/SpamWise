import Signals

/**
 Bounded numeric evidence features for the regularized logistic estimator.

 Features persist by name, so adding a property never shifts the meaning of an
 existing value: a sample recorded before the property existed reads it as zero.
 Increment ``schemaVersion`` and migrate older versions in `init(from:)` whenever an
 existing feature changes meaning; samples older than the minimum readable version are dropped.

 Domain age and trusted authentication depend on the receiving account's settings, so a
 sample recorded without that account, such as an imported message, holds zero for them and
 is marked as lacking account context.
 */
public struct LearningFeatures: Codable, Sendable, Equatable {
  /// Schema version of features recorded by this build.
  public static let schemaVersion = 2
  /// Oldest schema version whose samples are read; samples recorded under an older one are dropped.
  private static let minimumReadableVersion = 2
  /// Position of the constant intercept input in ``vector``.
  static let biasIndex = 0
  private static let bias = 1.0
  private static let youngDomainAgeDays = 30
  private static let saturatedLinkDomainCount = 10.0
  private static let valueRange = 0.0...1.0
  /// Schema version under which these values were recorded.
  public let version: Int
  /// One when the sender's top-level domain is abuse-heavy.
  public let abuseHeavyTLD: Double
  /// One when the sender's domain is known to be registered within the last 30 days.
  public let youngDomain: Double
  /// One when the sender's domain registration age is unknown.
  public let unknownDomainAge: Double
  /// One when a trusted authentication server reports a failure or soft failure.
  public let trustedAuthenticationFailure: Double
  /// One when Reply-To and From resolve to different registrable domains.
  public let replyToMismatch: Double
  /// One when the message has a List-Unsubscribe header.
  public let listUnsubscribe: Double
  /// Distinct link domains, saturating at one for ten or more.
  public let linkDomainDensity: Double
  /// Whether the domain-age and trusted-authentication features reflect a receiving account.
  public let hasAccountContext: Bool

  /// Whether the values were recorded under a readable schema and each is finite and within the bounded unit range.
  var isValid: Bool {
    version >= Self.minimumReadableVersion
      && vector().allSatisfy { $0.isFinite && Self.valueRange.contains($0) }
  }

  private static func indicator(_ condition: Bool) -> Double { condition ? 1 : 0 }

  /**
   Estimator inputs, beginning with the unregularized bias term at ``biasIndex``.

   - Parameter accountContext: Whether to include the features that depend on the receiving
     account; excluded features are zero.
   */
  func vector(accountContext: Bool = true) -> [Double] {
    let context = accountContext ? 1.0 : 0
    return [
      Self.bias, abuseHeavyTLD, youngDomain * context, unknownDomainAge * context,
      trustedAuthenticationFailure * context, replyToMismatch, listUnsubscribe, linkDomainDensity
    ]
  }
}

extension LearningFeatures {
  /**
   Derives the current schema's features from classification evidence.

   - Parameter hasAccountContext: Whether `evidence` was gathered for a receiving account;
     without one, the features that depend on it are zero.
   */
  init(_ evidence: EvidenceBundle, hasAccountContext: Bool = true) {
    version = Self.schemaVersion
    self.hasAccountContext = hasAccountContext
    abuseHeavyTLD = Self.indicator(evidence.tldIsAbuseHeavy)
    youngDomain = Self.indicator(
      hasAccountContext
        && evidence.domainAgeDays.map { (0..<Self.youngDomainAgeDays).contains($0) } ?? false
    )
    unknownDomainAge = Self.indicator(hasAccountContext && evidence.domainAgeDays == nil)
    trustedAuthenticationFailure = Self.indicator(
      hasAccountContext
        && evidence.authResults.contains { $0.trusted && ["fail", "softfail"].contains($0.result) }
    )
    replyToMismatch = Self.indicator(
      evidence.replyToDomain != nil && evidence.fromDomain != nil
        && evidence.replyToDomain != evidence.fromDomain
    )
    listUnsubscribe = Self.indicator(evidence.listUnsubscribePresent)
    linkDomainDensity = min(1, Double(evidence.linkDomains.count) / Self.saturatedLinkDomainCount)
  }

  /// Decodes named features, zero-filling absent values; a sample without the account-context mark has account context.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    func value(_ key: CodingKeys) throws -> Double {
      try values.decodeIfPresent(Double.self, forKey: key) ?? 0
    }
    self.init(
      version: try values.decode(Int.self, forKey: .version),
      abuseHeavyTLD: try value(.abuseHeavyTLD),
      youngDomain: try value(.youngDomain),
      unknownDomainAge: try value(.unknownDomainAge),
      trustedAuthenticationFailure: try value(.trustedAuthenticationFailure),
      replyToMismatch: try value(.replyToMismatch),
      listUnsubscribe: try value(.listUnsubscribe),
      linkDomainDensity: try value(.linkDomainDensity),
      hasAccountContext: try values.decodeIfPresent(Bool.self, forKey: .hasAccountContext) ?? true
    )
  }

  private enum CodingKeys: String, CodingKey {
    case version, abuseHeavyTLD, youngDomain, unknownDomainAge, trustedAuthenticationFailure
    case replyToMismatch, listUnsubscribe, linkDomainDensity, hasAccountContext
  }
}

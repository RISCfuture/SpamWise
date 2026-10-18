import Signals

/**
 Bounded numeric evidence features for the regularized logistic estimator.

 Features persist by name, so adding a property never shifts the meaning of an
 existing value: a sample recorded before the property existed reads it as zero.
 Samples persisted as schema version one, a positional eight-element vector that
 begins with the bias term, migrate by position. Increment ``schemaVersion`` and
 migrate older versions in `init(from:)` whenever an existing feature changes
 meaning.
 */
public struct LearningFeatures: Codable, Sendable, Equatable {
  /// Schema version of features recorded by this build.
  public static let schemaVersion = 2
  /// Position of the constant intercept input in ``vector``.
  static let biasIndex = 0
  private static let bias = 1.0
  private static let legacySchemaVersion = 1
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

  /// Estimator inputs, beginning with the unregularized bias term at ``biasIndex``.
  var vector: [Double] {
    [
      Self.bias, abuseHeavyTLD, youngDomain, unknownDomainAge, trustedAuthenticationFailure,
      replyToMismatch, listUnsubscribe, linkDomainDensity
    ]
  }

  /// Whether every value is finite and within the bounded unit range.
  var isValid: Bool {
    version >= Self.legacySchemaVersion
      && vector.allSatisfy { $0.isFinite && Self.valueRange.contains($0) }
  }

  private static func indicator(_ condition: Bool) -> Double { condition ? 1 : 0 }
}

extension LearningFeatures {
  /// Derives the current schema's features from classification evidence.
  init(_ evidence: EvidenceBundle) {
    version = Self.schemaVersion
    abuseHeavyTLD = Self.indicator(evidence.tldIsAbuseHeavy)
    youngDomain = Self.indicator(
      evidence.domainAgeDays.map { (0..<Self.youngDomainAgeDays).contains($0) } ?? false
    )
    unknownDomainAge = Self.indicator(evidence.domainAgeDays == nil)
    trustedAuthenticationFailure = Self.indicator(
      evidence.authResults.contains { $0.trusted && ["fail", "softfail"].contains($0.result) }
    )
    replyToMismatch = Self.indicator(
      evidence.replyToDomain != nil && evidence.fromDomain != nil
        && evidence.replyToDomain != evidence.fromDomain
    )
    listUnsubscribe = Self.indicator(evidence.listUnsubscribePresent)
    linkDomainDensity = min(1, Double(evidence.linkDomains.count) / Self.saturatedLinkDomainCount)
  }

  /// Decodes named features, zero-filling absent values and migrating positional version-one vectors.
  public init(from decoder: any Decoder) throws {
    if let legacy = try? decoder.singleValueContainer().decode([Double].self) {
      self.init(legacyVector: legacy)
      return
    }
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
      linkDomainDensity: try value(.linkDomainDensity)
    )
  }

  private init(legacyVector legacy: [Double]) {
    func value(_ position: VersionOnePosition) -> Double {
      legacy.indices.contains(position.rawValue) ? legacy[position.rawValue] : 0
    }
    self.init(
      version: Self.legacySchemaVersion,
      abuseHeavyTLD: value(.abuseHeavyTLD),
      youngDomain: value(.youngDomain),
      unknownDomainAge: value(.unknownDomainAge),
      trustedAuthenticationFailure: value(.trustedAuthenticationFailure),
      replyToMismatch: value(.replyToMismatch),
      listUnsubscribe: value(.listUnsubscribe),
      linkDomainDensity: value(.linkDomainDensity)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case version, abuseHeavyTLD, youngDomain, unknownDomainAge, trustedAuthenticationFailure
    case replyToMismatch, listUnsubscribe, linkDomainDensity
  }

  private enum VersionOnePosition: Int {
    case bias, abuseHeavyTLD, youngDomain, unknownDomainAge, trustedAuthenticationFailure
    case replyToMismatch, listUnsubscribe, linkDomainDensity
  }
}

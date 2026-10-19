public import Foundation
import MessageModel

/// Optional evidence status, distinct from any mail classification or action.
public enum ExternalEvidenceStatus: String, Codable, Sendable {
  case unknown
  case notListed = "notListed"
  case listed
  case observed
}

/// Named origin of an optional evidence observation.
public enum EvidenceSource: String, Codable, Sendable {
  /// Spamhaus Domain Blocklist through public mirrors or the HTTPS service.
  case spamhausDBL = "Spamhaus DBL"
  /// The user's Rspamd scanner on the IPv4 loopback interface.
  case localRspamd = "Local Rspamd"
}

/// Bounded external observations for a classifier to interpret alongside trusted gates.
public struct ExternalEvidenceFinding: Codable, Sendable, Equatable {
  private static let maximumSubjectCharacters = 253
  private static let maximumDetails = 20
  private static let maximumDetailCharacters = 120
  /// Evidence source, such as Spamhaus DBL or local Rspamd.
  public let source: EvidenceSource
  /// Domain or message scope queried.
  public let subject: String
  /// Explicit success, listing, or unavailable status.
  public let status: ExternalEvidenceStatus
  /// Bounded returned codes or symbols, never an action directive.
  public let details: [String]

  /// Plain-text evidence suitable for an escaped, untrusted prompt field.
  public var summary: String {
    "\(source.rawValue) \(subject): \(status.rawValue)"
      + (details.isEmpty ? "" : " (\(details.joined(separator: "; ")))")
  }

  /// Creates a bounded observation.
  public init(
    source: EvidenceSource,
    subject: String,
    status: ExternalEvidenceStatus,
    details: [String] = []
  ) {
    self.source = source
    self.subject = String(subject.prefix(Self.maximumSubjectCharacters))
    self.status = status
    self.details = details.prefix(Self.maximumDetails).map {
      String($0.prefix(Self.maximumDetailCharacters))
    }
  }
}

/// Explicit service selection; a failed transport never falls back to another service.
public enum SpamhausTransport: String, Codable, Sendable {
  /// Public mirrors through a user-owned, attributable DNS resolver.
  case publicDNS = "publicDNS"
  /// Subscription or trial access to DNS Blocklists via HTTPS.
  case https
}

/// Explicit opt-in for domain-only Spamhaus DBL queries.
public struct SpamhausConfiguration: Codable, Sendable, Equatable {
  /// Official fair-use conditions that must be reviewed before enabling queries.
  public static let termsURL = URL(
    string: "https://www.spamhaus.org/blocklists/dnsbl-fair-use-policy/"
  )!
  /// User acknowledgement of eligibility and resolver requirements, not automatic eligibility verification.
  public var termsAcknowledged: Bool
  /// IPv4 address of the user's configured recursive resolver.
  public var resolverAddress: String
  /// Service selected independently of credentials and consent.
  public var transport: SpamhausTransport

  /// Defaults to disabled; DNS access requires a separately configured recursive resolver.
  public init(
    termsAcknowledged: Bool = false,
    resolverAddress: String = "127.0.0.1",
    transport: SpamhausTransport = .publicDNS
  ) {
    self.termsAcknowledged = termsAcknowledged; self.resolverAddress = resolverAddress
    self.transport = transport
  }
}

/// Domain and URI-host reputation using DBL only, with no IP-list queries or mail actions.
public struct SpamhausDomainLookup: Sendable {
  /// Injectable DNS A-record lookup receiving a validated absolute query name and resolver address.
  public typealias Query = @Sendable (String, String) async throws -> DNSAnswer
  /// Injectable HTTPS boundary receiving a domain, query key and remaining time.
  public typealias HTTPSQuery = @Sendable (String, String, Duration) async throws -> DNSAnswer
  /// Longest time any lookup may take, even when the caller allows more.
  public static let maximumQueryTime = Duration.seconds(3)
  private static let maximumDomainCandidates = 40
  private static let maximumQueries = 5
  private static let maximumDomainBytes = 253
  private static let maximumLabelCharacters = 63
  private static let maximumAnswerAddresses = 20
  private static let lowercaseLetters = UInt8(ascii: "a")...UInt8(ascii: "z")
  private static let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
  private static let hyphen = UInt8(ascii: "-"), dot = UInt8(ascii: ".")
  private let configuration: SpamhausConfiguration
  private let query: Query
  private let key: @Sendable () throws -> String
  private let httpsQuery: HTTPSQuery

  /// Installs service configuration, credential access and optional transport boundaries.
  public init(
    configuration: SpamhausConfiguration,
    query: Query? = nil,
    key: @escaping @Sendable () throws -> String = { throw URLError(.userAuthenticationRequired) },
    httpsQuery: HTTPSQuery? = nil
  ) {
    self.configuration = configuration
    self.query =
      query ?? { name, resolver in await ResolverQuery.addresses(of: name, resolver: resolver) }
    self.key = key
    self.httpsQuery =
      httpsQuery ?? { domain, key, timeout in
        try await SpamhausHTTPS.query(domain: domain, key: key, timeout: timeout)
      }
  }

  private static func validDomain(_ value: String) -> String? {
    let domain = value.lowercased()
    guard domain.utf8.count <= maximumDomainBytes, !domain.hasPrefix("-"),
      domain.utf8.allSatisfy({
        lowercaseLetters.contains($0) || digits.contains($0) || $0 == hyphen || $0 == dot
      }),
      domain.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
        !$0.isEmpty && $0.count <= maximumLabelCharacters && !$0.hasPrefix("-")
          && !$0.hasSuffix("-")
      }), DomainResolver().registrableDomain(domain) != nil
    else { return nil }
    return domain
  }

  private static func finding(domain: String, answer: DNSAnswer) -> ExternalEvidenceFinding {
    if answer.status == .notFound {
      return .init(source: .spamhausDBL, subject: domain, status: .notListed)
    }
    guard answer.status == .answered, !answer.addresses.isEmpty,
      answer.addresses.count <= maximumAnswerAddresses,
      answer.addresses.allSatisfy(SpamhausDBL.listingAddressSet.contains)
    else { return unknown(domain) }
    return .init(
      source: .spamhausDBL,
      subject: domain,
      status: .listed,
      details: Array(Set(answer.addresses)).sorted()
    )
  }

  private static func unknown(_ domain: String) -> ExternalEvidenceFinding {
    .init(source: .spamhausDBL, subject: domain, status: .unknown)
  }

  private static func truncation(skipped: Int) -> [ExternalEvidenceFinding] {
    guard skipped > 0 else { return [] }
    return [
      .init(
        source: .spamhausDBL,
        subject: "\(skipped) more domains",
        status: .unknown,
        details: ["truncated at the \(maximumQueries)-query limit"]
      )
    ]
  }

  /**
   Queries the first five distinct valid domains in the supplied priority order, within the
   caller's budget or ``maximumQueryTime``. Remaining candidates produce one truncation finding;
   transport and policy failures remain unknown.
   */
  public func lookup(domains: [String], timeout: TimeInterval? = nil) async
    -> [ExternalEvidenceFinding]
  {
    guard configuration.termsAcknowledged else { return [] }
    let candidates = domains.prefix(Self.maximumDomainCandidates).compactMap(Self.validDomain)
      .uniqued()
    let queried = Array(candidates.prefix(Self.maximumQueries))
    let truncation = Self.truncation(skipped: candidates.count - queried.count)
    let limit = Self.maximumQueryTime / .seconds(1), timeout = timeout ?? limit
    guard !Task.isCancelled, timeout.isFinite, timeout > 0 else {
      return queried.map(Self.unknown) + truncation
    }
    let budget = Duration.seconds(min(timeout, limit))
    let findings = await withTaskGroup(of: (Int, ExternalEvidenceFinding).self) { group in
      for (index, domain) in queried.enumerated() {
        group.addTask { (index, await finding(for: domain, timeout: budget)) }
      }
      var findings: [(Int, ExternalEvidenceFinding)] = []
      for await result in group { findings.append(result) }
      return findings.sorted { $0.0 < $1.0 }.map(\.1)
    }
    return findings + truncation
  }

  private func finding(for domain: String, timeout: Duration) async -> ExternalEvidenceFinding {
    do {
      let answer = try await withResourceDeadline(seconds: timeout / .seconds(1)) {
        try Task.checkCancellation()
        return try await answer(for: domain, timeout: timeout)
      }
      return Self.finding(domain: domain, answer: answer)
    } catch { return Self.unknown(domain) }
  }

  private func answer(for domain: String, timeout: Duration) async throws -> DNSAnswer {
    switch configuration.transport {
      case .publicDNS:
        guard ResolverQuery.address(configuration.resolverAddress) != nil else {
          return .init(status: .failed, addresses: [])
        }
        return try await query(domain + "." + SpamhausDBL.zone, configuration.resolverAddress)
      case .https:
        return try await httpsQuery(domain, key(), timeout)
    }
  }

  /// DNS result that distinguishes NXDOMAIN from resolver failure.
  public struct DNSAnswer: Sendable {
    /// Result status returned by the DNS boundary.
    public let status: Status
    /// Returned A records; only documented DBL listing codes count as evidence.
    public let addresses: [String]
    /// Creates a DNS boundary result.
    public init(status: Status, addresses: [String]) {
      self.status = status; self.addresses = addresses
    }
    /// DNS answer, NXDOMAIN, or transport/server failure.
    public enum Status: Sendable { case answered, notFound, failed }
  }
}

public import Foundation
import MessageModel

/// Optional evidence status, distinct from any mail classification or action.
public enum ExternalEvidenceStatus: String, Codable, Sendable {
  case unknown, notListed, listed, observed
}

/// Bounded external observations for a classifier to interpret alongside trusted gates.
public struct ExternalEvidenceFinding: Codable, Sendable, Equatable {
  private static let maximumSourceCharacters = 80
  private static let maximumSubjectCharacters = 253
  private static let maximumDetails = 20
  private static let maximumDetailCharacters = 120
  /// Evidence source, such as Spamhaus DBL or local Rspamd.
  public let source: String
  /// Domain or message scope queried.
  public let subject: String
  /// Explicit success, listing, or unavailable status.
  public let status: ExternalEvidenceStatus
  /// Bounded returned codes or symbols, never an action directive.
  public let details: [String]

  /// Plain-text evidence suitable for an escaped, untrusted prompt field.
  public var summary: String {
    "\(source) \(subject): \(status.rawValue)"
      + (details.isEmpty ? "" : " (\(details.joined(separator: "; ")))")
  }

  /// Creates a bounded observation.
  public init(
    source: String,
    subject: String,
    status: ExternalEvidenceStatus,
    details: [String] = []
  ) {
    self.source = String(source.prefix(Self.maximumSourceCharacters))
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
  case publicDNS
  /// Subscription or trial access to DNS Blocklists via HTTPS.
  case https
}

/// Explicit opt-in for domain-only Spamhaus DBL queries.
public struct SpamhausConfiguration: Codable, Sendable, Equatable {
  /// Official fair-use conditions that must be reviewed before enabling queries.
  public static let termsURL = "https://www.spamhaus.org/blocklists/dnsbl-fair-use-policy/"
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
  /// Injectable HTTPS boundary receiving a domain, query key and remaining timeout in seconds.
  public typealias HTTPSQuery = @Sendable (String, String, TimeInterval) async throws -> DNSAnswer
  private static let maximumDomainCandidates = 40
  private static let maximumQueries = 5
  private static let maximumDomainBytes = 253
  private static let maximumLabelCharacters = 63
  private static let maximumAnswerAddresses = 20
  private static let queryTimeoutSec: TimeInterval = 3
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
    self.configuration = configuration; self.query = query ?? Self.query
    self.key = key
    self.httpsQuery =
      httpsQuery ?? { domain, key, timeout in
        try await SpamhausHTTPS.query(domain: domain, key: key, timeout: timeout)
      }
  }

  private static func validIPv4(_ address: String) -> Bool {
    let pieces = address.split(separator: ".", omittingEmptySubsequences: false)
    return pieces.count == 4
      && pieces.allSatisfy { part in
        !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) } && UInt8(part) != nil
      }
  }

  private static func validDomain(_ value: String) -> String? {
    let domain = value.lowercased()
    guard domain.utf8.count <= maximumDomainBytes, !domain.hasPrefix("-"),
      domain.utf8.allSatisfy({
        (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46
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
      return .init(source: "Spamhaus DBL", subject: domain, status: .notListed)
    }
    let validCodes: Set<String> = [
      "127.0.1.2", "127.0.1.4", "127.0.1.5", "127.0.1.6",
      "127.0.1.102", "127.0.1.103", "127.0.1.104", "127.0.1.105", "127.0.1.106"
    ]
    guard answer.status == .answered, !answer.addresses.isEmpty,
      answer.addresses.count <= maximumAnswerAddresses,
      answer.addresses.allSatisfy(validCodes.contains)
    else {
      return .init(source: "Spamhaus DBL", subject: domain, status: .unknown)
    }
    return .init(
      source: "Spamhaus DBL",
      subject: domain,
      status: .listed,
      details: Array(Set(answer.addresses)).sorted()
    )
  }

  private static func query(name: String, resolver: String) async throws -> DNSAnswer {
    let data = try await EvidenceProcess.live.run(
      executable: "/usr/bin/dig",
      arguments: [
        "@" + resolver, name + ".", "A", "+time=2", "+tries=1", "+noall", "+answer", "+comments"
      ],
      input: Data()
    )
    let text = String(decoding: data, as: UTF8.self)
    if text.contains("status: NXDOMAIN,") { return .init(status: .notFound, addresses: []) }
    guard text.contains("status: NOERROR,") else { return .init(status: .failed, addresses: []) }
    let addresses = text.split(separator: "\n").compactMap { line -> String? in
      let fields = line.split(whereSeparator: \.isWhitespace)
      guard fields.count == 5, fields[0].lowercased() == name.lowercased() + ".",
        fields[2] == "IN", fields[3] == "A"
      else { return nil }
      return String(fields[4])
    }
    return .init(status: .answered, addresses: addresses)
  }

  /// Queries at most five distinct valid domains; transport and policy failures remain unknown.
  public func lookup(domains: [String], timeout: TimeInterval = 3) async
    -> [ExternalEvidenceFinding]
  {
    guard configuration.termsAcknowledged else { return [] }
    let domains = Set(domains.prefix(Self.maximumDomainCandidates).compactMap(Self.validDomain))
      .sorted().prefix(Self.maximumQueries)
    guard !Task.isCancelled, timeout.isFinite, timeout > 0 else {
      return domains.map { Self.finding(domain: $0, answer: .init(status: .failed, addresses: [])) }
    }
    let timeout = min(timeout, Self.queryTimeoutSec)
    return await withTaskGroup(of: ExternalEvidenceFinding.self) { group in
      for domain in domains {
        group.addTask {
          do {
            let answer: DNSAnswer = try await withResourceDeadline(seconds: timeout) {
              try Task.checkCancellation()
              switch configuration.transport {
                case .publicDNS:
                  guard Self.validIPv4(configuration.resolverAddress) else {
                    return .init(status: .failed, addresses: [])
                  }
                  return try await query(
                    domain + ".dbl.spamhaus.org",
                    configuration.resolverAddress
                  )
                case .https:
                  return try await httpsQuery(domain, key(), timeout)
              }
            }
            return Self.finding(domain: domain, answer: answer)
          } catch { return .init(source: "Spamhaus DBL", subject: domain, status: .unknown) }
        }
      }
      var findings: [ExternalEvidenceFinding] = []
      for await result in group { findings.append(result) }
      return findings.sorted { $0.subject < $1.subject }
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

import Foundation
public import MessageModel
import Contacts

/// An authentication claim and whether its reporting server is explicitly trusted.
public struct AuthResult: Codable, Sendable, Equatable {
  /// The claimed authentication service identifier.
  public var server: String
  /// The authentication method, such as SPF, DKIM, or DMARC.
  public var mechanism: String
  /// The reported authentication result.
  public var result: String
  /// Whether the reporting server is in the configured trust set.
  public var trusted: Bool
  /// The authenticated domain: DKIM `header.d`, DMARC `header.from` or SPF `smtp.mailfrom`;
  /// nil when absent or longer than a DNS name.
  public var domain: String?
}
/// How the reporting servers the user trusts authenticated the From domain.
public enum SenderAuthentication: Sendable, Equatable {
  /// A trusted DMARC pass, or a trusted DKIM pass aligned with the From domain.
  case alignedPass
  /// A trusted DMARC failure, or a trusted SPF or DKIM failure without an aligned pass.
  case failed
  /// No trusted result decides the From domain either way.
  case unverified
}
/// Optional evidence supplied to classification; missing values mean unknown.
public struct EvidenceBundle: Codable, Sendable, Equatable {
  private static let maximumLinkDomains = 20
  private static let maximumDisplayNameScalars = 256
  private static let maximumAuthResults = 20
  private static let maximumAuxiliaryFindings = 32
  private static let maximumFindingScalars = 1024
  private static let abuseHeavyTLDs: Set<String> = ["lat", "world", "top", "click", "xyz"]
  private static let findingsTruncation = "Evidence truncated: further findings omitted"
  private static let displayNameSeparators = CharacterSet.whitespaces.union(
    CharacterSet(charactersIn: "<>()[]\"',;:")
  )
  private static let lookalikeAtSigns = ["\u{FF20}", "\u{FE6B}"]
  private static let surroundingPunctuation = CharacterSet.alphanumerics.inverted
  /// Normalized sender email address.
  public var fromAddress: String
  /// Decoded sender display name, bounded to 256 Unicode scalars; this is an untrusted claim.
  public var fromDisplayName: String
  /**
   An address claimed in the From display name or comments at a registrable domain other than the
   sender's; a phishing signal.

   Claims at the sender's own registrable domain are excluded: forging one also forges that domain,
   which sender authentication evidence covers, and organizations commonly show one of their own
   addresses over another, such as a support address over a no-reply sender.
   */
  public var mismatchedDisplayNameAddress: String?
  /// Registrable domain of the sender, or nil if unresolved.
  public var fromDomain: String?
  /// Registrable domain of Reply-To, or nil if unresolved.
  public var replyToDomain: String?
  /// Registrable domain of Return-Path, or nil if unresolved.
  public var returnPathDomain: String?
  /// At most 20 parsed authentication claims with explicit trust status.
  public var authResults: [AuthResult]
  /// Sender's final domain label.
  public var tld: String?
  /// Weak TLD evidence that cannot decide a message on its own.
  public var tldIsAbuseHeavy: Bool
  /// Known registration age in days; nil means unknown.
  public var domainAgeDays: Int?
  /// At most 20 distinct registrable link domains, in the ranked order of the message's URLs.
  public var linkDomains: [String]
  /// Whether a List-Unsubscribe header exists; this is weak evidence.
  public var listUnsubscribePresent: Bool
  /// Account-scoped relationship evidence available for this sender.
  public var senderHistory: SenderHistory
  /// Whether the address is a contact; nil means permission or evidence unavailable.
  public var contact: Bool?
  /// Optional uncalibrated lexical evidence; absence means insufficient training or disabled.
  public var bayesLogOdds: Double?
  /// Optional regularized evidence margin; not a probability or standalone action instruction.
  public var learnedMargin: Double?
  /// Bounded optional local or network findings, treated as untrusted evidence.
  public private(set) var auxiliaryFindings: [String]?
  /**
   Whether the account has trusted receiving-server identifiers.

   False means no authentication result can be trusted, so every entry in ``authResults`` is an
   unverified claim. Nil on evidence recorded before trust was configurable.
   */
  public var trustedServersConfigured: Bool?
  /// The scope of an Allow rule that matched the sender without trusted authentication
  /// confirming it, so the rule reached the classifier as evidence instead of deciding the message.
  public var unconfirmedAllowRule: RuleScope?

  /// Sender, Reply-To and Return-Path domains, then link domains, without duplicates.
  public var reputationDomains: [String] {
    ([fromDomain, replyToDomain, returnPathDomain].compactMap(\.self) + linkDomains).uniqued()
  }

  /**
   Creates bounded evidence, recording a finding when a message field exceeds its limit.

   - Parameters:
     - message: The message to gather evidence from.
     - history: Known correspondence with the sender.
     - contact: Whether the sender is a contact; nil when unknown.
     - domainAgeDays: The sender domain's registration age in days; nil when unknown.
     - trustedAuthServers: Receiving-server identifiers of the message's account. Only
       their topmost Authentication-Results headers, or the receiving provider's ARC set that
       ``AuthenticationHeaders/trustedARCResults(_:trustedServers:)`` accepts, produce trusted
       results.
   */
  public init(
    message: ParsedMessage,
    history: SenderHistory = .init(),
    contact: Bool? = nil,
    domainAgeDays: Int? = nil,
    trustedAuthServers: Set<String> = []
  ) {
    let resolver = DomainResolver()
    let trustedServers = AuthenticationHeaders.normalized(trustedAuthServers)
    // Trusted ARC results come first, so the bound on results never drops them.
    let claims =
      AuthenticationHeaders.trustedARCResults(message.headers, trustedServers: trustedServers)
      + AuthenticationHeaders.parse(
        message.headers["authentication-results"] ?? [],
        trustedServers: trustedServers
      )
    let domains = message.urls.compactMap { URL(string: $0)?.host }
      .compactMap(resolver.registrableDomain).uniqued()
    fromAddress = message.fromAddress
    fromDisplayName = message.fromDisplayName.prefix(unicodeScalars: Self.maximumDisplayNameScalars)
    let fromDomain = resolver.domain(ofAddress: message.fromAddress)
    self.fromDomain = fromDomain
    mismatchedDisplayNameAddress = Self.claimedAddresses(
      in: message.fromDisplayName + " " + message.fromComments
    ).first {
      $0 != message.fromAddress
        && (fromDomain == nil || resolver.domain(ofAddress: $0) != fromDomain)
    }
    replyToDomain = message.header("reply-to").flatMap(MIMEParser.address).flatMap(resolver.domain)
    returnPathDomain = message.header("return-path").flatMap(MIMEParser.address).flatMap(
      resolver.domain
    )
    authResults = Array(claims.prefix(Self.maximumAuthResults))
    tld = fromDomain?.split(separator: ".").last.map(String.init)
    tldIsAbuseHeavy = tld.map(Self.abuseHeavyTLDs.contains) ?? false
    self.domainAgeDays = domainAgeDays
    linkDomains = Array(domains.prefix(Self.maximumLinkDomains))
    listUnsubscribePresent = message.header("list-unsubscribe") != nil
    senderHistory = history; self.contact = contact
    trustedServersConfigured = !trustedServers.isEmpty
    record(
      findings: Self.truncation(
        displayName: message.fromDisplayName.unicodeScalars.count > Self.maximumDisplayNameScalars,
        authResults: claims.count > Self.maximumAuthResults,
        linkDomains: domains.count > Self.maximumLinkDomains
      )
    )
  }

  private static func truncation(displayName: Bool, authResults: Bool, linkDomains: Bool)
    -> [String]
  {
    let fields = [
      displayName ? "display name" : nil,
      authResults ? "authentication results" : nil,
      linkDomains ? "link domains" : nil
    ].compactMap(\.self)
    return fields.isEmpty ? [] : ["Evidence truncated: " + fields.joined(separator: ", ")]
  }

  private static func bounded(findings: [String]) -> [String] {
    guard findings.count > maximumAuxiliaryFindings else { return findings }
    return findings.filter { $0 != findingsTruncation }.prefix(maximumAuxiliaryFindings - 1)
      + [findingsTruncation]
  }

  private static func claimedAddresses(in displayName: String) -> [String] {
    lookalikeAtSigns.reduce(displayName) { $0.replacingOccurrences(of: $1, with: "@") }
      .components(separatedBy: displayNameSeparators)
      .compactMap { MIMEParser.address($0.trimmingCharacters(in: surroundingPunctuation)) }
  }

  /// Appends distinct findings, keeping at most 32 of up to 1,024 Unicode scalars each.
  public mutating func record(findings: [String]) {
    let truncated = findings.map { $0.prefix(unicodeScalars: Self.maximumFindingScalars) }
    let combined = ((auxiliaryFindings ?? []) + truncated).uniqued()
    auxiliaryFindings = combined.isEmpty ? nil : Self.bounded(findings: combined)
  }
}
/// Parses authentication claims without trusting arbitrary sender headers.
public enum AuthenticationHeaders {
  private static let maximumHeaders = 10
  private static let maximumServerCharacters = 253
  private static let maximumDomainBytes = 253
  private static let serverDelimiters = CharacterSet.whitespacesAndNewlines.union(
    CharacterSet(charactersIn: ";=")
  )
  private static let methodPattern =
    #"^\s*(spf|dkim|dmarc)\s*=\s*(pass|fail|softfail|neutral|none|temperror|permerror)\b"#
  private static let domainProperties = [
    "dkim": ["header.d", "header.i"], "dmarc": ["header.from"], "spf": ["smtp.mailfrom"]
  ]
  /**
   Parses SPF, DKIM, and DMARC claims with explicit reporting-server trust.

   Only the topmost header from each trusted server is trusted, and only while no untrusted or
   repeated server appears above it, because a sender can add lower headers naming any server.
   A header without a reporting-server identifier keeps its results, untrusted.
   */
  public static func parse(_ headers: [String], trustedServers: Set<String>) -> [AuthResult] {
    // Header claims remain untrusted by default; no recomputation of SPF/DKIM/DMARC.
    let reports = headers.prefix(maximumHeaders).map(report)
    let trusted = topmostTrusted(reports.map(\.server), trustedServers: normalized(trustedServers))
    return reports.indices.flatMap { index in
      reports[index].results.compactMap { field in
        result(field, server: reports[index].server, trusted: trusted[index])
      }
    }
  }
  /**
   The reporting servers of the contiguous topmost headers, where the receiving provider adds its
   own.

   The run ends at the first header without a server identifier or with a repeated one, because
   a sender can add lower headers naming any server.
   */
  public static func leadingServers(_ headers: [String]) -> [String] {
    var seen: Set<String> = []
    return Array(
      headers.prefix(maximumHeaders).map { report($0).server }
        .prefix { !$0.isEmpty && seen.insert($0).inserted }
    )
  }
  /// A lowercased reporting-server identifier, or nil when the text is not a single identifier.
  public static func normalizedServer(_ text: String) -> String? {
    let server = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !server.isEmpty, server.count <= maximumServerCharacters,
      server.rangeOfCharacter(from: serverDelimiters) == nil
    else { return nil }
    return server
  }
  /// Normalized reporting-server identifiers, dropping any that are not a single identifier.
  public static func normalized(_ servers: Set<String>) -> Set<String> {
    Set(servers.compactMap(normalizedServer))
  }
  /// Splits a header into its reporting server, empty when absent, and its result fields.
  static func report(_ header: String) -> (server: String, results: ArraySlice<String>) {
    let fields = header.lowercased().components(separatedBy: ";")
    guard captures(methodPattern, in: fields[0]) == nil else { return ("", fields[...]) }
    let token = fields[0].components(separatedBy: .whitespacesAndNewlines).first { !$0.isEmpty }
    return (token.flatMap(normalizedServer) ?? "", fields.dropFirst())
  }
  private static func topmostTrusted(_ servers: [String], trustedServers: Set<String>) -> [Bool] {
    var seen: Set<String> = [], leading = true
    return servers.map { server in
      leading =
        leading && !server.isEmpty && trustedServers.contains(server)
        && seen.insert(server).inserted
      return leading
    }
  }
  static func result(_ field: String, server: String, trusted: Bool) -> AuthResult? {
    guard let match = captures(methodPattern, in: field), match.count == 2 else { return nil }
    let domain = domainProperties[match[0], default: []].lazy
      .compactMap { captures(propertyPattern($0), in: field)?.first }
      .first?.split(separator: "@").last.map(String.init)
      .flatMap { $0.utf8.count <= maximumDomainBytes ? $0 : nil }
    return AuthResult(
      server: server,
      mechanism: match[0],
      result: match[1],
      trusted: trusted,
      domain: domain
    )
  }
  private static func propertyPattern(_ property: String) -> String {
    #"\b"# + NSRegularExpression.escapedPattern(for: property) + #"\s*=\s*([^\s;()]+)"#
  }
  private static func captures(_ pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    return (1..<match.numberOfRanges).compactMap { index in
      Range(match.range(at: index), in: text).map { String(text[$0]) }
    }
  }
}
extension EvidenceBundle {
  private static let failureResults: Set<String> = ["fail", "softfail"]
  /// Trusted authentication of the From domain; untrusted claims never decide it.
  public var senderAuthentication: SenderAuthentication {
    let trusted = authResults.filter(\.trusted)
    if trusted.contains(where: { $0.mechanism == "dmarc" && $0.result == "fail" }) {
      return .failed
    }
    if trusted.contains(where: { $0.result == "pass" && isAligned($0) }) { return .alignedPass }
    if trusted.contains(where: { Self.failureResults.contains($0.result) }) { return .failed }
    return .unverified
  }

  private func isAligned(_ result: AuthResult) -> Bool {
    guard ["dkim", "dmarc"].contains(result.mechanism), let fromDomain, let domain = result.domain
    else { return false }
    return DomainResolver().registrableDomain(domain) == fromDomain
  }
}
/// Reads contact email addresses only when permission is available.
public actor ContactsLookup {
  /// Creates a lookup that asks for Contacts access only when ``addresses(requestAccess:)`` requests it.
  public init() {}
  /// Returns known contact addresses, or nil when access is unavailable.
  public func addresses(requestAccess: Bool = false) async throws -> Set<String>? {
    let store = CNContactStore()
    if requestAccess && CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
      _ = try await store.requestAccess(for: .contacts)
    }
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
    var addresses: Set<String> = []
    unsafe try store.enumerateContacts(
      with: CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as any CNKeyDescriptor])
    ) { contact, _ in
      for email in contact.emailAddresses { addresses.insert(String(email.value).lowercased()) }
    }
    return addresses
  }
}

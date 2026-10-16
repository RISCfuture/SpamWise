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
}
/// Optional evidence supplied to classification; missing values mean unknown.
public struct EvidenceBundle: Codable, Sendable, Equatable {
  private static let maximumLinkDomains = 20
  /// Normalized sender email address.
  public var fromAddress: String
  /// Decoded sender display name; this is an untrusted claim.
  public var fromDisplayName: String
  /// Registrable domain of the sender, or nil if unresolved.
  public var fromDomain: String?
  /// Registrable domain of Reply-To, or nil if unresolved.
  public var replyToDomain: String?
  /// Registrable domain of Return-Path, or nil if unresolved.
  public var returnPathDomain: String?
  /// Parsed authentication claims with explicit trust status.
  public var authResults: [AuthResult]
  /// Sender's final domain label.
  public var tld: String?
  /// Weak TLD evidence that cannot decide a message on its own.
  public var tldIsAbuseHeavy: Bool
  /// Known registration age in days; nil means unknown.
  public var domainAgeDays: Int?
  /// Distinct registrable domains found in message URLs.
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
  public var auxiliaryFindings: [String]?
  /// Creates an EvidenceBundle with the supplied configuration.
  public init(
    message: ParsedMessage,
    history: SenderHistory = .init(),
    contact: Bool? = nil,
    domainAgeDays: Int? = nil,
    trustedAuthServers: Set<String> = []
  ) {
    let resolver = DomainResolver()
    fromAddress = message.fromAddress; fromDisplayName = message.fromDisplayName
    fromDomain = resolver.domain(ofAddress: message.fromAddress)
    replyToDomain = message.header("reply-to").flatMap(MIMEParser.address).flatMap(resolver.domain)
    returnPathDomain = message.header("return-path").flatMap(MIMEParser.address).flatMap(
      resolver.domain
    )
    authResults = AuthenticationHeaders.parse(
      message.headers["authentication-results"] ?? [],
      trustedServers: trustedAuthServers
    )
    tld = fromDomain?.split(separator: ".").last.map(String.init)
    tldIsAbuseHeavy = ["lat", "world", "top", "click", "xyz"].contains(tld ?? "")
    self.domainAgeDays = domainAgeDays
    linkDomains = Array(
      Set(message.urls.compactMap { URL(string: $0)?.host }.compactMap(resolver.registrableDomain))
    ).sorted().prefix(Self.maximumLinkDomains).map { $0 }
    listUnsubscribePresent = message.header("list-unsubscribe") != nil
    senderHistory = history; self.contact = contact
  }
}
/// Parses authentication claims without trusting arbitrary sender headers.
public enum AuthenticationHeaders {
  private static let maximumHeaders = 10
  /// Parses SPF, DKIM, and DMARC claims with explicit reporting-server trust.
  public static func parse(_ headers: [String], trustedServers: Set<String>) -> [AuthResult] {
    // Header claims remain untrusted by default; no recomputation of SPF/DKIM/DMARC.
    headers.prefix(maximumHeaders).flatMap { header -> [AuthResult] in
      let fields = header.lowercased().components(separatedBy: ";")
      let server = (fields.first ?? "").trimmingCharacters(in: .whitespaces).components(
        separatedBy: " "
      )[0]
      let regex = try? NSRegularExpression(
        pattern:
          #"\b(spf|dkim|dmarc)\s*=\s*(pass|fail|softfail|neutral|none|temperror|permerror)\b"#
      )
      return
        (regex?.matches(
          in: header.lowercased(),
          range: NSRange(header.lowercased().startIndex..., in: header.lowercased())
        ) ?? []).map { match in
          let lower = header.lowercased()
          return AuthResult(
            server: server,
            mechanism: String(lower[Range(match.range(at: 1), in: lower)!]),
            result: String(lower[Range(match.range(at: 2), in: lower)!]),
            trusted: trustedServers.contains(server)
          )
        }
    }
  }
}
/// Reads contact email addresses only when permission is available.
public actor ContactsLookup {
  /// Creates a ContactsLookup with the supplied configuration.
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

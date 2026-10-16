import Foundation
import MessageModel
import Contacts

public struct AuthResult: Codable, Sendable, Equatable {
    public var server: String
    public var mechanism: String
    public var result: String
    public var trusted: Bool
}
public struct EvidenceBundle: Codable, Sendable, Equatable {
    public var fromAddress: String
    public var fromDisplayName: String
    public var fromDomain: String?
    public var replyToDomain: String?
    public var returnPathDomain: String?
    public var authResults: [AuthResult]
    public var tld: String?
    public var tldIsAbuseHeavy: Bool
    public var domainAgeDays: Int?
    public var linkDomains: [String]
    public var listUnsubscribePresent: Bool
    public var senderHistory: SenderHistory
    public var contact: Bool?
    public init(message: ParsedMessage, history: SenderHistory = .init(), contact: Bool? = nil, domainAgeDays: Int? = nil, trustedAuthServers: Set<String> = []) {
        let resolver = DomainResolver()
        fromAddress = message.fromAddress; fromDisplayName = message.fromDisplayName
        fromDomain = resolver.domain(ofAddress: message.fromAddress)
        replyToDomain = message.header("reply-to").flatMap(MIMEParser.address).flatMap(resolver.domain)
        returnPathDomain = message.header("return-path").flatMap(MIMEParser.address).flatMap(resolver.domain)
        authResults = AuthenticationHeaders.parse(message.headers["authentication-results"] ?? [], trustedServers: trustedAuthServers)
        tld = fromDomain?.split(separator: ".").last.map(String.init)
        tldIsAbuseHeavy = ["lat", "world", "top", "click", "xyz"].contains(tld ?? "")
        self.domainAgeDays = domainAgeDays
        linkDomains = Array(Set(message.urls.compactMap { URL(string: $0)?.host }.compactMap(resolver.registrableDomain))).sorted().prefix(20).map { $0 }
        listUnsubscribePresent = message.header("list-unsubscribe") != nil
        senderHistory = history; self.contact = contact
    }
}
public enum AuthenticationHeaders {
    public static func parse(_ headers: [String], trustedServers: Set<String>) -> [AuthResult] {
        // Header claims remain untrusted by default; no recomputation of SPF/DKIM/DMARC.
        headers.prefix(10).flatMap { header -> [AuthResult] in
            let fields = header.lowercased().components(separatedBy: ";")
            let server = (fields.first ?? "").trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]
            let regex = try? NSRegularExpression(pattern: #"\b(spf|dkim|dmarc)\s*=\s*(pass|fail|softfail|neutral|none|temperror|permerror)\b"#)
            return (regex?.matches(in: header.lowercased(), range: NSRange(header.lowercased().startIndex..., in: header.lowercased())) ?? []).map { match in
                let lower = header.lowercased()
                return AuthResult(server: server, mechanism: String(lower[Range(match.range(at: 1), in: lower)!]), result: String(lower[Range(match.range(at: 2), in: lower)!]), trusted: trustedServers.contains(server))
            }
        }
    }
}
public actor ContactsLookup {
    public init() {}
    public func addresses(requestAccess: Bool = false) async throws -> Set<String>? {
        let store = CNContactStore()
        if requestAccess && CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try await store.requestAccess(for: .contacts)
        }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
        var addresses: Set<String> = []
        try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor])) { contact, _ in
            for email in contact.emailAddresses { addresses.insert(String(email.value).lowercased()) }
        }
        return addresses
    }
}

import Foundation
import Testing
import SpamWiseCore
@Test func addressRulesBeatDomainAndTrustedGates() {
    let rules = [SenderRule(scope: .domain, value: "example.org", disposition: .allow), SenderRule(scope: .address, value: "jane@example.org", disposition: .block)]
    #expect(Gates.evaluate(address: "jane@example.org", domain: "example.org", rules: rules, contact: true, history: .init(replyCount: 2))?.disposition == .block)
    #expect(Gates.evaluate(address: "other@example.org", domain: "example.org", rules: rules, contact: false, history: .init())?.disposition == .allow)
}
@Test func latestCorrectionReplacesSameScope() {
    let old = SenderRule(scope: .address, value: "Jane@example.org", disposition: .block)
    let new = SenderRule(scope: .address, value: "jane@example.org", disposition: .allow)
    let rules = Gates.replacing(new, in: [old])
    #expect(rules.count == 1)
    #expect(rules.first?.disposition == .allow)
}
@Test func missingHistoryIsNeverAbsence() {
    let unknown = SenderHistory()
    #expect(unknown.summary.contains("unknown"))
    #expect(Gates.evaluate(address: "jane@example.org", domain: "example.org", rules: [], contact: nil, history: unknown) == nil)
    #expect(SenderHistory(availability: .complete).summary.contains("No prior"))
    #expect(Gates.evaluate(address: "jane@example.org", domain: "example.org", rules: [], contact: false, history: .init(replyCount: 1))?.disposition == .allow)
}
@Test func authenticationClaimsAndDomains() throws {
    let message = try MIMEParser().parse(fixture("filler-spam"))
    let evidence = EvidenceBundle(message: message)
    #expect(evidence.tldIsAbuseHeavy)
    #expect(evidence.domainAgeDays == nil)
    #expect(evidence.authResults.count == 3)
    #expect(evidence.authResults.allSatisfy { !$0.trusted })
    #expect(EvidenceBundle(message: message, trustedAuthServers: ["mx.example"]).authResults.allSatisfy { $0.trusted })
}
actor StubRDAP: HTTPFetcher {
    var calls = 0
    var fail: Bool
    init(fail: Bool = false) { self.fail = fail }
    func fetch(_ url: URL) async throws -> Data {
        calls += 1
        if fail { throw URLError(.timedOut) }
        if url.host == "data.iana.org" { return Data(#"{"services":[[["com"],["https://rdap.example/"]]]}"#.utf8) }
        return Data(#"{"events":[{"eventAction":"registration","eventDate":"2026-01-01T00:00:00Z"}]}"#.utf8)
    }
}
@Test func rdapCachesAndFailureIsUnknown() async {
    let network = StubRDAP(), lookup = RDAPLookup(fetcher: StubRDAP(fail: true))
    #expect(await lookup.ageDays(domain: "example.com") == nil)
    let rdap = RDAPLookup(fetcher: network)
    let now = ISO8601DateFormatter().date(from: "2026-01-11T00:00:00Z")!
    #expect(await rdap.ageDays(domain: "example.com", now: now) == 10)
    #expect(await rdap.ageDays(domain: "example.com", now: now) == 10)
    #expect(await network.calls == 2)
}
@Test func storesShareCommittedRulesAndRollback() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try Store(url: directory.appending(path: "state.store"))
    let second = try Store(url: directory.appending(path: "state.store"))
    try await first.update("rules", default: [SenderRule]()) { rules in
        rules = Gates.replacing(.init(scope: .address, value: "jane@example.org", disposition: .block), in: rules)
    }
    #expect(try await second.read("rules", default: [SenderRule]()).count == 1)
    do {
        try await second.update("rules", default: [SenderRule]()) { rules in rules = []; throw ParseError.malformed }
    } catch {}
    #expect(try await first.read("rules", default: [SenderRule]()).count == 1)
}

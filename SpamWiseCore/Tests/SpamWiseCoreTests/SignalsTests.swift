import Foundation
import Testing
import SpamWiseCore

private let precedenceRules = [
  SenderRule(scope: .domain, value: "example.org", disposition: .allow),
  SenderRule(scope: .address, value: "jane@example.org", disposition: .block),
  SenderRule(scope: .domain, value: "example.net", disposition: .block),
  SenderRule(scope: .address, value: "ann@example.net", disposition: .allow)
]

@Test(arguments: [
  (
    address: "jane@example.org", authentication: SenderAuthentication.unverified,
    expected: GateReason?.some(.senderRule(scope: .address, disposition: .block))
  ),
  ("other@example.org", .alignedPass, .senderRule(scope: .domain, disposition: .allow)),
  ("other@example.org", .unverified, nil),
  ("ann@example.net", .unverified, nil),
  ("ann@example.net", .alignedPass, .senderRule(scope: .address, disposition: .allow))
])
func `prioritizes address rules over domain and authenticated relationship gates`(
  address: String,
  authentication: SenderAuthentication,
  expected: GateReason?
) {
  let gate = Gates.evaluate(
    address: address,
    domain: DomainResolver().domain(ofAddress: address),
    rules: precedenceRules,
    contact: true,
    history: .init(replyCount: 2),
    authentication: authentication
  )
  #expect(gate?.reason == expected)
}

@Test
func `replaces same scope rules with the latest correction`() {
  let old = SenderRule(scope: .address, value: "Jane@example.org", disposition: .block)
  let new = SenderRule(scope: .address, value: "jane@example.org", disposition: .allow)
  let rules = Gates.replacing(new, in: [old])
  #expect(rules.count == 1)
  #expect(rules.first?.disposition == .allow)
}

@Test(arguments: [
  (SenderHistory(), "unknown"), (SenderHistory(availability: .complete), "No prior")
])
func `summarizes missing history without inventing a relationship`(
  history: SenderHistory,
  phrase: String
) {
  #expect(history.summary.contains(phrase))
}

@Test
func `leaves a sender with unknown contacts and history to the classifier`() {
  #expect(
    Gates.evaluate(
      address: "jane@example.org",
      domain: "example.org",
      rules: [],
      contact: nil,
      history: SenderHistory()
    ) == nil
  )
}

@Test(arguments: [
  (
    contact: false, authentication: SenderAuthentication.alignedPass,
    expected: GateResult?.some(.init(.allow, .priorCorrespondence))
  ),
  (false, .unverified, nil), (true, .alignedPass, .init(.allow, .contact)), (true, .failed, nil)
])
func `allows contacts and correspondents only with aligned trusted authentication`(
  contact: Bool,
  authentication: SenderAuthentication,
  expected: GateResult?
) {
  #expect(
    Gates.evaluate(
      address: "jane@example.org",
      domain: "example.org",
      rules: [],
      contact: contact,
      history: .init(replyCount: 1),
      authentication: authentication
    ) == expected
  )
}

actor StubRDAP: HTTPFetcher {
  var calls = 0
  var fail: Bool

  init(fail: Bool = false) { self.fail = fail }
  func fetch(_ url: URL) throws -> Data {
    calls += 1
    if fail { throw URLError(.timedOut) }
    if url.host == "data.iana.org" {
      return Data(#"{"services":[[["com"],["https://rdap.example/"]]]}"#.utf8)
    }
    return Data(
      #"{"events":[{"eventAction":"registration","eventDate":"2026-01-01T00:00:00Z"}]}"#.utf8
    )
  }
}

@Test
func `leaves domain age unknown after an RDAP lookup failure`() async {
  #expect(await RDAPLookup(fetcher: StubRDAP(fail: true)).ageDays(domain: "example.com") == nil)
}

@Test
func `caches RDAP registration age`() async throws {
  let network = StubRDAP(), rdap = RDAPLookup(fetcher: network)
  let now = try #require(ISO8601DateFormatter().date(from: "2026-01-11T00:00:00Z"))
  #expect(await rdap.ageDays(domain: "example.com", now: now) == 10)
  #expect(await rdap.ageDays(domain: "example.com", now: now) == 10)
  #expect(await network.calls == 2)
}

@Suite
struct `Store sharing between instances` {
  private let first: Store, second: Store

  /// Opens two stores at one location and commits one rule through the first.
  init() async throws {
    first = try testStore()
    second = try Store(url: first.url)
    try await first.update("rules", default: [SenderRule]()) { rules in
      rules = Gates.replacing(
        .init(scope: .address, value: "jane@example.org", disposition: .block),
        in: rules
      )
    }
  }

  @Test
  func `shares committed documents across instances`() async throws {
    #expect(try await second.read("rules", default: [SenderRule]()).count == 1)
  }

  @Test
  func `rolls back a transaction whose body throws`() async throws {
    await #expect(throws: ParseError.tooLarge) {
      try await second.update("rules", default: [SenderRule]()) { rules in
        rules = []; throw ParseError.tooLarge
      }
    }
    #expect(try await first.read("rules", default: [SenderRule]()).count == 1)
  }
}

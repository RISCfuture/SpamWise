import Foundation
import Testing
import SpamWiseCore
@Test func `prioritizes address rules over domain and trusted gates`() {
  let rules = [
    SenderRule(scope: .domain, value: "example.org", disposition: .allow),
    SenderRule(scope: .address, value: "jane@example.org", disposition: .block)
  ]
  #expect(
    Gates.evaluate(
      address: "jane@example.org",
      domain: "example.org",
      rules: rules,
      contact: true,
      history: .init(replyCount: 2)
    )?.disposition == .block
  )
  #expect(
    Gates.evaluate(
      address: "other@example.org",
      domain: "example.org",
      rules: rules,
      contact: false,
      history: .init()
    )?.disposition == .allow
  )
}
@Test func `replaces same scope rules with the latest correction`() {
  let old = SenderRule(scope: .address, value: "Jane@example.org", disposition: .block)
  let new = SenderRule(scope: .address, value: "jane@example.org", disposition: .allow)
  let rules = Gates.replacing(new, in: [old])
  #expect(rules.count == 1)
  #expect(rules.first?.disposition == .allow)
}
@Test func `preserves uncertainty when sender history is missing`() {
  let unknown = SenderHistory()
  #expect(unknown.summary.contains("unknown"))
  #expect(
    Gates.evaluate(
      address: "jane@example.org",
      domain: "example.org",
      rules: [],
      contact: nil,
      history: unknown
    ) == nil
  )
  #expect(SenderHistory(availability: .complete).summary.contains("No prior"))
  #expect(
    Gates.evaluate(
      address: "jane@example.org",
      domain: "example.org",
      rules: [],
      contact: false,
      history: .init(replyCount: 1)
    )?.disposition == .allow
  )
}
@Test func `extracts domain evidence and explicitly trusted authentication claims`() throws {
  let message = try MIMEParser().parse(fixture("filler-spam"))
  let evidence = EvidenceBundle(message: message)
  #expect(evidence.tldIsAbuseHeavy)
  #expect(evidence.domainAgeDays == nil)
  #expect(evidence.authResults.count == 3)
  #expect(evidence.authResults.allSatisfy { !$0.trusted })
  #expect(
    EvidenceBundle(message: message, trustedAuthServers: ["mx.example"]).authResults.allSatisfy {
      $0.trusted
    }
  )
}
actor StubRDAP: HTTPFetcher {
  var calls = 0
  var fail: Bool
  init(fail: Bool = false) { self.fail = fail }
  func fetch(_ url: URL) async throws -> Data {
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
@Test func `caches RDAP results and preserves uncertainty after lookup failure`() async throws {
  let network = StubRDAP(), lookup = RDAPLookup(fetcher: StubRDAP(fail: true))
  #expect(await lookup.ageDays(domain: "example.com") == nil)
  let rdap = RDAPLookup(fetcher: network)
  let now = try #require(ISO8601DateFormatter().date(from: "2026-01-11T00:00:00Z"))
  #expect(await rdap.ageDays(domain: "example.com", now: now) == 10)
  #expect(await rdap.ageDays(domain: "example.com", now: now) == 10)
  #expect(await network.calls == 2)
}
@Test func `shares committed rules across stores and rolls back failed transactions`() async throws
{
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let first = try Store(url: directory.appending(path: "state.store"))
  let second = try Store(url: directory.appending(path: "state.store"))
  try await first.update("rules", default: [SenderRule]()) { rules in
    rules = Gates.replacing(
      .init(scope: .address, value: "jane@example.org", disposition: .block),
      in: rules
    )
  }
  #expect(try await second.read("rules", default: [SenderRule]()).count == 1)
  await #expect(throws: ParseError.malformed) {
    try await second.update("rules", default: [SenderRule]()) { rules in
      rules = []; throw ParseError.malformed
    }
  }
  #expect(try await first.read("rules", default: [SenderRule]()).count == 1)
}

@Test func `preserves safety settings and validated accounts during field edits`() async throws {
  let store = try testStore()
  try await enableActions(store)
  try await StateRepository.editSettings(store) {
    $0.paused = true; $0.dryRun = true
  }
  try await StateRepository.editSettings(store) {
    $0.strength = .aggressive; $0.bodyTokenBudget = 50_000
  }
  let state = try await StateRepository.load(store)
  #expect(state.settings.paused)
  #expect(state.settings.dryRun)
  #expect(state.settings.validatedAccounts == ["account-A"])
  #expect(state.settings.bodyTokenBudget == 4000)
  #expect(state.revision == 2)
}

@Test func `orders content rules and aborts pathological expressions`() throws {
  var message = try MIMEParser().parse(fixture("filler-spam"))
  message.subject = "Example newsletter"
  var older = ContentRule()
  older.pattern = "NEWSLETTER"; older.disposition = .allow
  var newer = ContentRule()
  newer.pattern = "^Example.*"; newer.operation = .regularExpression
  newer.updatedAt = older.updatedAt.addingTimeInterval(1)
  #expect(
    try ContentRules.matches([older, newer], message: message).map(\.id) == [newer.id, older.id]
  )
  newer.enabled = false
  #expect(try ContentRules.matches([older, newer], message: message).map(\.id) == [older.id])
  newer.enabled = true; newer.pattern = "(a+)+$"
  message.subject = String(repeating: "a", count: 10_000) + "!"
  #expect(throws: ContentRuleError.timeout) { try ContentRules.matches([newer], message: message) }
}

import Foundation
import Testing
import SpamWiseCore
@Test func `prioritizes address rules over domain and authenticated relationship gates`() {
  let rules = [
    SenderRule(scope: .domain, value: "example.org", disposition: .allow),
    SenderRule(scope: .address, value: "jane@example.org", disposition: .block),
    SenderRule(scope: .domain, value: "example.net", disposition: .block),
    SenderRule(scope: .address, value: "ann@example.net", disposition: .allow)
  ]
  func gate(_ address: String, _ authentication: SenderAuthentication) -> GateReason? {
    Gates.evaluate(
      address: address,
      domain: DomainResolver().domain(ofAddress: address),
      rules: rules,
      contact: true,
      history: .init(replyCount: 2),
      authentication: authentication
    )?.reason
  }
  #expect(
    gate("jane@example.org", .unverified) == .senderRule(scope: .address, disposition: .block)
  )
  #expect(
    gate("other@example.org", .alignedPass) == .senderRule(scope: .domain, disposition: .allow)
  )
  #expect(gate("other@example.org", .unverified) == nil)
  #expect(gate("ann@example.net", .unverified) == nil)
  #expect(
    gate("ann@example.net", .alignedPass) == .senderRule(scope: .address, disposition: .allow)
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
  for authentication: SenderAuthentication in [.alignedPass, .unverified] {
    #expect(
      Gates.evaluate(
        address: "jane@example.org",
        domain: "example.org",
        rules: [],
        contact: false,
        history: .init(replyCount: 1),
        authentication: authentication
      )?.disposition == (authentication == .alignedPass ? .allow : nil)
    )
  }
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
  #expect(try authentication("dmarc=pass header.from=mail.example.org") == .alignedPass)
  #expect(try authentication("dkim=pass header.i=@example.org; spf=fail") == .alignedPass)
  #expect(try authentication("dkim=pass header.d=other.example") == .unverified)
  #expect(
    try authentication("dmarc=pass header.from=example.org", server: "relay.example") == .unverified
  )
  #expect(try authentication("dkim=pass header.d=example.org; dmarc=fail") == .failed)
  #expect(try authentication("dkim=pass header.d=other.example; spf=softfail") == .failed)
  #expect(
    try authentication("dkim=none", below: "mx.example; dmarc=pass header.from=example.org")
      == .unverified
  )
  let exchange = AuthenticationHeaders.parse(
    ["spf=pass (sender IP is 192.0.2.1) smtp.mailfrom=example.org; dkim=pass header.d=example.org"],
    trustedServers: ["spf=pass"]
  )
  #expect(exchange.map(\.mechanism) == ["spf", "dkim"])
  #expect(exchange.allSatisfy { !$0.trusted && $0.server.isEmpty })
  #expect(
    Gates.evaluate(
      address: "jane@example.org",
      domain: "example.org",
      rules: [],
      contact: true,
      history: .init(replyCount: 1),
      authentication: .failed
    ) == nil
  )
  let links = (1...25).reversed().map { "https://link\($0).com/" }.joined(separator: " ")
  var flooded = EvidenceBundle(
    message: try MIMEParser().parse(
      Data(
        """
        From: "\(String(repeating: "A", count: 1000))" <sender@zz-login.xyz>\r
        Reply-To: help@reply.com\r
        Return-Path: <bounce@bounce.com>\r
        Authentication-Results: mx.example; \(String(repeating: "spf=pass; ", count: 30))\r
        Subject: Flood\r
        \r
        \(links) https://link25.com/again\r
        """.utf8
      )
    )
  )
  #expect(flooded.fromDisplayName.count == 256)
  #expect(flooded.authResults.count == 20)
  #expect(flooded.linkDomains == (6...25).reversed().map { "link\($0).com" })
  #expect(
    flooded.reputationDomains.prefix(4) == ["zz-login.xyz", "reply.com", "bounce.com", "link25.com"]
  )
  let truncation = "Evidence truncated: display name, authentication results, link domains"
  #expect(flooded.auxiliaryFindings == [truncation])
  flooded.record(findings: (1...40).map { "Finding \($0)" } + ["Finding 1"])
  #expect(flooded.auxiliaryFindings?.count == 32)
  #expect(flooded.auxiliaryFindings?.last == "Evidence truncated: further findings omitted")
}
private func authentication(
  _ results: String,
  server: String = "MX.example",
  below lowerHeader: String? = nil
) throws -> SenderAuthentication {
  let headers = ["mx.example; \(results)", lowerHeader].compactMap(\.self)
    .map { "Authentication-Results: \($0)\n" }.joined()
  let raw = "From: jane@example.org\n\(headers)\nHello"
  return EvidenceBundle(
    message: try MIMEParser().parse(Data(raw.utf8)),
    trustedAuthServers: [server]
  ).senderAuthentication
}

@Test(arguments: [
  (sender: #""security@apple.com" <alerts@phish.example>"#, claim: "security@apple.com"),
  (sender: #""jane@example.org" <jane@example.org>"#, claim: nil)
])
func `classifies display-name senders with mismatch evidence only for spoofs`(
  _ sender: String,
  claim: String?
) async throws {
  let raw = Data("From: \(sender)\nSubject: Account locked\n\nVerify your account now.".utf8)
  let assessed = Counter()
  let pipeline = Pipeline(
    store: try testStore(),
    classifier: MockClassifier(operation: { input in
      #expect(input.evidence.mismatchedDisplayNameAddress == claim)
      let prompt = try PromptBuilder.prompt(input)
      #expect(prompt.contains("mismatchedDisplayNameAddress") == (claim != nil))
      return .init(label: .junk, confidence: 99, reason: "Fixture verdict")
    }),
    threatDetector: FixtureThreatDetector { input in
      assessed.increment()
      #expect(input.evidence.mismatchedDisplayNameAddress == claim)
      return []
    }
  )
  let record = await pipeline.process(
    MailEnvelope(identity: .init(accountID: "account-A", contentHash: stableHash(raw)), raw: raw)
  )
  #expect(record.path == .model)
  #expect(record.verdict?.label == .junk)
  #expect(record.evidence?.mismatchedDisplayNameAddress == claim)
  #expect(assessed.value == 1)
}

@Test(arguments: [
  "From: PayPal <alerts@evil.top>>", #"From: "friend@example.org"@attacker.example"#,
  "From: friend@example.org\nFrom: evil@attacker.top", "Subject: No sender"
])
func `flags mail without one readable sender for Review without classifying it`(
  _ headers: String
) async throws {
  let store = try testStore(), adapter = RecordingAdapter(), classified = Counter()
  try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      classified.increment()
      return .init(label: .inbox, confidence: 99, reason: "Fixture verdict")
    })
  )
  let raw = Data("\(headers)\nSubject: Account locked\n\nVerify your account now.".utf8)
  let message = MailEnvelope(
    identity: .init(accountID: "account-A", contentHash: stableHash(raw)),
    raw: raw
  )
  let record = await pipeline.process(message, adapter: adapter)
  #expect(record.path == .unreadableSender)
  #expect(
    record.decision == Decision(label: .review, action: .orangeFlag, reason: .unreadableSender)
  )
  #expect(record.outcome == .applied)
  #expect(await pipeline.process(message, adapter: adapter).id == record.id)
  #expect(await adapter.actions == [.orangeFlag])
  #expect(classified.value == 0)
}

@Test(arguments: ["self-mail", "forwarded-contact", "list-contact"])
func `keeps self and forwarded authentication claims untrusted when excluding aliases`(
  _ name: String
) async throws {
  let store = try testStore()
  let raw = try fixture(name), message = try MIMEParser().parse(raw)
  let address = message.fromAddress
  try await StateRepository.update(store) {
    $0.contactAddresses = [address]; $0.contactsUpdatedAt = .now
    $0.settings.mailOptions.trustExclusions = [address]
  }
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { input in
      #expect(input.evidence.contact == nil)
      #expect(input.evidence.authResults.allSatisfy { !$0.trusted })
      return .init(label: .review, confidence: 50, reason: "Authentication remains unknown")
    })
  )
  let result = await pipeline.process(
    MailEnvelope(identity: .init(accountID: "account", contentHash: message.hash), raw: raw)
  )
  #expect(result.path == .model)
  #expect(result.decision.label == .review)
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
  await #expect(throws: ParseError.tooLarge) {
    try await second.update("rules", default: [SenderRule]()) { rules in
      rules = []; throw ParseError.tooLarge
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
  #expect(state.revision == 1)
  #expect(
    state.auditEvents.last?.change == .settingsChanged(fields: ["bodyTokenBudget", "strength"])
  )
}

@Test func `validates accounts from mailbox roles and gates automatic checks and actions on them`()
  async throws
{
  let store = try testStore()
  try await StateRepository.update(store) { $0.settings.onboardingComplete = true }
  var settings = try await StateRepository.load(store).settings
  #expect(FilteringStatus(settings: settings, mailAutomation: .notAuthorized) == .mailNotAuthorized)
  #expect(FilteringStatus(settings: settings, mailAutomation: .mailNotRunning) == .mailNotRunning)
  #expect(FilteringStatus(settings: settings, mailAutomation: .granted) == .rolesNotValidated)
  #expect(FilteringStatus(settings: settings, mailAutomation: .granted).allowsAutomaticChecks)

  try await StateRepository.recordMailboxRoles(["account-A": true, "account-B": false], in: store)
  try await StateRepository.editSettings(store) { $0.dryRun = false }
  settings = try await StateRepository.load(store).settings
  #expect(settings.validatedAccounts == ["account-A"])
  #expect(FilteringStatus(settings: settings, mailAutomation: .granted) == .filtering)
  let adapter = RecordingAdapter()
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "lure"))
  )
  var unvalidated = try envelope()
  unvalidated.identity.accountID = "account-B"
  #expect(await pipeline.process(unvalidated, adapter: adapter).outcome == .integrationUnavailable)
  #expect(await adapter.actions.isEmpty)
  settings.paused = true
  #expect(!FilteringStatus(settings: settings, mailAutomation: .granted).allowsAutomaticChecks)

  try await StateRepository.recordMailboxRoles(["account-B": true], in: store)
  try await StateRepository.editSettings(store) { $0.dryRun = false }
  try await StateRepository.recordMailboxRoles(
    ["account-A": false],
    in: store,
    currentAccounts: ["account-A"]
  )
  settings = try await StateRepository.load(store).settings
  #expect(settings.validatedAccounts.isEmpty)
  #expect(settings.dryRun)
}

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
    )?.reason == .senderRule(scope: .address, disposition: .block)
  )
  #expect(
    Gates.evaluate(
      address: "other@example.org",
      domain: "example.org",
      rules: rules,
      contact: false,
      history: .init()
    )?.reason == .senderRule(scope: .domain, disposition: .allow)
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

@Test func `orders content rules and skips pathological expressions`() async throws {
  var message = try MIMEParser().parse(fixture("filler-spam"))
  message.subject = "Example newsletter"
  var older = ContentRule()
  older.pattern = "NEWSLETTER"; older.disposition = .allow
  var newer = ContentRule()
  newer.pattern = "^Example.*"; newer.operation = .regularExpression
  newer.updatedAt = older.updatedAt.addingTimeInterval(1)
  #expect(
    ContentRules.evaluate([older, newer], message: message).matching.map(\.id)
      == [newer.id, older.id]
  )
  newer.enabled = false
  #expect(ContentRules.evaluate([older, newer], message: message).matching.map(\.id) == [older.id])
  newer.enabled = true; newer.pattern = "(a+)+$"
  older.pattern = "aaa!"
  message.subject = String(repeating: "a", count: 10_000) + "!"
  let pathological = ContentRules.evaluate([older, newer], message: message)
  #expect(pathological.matching.map(\.id) == [older.id])
  #expect(pathological.skipped == [newer.id: .timeout])
  #expect(pathological.decisive == nil)
  newer.pattern = "a$"
  message.subject = String(repeating: "a", count: 40_000) + "tail"
  #expect(ContentRules.evaluate([newer], message: message) == .init())
  newer.pattern = "a{3}tail$"; older.pattern = "TAIL"
  let windowed = ContentRules.evaluate([older, newer], message: message)
  #expect(windowed.matching.map(\.id) == [newer.id, older.id])
  #expect(windowed.decisive == newer)
  var clusters = older
  let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
  clusters.pattern = String(repeating: family, count: 256)
  #expect(throws: ContentRuleError.invalid) { try ContentRules.validate(clusters) }
  let raw = Data(
    """
    From: person@example.org
    Content-Type: multipart/mixed; boundary=test

    --test
    Content-Type: application/pdf
    Content-Disposition: attachment; filename="../invoice.pdf"

    Not a real PDF and must not be opened.
    --test--

    """.utf8
  )
  message = try MIMEParser().parse(raw)
  newer.field = .attachmentNames; newer.pattern = "invoice.pdf"; newer.operation = .contains
  #expect(ContentRules.evaluate([newer], message: message).matching.count == 1)
  #expect(message.text.isEmpty)
  #expect(message.attachments?.first?.mediaType == "application/pdf")
  newer.field = .subject; newer.pattern = "("; newer.operation = .regularExpression
  newer.disposition = .allow
  older.pattern = "courtesy kit"; older.disposition = .block
  let store = try testStore(), unusable = newer, outranked = older
  try await StateRepository.update(store) { $0.contentRules = [unusable, outranked] }
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "lure"))
  )
  let record = await pipeline.process(try envelope())
  #expect(record.path == .model)
  #expect(record.outcome == .dryRun)
  let state = try await StateRepository.load(store)
  #expect(state.contentRuleSkips == [unusable.id: 1])
  #expect(state.contentRuleHits == nil)
}

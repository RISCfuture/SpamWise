import Foundation
import Testing
import SpamWiseCore

@Test
func `flags abuse-heavy TLDs and leaves domain age unknown`() throws {
  let evidence = EvidenceBundle(message: try MIMEParser().parse(fixture("filler-spam")))
  #expect(evidence.tldIsAbuseHeavy)
  #expect(evidence.domainAgeDays == nil)
}

@Test
func `trusts authentication results only from configured receiving servers`() throws {
  let message = try MIMEParser().parse(fixture("filler-spam"))
  let untrusted = EvidenceBundle(message: message)
  #expect(untrusted.authResults.count == 3)
  #expect(untrusted.authResults.allSatisfy { !$0.trusted })
  let trusted = EvidenceBundle(message: message, trustedAuthServers: ["mx.example"])
  let allTrusted = trusted.authResults.allSatisfy(\.trusted)
  #expect(allTrusted)
}

@Test(arguments: [
  (
    results: "dmarc=pass header.from=mail.example.org", server: "MX.example",
    expected: SenderAuthentication.alignedPass
  ),
  ("dkim=pass header.i=@example.org; spf=fail", "MX.example", .alignedPass),
  ("dkim=pass header.d=other.example", "MX.example", .unverified),
  ("dmarc=pass header.from=example.org", "relay.example", .unverified),
  ("dkim=pass header.d=example.org; dmarc=fail", "MX.example", .failed),
  ("dkim=pass header.d=other.example; spf=softfail", "MX.example", .failed)
])
func `derives sender authentication from the trusted server's results`(
  results: String,
  server: String,
  expected: SenderAuthentication
) throws {
  #expect(try authentication(results, server: server) == expected)
}

@Test
func `ignores trusted results below the topmost Authentication-Results header`() throws {
  #expect(
    try authentication("dkim=none", below: "mx.example; dmarc=pass header.from=example.org")
      == .unverified
  )
}

@Test
func `never trusts results without an authserv-id`() {
  let exchange = AuthenticationHeaders.parse(
    ["spf=pass (sender IP is 192.0.2.1) smtp.mailfrom=example.org; dkim=pass header.d=example.org"],
    trustedServers: ["spf=pass"]
  )
  #expect(exchange.map(\.mechanism) == ["spf", "dkim"])
  #expect(exchange.allSatisfy { !$0.trusted && $0.server.isEmpty })
}

@Test
func `bounds flooded sender, authentication and link evidence`() throws {
  let links = (1...25).reversed().map { "https://link\($0).com/" }.joined(separator: " ")
  let flooded = EvidenceBundle(
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
  #expect(
    flooded.auxiliaryFindings
      == ["Evidence truncated: display name, authentication results, link domains"]
  )
}

@Test
func `bounds authentication domains and combining marks so evidence fits a prompt`() throws {
  let marks = String(repeating: "\u{E0101}", count: 2_000)
  let message = try MIMEParser().parse(
    Data(
      """
      From: "a\(marks)" <sender@example.com>\r
      Authentication-Results: mx.example; dkim=pass \
      header.d=\(String(repeating: "<", count: 11_000))\r
      Subject: Oversized evidence\r
      \r
      Body\r
      """.utf8
    )
  )
  var evidence = EvidenceBundle(message: message)
  evidence.record(findings: ["b" + marks])
  #expect(evidence.fromDisplayName.unicodeScalars.count <= 256)
  #expect(evidence.auxiliaryFindings?.allSatisfy { $0.unicodeScalars.count <= 1024 } == true)
  #expect(evidence.authResults.map(\.domain) == [nil])
  #expect(try PromptBuilder.prompt(.init(message: message, evidence: evidence)).isEmpty == false)
}

@Test
func `caps recorded findings, ignoring duplicates, and notes the omission`() throws {
  var evidence = EvidenceBundle(message: try MIMEParser().parse(fixture("filler-spam")))
  evidence.record(findings: (1...40).map { "Finding \($0)" } + ["Finding 1"])
  #expect(evidence.auxiliaryFindings?.count == 32)
  #expect(evidence.auxiliaryFindings?.last == "Evidence truncated: further findings omitted")
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

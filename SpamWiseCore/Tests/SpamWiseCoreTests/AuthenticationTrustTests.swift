import Foundation
import Testing
import SpamWiseCore

@Test(arguments: [
  ("authentic-contact", true, true), ("authentic-contact", false, false),
  ("forged-contact", true, false), ("forged-contact", false, false)
])
func `lets Contacts and Allow rules decide only with trusted aligned authentication`(
  _ name: String,
  _ trustsServer: Bool,
  _ decides: Bool
) async throws {
  let store = try testStore(), selected = try envelope(name)
  let sender = try MIMEParser().parse(selected.raw).fromAddress
  try await StateRepository.update(store) {
    $0.contactAddresses = [sender]; $0.contactsUpdatedAt = .now
  }
  if trustsServer {
    try await AuthenticationTrust.save([" MX.Example "], accountID: "account-A", store: store)
  }
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .review, confidence: 50, reason: "Unknown"))
  )
  let contact = await pipeline.process(selected)
  try await RuleManagement.save(scope: .address, value: sender, disposition: .allow, store: store)
  let allowed = await pipeline.process(selected)
  #expect(contact.evidence?.contact == true)
  #expect(contact.evidence?.trustedServersConfigured == trustsServer)
  #expect(contact.correctionWarning(for: .junk) == (decides ? nil : .unauthenticatedSender))
  if decides {
    #expect(contact.decision.reason == .gate(.contact))
    #expect(allowed.decision.reason == .gate(.senderRule(scope: .address, disposition: .allow)))
  } else {
    #expect([contact.path, allowed.path] == [.model, .model])
    #expect(allowed.evidence?.unconfirmedAllowRule == .address)
  }
  if name == "forged-contact" && trustsServer {
    #expect(contact.evidence?.senderAuthentication == .failed)
    #expect(contact.evidence?.authResults.filter(\.trusted).count == 3)
  }
}

@Test func `detects an account's receiving servers before trusting them on confirmation`()
  async throws
{
  let store = try testStore()
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .review, confidence: 50, reason: "Unknown"))
  )
  #expect(
    AuthenticationHeaders.leadingServers([
      "MX.example; spf=pass", "relay.example; dkim=pass", "mx.example; dmarc=pass", "x; spf=pass"
    ]) == ["mx.example", "relay.example"]
  )
  func receive(_ index: Int) async throws -> AuthServerDetection? {
    let forged = index == 0 ? "Authentication-Results: forger.example; dmarc=pass\n" : ""
    let raw = Data(
      """
      From: sender\(index)@example.org
      Authentication-Results: mx.example; spf=pass smtp.mailfrom=example.org
      \(forged)Subject: Message \(index)

      Body \(index)
      """.utf8
    )
    _ = await pipeline.process(
      MailEnvelope(identity: .init(accountID: "account-A", contentHash: stableHash(raw)), raw: raw)
    )
    return try await AuthenticationTrust.accounts(store)["account-A"]?.detection
  }
  for index in 0..<9 { _ = try await receive(index) }
  #expect(try await receive(0) == .collecting(observed: 9, required: 10))
  await #expect(throws: AuthenticationTrustError.notDetected) {
    try await AuthenticationTrust.confirmDetected(accountID: "account-A", store: store)
  }
  #expect(try await receive(9) == .detected(["mx.example"]))
  let revision = try await StateRepository.load(store, StateSlices()).revision
  try await AuthenticationTrust.confirmDetected(accountID: "account-A", store: store)
  let state = try await StateRepository.load(store, StateSlices())
  #expect(state.settings.mailOptions.trustedAuthServers == ["account-A": ["mx.example"]])
  #expect(state.revision > revision)
  await #expect(throws: AuthenticationTrustError.invalidServer) {
    try await AuthenticationTrust.save(["mx example"], accountID: "account-A", store: store)
  }
}

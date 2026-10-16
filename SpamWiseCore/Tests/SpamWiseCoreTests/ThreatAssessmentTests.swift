import Foundation
import Testing
import SpamWiseCore

/// A trusted contact's message, gated before classification, with a detector that finds phishing.
@Suite
struct `Threat assessment of trusted mail` {
  private let store: Store
  private let adapter = RecordingAdapter()
  private let selected: MailEnvelope
  private let calls = Counter()
  private let pipeline: Pipeline

  init() async throws {
    store = try testStore()
    selected = try envelope("authentic-contact")
    let message = try MIMEParser().parse(selected.raw), calls = calls
    try await StateRepository.update(store) { [message] in
      $0.contactAddresses = [message.fromAddress]; $0.contactsUpdatedAt = .now
    }
    try await AuthenticationTrust.save(["mx.example"], accountID: "account-A", store: store)
    let detector = FixtureThreatDetector { input in
      calls.increment()
      #expect(input.accountID == "account-A")
      #expect(input.evidence.senderHistory.availability == .unavailable)
      return [
        .init(
          kind: .phishing,
          status: .detected,
          score: 0.9,
          reason: "Synthetic phishing finding",
          coverage: "Fixture text only"
        )
      ]
    }
    pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(operation: { _ in
        Issue.record("A trusted-contact gate must not invoke the preference classifier")
        throw ClassificationError.configuration
      }),
      threatDetector: detector
    )
  }

  @Test
  func `assesses gated mail without changing its action`() async {
    let trusted = await pipeline.process(selected, adapter: adapter)
    #expect(trusted.path == .gate)
    #expect(trusted.decision.action == .none)
    #expect(trusted.threats?.finding(for: .phishing)?.status == .detected)
  }

  @Test
  func `leaves threats the detector did not report unknown`() async {
    let trusted = await pipeline.process(selected, adapter: adapter)
    #expect(trusted.threats?.finding(for: .malware)?.status == .unknown)
    #expect(trusted.threats?.finding(for: .spearphishing)?.status == .unknown)
  }

  @Test
  func `assesses mail a Junk correction blocks and keeps its assessment`() async throws {
    let trusted = await pipeline.process(selected, adapter: adapter)
    _ = try await pipeline.correct(recordID: trusted.id, label: .junk, adapter: adapter)
    let blocked = await pipeline.process(selected, adapter: adapter)
    #expect(blocked.decision.action == .moveToJunk)
    #expect(blocked.threats?.finding(for: .phishing)?.status == .detected)
    #expect(calls.value == 2)
    #expect(await adapter.actions.isEmpty)
    #expect(try await StateRepository.load(store).records.last?.threats == blocked.threats)
  }

  @Test
  func `decodes a record saved before threat assessment as unassessed`() async throws {
    let trusted = await pipeline.process(selected, adapter: adapter)
    var historical = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(trusted)) as? [String: Any]
    )
    historical.removeValue(forKey: "threats")
    let decoded = try JSONDecoder().decode(
      DecisionRecord.self,
      from: JSONSerialization.data(withJSONObject: historical)
    )
    #expect(decoded.threats == nil)
  }
}

@Suite
struct `Unavailable threat assessment` {
  private typealias Detection = @Sendable (ThreatInput) async throws -> [ThreatFinding]

  private let store: Store
  private let selected: MailEnvelope
  private let classifier = MockClassifier(
    verdict: .init(label: .inbox, confidence: 90, reason: "wanted")
  )

  init() throws {
    store = try testStore()
    selected = try envelope()
  }

  private func pipeline(detecting operation: @escaping Detection, usesNetwork: Bool = false)
    -> Pipeline
  {
    Pipeline(
      store: store,
      classifier: classifier,
      threatDetector: FixtureThreatDetector(usesNetwork: usesNetwork, operation: operation)
    )
  }

  @Test
  func `keeps every threat unknown when the detector fails`() async {
    let unavailable = await pipeline { _ in throw ClassificationError.network }.process(selected)
    #expect(
      unavailable.threats?.findings.allSatisfy { $0.status == .unknown && $0.score == nil } == true
    )
    #expect(unavailable.decision.action == .none)
  }

  @Test
  func `skips a network detector in local-only mode`() async throws {
    let calls = Counter()
    let networked = pipeline(
      detecting: { _ in
        calls.increment()
        return []
      },
      usesNetwork: true
    )
    try await StateRepository.editSettings(store) { $0.mailOptions.localOnly = true }
    let local = await networked.process(selected)
    #expect(calls.value == 0)
    #expect(local.threats?.detector == nil)
  }

  @Test
  func `treats a finding with an invalid status and score as unknown`() async {
    let malformed = pipeline { _ in
      [.init(kind: .spam, status: .unknown, score: 1, reason: "invalid", coverage: "Text")]
    }
    #expect(
      await malformed.process(selected).threats?.findings.allSatisfy { $0.status == .unknown }
        == true
    )
  }

  @Test
  func `records no assessment without a detector`() async {
    #expect(await Pipeline(store: store, classifier: classifier).process(selected).threats == nil)
  }

  @Test
  func `keeps a late assessment unknown and the classification it outlasted`() async {
    let delayed = pipeline { _ in
      try await Task.sleep(for: .seconds(60))
      return [.init(kind: .phishing, status: .detected, reason: "Late", coverage: "Fixture")]
    }
    let expired = await delayed.process(selected)
    #expect(expired.verdict?.label == .inbox)
    #expect(expired.threats?.finding(for: .phishing)?.status == .unknown)
    #expect(expired.threats?.detector?.implementation == "fixture-v1")
  }
}

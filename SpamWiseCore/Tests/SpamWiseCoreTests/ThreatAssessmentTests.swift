import Foundation
import Testing
import SpamWiseCore

@Test
func `assesses trusted mail independently without changing explicit rule actions`()
  async throws
{
  let store = try testStore(), adapter = RecordingAdapter()
  let selected = try envelope("authentic-contact")
  let message = try MIMEParser().parse(selected.raw), calls = Counter()
  try await StateRepository.update(store) {
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
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      Issue.record("A trusted-contact gate must not invoke the preference classifier")
      throw ClassificationError.configuration
    }),
    threatDetector: detector
  )
  let trusted = await pipeline.process(selected, adapter: adapter)
  #expect(trusted.path == .gate)
  #expect(trusted.decision.action == .none)
  #expect(trusted.threats?.finding(for: .phishing)?.status == .detected)
  #expect(trusted.threats?.finding(for: .malware)?.status == .unknown)
  #expect(trusted.threats?.finding(for: .spearphishing)?.status == .unknown)
  _ = try await pipeline.correct(recordID: trusted.id, label: .junk, adapter: adapter)
  let blocked = await pipeline.process(selected, adapter: adapter)
  #expect(blocked.decision.action == .moveToJunk)
  #expect(blocked.threats?.finding(for: .phishing)?.status == .detected)
  #expect(calls.value == 2)
  #expect(await adapter.actions.isEmpty)
  #expect(try await StateRepository.load(store).records.last?.threats == blocked.threats)
  var historical = try #require(
    JSONSerialization.jsonObject(
      with: JSONEncoder().encode(trusted)
    ) as? [String: Any]
  )
  historical.removeValue(forKey: "threats")
  let decoded = try JSONDecoder().decode(
    DecisionRecord.self,
    from: JSONSerialization.data(withJSONObject: historical)
  )
  #expect(decoded.threats == nil)
}

@Test
func `keeps unavailable threat assessments unknown and excludes network detectors locally`()
  async throws
{
  let store = try testStore(), selected = try envelope(), calls = Counter()
  let classifier = MockClassifier(verdict: .init(label: .inbox, confidence: 90, reason: "wanted"))
  let detector = FixtureThreatDetector(usesNetwork: true) { _ in
    calls.increment()
    throw ClassificationError.network
  }
  let pipeline = Pipeline(store: store, classifier: classifier, threatDetector: detector)
  let unavailable = await pipeline.process(selected)
  #expect(
    unavailable.threats?.findings.allSatisfy { $0.status == .unknown && $0.score == nil } == true
  )
  #expect(unavailable.decision.action == .none)
  #expect(calls.value == 1)
  try await StateRepository.editSettings(store) { $0.mailOptions.localOnly = true }
  let local = await pipeline.process(selected)
  #expect(calls.value == 1)
  #expect(local.threats?.detector == nil)
  let malformed = Pipeline(
    store: store,
    classifier: classifier,
    threatDetector: FixtureThreatDetector { _ in
      [.init(kind: .spam, status: .unknown, score: 1, reason: "invalid", coverage: "Text")]
    }
  )
  #expect(
    await malformed.process(selected).threats?.findings.allSatisfy { $0.status == .unknown } == true
  )
  let absent = await Pipeline(store: store, classifier: classifier).process(selected)
  #expect(absent.threats == nil)
  let delayed = Pipeline(
    store: store,
    classifier: classifier,
    threatDetector: FixtureThreatDetector { _ in
      try await Task.sleep(for: .seconds(3))
      return [.init(kind: .phishing, status: .detected, reason: "Late", coverage: "Fixture")]
    }
  )
  let expired = await delayed.process(selected)
  #expect(expired.verdict?.label == .inbox)
  #expect(expired.threats?.finding(for: .phishing)?.status == .unknown)
  #expect(expired.threats?.detector?.implementation == "fixture-v1")
}

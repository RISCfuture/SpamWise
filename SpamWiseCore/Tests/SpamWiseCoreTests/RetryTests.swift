import Foundation
import Testing
import SpamWiseCore

@Test
func `consumes retries only within the selected account`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  try await enqueueFailedRetries(store: store, accountIDs: ["account-A", "account-B"])
  let due = Date().addingTimeInterval(35)
  let successful = Pipeline(
    store: store,
    classifier: MockClassifier(
      verdict:
        .init(label: .inbox, confidence: 99, reason: "Retry succeeded")
    )
  )
  await successful.retryDue(adapter: adapter, now: due, accountID: "account-A")
  let state = try await StateRepository.load(store)
  #expect(state.retries.map(\.identity.accountID) == ["account-B"])
  #expect(state.records.last?.identity.accountID == "account-A")
  #expect(state.records.last?.decision.label == .inbox)
  #expect(await adapter.actions.isEmpty)
}
@Test
func `retries with the evidence the first attempt gathered`() async throws {
  let store = try testStore(), scans = Counter()
  try await StateRepository.editSettings(store) { settings in
    var evidence = ExternalEvidenceSettings()
    evidence.localRspamd = true
    settings.advancedOptions.externalEvidence = evidence
  }
  let scanned = ExternalEvidenceFinding(source: .localRspamd, subject: "message", status: .unknown)
    .summary
  _ = await Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in throw ClassificationError.rateLimited }),
    rspamdScan: countingRspamd(scans)
  ).process(try envelope())
  #expect(try await StateRepository.load(store).retries.map(\.auxiliaryFindings) == [[scanned]])
  let retried = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { input in
      #expect(input.evidence.auxiliaryFindings?.contains(scanned) == true)
      return .init(label: .inbox, confidence: 99, reason: "Retry succeeded")
    }),
    rspamdScan: countingRspamd(scans)
  )
  await retried.retryDue(adapter: RecordingAdapter(), now: Date().addingTimeInterval(35))
  #expect(scans.value == 1)
  #expect(try await StateRepository.load(store).records.last?.decision.label == .inbox)
}
@Test(arguments: [false, true])
func `retains unstarted retries across cancellation and restart`(cancelBeforeStart: Bool)
  async throws
{
  let store = try testStore(), adapter = RecordingAdapter()
  try await enqueueFailedRetries(store: store, accountIDs: ["account-A", "account-B", "account-C"])
  let due = Date().addingTimeInterval(35)
  let (started, signalStarted) = AsyncStream<Void>.makeStream()
  let (released, release) = AsyncStream<Void>.makeStream()
  let (ready, begin) = AsyncStream<Void>.makeStream()
  let delayed = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      signalStarted.yield(()); signalStarted.finish()
      for await _ in released { break }
      try Task.checkCancellation()
      return .init(label: .inbox, confidence: 99, reason: "Completed retry")
    })
  )
  let task = Task {
    for await _ in ready { break }
    await delayed.retryDue(adapter: adapter, now: due)
    signalStarted.finish()
  }
  defer { task.cancel(); begin.finish(); release.finish(); signalStarted.finish() }
  if !cancelBeforeStart {
    begin.finish()
    var starts = started.makeAsyncIterator()
    try #require(await starts.next() != nil)
  }
  task.cancel(); begin.finish(); release.finish()
  await task.value
  let reopened = try Store(url: store.url)
  let pending = try await StateRepository.load(reopened)
  let expected =
    cancelBeforeStart ? ["account-A", "account-B", "account-C"] : ["account-B", "account-C"]
  #expect(pending.retries.compactMap(\.identity.accountID) == expected)
  let resumed = Pipeline(
    store: reopened,
    classifier: MockClassifier(
      verdict: .init(label: .inbox, confidence: 99, reason: "Resumed retry")
    )
  )
  await resumed.retryDue(adapter: adapter, now: due)
  let finished = try await StateRepository.load(reopened)
  #expect(finished.retries.isEmpty)
  #expect(
    Set(
      finished.records.filter { $0.decision.label == .inbox }.compactMap(\.identity.accountID)
    ) == Set(expected)
  )
  #expect(await adapter.actions.isEmpty)
}

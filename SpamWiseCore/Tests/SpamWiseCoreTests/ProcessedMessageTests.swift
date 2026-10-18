import Foundation
import Testing
import SpamWiseCore

@Test
func `skips settled mail but not live previews across eviction, failures and retention`()
  async throws
{
  let store = try testStore(), adapter = RecordingAdapter(), calls = Counter()
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { input in
      calls.increment()
      if input.message.subject.contains("cart") { throw ClassificationError.network }
      return Verdict(label: .junk, confidence: 99, reason: "lure")
    })
  )
  let previewed = try envelope()
  let transient = try envelope("stranger-cart")
  var unparseable = transient
  unparseable.raw = Data(repeating: 65, count: 2_100_000)
  unparseable.identity.contentHash = stableHash(unparseable.raw)
  let batch = [previewed, transient, unparseable]
  let sweep = { (dryRun: Bool) in
    try await pipeline.processBatch(batch, adapter: adapter, dryRun: dryRun, skipsSettled: true)
      .count
  }
  #expect(try await sweep(true) == 3)
  #expect(calls.value == 2)
  let reasons = try await StateRepository.load(store).records.map(\.decision.reason)
  #expect(reasons.contains(.classificationFailed(.network)) && reasons.contains(.messageUnreadable))
  try await StateRepository.update(store) { $0.records.removeAll() }
  try await enableActions(store)
  try await StateRepository.editSettings(store) { $0.strength = .aggressive }
  #expect(try await sweep(false) == 1)
  #expect(calls.value == 3)
  #expect(await adapter.actions.isEmpty)
  #expect(try await StateRepository.load(store).records.map(\.identity) == [transient.identity])
  #expect(try await sweep(false) == 0)
  let revision = try await StateRepository.load(store).revision
  let settledLater = try await ProcessedMessageRepository.settledKeys(
    among: batch.map(\.identity.key),
    revision: revision,
    now: .now.addingTimeInterval(3600),
    in: store
  )
  #expect(settledLater == [previewed.identity.key, unparseable.identity.key])
  let polled = try envelope("order-confirmation")
  for _ in 1...2 {
    try await pipeline.processBatch([polled], adapter: adapter, dryRun: true, skipsSettled: true)
  }
  #expect(calls.value == 4)
  let fresh = try envelope("unsolicited-newsletter")
  try await pipeline.processBatch([fresh], adapter: adapter, dryRun: true, skipsSettled: false)
  #expect(await adapter.actions.isEmpty)
  try await pipeline.processBatch([fresh], adapter: adapter, dryRun: false, skipsSettled: true)
  #expect(await adapter.actions == [.moveToJunk])
  let observed = Date.now.addingTimeInterval(300 * 86_400)
  let pruned = observed.addingTimeInterval(200 * 86_400)
  let settledAt = { (now: Date) in
    try await ProcessedMessageRepository.settledKeys(
      among: [previewed.identity.key],
      revision: revision,
      now: now,
      in: store
    )
  }
  #expect(try await settledAt(observed) == [previewed.identity.key])
  let neighbor = try #require(try await StateRepository.load(store).records.first)
  try await ProcessedMessageRepository.record(
    neighbor,
    key: previewed.identity.key.prefix(2) + "-neighbor",
    in: store,
    now: pruned
  )
  #expect(try await settledAt(pruned) == [previewed.identity.key])
  var contended = previewed
  contended.identity.contentHash = "unavailable-storage"
  try blockStorage(store)
  #expect(await pipeline.process(contended, discovered: true).outcome == .unclassified)
  try restoreStorage(store)
  let classified = calls.value
  #expect(
    try await pipeline.processBatch([contended], adapter: adapter, dryRun: true, skipsSettled: true)
      .count == 1
  )
  #expect(calls.value == classified + 1)
}
@Test func `records unavailable shared storage as a transient failure`() async throws {
  let store = try testStore(), fresh = try envelope("unsolicited-newsletter")
  let unclassifiable = MockClassifier(operation: { _ in throw ClassificationError.network })
  let pipeline = Pipeline(store: store, classifier: unclassifiable)
  try blockStorage(store)
  let unavailable = await pipeline.process(fresh, discovered: true)
  #expect(unavailable.decision.reason == .storageUnavailable)
  try restoreStorage(store)
  try await pipeline.processBatch([], adapter: RecordingAdapter(), dryRun: true, skipsSettled: true)
  let entry = try await ProcessedMessageRepository.entries(for: [fresh.identity.key], in: store)
  #expect(entry[fresh.identity.key]?.failure == .transient)
}
/// Makes every transaction on `store` fail, as when its lock file cannot be opened.
private func blockStorage(_ store: Store) throws {
  let lock = store.url.path + ".lock"
  try? FileManager.default.removeItem(atPath: lock)
  try FileManager.default.createDirectory(atPath: lock, withIntermediateDirectories: false)
}
/// Makes `store` available again after ``blockStorage(_:)``.
private func restoreStorage(_ store: Store) throws {
  try FileManager.default.removeItem(atPath: store.url.path + ".lock")
}
@Test func `keeps evicted action claims without classifying again`() async throws {
  let store = try testStore(), adapter = RecordingAdapter(), calls = Counter()
  try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      calls.increment()
      return Verdict(label: .junk, confidence: 99, reason: "lure")
    })
  )
  #expect(await pipeline.process(try envelope(), adapter: adapter).outcome == .applied)
  try await StateRepository.update(store) { $0.records.removeAll() }
  let evicted = await pipeline.process(try envelope(), adapter: adapter)
  #expect(evicted.outcome == .duplicate)
  #expect(evicted.decision.label == .junk)
  #expect(calls.value == 1)
  #expect(await adapter.actions == [.moveToJunk])
  #expect(try await StateRepository.load(store).records.isEmpty)
}
@Test func `settles existing Activity once without classifying it again`() async throws {
  let store = try testStore(), calls = Counter()
  let classifier = MockClassifier(operation: { _ in
    calls.increment()
    return Verdict(label: .junk, confidence: 99, reason: "lure")
  })
  let manual = Pipeline(store: store, classifier: classifier)
  let sweep = { (batch: [MailEnvelope]) in
    try await Pipeline(store: store, classifier: classifier)
      .processBatch(batch, adapter: nil, dryRun: true, skipsSettled: true).count
  }
  let existing = try envelope(), later = try envelope("unsolicited-newsletter")
  try await enableActions(store)
  _ = await manual.process(existing, forceDryRun: true)
  #expect(try await sweep([existing]) == 0)
  #expect(calls.value == 1)
  _ = await manual.process(later, forceDryRun: true)
  #expect(try await sweep([existing, later]) == 1)
  #expect(calls.value == 3)
}

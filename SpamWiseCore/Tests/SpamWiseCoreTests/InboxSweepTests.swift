import Foundation
import Testing
import SpamWiseCore
@testable import MailIntegration

private actor InboxFixtureEvents: AppleEventRunner {
  private static let boundary = Date(timeIntervalSince1970: 1_700_000_000)
  private static let earlierMessages = 5
  private var localIDs: [Int]
  private var arrivals: (read: Int, localIDs: ClosedRange<Int>)?
  private(set) var requests: [MailRequest] = []
  init(count: Int) { localIDs = Array((1...count).reversed()) }
  /// Messages arrive an hour apart, and messages 1 through 5 arrive before the boundary.
  static func received(_ localID: Int) -> Date {
    boundary.addingTimeInterval(Double(localID - earlierMessages - 1) * 3600)
  }
  func deliver(_ localID: Int) { localIDs.insert(localID, at: 0) }
  /// Delivers `arriving` just before the `read`th page read from now returns.
  func deliver(_ arriving: ClosedRange<Int>, duringRead read: Int) {
    arrivals = (requests.count + read, arriving)
  }
  func run(_ request: MailRequest) async throws -> ScriptValue {
    requests.append(request)
    if let arrivals, arrivals.read == requests.count { arrivals.localIDs.forEach(deliver) }
    guard case let .accountPage(.inbox, account, offset, size, false, since, before) = request
    else { throw IntegrationError.scriptFailed }
    let received = (since ?? .distantPast)..<(before ?? .distantFuture)
    let candidates = localIDs.filter { received.contains(Self.received($0)) }
    let rows = candidates.dropFirst(offset).prefix(size).map { localID in
      MailReply.message(
        account: account,
        localID: localID,
        messageID: "id-\(localID)",
        source: "From: person@example.org\nSubject: Message \(localID)\n\nHello"
      )
    }
    return .list([.integer(candidates.count), .list(Array(rows))])
  }
}

@Test
func `checks every newly delivered Inbox message first and never reads before the boundary`()
  async throws
{
  let store = try testStore(), calls = Counter(), events = InboxFixtureEvents(count: 80)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      calls.increment()
      return Verdict(label: .inbox, confidence: 99, reason: "wanted")
    })
  )
  let sweep = AppleMailInboxSweep(
    adapter: AppleMailAdapter(runner: events),
    pipeline: pipeline,
    store: store
  )
  let account = MailAccount(id: "account", name: "Account")
  let start = InboxFixtureEvents.received(6)
  try await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
    $0.inboxStart = start
  }
  let tick = { try await sweep.run(account: account, dryRun: true, limit: 10) }
  let backfillOffset = { try await MailHealthRepository.load(store)[account.id]?.nextOffset ?? 0 }
  try await tick()
  try await tick()
  #expect(calls.value == 75)
  while try await backfillOffset() < 30 { try await tick() }
  for localID in 81...105 { await events.deliver(localID) }
  try await tick()
  let classified = try await StateRepository.load(store).records.compactMap(\.identity.localID)
  #expect(Set(classified) == Set(6...105))
  #expect(calls.value == 100)
  while try await backfillOffset() < 60 { try await tick() }
  for localID in 106...130 { await events.deliver(localID) }
  await events.deliver(131...133, duringRead: 2)
  try await tick()
  try await tick()
  let afterBurst = try await StateRepository.load(store).records.compactMap(\.identity.localID)
  #expect(Set(afterBurst) == Set(6...133))
  #expect(calls.value == 128)
  #expect(try await MailHealthRepository.load(store)[account.id]?.inboxStart == start)
  let added = MailAccount(id: "added", name: "Added after setup")
  try await sweep.run(account: added, dryRun: true, limit: 10)
  #expect(calls.value == 128)
  #expect(try await MailHealthRepository.load(store)[added.id]?.inboxStart ?? start > start)
}

@Test func `applies a current older mail preview and supersedes a stale one`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "lure"))
  )
  let preview = { (name: String) in
    try await pipeline.processBatch(
      [envelope(name)],
      adapter: adapter,
      dryRun: true,
      skipsSettled: false
    )
  }
  let current = try await preview("filler-spam"), stale = try await preview("stranger-cart")
  #expect((current + stale).map(\.outcome) == [.dryRun, .dryRun])
  #expect(await adapter.actions.isEmpty)
  let applied = try await pipeline.applyPreview(recordID: current[0].id, adapter: adapter)
  #expect(applied.outcome == .applied)
  try await StateRepository.editSettings(store) { $0.strength = .conservative }
  let superseded = try await pipeline.applyPreview(recordID: stale[0].id, adapter: adapter)
  #expect(superseded.outcome == .superseded)
  #expect(await adapter.actions == [.moveToJunk])
}

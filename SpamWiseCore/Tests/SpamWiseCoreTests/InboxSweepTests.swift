import Foundation
import Testing
import SpamWiseCore
@testable import MailIntegration

private actor InboxFixtureEvents: AppleEventRunner {
  private static let boundary = Date(timeIntervalSince1970: 1_700_000_000)
  private static let earlierMessages = 5
  private var localIDs: [Int]
  private var arrivals: (read: Int, localIDs: ClosedRange<Int>)?
  private(set) var scripts: [String] = []
  init(count: Int) { localIDs = Array((1...count).reversed()) }
  /// Messages arrive an hour apart, and messages 1 through 5 arrive before the boundary.
  static func received(_ localID: Int) -> Date {
    boundary.addingTimeInterval(Double(localID - earlierMessages - 1) * 3600)
  }
  private static func number(after marker: String, in source: String) -> Int? {
    guard let start = source.range(of: marker, options: .backwards)?.upperBound else { return nil }
    return Int(source[start...].prefix(while: \.isNumber))
  }
  private static func date(_ name: String, in source: String) -> Date? {
    guard let year = number(after: "set year of \(name) to ", in: source),
      let month = number(after: "set month of \(name) to ", in: source),
      let day = number(after: "set day of \(name) to ", in: source),
      let time = number(after: "set time of \(name) to ", in: source)
    else { return nil }
    return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))?
      .addingTimeInterval(Double(time))
  }
  func deliver(_ localID: Int) { localIDs.insert(localID, at: 0) }
  /// Delivers `arriving` just before the `read`th page read from now returns.
  func deliver(_ arriving: ClosedRange<Int>, duringRead read: Int) {
    arrivals = (scripts.count + read, arriving)
  }
  func run(_ source: String) async throws -> ScriptValue {
    scripts.append(source)
    if let arrivals, arrivals.read == scripts.count { arrivals.localIDs.forEach(deliver) }
    guard let first = Self.number(after: "set firstIndex to ", in: source),
      let size = Self.number(after: "set lastIndex to firstIndex + ", in: source)
    else { throw IntegrationError.scriptFailed }
    let since = Self.date("sinceDate", in: source) ?? .distantPast
    let before = Self.date("beforeDate", in: source) ?? .distantFuture
    let candidates = localIDs.filter { (since..<before).contains(Self.received($0)) }
    let rows = candidates.dropFirst(first - 1).prefix(size).map { localID in
      ScriptValue.list([
        .string("account"), .string("Inbox"), .integer(localID), .string("id-\(localID)"),
        .string("From: person@example.org\nSubject: Message \(localID)\n\nHello")
      ])
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

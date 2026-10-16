import Foundation
import Synchronization
import Testing
import SpamWiseCore
@testable import MailIntegration
@Test func `escapes AppleScript literals so they cannot become commands`() {
  #expect(
    MailScripts.literal("a\" & do shell script \"bad") == "\"a\\\" & do shell script \\\"bad\""
  )
  #expect(MailScripts.literal("a\\b").contains("a\\\\b"))
  #expect(!MailScripts.literal("a\nb").contains("\n"))
}
@Test func `requires account scoped identity and exact source in Mail scripts`() throws {
  #expect(throws: IntegrationError.self) {
    try MailScripts.lookup(.init(accountID: nil, contentHash: "x"))
  }
  let identity = MessageIdentity(accountID: "account", messageID: "<id>", contentHash: "x")
  let script = try MailScripts.lookup(identity, action: .moveToJunk, expectedSource: "safe source")
  #expect(script.contains("count of matches) is not 1"))
  #expect(script.contains("source of targetMessage"))
  #expect(script.contains("mailboxes of junk mailbox"))
}
actor StubAppleEvents: AppleEventRunner {
  var responses: [ScriptValue]
  private(set) var moves = 0
  init(_ response: ScriptValue) { responses = [response] }
  init(responses: [ScriptValue]) { self.responses = responses }
  func run(_ source: String) async throws -> ScriptValue {
    if source.contains("move targetMessage") { moves += 1 }
    return responses.removeFirst()
  }
}
@Test func `rejects changed source and unstable Mail probe restoration`() async throws {
  let runner = StubAppleEvents(
    .list([.string("account"), .string("Inbox"), .integer(1), .string("id"), .string("changed")])
  )
  let adapter = AppleMailAdapter(runner: runner)
  await #expect(throws: IntegrationError.staleMessage) {
    _ = try await adapter.lookup(
      .init(accountID: "account", messageID: "id", contentHash: "expected")
    )
  }
  let raw = "From: probe@example.org\r\nSubject: [SpamWise Probe] Test\r\n\r\nDisposable probe."
  let selected = ScriptValue.list([
    .string("account"), .string("Inbox"), .integer(1), .string("id"), .string(raw)
  ])
  let unconfirmed = AppleMailAdapter(
    runner: StubAppleEvents(responses: [selected, .boolean(true), .boolean(false)]),
    moveSettlingTime: .zero
  )
  await #expect(throws: IntegrationError.staleMessage) {
    try await unconfirmed.perform(
      .moveToJunk,
      for: MessageIdentity(
        accountID: "account",
        messageID: "id",
        contentHash: stableHash(Data(raw.utf8))
      )
    )
  }
  let unstable = StubAppleEvents(responses: [
    selected, .boolean(true), selected, .boolean(true), .boolean(false)
  ])
  let probe = AppleMailAdapter(runner: unstable, moveSettlingTime: .zero)
  await #expect(throws: IntegrationError.staleMessage) {
    try await probe.testDisposableMessage()
  }
  #expect(await unstable.moves == 1)
  let junk = ScriptValue.list([
    .string("account"), .string("Junk"), .integer(2), .string("id"), .string(raw)
  ])
  let restored = ScriptValue.list([
    .string("account"), .string("Inbox"), .integer(3), .string("id"), .string(raw)
  ])
  let settled = StubAppleEvents(responses: [
    selected, .boolean(true), selected, .boolean(true), .boolean(true),
    junk, .boolean(true), .boolean(true), restored, .boolean(true), .boolean(true), .boolean(true)
  ])
  #expect(
    try await AppleMailAdapter(runner: settled, moveSettlingTime: .zero).testDisposableMessage()
      == "account"
  )
  #expect(await settled.moves == 2)
}
@Test func `invokes completion exactly once under concurrent calls`() async {
  let count = Counter()
  let completion = CompletionOnce<Int> { _ in count.increment() }
  await withTaskGroup(of: Void.self) { group in
    for _ in 0..<100 { group.addTask { completion.finish(1) } }
  }
  #expect(count.value == 1)
}
final class Counter: Sendable {
  private let storage = Mutex(0)
  var value: Int { storage.withLock { $0 } }
  func increment() { storage.withLock { $0 += 1 } }
}
@Test @MainActor func `compiles generated scripts and decodes Apple Event booleans`() throws {
  for (source, expected) in [
    ("return true", ScriptValue.boolean(true)),
    ("return false", .boolean(false)),
    ("return {true, false}", .list([.boolean(true), .boolean(false)]))
  ] {
    let script = try #require(NSAppleScript(source: source))
    #expect(ScriptValue.decode(unsafe script.executeAndReturnError(nil)) == expected)
  }
  let identity = MessageIdentity(
    accountID: "test-account",
    messageID: "test-id",
    contentHash: "test"
  )
  let scripts = [
    MailScripts.accounts, MailScripts.selected, MailScripts.recent(limit: 5, offset: 20),
    try MailScripts.lookup(identity),
    try MailScripts.lookup(identity, action: .moveToJunk, expectedSource: "From: x\n\nbody"),
    try MailScripts.verification(identity, action: .moveToJunk, expectedSource: "From: x\n\nbody"),
    try MailScripts.verification(identity, action: .orangeFlag, expectedSource: "From: x\n\nbody")
  ]
  for source in scripts {
    let script = try #require(NSAppleScript(source: source))
    var error: NSDictionary?
    let compiled = unsafe script.compileAndReturnError(&error)
    #expect(compiled, Comment(rawValue: error?.description ?? "Script compiles"))
  }
}

private struct HistoryEvents: AppleEventRunner {
  func run(_ source: String) async throws -> ScriptValue {
    if source.contains("messages of sent mailbox") { return .list([]) }
    return .list([
      .list([
        .string("account"), .string("Inbox"), .integer(1), .string("receipt"),
        .string("From: orders@shop.example.org\nSubject: Your receipt\n\nOrder 123 total USD 10")
      ])
    ])
  }
}
@Test func `retains prior history and deduplicates repeated imports`() async throws {
  let adapter = AppleMailAdapter(runner: HistoryEvents())
  var old = HistoryIndex()
  old.received["prior.example"] = 4
  let excluded = try await adapter.importHistory(
    previous: ["account": old],
    eligibleInbox: [],
    incremental: true
  )
  #expect(excluded["account"]?.receipts.isEmpty == true)
  let first = try await adapter.importHistory(previous: ["account": old])
  let second = try await adapter.importHistory(previous: first)
  #expect(second["account"]?.received["prior.example"] == 4)
  #expect(second["account"]?.received["example.org"] == 1)
  #expect(second["account"]?.receipts["example.org"] == 1)
  #expect(second["account"]?.availability == .partial)
}

private actor PagedEvents: AppleEventRunner {
  private var offsets: [Int] = []
  func run(_ source: String) async throws -> ScriptValue {
    let marker = "set firstIndex to "
    guard let start = source.range(of: marker)?.upperBound,
      let first = Int(source[start...].prefix(while: \.isNumber))
    else {
      throw IntegrationError.scriptFailed
    }
    offsets.append(first)
    if first > 21 { return .list([]) }
    return .list(
      (first...min(21, first + 19)).map { index in
        .list([
          .string("account"), .string("Inbox"), .integer(index), .string("id-\(index)"),
          .string("From: person@example.org\nSubject: Message \(index)\n\nHello")
        ])
      }
    )
  }
}
@Test func `advances Inbox sweeps beyond the retained first page and wraps`() async throws {
  let adapter = AppleMailAdapter(runner: PagedEvents())
  let first = try await adapter.nextInboxMessages(limit: 20)
  let second = try await adapter.nextInboxMessages(limit: 20)
  let wrapped = try await adapter.nextInboxMessages(limit: 20)
  #expect(first.count == 20)
  #expect(second.map { $0.identity.localID } == [21])
  #expect(wrapped.map { $0.identity.key } == first.map { $0.identity.key })
}

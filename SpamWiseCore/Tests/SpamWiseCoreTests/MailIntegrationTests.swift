import Foundation
import Testing
import SpamWiseCore
@testable import MailIntegration

@Test
func `refuses unscoped identities and unverifiable moves before contacting Mail`() async {
  let runner = StubAppleEvents([:])
  let adapter = AppleMailAdapter(runner: runner)
  await #expect(throws: IntegrationError.accountUnresolved) {
    try await adapter.perform(.orangeFlag, for: .init(accountID: nil, contentHash: "x"))
  }
  await #expect(throws: IntegrationError.missingMessageID) {
    try await adapter.perform(.moveToJunk, for: MailReply.identity(messageID: nil))
  }
  #expect(await runner.requests.isEmpty)
}

@Test
func `refuses an automatic action once the message has left its recorded mailbox`()
  async throws
{
  let runner = StubAppleEvents([.findMessages: [MailReply.found()]])
  await #expect(throws: IntegrationError.messageMoved) {
    try await AppleMailAdapter(runner: runner).perform(.moveToJunk, for: MailReply.identity())
  }
  #expect(await runner.searchedMailboxes == ["Inbox"])
  #expect(await runner.appliedCount == 0)
}

@Test
func `corrects a message wherever it has moved within its account`() async throws {
  let receipts = MailReply.message(mailbox: "Receipts", localID: 7)
  let runner = StubAppleEvents([
    .findMessages: [MailReply.found(), MailReply.found(receipts)],
    .applyAction: [MailReply.applied],
    .observeMessages: [MailReply.found(MailReply.message(mailbox: "Junk", localID: 8))]
  ])
  let adapter = AppleMailAdapter(runner: runner, observationInterval: .zero)
  let receipt = try await adapter.performCorrection(.moveToJunk, for: MailReply.identity())
  #expect(await runner.searchedMailboxes == ["Inbox", nil])
  #expect(await runner.moves.map(\.mailbox) == ["Receipts"])
  #expect(receipt.confirmed)
  #expect(receipt.updatedIdentity?.mailbox == "Junk")
  #expect(receipt.updatedIdentity?.localID == 8)
}

@Test
func `runs corrections and lookups interactively and automatic actions in the background`()
  async throws
{
  let runner = StubAppleEvents([
    .findMessages: [MailReply.found(MailReply.message())], .applyAction: [MailReply.applied]
  ])
  let adapter = AppleMailAdapter(runner: runner)
  _ = try await adapter.perform(.orangeFlag, for: MailReply.identity())
  #expect(Set(await runner.lanes) == [.background])
  _ = try await adapter.lookup(MailReply.identity())
  _ = try await adapter.performCorrection(.orangeFlag, for: MailReply.identity())
  #expect(await runner.lanes.dropFirst(2).allSatisfy { $0 == .interactive })
}

@Test
func `runs an interactive call while a background call is still running`() async throws {
  let source = """
    on slow()
        delay 1
        return 1
    end slow
    on quick()
        return 2
    end quick
    """
  let background = AppleScriptExecutor(lane: .background, source: source)
  let interactive = AppleScriptExecutor(lane: .interactive, source: source)
  _ = try await interactive.call("quick", [])
  let slow = Task { try await background.call("slow", []) }
  try await Task.sleep(for: .milliseconds(200))
  let clock = ContinuousClock(), start = clock.now
  #expect(try await interactive.call("quick", []) == .integer(2))
  #expect(clock.now - start < .milliseconds(500))
  #expect(try await slow.value == .integer(1))
}

@Test
func `resolves duplicate Message-IDs by content and local ID`() throws {
  let identity = MailReply.identity(localID: 2)
  let other = try MailRow(MailReply.message(localID: 1, source: "From: a@example.org\n\nOther"))
  let first = try MailRow(MailReply.message(localID: 2))
  let second = try MailRow(MailReply.message(localID: 3))
  #expect(try AppleMailAdapter.select(identity, from: [other, second])?.location.localID == 3)
  #expect(try AppleMailAdapter.select(identity, from: [first, second])?.location.localID == 2)
  #expect(throws: IntegrationError.ambiguous) {
    try AppleMailAdapter.select(MailReply.identity(localID: nil), from: [first, second])
  }
  #expect(throws: IntegrationError.staleMessage) {
    try AppleMailAdapter.select(identity, from: [other])
  }
  let oversized = try MailRow(MailReply.message(localID: 4, source: nil))
  #expect(throws: IntegrationError.messageTooLarge) {
    try AppleMailAdapter.select(identity, from: [other, oversized])
  }
  #expect(try AppleMailAdapter.select(identity, from: []) == nil)
}

@Test
func `reports a move as unconfirmed when its observation is cancelled`() async throws {
  let unobserved = StubAppleEvents([
    .findMessages: [MailReply.found(MailReply.message())],
    .applyAction: [MailReply.applied],
    .observeMessages: [MailReply.found()]
  ])
  let polling = Task {
    try await AppleMailAdapter(runner: unobserved, observationInterval: .milliseconds(5))
      .perform(.moveToJunk, for: MailReply.identity())
  }
  while await unobserved.appliedCount == 0 { await Task.yield() }
  polling.cancel()
  #expect(try await polling.value.confirmed == false)
}

@Test
func `reports a move that exceeds the call time limit as unconfirmed`() async throws {
  let slowMove = StubAppleEvents(
    [.findMessages: [MailReply.found(MailReply.message())], .applyAction: [MailReply.applied]],
    delays: [.applyAction: .seconds(10)]
  )
  let limited = AppleMailAdapter(runner: slowMove, callTimeLimit: .milliseconds(50))
  #expect(try await limited.perform(.moveToJunk, for: MailReply.identity()).confirmed == false)
}

@Test
func `times out a lookup that exceeds the call time limit`() async {
  let slowRead = StubAppleEvents(
    [.findMessages: [MailReply.found(MailReply.message())]],
    delays: [.findMessages: .seconds(10)]
  )
  await #expect(throws: IntegrationError.timedOut) {
    try await AppleMailAdapter(runner: slowRead, callTimeLimit: .milliseconds(50))
      .lookup(MailReply.identity())
  }
}

@Test
func `stops the disposable probe when its first move does not settle`() async throws {
  let inbox = MailReply.message()
  let unstable = StubAppleEvents([
    .selectedRows: [MailReply.selection(inbox)],
    .findMessages: [MailReply.found(inbox)],
    .applyAction: [MailReply.applied],
    .observeMessages: [MailReply.found(inbox), MailReply.found()]
  ])
  let probe = AppleMailAdapter(
    runner: unstable,
    moveSettlingTime: .milliseconds(50),
    observationInterval: .zero
  )
  await #expect(throws: IntegrationError.actionUnconfirmed) {
    try await probe.testDisposableMessage()
  }
  #expect(await unstable.moves.count == 1)
}

@Test
func `refuses to probe a selected message that is not a probe`() async {
  let ordinary = MailReply.selection(MailReply.message(source: "From: a@example.org\r\n\r\nMail"))
  let runner = StubAppleEvents([.selectedRows: [ordinary]])
  await #expect(throws: IntegrationError.notProbeMessage) {
    try await AppleMailAdapter(runner: runner).testDisposableMessage()
  }
  #expect(await runner.appliedCount == 0)
}

@Test
func `moves the disposable probe to Junk and back after each move settles`() async throws {
  let inbox = MailReply.message(), junk = MailReply.message(mailbox: "Junk", localID: 2)
  let restored = MailReply.message(localID: 3)
  let settled = StubAppleEvents(
    [
      .selectedRows: [MailReply.selection(inbox)],
      .findMessages: [MailReply.found(inbox), MailReply.found(junk), MailReply.found(restored)],
      .applyAction: [MailReply.applied]
    ],
    observations: [
      .inbox: [MailReply.found(inbox), MailReply.found(restored)], .junk: [MailReply.found(junk)]
    ]
  )
  let window = Duration.milliseconds(40)
  let adapter = AppleMailAdapter(
    runner: settled,
    moveSettlingTime: window,
    observationInterval: .milliseconds(5)
  )
  let clock = ContinuousClock(), start = clock.now
  #expect(try await adapter.testDisposableMessage() == "account")
  #expect(clock.now - start >= window * 2)
  #expect(await settled.moves.map(\.mailbox) == ["Inbox", "Junk"])
  #expect(await settled.searchedMailboxes == ["Inbox", "Junk", "Inbox"])
}

@Test
func `rejects a disposable probe whose move reverts before the settling window ends`()
  async throws
{
  let inbox = MailReply.message(), junk = MailReply.message(mailbox: "Junk", localID: 2)
  let reverting = StubAppleEvents(
    [
      .selectedRows: [MailReply.selection(inbox)],
      .findMessages: [MailReply.found(inbox)],
      .applyAction: [MailReply.applied]
    ],
    observations: [
      .inbox: [MailReply.found(inbox)],
      .junk: [MailReply.found(junk), MailReply.found(junk), MailReply.found()]
    ]
  )
  let probe = AppleMailAdapter(
    runner: reverting,
    moveSettlingTime: .milliseconds(40),
    observationInterval: .milliseconds(5)
  )
  await #expect(throws: IntegrationError.actionUnconfirmed) {
    try await probe.testDisposableMessage()
  }
  #expect(await reverting.moves.count == 1)
}

@Test(arguments: [false, true])
func `rechecks an automatic move once the settling window ends`(reverted: Bool) async throws {
  let store = try testStore()
  try await StateRepository.update(store) { state in
    state.settings.dryRun = false
    state.settings.validatedAccounts = ["account"]
  }
  let junk = MailReply.found(MailReply.message(mailbox: "Junk", localID: 2))
  let runner = StubAppleEvents(
    [.findMessages: [MailReply.found(MailReply.message())], .applyAction: [MailReply.applied]],
    observations: [.junk: [junk, junk] + (reverted ? [MailReply.found()] : [])]
  )
  let window = Duration.seconds(1)
  let adapter = AppleMailAdapter(
    runner: runner,
    moveSettlingTime: window,
    observationInterval: .milliseconds(1)
  )
  let pipeline = Pipeline(store: store, classifier: junkClassifier)
  let message = MailEnvelope(
    identity: MailReply.identity(),
    raw: Data(MailReply.probeSource.utf8)
  )
  let clock = ContinuousClock(), start = clock.now
  let record = await pipeline.process(message, adapter: adapter)
  #expect(clock.now - start < window)
  #expect(record.outcome == .applied)
  await pipeline.settleMoves()
  let saved = try await StateRepository.load(store, StateSlices(records: .only([record.id])))
  #expect(saved.records.first?.outcome == (reverted ? .requested : .applied))
}

@Test
@MainActor
func `invokes compiled handlers with typed arguments and private error numbers`() throws {
  let library = try AppleScriptLibrary(
    source: """
      on echovalues(a, b, c)
          return {a, b, c}
      end echovalues
      on fail(n)
          error "Failed" number n
      end fail
      on unary()
          return true
      end unary
      """
  )
  #expect(try library.call("unary", []) == .boolean(true))
  #expect(
    try library.call("echovalues", [.string("Quot\"ed"), .list([.integer(5)]), .boolean(false)])
      == .list([.string("Quot\"ed"), .list([.integer(5)]), .boolean(false)])
  )
  for failure in MailScriptError.allCases {
    let error = try #require(throws: AppleScriptFailure.self) {
      try library.call("fail", [.integer(failure.rawValue)])
    }
    #expect(error.number == failure.rawValue)
    #expect(error.integrationError == failure.integrationError)
  }
  _ = try AppleScriptLibrary(source: MailScripts.library)
}

@Test
@MainActor
func `decodes Apple Event booleans`() throws {
  for (source, expected) in [
    ("return true", ScriptValue.boolean(true)),
    ("return false", .boolean(false)),
    ("return {true, false}", .list([.boolean(true), .boolean(false)]))
  ] {
    let script = try #require(NSAppleScript(source: source))
    #expect(ScriptValue.decode(unsafe script.executeAndReturnError(nil)) == expected)
  }
}

@Test
func `persists Inbox sweep progress and wraps after the last page`() async throws {
  let store = try testStore()
  try await MailHealthRepository.update(store, accountID: "account", name: "Test") {
    $0.complete(count: 20, total: 21)
  }
  let restarted = try Store(url: store.url)
  #expect(try await MailHealthRepository.load(restarted)["account"]?.nextOffset == 20)
  try await MailHealthRepository.update(store, accountID: "other", name: "Other") {
    $0.failure = "unavailable"
  }
  try await MailHealthRepository.update(store, accountID: "account", name: "Test") {
    $0.complete(count: 1, total: 21)
  }
  let health = try await MailHealthRepository.load(store)
  #expect(health["account"]?.nextOffset == 0)
  #expect(health["account"]?.lastCompletedSweep != nil)
  #expect(health["other"]?.failure == "unavailable")
}

@Test
func `persists the unreadable count with sweep progress`() async throws {
  let store = try testStore()
  try await MailHealthRepository.update(store, accountID: "account", name: "Test") {
    $0.complete(count: 2, total: 3, unavailable: 1)
  }
  let resumed = try await MailHealthRepository.load(try Store(url: store.url))["account"]
  #expect(resumed?.nextOffset == 2)
  #expect(resumed?.unavailableCount == 1)
}

@Test
func `reports the completed sweep's unreadable count until the next sweep completes`() {
  var health = MailScanHealth(accountName: "Test")
  health.complete(count: 2, total: 3, unavailable: 1)
  health.complete(count: 1, total: 3)
  #expect(health.nextOffset == 0)
  #expect(health.unavailableCount == 1)
  health.complete(count: 0, total: 0)
  #expect(health.unavailableCount == 0)
}

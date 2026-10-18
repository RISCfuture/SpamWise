import Foundation
import Synchronization
import Testing
import SpamWiseCore
@testable import MailIntegration

@Test func `refuses unscoped identities and unverifiable moves before contacting Mail`() async {
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

@Test func `acts only in the recorded mailbox unless the user corrects the message`() async throws {
  let receipts = MailReply.message(mailbox: "Receipts", localID: 7)
  let runner = StubAppleEvents([
    .findMessages: [MailReply.found(), MailReply.found(), MailReply.found(receipts)],
    .applyAction: [MailReply.applied],
    .observeMessages: [MailReply.found(MailReply.message(mailbox: "Junk", localID: 8))]
  ])
  let adapter = AppleMailAdapter(runner: runner, observationInterval: .zero)
  await #expect(throws: IntegrationError.messageMoved) {
    try await adapter.perform(.moveToJunk, for: MailReply.identity())
  }
  #expect(await runner.appliedCount == 0)
  let receipt = try await adapter.performCorrection(.moveToJunk, for: MailReply.identity())
  #expect(await runner.searchedMailboxes == ["Inbox", "Inbox", nil])
  #expect(await runner.moves.map(\.mailbox) == ["Receipts"])
  #expect(receipt.confirmed)
  #expect(receipt.updatedIdentity?.mailbox == "Junk")
  #expect(receipt.updatedIdentity?.localID == 8)
}

@Test func `resolves duplicate Message-IDs by content and local ID`() throws {
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

@Test func `reports moves as unknown once Mail may have applied them`() async throws {
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
  let slowMove = StubAppleEvents(
    [.findMessages: [MailReply.found(MailReply.message())], .applyAction: [MailReply.applied]],
    delays: [.applyAction: .seconds(10)]
  )
  let limited = AppleMailAdapter(runner: slowMove, callTimeLimit: .milliseconds(50))
  #expect(try await limited.perform(.moveToJunk, for: MailReply.identity()).confirmed == false)
  let slowRead = StubAppleEvents(
    [.findMessages: [MailReply.found(MailReply.message())]],
    delays: [.findMessages: .seconds(10)]
  )
  await #expect(throws: IntegrationError.timedOut) {
    try await AppleMailAdapter(runner: slowRead, callTimeLimit: .milliseconds(50))
      .lookup(MailReply.identity())
  }
}

@Test func `verifies the disposable probe through each settled move`() async throws {
  let inbox = MailReply.message(), junk = MailReply.message(mailbox: "Junk", localID: 2)
  let restored = MailReply.message(localID: 3)
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
  let ordinary = MailReply.selection(MailReply.message(source: "From: a@example.org\r\n\r\nMail"))
  await #expect(throws: IntegrationError.notProbeMessage) {
    try await AppleMailAdapter(runner: StubAppleEvents([.selectedRows: [ordinary]]))
      .testDisposableMessage()
  }
  let settled = StubAppleEvents([
    .selectedRows: [MailReply.selection(inbox)],
    .findMessages: [MailReply.found(inbox), MailReply.found(junk), MailReply.found(restored)],
    .applyAction: [MailReply.applied],
    .observeMessages: [
      MailReply.found(inbox), MailReply.found(junk), MailReply.found(junk),
      MailReply.found(restored)
    ]
  ])
  let adapter = AppleMailAdapter(runner: settled, observationInterval: .zero)
  #expect(try await adapter.testDisposableMessage() == "account")
  #expect(await settled.moves.map(\.mailbox) == ["Inbox", "Junk"])
  #expect(await settled.searchedMailboxes == ["Inbox", "Junk", "Inbox"])
}
@Test @MainActor
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

final class Counter: Sendable {
  private let storage = Mutex(0)
  var value: Int { storage.withLock { $0 } }
  func increment() { storage.withLock { $0 += 1 } }
}
@Test @MainActor func `decodes Apple Event booleans`() throws {
  for (source, expected) in [
    ("return true", ScriptValue.boolean(true)),
    ("return false", .boolean(false)),
    ("return {true, false}", .list([.boolean(true), .boolean(false)]))
  ] {
    let script = try #require(NSAppleScript(source: source))
    #expect(ScriptValue.decode(unsafe script.executeAndReturnError(nil)) == expected)
  }
}

@Test func `persists Inbox sweep progress and wraps after the last page`() async throws {
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

@Test func `skips unreadable messages in pages and selections`() async throws {
  let oversized = MailReply.message(
    localID: 1,
    messageID: "oversized",
    source: String(repeating: "x", count: MailScripts.maximumMessageBytes + 1)
  )
  let unreadable = MailReply.message(localID: 3, messageID: "missing", source: nil)
  let readable = MailReply.message(
    localID: 2,
    messageID: "readable",
    source: "From: person@example.org\nSubject: Later mail\n\nHello"
  )
  let partial = AppleMailAdapter(
    runner: StubAppleEvents([
      .accountPage: [MailReply.page(total: 3, [oversized, readable])],
      .selectedRows: [MailReply.selection(unreadable, readable)]
    ])
  )
  let page = try await partial.inboxPage(accountID: "account", offset: 0, limit: 20)
  #expect(page.messages.map { $0.identity.localID } == [2])
  #expect(page.visitedCount == 2)
  #expect(page.unavailableCount == 1)
  let selection = try await partial.selectedMessages()
  #expect(selection.messages.map { $0.identity.localID } == [2])
  #expect(selection.unavailableCount == 1)
  let store = try testStore()
  try await MailHealthRepository.update(store, accountID: "account", name: "Test") {
    $0.complete(count: page.visitedCount, total: 3, unavailable: page.unavailableCount)
  }
  let resumed = try await MailHealthRepository.load(try Store(url: store.url))["account"]
  #expect(resumed?.nextOffset == 2)
  #expect(resumed?.unavailableCount == 1)
  var completed = try #require(resumed)
  completed.complete(count: 1, total: 3)
  #expect(completed.nextOffset == 0)
  #expect(completed.unavailableCount == 1)
  completed.complete(count: 0, total: 0)
  #expect(completed.unavailableCount == 0)
  let allUnreadable = try AppleMailAdapter.decodePage(
    MailReply.page(total: 3, [unreadable]),
    accountID: "account",
    offset: 2,
    limit: 20
  )
  #expect(allUnreadable.messages.isEmpty)
  #expect(allUnreadable.visitedCount == 1)
  for accountID in ["other", ""] {
    #expect(throws: IntegrationError.mailboxUnresolved) {
      try AppleMailAdapter.decodePage(
        MailReply.page(total: 1, [unreadable]),
        accountID: accountID,
        offset: 0,
        limit: 20
      )
    }
  }
  #expect(throws: IntegrationError.scriptFailed) {
    try AppleMailAdapter.decodePage(
      MailReply.page(total: 1, []),
      accountID: "account",
      offset: 0,
      limit: 20
    )
  }
}

@Test func `claims training corrections atomically and keeps uncertain moves claimed`() async throws
{
  let store = try testStore(), adapter = RecordingAdapter()
  var selected = try envelope()
  selected.identity.mailbox = "SpamWise Train Good"
  var plan = MailFolderPlan(
    folder: .init(accountID: "account-A", path: ["SpamWise Train Good"]),
    purpose: .trainGood
  )
  plan.enabled = true
  let unvalidated = plan
  try await StateRepository.editSettings(store) { $0.mailOptions.folderPlans = [unvalidated] }
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in
      Issue.record("Deliberate training must not classify first")
      throw ClassificationError.configuration
    })
  )
  await #expect(throws: IntegrationError.self) {
    try await pipeline.correct(
      envelope: selected,
      label: .inbox,
      adapter: adapter,
      trainingPlanID: plan.id
    )
  }
  plan.trainingBaselineValidated = true
  let validated = plan
  try await StateRepository.editSettings(store) { $0.mailOptions.folderPlans = [validated] }
  let first = try await pipeline.correct(
    envelope: selected,
    label: .inbox,
    adapter: adapter,
    trainingPlanID: plan.id
  )
  await #expect(throws: IntegrationError.staleMessage) {
    try await pipeline.correct(
      envelope: selected,
      label: .inbox,
      adapter: adapter,
      trainingPlanID: plan.id
    )
  }
  #expect(try await StateRepository.load(store).corrections.count == 1)
  try await TrainingFolders.observe(
    [],
    planID: plan.id,
    sweepComplete: true,
    canReleaseClaims: false,
    store: store
  )
  let incomplete = try await StateRepository.load(store)
  #expect(incomplete.trainingClaims.count == 1)
  #expect(incomplete.trainingObservations[plan.id]?.isEmpty == true)
  try await TrainingFolders.observe(
    [selected.identity],
    planID: plan.id,
    sweepComplete: true,
    canReleaseClaims: false,
    store: store
  )
  #expect(try await StateRepository.load(store).trainingObservations[plan.id]?.isEmpty == true)
  try await TrainingFolders.observe([], planID: plan.id, sweepComplete: true, store: store)
  #expect(try await StateRepository.load(store).trainingClaims.isEmpty == true)
  let second = try await pipeline.correct(
    envelope: selected,
    label: .inbox,
    adapter: adapter,
    trainingPlanID: plan.id
  )
  #expect(second.id != first.id)
  try await StateRepository.update(store) { state in
    if let index = state.records.firstIndex(where: { $0.id == second.id }) {
      state.records[index].outcome = .failed
    }
  }
  try await TrainingFolders.observe([], planID: plan.id, sweepComplete: true, store: store)
  #expect(try await StateRepository.load(store).trainingClaims.count == 1)
  #expect(await adapter.actions.isEmpty)
}

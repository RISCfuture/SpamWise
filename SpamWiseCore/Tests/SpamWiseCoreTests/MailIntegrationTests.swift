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
  let ordinary = ScriptValue.list([
    .string("account"), .string("Inbox"), .integer(1), .string("id"),
    .string(raw.replacingOccurrences(of: "[SpamWise Probe]", with: "Ordinary"))
  ])
  await #expect(throws: IntegrationError.notProbeMessage) {
    try await AppleMailAdapter(runner: StubAppleEvents(ordinary)).testDisposableMessage()
  }
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
@Test func `previews extension mail only on the chosen all-account Apple Mail route`() async throws
{
  let store = try testStore(), calls = Counter()
  let classifier = MockClassifier { _ in
    calls.increment()
    return .init(label: .junk, confidence: 99, reason: "Synthetic spam")
  }
  let raw = try fixture("filler-spam")
  func preview(_ edit: @Sendable (inout Settings) -> Void) async throws -> DecisionRecord? {
    try await StateRepository.update(store) { state in
      state.settings = Settings(); state.settings.onboardingComplete = true
      edit(&state.settings)
    }
    return try await MailExtensionPreview.process(
      raw: raw,
      store: store,
      classifier: classifier,
      timeout: 1
    )
  }
  #expect(try await preview { _ in } == nil)
  #expect(
    try await preview {
      $0.route = .mailKit; $0.mailOptions.accountIDs = ["work"]
    } == nil
  )
  #expect(
    try await preview {
      $0.route = .mailKit; $0.advancedOptions.transport = .imap
    } == nil
  )
  #expect(
    try await preview {
      $0.route = .mailKit; $0.paused = true
    } == nil
  )
  #expect(
    try await preview {
      $0.route = .mailKit; $0.onboardingComplete = false
    } == nil
  )
  #expect(calls.value == 0)
  #expect(try await StateRepository.load(store).records.isEmpty)

  let previewed = try await preview {
    $0.route = .mailKit; $0.dryRun = false
  }
  #expect(previewed?.outcome == .dryRun)
  #expect(calls.value == 1)

  var settings = try await StateRepository.load(store).settings
  #expect(FilteringStatus(settings: settings, mailAutomation: .granted) == .extensionPreview)
  settings.mailOptions.accountIDs = ["work"]
  #expect(FilteringStatus(settings: settings, mailAutomation: .granted) == .extensionScoped)
  #expect(!FilteringStatus(settings: settings, mailAutomation: .granted).allowsAutomaticChecks)
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
    try MailScripts.markRead(identity, expectedSource: "From: x\n\nbody"),
    MailScripts.folders, MailScripts.destinations(accountID: "test-account"),
    try MailScripts.folderPage(
      .init(accountID: "account", path: ["Parent", "Quot\"ed"]),
      offset: 0,
      limit: 20,
      since: Date()
    ),
    MailScripts.accounts, MailScripts.selected, MailScripts.selectedBatch,
    MailScripts.recent(limit: 5, offset: 20),
    MailScripts.accountPage(accountID: "test-account", offset: 20, limit: 5),
    MailScripts.accountPage(accountID: "test-account", offset: 0, limit: 5, role: "junk mailbox"),
    MailScripts.accountPage(
      accountID: "test-account",
      offset: 0,
      limit: 5,
      role: "sent mailbox",
      headersOnly: true
    ),
    MailScripts.accountPage(accountID: "test-account", offset: 0, limit: 5, since: Date()),
    MailScripts.accountPage(accountID: "test-account", offset: 20, limit: 5, before: Date()),
    try MailScripts.resolve(identity, operation: "open targetMessage\nreturn true"),
    try MailScripts.lookup(identity),
    try MailScripts.lookup(identity, action: .moveToJunk, expectedSource: "From: x\n\nbody"),
    try MailScripts.lookup(identity, action: .orangeFlag, expectedSource: "From: x\n\nbody"),
    try MailScripts.lookup(identity, action: .orangeBackground, expectedSource: "From: x\n\nbody"),
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

@Test func `resumes Inbox sweeps past unreadable messages and wraps after the last page`()
  async throws
{
  let store = try testStore()
  try await MailHealthRepository.update(store, accountID: "account", name: "Test") {
    $0.complete(count: 20, total: 21)
  }
  let restarted = try await Store(url: store.url)
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
  let oversized = ScriptValue.list([
    .string("account"), .string("Inbox"), .integer(1), .string("oversized"),
    .string(String(repeating: "x", count: 2_000_001))
  ])
  let readable = ScriptValue.list([
    .string("account"), .string("Inbox"), .integer(2), .string("readable"),
    .string("From: person@example.org\nSubject: Later mail\n\nHello")
  ])
  let partial = AppleMailAdapter(
    runner: StubAppleEvents(.list([.integer(2), .list([oversized, readable])]))
  )
  let page = try await partial.inboxPage(accountID: "account", offset: 0, limit: 20)
  #expect(page.messages.map { $0.identity.localID } == [2])
  #expect(page.visitedCount == 2)
  #expect(page.unavailableCount == 1)
  try await MailHealthRepository.update(store, accountID: "account", name: "Test") {
    $0.complete(count: page.visitedCount, total: 3, unavailable: page.unavailableCount)
  }
  let resumed = try await MailHealthRepository.load(Store(url: store.url))["account"]
  #expect(resumed?.nextOffset == 2)
  #expect(resumed?.unavailableCount == 1)
  var completed = try #require(resumed)
  completed.complete(count: 1, total: 3)
  #expect(completed.nextOffset == 0)
  #expect(completed.unavailableCount == 1)
  completed.complete(count: 0, total: 0)
  #expect(completed.unavailableCount == 0)
  let unreadable = ScriptValue.list([
    .string("account"), .string("Inbox"), .integer(3), .string("missing"), .boolean(false)
  ])
  let allUnreadable = try AppleMailAdapter.decodePage(
    .list([.integer(3), .list([unreadable])]),
    accountID: "account",
    offset: 2,
    limit: 20
  )
  #expect(allUnreadable.messages.isEmpty)
  #expect(allUnreadable.visitedCount == 1)
  for accountID in ["other", ""] {
    #expect(throws: IntegrationError.ambiguous) {
      try AppleMailAdapter.decodePage(
        .list([.integer(1), .list([unreadable])]),
        accountID: accountID,
        offset: 0,
        limit: 20
      )
    }
  }
  #expect(throws: IntegrationError.scriptFailed) {
    try AppleMailAdapter.decodePage(
      .list([.integer(1), .list([])]),
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
  #expect(incomplete.trainingClaims?.count == 1)
  #expect(incomplete.trainingObservations?[plan.id]?.isEmpty == true)
  try await TrainingFolders.observe(
    [selected.identity],
    planID: plan.id,
    sweepComplete: true,
    canReleaseClaims: false,
    store: store
  )
  #expect(try await StateRepository.load(store).trainingObservations?[plan.id]?.isEmpty == true)
  try await TrainingFolders.observe([], planID: plan.id, sweepComplete: true, store: store)
  #expect(try await StateRepository.load(store).trainingClaims?.isEmpty == true)
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
  #expect(try await StateRepository.load(store).trainingClaims?.count == 1)
  #expect(await adapter.actions.isEmpty)
}

import Foundation
import Synchronization
import Testing
import SpamWiseCore

/// An in-memory client whose Inbox and folder pages are addressed newest first.
private actor StubSweepSource: PositionalInboxSource {
  private var inboxes: [String: [MailEnvelope]]
  private var folderMessages: [String: [MailEnvelope]] = [:]
  private var failures: [String: any Error] = [:]
  private let accountIDs: [String]
  private(set) var actions: [MailAction] = []

  init(_ inboxes: [(String, [MailEnvelope])]) {
    accountIDs = inboxes.map(\.0)
    self.inboxes = Dictionary(uniqueKeysWithValues: inboxes)
  }

  static func message(
    _ account: String,
    _ index: Int,
    mailbox: String = "Inbox",
    from sender: String = "person@example.org"
  ) -> MailEnvelope {
    let raw = Data(
      """
      From: \(sender)\r
      Subject: Message \(index)\r
      Message-ID: <\(account)-\(index)@example.org>\r
      \r
      Hello \(index)
      """.utf8
    )
    return MailEnvelope(
      identity: .init(
        accountID: account,
        messageID: "<\(account)-\(index)@example.org>",
        localID: index,
        mailbox: mailbox,
        contentHash: stableHash(raw)
      ),
      raw: raw
    )
  }

  private static func page(_ messages: [MailEnvelope], offset: Int, limit: Int) -> MailPage {
    let rows = Array(messages.dropFirst(offset).prefix(limit))
    return MailPage(messages: rows, total: messages.count, visitedCount: rows.count)
  }

  func fail(_ accountID: String, with error: any Error) { failures[accountID] = error }
  func deliver(_ envelope: MailEnvelope, to accountID: String) {
    inboxes[accountID, default: []].insert(envelope, at: 0)
  }
  func place(_ envelopes: [MailEnvelope], in folder: MailFolder) {
    folderMessages[folder.id] = envelopes
  }

  func sweepAccounts() throws -> [MailAccount] {
    accountIDs.map { MailAccount(id: $0, name: $0) }
  }
  func inboxSweepPage(accountID: String, offset: Int, limit: Int, since _: Date?) throws
    -> MailPage
  {
    if let failure = failures[accountID] { throw failure }
    return Self.page(inboxes[accountID] ?? [], offset: offset, limit: limit)
  }
  func folderPage(_ folder: MailFolder, offset: Int, limit: Int, since _: Date?) throws
    -> MailPage
  {
    Self.page(folderMessages[folder.id] ?? [], offset: offset, limit: limit)
  }
  func historyPage(accountID _: String, mailbox _: HistoryMailbox, offset _: Int, limit _: Int)
    throws -> MailPage
  {
    MailPage(messages: [], total: 0, visitedCount: 0)
  }
  func lookup(_: MessageIdentity) throws -> MailEnvelope? { nil }
  func recentMessages(limit _: Int) throws -> [MailEnvelope] { [] }
  /// Records `action`; a move takes the message out of every folder.
  func perform(_ action: MailAction, for identity: MessageIdentity) throws -> ActionReceipt {
    actions.append(action)
    if [.moveToJunk, .moveToInbox].contains(action) {
      for folder in folderMessages.keys {
        folderMessages[folder]?.removeAll { $0.identity.key == identity.key }
      }
    }
    return ActionReceipt(confirmed: true)
  }
}

/// Subjects in the order the classifier received them.
private final class ClassifiedSubjects: Sendable {
  private let subjects = Mutex<[String]>([])
  var all: [String] { subjects.withLock { $0 } }

  func append(_ subject: String) { subjects.withLock { $0.append(subject) } }
}

@Suite
struct `Mail sweeper` {
  private let store: Store
  private let classified = ClassifiedSubjects()

  init() throws { store = try testStore() }

  private func sweeper(_ source: StubSweepSource, label: MailLabel = .inbox) -> MailSweeper {
    sweeper(source) { _ in label }
  }

  /// A sweeper whose classifier labels each message by its subject.
  private func sweeper(
    _ source: StubSweepSource,
    labelling label: @escaping @Sendable (String) -> MailLabel
  ) -> MailSweeper {
    let classified = classified
    let pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(operation: { input in
        classified.append(input.message.subject)
        return Verdict(label: label(input.message.subject), confidence: 99, reason: "fixture")
      })
    )
    return MailSweeper(source: source, store: store, pipeline: pipeline)
  }

  /// Saves an enabled filtering plan for `folder` and turns on live actions for its account.
  private func filterLive(_ folder: MailFolder) async throws {
    var plan = MailFolderPlan(folder: folder)
    plan.enabled = true
    plan.startDate = .distantPast
    let saved = plan
    try await StateRepository.editSettings(store) {
      $0.mailOptions.folderPlans = [saved]
      $0.validatedAccounts = [folder.accountID]
      $0.dryRun = false
    }
  }

  private func records() async throws -> [DecisionRecord] {
    try await StateRepository.load(store, StateSlices(records: .all)).records
  }

  @Test
  func `classifies newest mail first across sweeps and isolates a failing account`() async throws {
    let source = StubSweepSource([
      ("broken", [StubSweepSource.message("broken", 1)]),
      ("account", (1...3).reversed().map { StubSweepSource.message("account", $0) })
    ])
    await source.fail("broken", with: IntegrationError.scriptFailed)
    let sweeper = sweeper(source)

    let first = try await sweeper.sweep(dryRun: true, limit: 2)
    #expect(first.sweptAccounts == 1 && first.failures == 1)
    #expect(classified.all == ["Message 3", "Message 2", "Message 1"])
    let health = try await MailHealthRepository.load(store)
    #expect(health["broken"]?.failure != nil)
    #expect(health["broken"]?.consecutiveFailures == 1)
    #expect(health["account"]?.coverage.classified == 3)
    #expect(health["account"]?.nextOffset == 0)

    await source.deliver(StubSweepSource.message("account", 4), to: "account")
    try await sweeper.sweep(dryRun: true, limit: 2)
    #expect(classified.all == ["Message 3", "Message 2", "Message 1", "Message 4"])
    let state = try await StateRepository.load(store, StateSlices(histories: .all))
    #expect(state.histories["account"]?.received["example.org"] == 4)
  }

  @Test
  func `ends the sweep on cancellation without recording an account failure`() async throws {
    let source = StubSweepSource([
      ("cancelled", [StubSweepSource.message("cancelled", 1)]),
      ("later", [StubSweepSource.message("later", 1)])
    ])
    await source.fail("cancelled", with: CancellationError())
    await #expect(throws: CancellationError.self) {
      try await sweeper(source).sweep(dryRun: true, limit: 20)
    }
    let health = try await MailHealthRepository.load(store)
    #expect(health["cancelled"]?.failure == nil)
    #expect(health["later"] == nil)
    #expect(classified.all.isEmpty)
  }

  @Test
  func `trains past a placement that cannot be corrected and does not retry it every sweep`()
    async throws
  {
    let folder = MailFolder(accountID: "account", path: ["SpamWise Train Junk"])
    var plan = MailFolderPlan(folder: folder, purpose: .trainJunk)
    plan.enabled = true; plan.trainingBaselineValidated = true
    let saved = plan
    try await StateRepository.editSettings(store) { $0.mailOptions.folderPlans = [saved] }
    let source = StubSweepSource([("account", [])])
    let mailbox = folder.path[0]
    await source.place(
      [
        StubSweepSource.message("account", 1, mailbox: mailbox, from: "not an address"),
        StubSweepSource.message("account", 2, mailbox: mailbox),
        StubSweepSource.message("account", 3, mailbox: mailbox)
      ],
      in: folder
    )
    let sweeper = sweeper(source)

    let first = try await sweeper.sweep(dryRun: true, limit: 20)
    #expect(first.failures == 0)
    let corrected = try await records().filter { $0.path == .correction }
    #expect(corrected.compactMap(\.identity.localID).sorted() == [2, 3])
    let health = try await MailHealthRepository.load(store, key: MailSweeper.healthKey(for: plan))
    #expect(health?.lastCompletedSweep != nil)
    #expect(health.map { [$0.coverage.classified, $0.coverage.unclassified] } == [2, 1])

    let recorded = try await records().count
    try await sweeper.sweep(dryRun: true, limit: 20)
    #expect(try await records().count == recorded)
  }

  @Test
  func `reaches folder mail that moved up into positions the previous page emptied`()
    async throws
  {
    let folder = MailFolder(accountID: "account", path: ["Newsletters"])
    try await filterLive(folder)
    let source = StubSweepSource([("account", [])])
    await source.place(
      (1...6).map { StubSweepSource.message("account", $0, mailbox: folder.path[0]) },
      in: folder
    )
    let junk: Set = ["Message 3", "Message 4"]
    let sweeper = sweeper(source) { junk.contains($0) ? .junk : .inbox }

    for _ in 1...3 { try await sweeper.sweep(dryRun: false, limit: 2) }
    #expect(classified.all == (1...6).map { "Message \($0)" })
    #expect(await source.actions == [.moveToJunk, .moveToJunk])
  }

  @Test
  func `previews the advertised total across accounts and reuses unchanged previews`()
    async throws
  {
    let source = StubSweepSource([
      ("first", (1...15).reversed().map { StubSweepSource.message("first", $0) }),
      ("second", (1...15).reversed().map { StubSweepSource.message("second", $0) })
    ])
    let sweeper = sweeper(source, label: .junk)

    let preview = try await sweeper.previewRecent(total: 20)
    #expect(preview.records.count == 20)
    #expect(preview.records.prefix(2).map(\.identity.accountID) == ["first", "second"])
    #expect(preview.records.allSatisfy { $0.outcome == .dryRun })
    let recorded = try await records().count

    let repeated = try await sweeper.previewRecent(total: 20)
    #expect(repeated.records.map(\.id) == preview.records.map(\.id))
    #expect(classified.all.count == 20)
    #expect(try await records().count == recorded)
    #expect(await source.actions.isEmpty)
  }

  @Test
  func `shrinks a timed-out page and then skips a backfill position that keeps stalling`() {
    var health = MailScanHealth(accountName: "account")
    health.complete(through: 40, visited: 40, total: 100)
    let stalled = InboxTraversal(end: 40, total: 100, stalledOffset: 40)
    var limits: [Int] = []
    for _ in 1..<MailScanHealth.skippingTimeouts {
      health.recordStall(stalled, coverage: .init(), failure: "timed out")
      limits.append(health.pageLimit(for: 20))
    }
    #expect(limits == [10, 5, 2, 1, 1])
    #expect(health.nextOffset == 40 && health.isStalled)
    health.recordStall(stalled, coverage: .init(), failure: "timed out")
    #expect(health.nextOffset == 41)
    #expect(health.unavailableInSweep == 1)
    #expect(health.pageLimit(for: 20) == 20)
  }
}

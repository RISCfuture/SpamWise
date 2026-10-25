import Foundation
import Testing
import SpamWiseCore
@testable import MailIntegration

private enum HistoryRows {
  static let authenticated = "Authentication-Results: mx.example; dkim=pass header.d="
  static let shop = receipt("orders@shop.example.org", auth: authenticated + "shop.example.org")
  static let freemail = receipt("deals4u@gmail.com", auth: authenticated + "gmail.com")
  static let unauthenticated = receipt("billing@store.example.net", auth: nil)
  static let corrected = receipt("sales@shop.example.org", auth: authenticated + "shop.example.org")
  static let modelLabelled = receipt(
    "orders@outlet.example.com",
    auth: authenticated + "outlet.example.com"
  )
  static let receipts = [shop, freemail, unauthenticated, corrected, modelLabelled]
  static let inbox = receipts + [oversized]
  static let oversized = row(
    "Inbox",
    id: "oversized",
    .string(String(repeating: "x", count: 2_000_001))
  )
  /// An oversized Sent message, as the header reader reports it, followed by 100 replies whose
  /// header lines end in a bare CR.
  static let sent =
    [row("Sent", id: "unreadable", .boolean(false))]
    + (1...100).map { index in
      row(
        "Sent",
        id: "reply-\(index)",
        .string("To: friend\(index)@example.com\rIn-Reply-To: <original-\(index)>\r")
      )
    }

  /// A Sent mailbox deeper than one run's page budget.
  static let deepSent = (1...600).map { index in
    row("Sent", id: "deep-\(index)", .string("To: friend\(index)@example.com\r"))
  }

  static func receipt(_ sender: String, auth: String?) -> ScriptValue {
    let headers = ["From: \(sender)", "Subject: Your receipt", auth].compactMap(\.self)
    return row(
      "Inbox",
      id: sender,
      .string(headers.joined(separator: "\n") + "\n\nOrder 123 total USD 10")
    )
  }
  static func row(_ mailbox: String, id: String, _ content: ScriptValue) -> ScriptValue {
    let byteCount = content.string?.utf8.count ?? MIMEParser.maximumMessageBytes + 1
    return .list([
      .string("account"), .string(mailbox), .integer(1), .string("<\(id)>"), .integer(byteCount),
      content
    ])
  }
  static func envelope(_ row: ScriptValue) throws -> MailEnvelope {
    try #require(try MailRow(row).envelope)
  }
  static func key(_ row: ScriptValue) throws -> String {
    try envelope(row).identity.key
  }
}
private actor HistoryEvents: AppleEventRunner {
  private let accountIDs: [String]
  private let failingInbox: String?
  private let sentRows: [ScriptValue]
  private var failingSent: String?
  private(set) var sentOffsets: [String: [Int]] = [:]
  private(set) var inboxOffsets: [String: [Int]] = [:]

  init(
    accounts: [String] = ["account"],
    sentRows: [ScriptValue] = HistoryRows.sent,
    failingInbox: String? = nil,
    failingSent: String? = nil
  ) {
    accountIDs = accounts
    self.sentRows = sentRows
    self.failingInbox = failingInbox
    self.failingSent = failingSent
  }

  /// Makes every Sent read of `account` fail, or none when nil.
  func failSent(_ account: String?) { failingSent = account }

  func run(_ request: MailRequest) throws -> ScriptValue {
    if request == .accounts {
      return .list(accountIDs.map { .list([.string($0), .string($0), .list([])]) })
    }
    guard case let .accountPage(role, account, offset, limit, headersOnly, _, _) = request,
      accountIDs.contains(account), role != .junk
    else { throw IntegrationError.scriptFailed }
    let isSent = role == .sent
    guard headersOnly == isSent else { throw IntegrationError.scriptFailed }
    if isSent {
      sentOffsets[account, default: []].append(offset)
    } else {
      inboxOffsets[account, default: []].append(offset)
    }
    if account == (isSent ? failingSent : failingInbox) { throw IntegrationError.scriptFailed }
    let rows = (isSent ? sentRows : HistoryRows.inbox).map { row in
      row.list.map { ScriptValue.list([.string(account)] + $0.dropFirst()) } ?? row
    }
    return .list([.integer(rows.count), .list(Array(rows.dropFirst(offset).prefix(limit)))])
  }
}
/// Receipts the model kept in the Inbox during a dry run, one of them corrected to Junk.
@Suite
struct `Receipt history` {
  private static let trustedServers: Set<String> = ["mx.example"]
  private var state = AppState()
  private let sent: [MailEnvelope]
  private let inbox: [MailEnvelope]

  init() throws {
    for row in HistoryRows.receipts {
      state.record(
        .init(
          identity: try HistoryRows.envelope(row).identity,
          decision: .init(label: .inbox, action: .none, reason: .model("Wanted")),
          outcome: .dryRun
        )
      )
    }
    correct(&state, key: try HistoryRows.key(HistoryRows.corrected), as: .junk)
    sent = try HistoryRows.sent.compactMap { try MailRow($0).envelope }
    inbox = try HistoryRows.inbox.compactMap { try MailRow($0).envelope }
  }

  /// The history ingested from the fixture's mailboxes, after the user kept the shop receipt.
  private func confirmedIndex() throws -> HistoryIndex {
    var state = state
    correct(&state, key: try HistoryRows.key(HistoryRows.shop), as: .inbox)
    return ingested(eligible: state.historyEligibleInbox)
  }

  private func ingested(
    eligible: [String: InboxEligibility]? = nil,
    trustedAuthServers: Set<String> = Self.trustedServers
  ) -> HistoryIndex {
    var index = HistoryIndex()
    index.received["prior.example"] = 4
    if let eligible {
      index.ingest(
        sent: sent,
        inbox: inbox,
        eligible: eligible,
        trustedAuthServers: trustedAuthServers
      )
    } else {
      index.ingest(sent: sent, inbox: inbox, trustedAuthServers: trustedAuthServers)
    }
    return index
  }

  @Test
  func `counts no receipts from Inbox mail without eligibility`() throws {
    #expect(ingested().senderReceipts == nil)
  }

  @Test
  func `excludes a receipt the user corrected to Junk`() throws {
    #expect(state.historyEligibleInbox[try HistoryRows.key(HistoryRows.corrected)] == nil)
  }

  @Test
  func `authenticates no receipt until the user confirms one`() {
    #expect(ingested(eligible: state.historyEligibleInbox).authenticatedSenderReceipts == nil)
  }

  @Test
  func `counts receipts from exact non-freemail senders the model kept`() throws {
    #expect(
      try confirmedIndex().senderReceipts == [
        "orders@shop.example.org": 1, "billing@store.example.net": 1,
        "orders@outlet.example.com": 1
      ]
    )
  }

  @Test
  func `authenticates only a confirmed receipt through a trusted server in any case`() throws {
    var state = state
    correct(&state, key: try HistoryRows.key(HistoryRows.shop), as: .inbox)
    let index = ingested(eligible: state.historyEligibleInbox, trustedAuthServers: ["MX.example"])
    #expect(index.authenticatedSenderReceipts == ["orders@shop.example.org": 1])
  }

  @Test
  func `adds received counts to the stored ones`() throws {
    let index = try confirmedIndex()
    #expect(index.received["prior.example"] == 4)
    #expect(index.received["deals4u@gmail.com"] == 1)
    #expect(index.summary(address: "friend@gmail.com", domain: "gmail.com").receivedCount == 0)
    #expect(
      index.summary(address: "billing@store.example.net", domain: "store.example.net")
        .receiptCount == 1
    )
  }

  @Test
  func `counts replies with bare carriage returns and reports unreadable mail as partial`()
    throws
  {
    let index = try confirmedIndex()
    #expect(index.replied.count == 100)
    #expect(index.replied.values.allSatisfy { $0 == 1 })
    #expect(index.availability == .partial)
  }

  @Test
  func `allows a sender only through its confirmed authenticated receipt`() throws {
    let index = try confirmedIndex()
    let shop = try MIMEParser().parse(HistoryRows.envelope(HistoryRows.shop).raw)
    let authenticated = EvidenceBundle(message: shop, trustedAuthServers: Self.trustedServers)
    #expect(
      gate("orders@shop.example.org", index, authentication: authenticated.senderAuthentication)
        == .allow
    )
    #expect(gate("orders@shop.example.org", index, authentication: .unverified) == nil)
    #expect(gate("billing@store.example.net", index, authentication: .alignedPass) == nil)
    #expect(gate("friend@gmail.com", index, authentication: .alignedPass) == nil)
  }

  @Test
  func `never allows a freemail sender through receipts`() {
    #expect(
      Gates.evaluate(
        address: "deals4u@gmail.com",
        domain: "gmail.com",
        rules: [],
        contact: nil,
        history: .init(receiptCount: 1, authenticatedReceiptCount: 1),
        authentication: .alignedPass
      ) == nil
    )
  }
}
private func correct(_ state: inout AppState, key: String, as label: MailLabel) {
  for index in state.records.indices where state.records[index].identity.key == key {
    state.records[index].correctedLabel = label
  }
}
private func gate(
  _ address: String,
  _ index: HistoryIndex,
  authentication: SenderAuthentication
) -> RuleDisposition? {
  let domain = DomainResolver().domain(ofAddress: address)
  return Gates.evaluate(
    address: address,
    domain: domain,
    rules: [],
    contact: nil,
    history: index.summary(address: address, domain: domain),
    authentication: authentication
  )?.disposition
}
@Test
func `reads Sent history from its high-water mark on its own schedule`() async throws {
  let store = try testStore(), now = Date.now
  let runner = HistoryEvents(accounts: ["broken", "account"], failingSent: "broken")
  let maintenance = HistoryMaintenance(source: AppleMailAdapter(runner: runner), store: store)
  let accounts = try await AppleMailAdapter(runner: runner).accounts()
  #expect(try await maintenance.runIfDue(for: accounts, now: now))
  #expect(try await !maintenance.runIfDue(for: accounts, now: now.addingTimeInterval(60)))
  let replied = try await StateRepository.load(store, StateSlices(histories: .all))
    .histories["account"]?.replied
  #expect(replied?.count == 100)
  #expect(replied?.values.allSatisfy { $0 == 1 } == true)
  #expect(try await maintenance.runIfDue(for: accounts, now: now + HistoryMaintenance.interval))
  #expect(await runner.sentOffsets["account"] == [0, 20, 0])
}
@Test
func `maintains each account's Sent history on its own schedule`() async throws {
  let store = try testStore(), now = Date.now
  let runner = HistoryEvents(accounts: ["app", "daemon"])
  let maintenance = HistoryMaintenance(source: AppleMailAdapter(runner: runner), store: store)
  let app = MailAccount(id: "app", name: "app"), daemon = MailAccount(id: "daemon", name: "daemon")
  #expect(try await maintenance.runIfDue(for: [app], now: now))
  #expect(try await maintenance.runIfDue(for: [daemon], now: now.addingTimeInterval(60)))
  #expect(await runner.sentOffsets["daemon"] == [0, 20])
  #expect(try await maintenance.runIfDue(for: [app], now: now + HistoryMaintenance.interval))
  #expect(await runner.sentOffsets["app"] == [0, 20, 0])
}
@Test
func `resumes the Sent backfill where it stopped after the newest page keeps failing`()
  async throws
{
  let store = try testStore(), now = Date.now
  let runner = HistoryEvents(sentRows: HistoryRows.deepSent)
  let maintenance = HistoryMaintenance(source: AppleMailAdapter(runner: runner), store: store)
  let account = MailAccount(id: "account", name: "account")
  try await maintenance.runIfDue(for: [account], now: now)
  await runner.failSent("account")
  for run in 1...3 {
    await #expect(throws: IntegrationError.self) {
      try await maintenance.runIfDue(
        for: [account],
        now: now + HistoryMaintenance.interval * Double(run)
      )
    }
  }
  await runner.failSent(nil)
  try await maintenance.runIfDue(for: [account], now: now + HistoryMaintenance.interval * 4)
  #expect(await runner.sentOffsets["account"]?.suffix(3) == [0, 420, 520])
}
@Test
func `fails maintenance when the only due mailbox fails`() async throws {
  let now = Date.now
  let lone = HistoryEvents(failingSent: "account")
  await #expect(throws: IntegrationError.self) {
    try await HistoryMaintenance(source: AppleMailAdapter(runner: lone), store: testStore())
      .runIfDue(for: [MailAccount(id: "account", name: "account")], now: now)
  }
}

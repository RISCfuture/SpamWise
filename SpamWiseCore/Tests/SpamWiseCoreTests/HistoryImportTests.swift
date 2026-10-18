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

  static func receipt(_ sender: String, auth: String?) -> ScriptValue {
    let headers = ["From: \(sender)", "Subject: Your receipt", auth].compactMap(\.self)
    return row(
      "Inbox",
      id: sender,
      .string(headers.joined(separator: "\n") + "\n\nOrder 123 total USD 10")
    )
  }
  static func row(_ mailbox: String, id: String, _ content: ScriptValue) -> ScriptValue {
    let byteCount = content.string?.utf8.count ?? MailScripts.maximumMessageBytes + 1
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
  private let failingSent: String?
  private(set) var sentOffsets: [String: [Int]] = [:]
  private(set) var inboxOffsets: [String: [Int]] = [:]

  init(accounts: [String] = ["account"], failingInbox: String? = nil, failingSent: String? = nil) {
    accountIDs = accounts
    self.failingInbox = failingInbox
    self.failingSent = failingSent
  }

  func run(_ request: MailRequest) async throws -> ScriptValue {
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
    let rows = (isSent ? HistoryRows.sent : HistoryRows.inbox).map { row in
      row.list.map { ScriptValue.list([.string(account)] + $0.dropFirst()) } ?? row
    }
    return .list([.integer(rows.count), .list(Array(rows.dropFirst(offset).prefix(limit)))])
  }
}
@Test func `gates only on confirmed authenticated receipts from exact non-freemail senders`()
  throws
{
  var state = AppState()
  for row in HistoryRows.receipts {
    state.record(
      .init(
        identity: try HistoryRows.envelope(row).identity,
        decision: .init(label: .inbox, action: .none, reason: .model("Wanted")),
        outcome: .dryRun
      )
    )
  }
  let correctedKey = try HistoryRows.key(HistoryRows.corrected)
  correct(&state, key: correctedKey, as: .junk)
  let sent = try HistoryRows.sent.compactMap { try MailRow($0).envelope }
  let inbox = try HistoryRows.inbox.compactMap { try MailRow($0).envelope }
  var index = HistoryIndex()
  index.received["prior.example"] = 4
  index.ingest(sent: sent, inbox: inbox, trustedAuthServers: ["mx.example"])
  #expect(index.senderReceipts == nil)
  #expect(state.historyEligibleInbox[correctedKey] == nil)
  index.ingest(
    sent: sent,
    inbox: inbox,
    eligible: state.historyEligibleInbox,
    trustedAuthServers: ["mx.example"]
  )
  #expect(index.authenticatedSenderReceipts == nil)
  correct(&state, key: try HistoryRows.key(HistoryRows.shop), as: .inbox)
  index.ingest(
    sent: sent,
    inbox: inbox,
    eligible: state.historyEligibleInbox,
    trustedAuthServers: ["MX.example"]
  )
  #expect(index.received["prior.example"] == 4)
  #expect(index.received["deals4u@gmail.com"] == 1)
  #expect(index.summary(address: "friend@gmail.com", domain: "gmail.com").receivedCount == 0)
  #expect(
    index.senderReceipts == [
      "orders@shop.example.org": 1, "billing@store.example.net": 1, "orders@outlet.example.com": 1
    ]
  )
  #expect(index.authenticatedSenderReceipts == ["orders@shop.example.org": 1])
  #expect(
    index.summary(address: "billing@store.example.net", domain: "store.example.net").receiptCount
      == 1
  )
  #expect(index.replied.count == 100)
  #expect(index.replied.values.allSatisfy { $0 == 1 })
  #expect(index.availability == .partial)
  let shop = try MIMEParser().parse(HistoryRows.envelope(HistoryRows.shop).raw)
  let authenticated = EvidenceBundle(message: shop, trustedAuthServers: ["mx.example"])
  #expect(
    gate("orders@shop.example.org", index, authentication: authenticated.senderAuthentication)
      == .allow
  )
  #expect(gate("orders@shop.example.org", index, authentication: .unverified) == nil)
  #expect(gate("billing@store.example.net", index, authentication: .alignedPass) == nil)
  #expect(gate("friend@gmail.com", index, authentication: .alignedPass) == nil)
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
@Test func `reads Sent history from its high-water mark on its own schedule`() async throws {
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
  let lone = HistoryEvents(failingSent: "account")
  await #expect(throws: IntegrationError.self) {
    try await HistoryMaintenance(source: AppleMailAdapter(runner: lone), store: testStore())
      .runIfDue(for: [MailAccount(id: "account", name: "account")], now: now)
  }
}

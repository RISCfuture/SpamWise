import Foundation
public import SpamWiseCore
/// Client-independent, bounded IMAP adapter using explicit TLS credentials and UID-scoped actions.
public actor IMAPAdapter: MailClientAdapter {
  /// Explicit account identity used to scope retries and persisted actions.
  public nonisolated let accountID: String
  private let configuration: IMAPConfiguration
  private let credentials: @Sendable () async throws -> IMAPCredential
  private let transport: @Sendable (IMAPConfiguration) throws -> any IMAPTransport
  private var validated = false
  private var sweepCursor = IMAPSweepCursor()
  /// Creates an adapter. Inject a transport for offline tests; the default verifies TLS using Network.framework.
  public init(
    configuration: IMAPConfiguration,
    credentials: @escaping @Sendable () async throws -> IMAPCredential,
    transport: @escaping @Sendable (IMAPConfiguration) throws -> any IMAPTransport = {
      try IMAPTLSTransport(configuration: $0)
    }
  ) {
    self.configuration = configuration; self.credentials = credentials; self.transport = transport
    accountID = configuration.id
  }
  /// Authenticates, discovers special-use roles and examines Inbox without marking or moving any message.
  public func validateReadOnly() async throws -> IMAPValidation {
    validated = false
    let result = try await withSession { session, capabilities in
      let roles = try await Self.roles(session: session, capabilities: capabilities)
      let selected = try await Self.select("INBOX", writable: false, session: session)
      return IMAPValidation(
        supportsMove: capabilities.contains("MOVE") || capabilities.contains("IMAP4REV2"),
        junkMailbox: roles.junk,
        sentMailbox: roles.sent,
        inboxValidity: selected.validity
      )
    }
    validated = true
    return result
  }
  /// Fetches exactly the matching UID after checking UIDVALIDITY and content hash.
  public func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope? {
    try validateIdentity(identity)
    return try await withSession { session, _ in
      guard let mailbox = identity.mailbox else { throw IntegrationError.staleMessage }
      let selected = try await Self.select(mailbox, writable: false, session: session)
      guard selected.validity == identity.mailboxValidity else {
        throw IntegrationError.staleMessage
      }
      return try await Self.lookup(identity, session: session)
    }
  }
  /// Fetches at most 100 recent Inbox messages, each capped at 2 MB, with a 4 MB aggregate content limit.
  public func recentMessages(limit: Int) async throws -> [MailEnvelope] {
    try await messages(mailbox: "INBOX", limit: limit)
  }
  /// Advances bounded Inbox pages and restarts after the oldest page; an optional store preserves progress across instances.
  public func nextInboxMessages(limit: Int, cursorStore: Store? = nil) async throws
    -> [MailEnvelope]
  {
    guard limit > 0 else { return [] }
    let account = configuration.id
    let key =
      "imap-sweep-v1:"
      + stableHash(
        Data(
          [account, configuration.host, String(configuration.port), configuration.username].joined(
            separator: "\u{0}"
          ).utf8
        )
      )
    let saved = try await cursorStore?.read(key, default: sweepCursor) ?? sweepCursor
    let (messages, next) = try await withSession { session, _ in
      let selected = try await Self.select("INBOX", writable: false, session: session)
      let offset = saved.currentOffset(validity: selected.validity, count: selected.count)
      let messages = try await Self.messages(
        mailbox: "INBOX",
        account: account,
        limit: limit,
        session: session,
        offset: offset,
        selection: selected
      )
      return (
        messages.envelopes,
        IMAPSweepCursor(
          offset: messages.nextOffset,
          validity: selected.validity
        )
      )
    }
    if let cursorStore {
      try await cursorStore.update(key, default: IMAPSweepCursor()) { $0 = next }
    }
    sweepCursor = next
    return messages
  }
  /// Reads a bounded mailbox page without setting the Seen flag; names use the server's wire encoding.
  public func messages(mailbox: String, limit: Int) async throws -> [MailEnvelope] {
    let account = configuration.id
    return try await withSession { session, _ in
      try await Self.messages(mailbox: mailbox, account: account, limit: limit, session: session)
        .envelopes
    }
  }
  /// Imports at most 100 sent messages as partial reply history; incoming mail never trusts itself.
  public func importHistory() async throws -> [String: HistoryIndex] {
    let account = configuration.id
    return try await withSession { session, capabilities in
      let roles = try await Self.roles(session: session, capabilities: capabilities)
      guard let sent = roles.sent else { return [:] }
      let messages = try await Self.messages(
        mailbox: sent,
        account: account,
        limit: 100,
        session: session
      )
      var index = HistoryIndex()
      index.availability = .partial; index.updatedAt = .now
      for envelope in messages.envelopes {
        guard let message = try? MIMEParser().parse(envelope.raw),
          message.header("in-reply-to") != nil
        else { continue }
        index.importedIDs.insert(envelope.identity.key)
        for value in (message.headers["to"] ?? []) + (message.headers["cc"] ?? []) {
          for address in value.components(separatedBy: ",").compactMap(MIMEParser.address) {
            index.replied[address, default: 0] += 1
          }
        }
      }
      return [account: index]
    }
  }
  /// Performs only supported UID MOVE operations after validation and an exact content recheck.
  /// Flag colors have no portable IMAP representation and are rejected without a substitute action.
  public func perform(_ action: MailAction, for identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    guard action != .none else { return .init(confirmed: true) }
    guard configuration.allowsActions, validated else { throw IntegrationError.accountUnverified }
    guard action == .moveToInbox || action == .moveToJunk else { throw IMAPError.unsupported }
    try validateIdentity(identity)
    return try await withSession { session, capabilities in
      guard capabilities.contains("MOVE") || capabilities.contains("IMAP4REV2") else {
        throw IMAPError.unsupported
      }
      guard let mailbox = identity.mailbox, let uid = identity.localID else {
        throw IntegrationError.staleMessage
      }
      let selected = try await Self.select(mailbox, writable: true, session: session)
      guard selected.validity == identity.mailboxValidity else {
        throw IntegrationError.staleMessage
      }
      guard try await Self.lookup(identity, session: session) != nil else {
        throw IntegrationError.staleMessage
      }
      let roles = try await Self.roles(session: session, capabilities: capabilities)
      guard let destination = action == .moveToInbox ? "INBOX" : roles.junk else {
        throw IMAPError.unsupported
      }
      if destination == mailbox { return .init(confirmed: true) }
      let rows = try await session.command("UID MOVE \(uid) \(IMAPSession.quote(destination))")
      guard let mapping = Self.moveMapping(rows, uid: uid) else { return .init(confirmed: false) }
      var moved = identity
      moved.localID = mapping.uid
      moved.mailboxValidity = mapping.validity
      moved.mailbox = destination
      let observed = try await Self.select(destination, writable: false, session: session)
      guard observed.validity == mapping.validity,
        try await Self.lookup(moved, session: session) != nil
      else {
        throw IntegrationError.staleMessage
      }
      return .init(confirmed: true, updatedIdentity: moved)
    }
  }
  /// Explicit disposable-message probe. Only an Inbox UID whose subject starts with `[SpamWise Probe]` is eligible.
  /// Both moves require COPYUID mappings and verified destination content; failures never trigger a guessed reverse move.
  public func testDisposableMessage(uid: UInt32) async throws -> MessageIdentity {
    guard uid > 0 else { throw IntegrationError.staleMessage }
    let account = configuration.id
    return try await withSession { session, capabilities in
      guard capabilities.contains("MOVE") || capabilities.contains("IMAP4REV2") else {
        throw IMAPError.unsupported
      }
      let roles = try await Self.roles(session: session, capabilities: capabilities)
      guard let junk = roles.junk, junk.uppercased() != "INBOX" else { throw IMAPError.unsupported }
      let selected = try await Self.select("INBOX", writable: false, session: session)
      guard let raw = try await Self.fetch(uid: Int(uid), session: session),
        let parsed = try? MIMEParser().parse(raw), parsed.subject.hasPrefix("[SpamWise Probe]")
      else {
        throw IntegrationError.staleMessage
      }
      let original = MessageIdentity(
        accountID: account,
        localID: Int(uid),
        mailboxValidity: selected.validity,
        mailbox: "INBOX",
        contentHash: stableHash(raw)
      )
      let moved = try await Self.probeMove(original, to: junk, session: session)
      return try await Self.probeMove(moved, to: "INBOX", session: session)
    }
  }
  private func validateIdentity(_ identity: MessageIdentity) throws {
    guard identity.accountID == configuration.id, let uid = identity.localID,
      uid > 0, uid <= UInt32.max, let validity = identity.mailboxValidity,
      validity > 0, validity <= UInt32.max, identity.mailbox != nil
    else {
      throw IntegrationError.staleMessage
    }
  }
  private func withSession<Value: Sendable>(
    _ operation: @Sendable (IMAPSession, Set<String>) async throws -> Value
  ) async throws -> Value {
    try configuration.validate()
    try Task.checkCancellation()
    let connection = try transport(configuration)
    let session = IMAPSession(transport: connection)
    do {
      let capabilities = try await session.open(
        configuration: configuration,
        credential: credentials()
      )
      let result = try await operation(session, capabilities)
      await connection.close()
      return result
    } catch {
      await connection.close()
      try Task.checkCancellation()
      throw error
    }
  }
}

extension IMAPAdapter {
  private static func probeMove(
    _ identity: MessageIdentity,
    to destination: String,
    session: IMAPSession
  )
    async throws -> MessageIdentity
  {
    guard let mailbox = identity.mailbox, let uid = identity.localID else {
      throw IntegrationError.staleMessage
    }
    let selected = try await select(mailbox, writable: true, session: session)
    guard selected.validity == identity.mailboxValidity,
      try await lookup(identity, session: session) != nil
    else {
      throw IntegrationError.staleMessage
    }
    let rows = try await session.command("UID MOVE \(uid) \(IMAPSession.quote(destination))")
    guard let mapping = moveMapping(rows, uid: uid) else { throw IntegrationError.staleMessage }
    var moved = identity
    moved.localID = mapping.uid
    moved.mailboxValidity = mapping.validity
    moved.mailbox = destination
    let observed = try await select(destination, writable: false, session: session)
    guard observed.validity == mapping.validity, try await lookup(moved, session: session) != nil
    else {
      throw IntegrationError.staleMessage
    }
    return moved
  }
  private static func roles(session: IMAPSession, capabilities: Set<String>) async throws -> (
    junk: String?, sent: String?
  ) {
    guard capabilities.contains("SPECIAL-USE") || capabilities.contains("IMAP4REV2") else {
      return (nil, nil)
    }
    let rows = try await session.command("LIST \"\" \"*\" RETURN (SPECIAL-USE)")
    var junk: Set<String> = [], sent: Set<String> = []
    for row in rows where row.count > 1 && row[1].isAtom("LIST") {
      guard row.count >= 6, row[2] == .open, let end = row.dropFirst(3).firstIndex(of: .close),
        end + 2 < row.count, let mailbox = row[end + 2].text
      else { throw IMAPError.malformedResponse }
      _ = try IMAPSession.quote(mailbox)
      let attributes = row[3..<end]
      guard !attributes.contains(where: { $0.isAtom("\\Noselect") || $0.isAtom("\\Trash") }) else {
        continue
      }
      if attributes.contains(where: { $0.isAtom("\\Junk") }) { junk.insert(mailbox) }
      if attributes.contains(where: { $0.isAtom("\\Sent") }) { sent.insert(mailbox) }
    }
    guard junk.count <= 1, sent.count <= 1 else { throw IntegrationError.ambiguous }
    return (junk.first, sent.first)
  }
  static func select(_ mailbox: String, writable: Bool, session: IMAPSession) async throws
    -> (validity: UInt64, count: Int)
  {
    let rows = try await session.command(
      "\(writable ? "SELECT" : "EXAMINE") \(IMAPSession.quote(mailbox))"
    )
    var validities: Set<UInt64> = []
    var count: Int?
    for row in rows {
      if row.count == 3, row[0].isAtom("*"), row[2].isAtom("EXISTS"), let text = row[1].text,
        let value = Int(text), value >= 0, value <= UInt32.max
      {
        count = value
      }
      for index in row.indices where row[index].isAtom("[UIDVALIDITY") {
        guard index + 1 < row.count, let text = row[index + 1].text, text.hasSuffix("]"),
          let value = UInt64(text.dropLast()), value > 0, value <= UInt32.max
        else { throw IMAPError.malformedResponse }
        validities.insert(value)
      }
    }
    guard validities.count == 1, let validity = validities.first, let count else {
      throw IMAPError.malformedResponse
    }
    if writable, rows.contains(where: { $0.contains(where: { $0.isAtom("[READ-ONLY]") }) }) {
      throw IMAPError.rejected
    }
    return (validity, count)
  }
  private static func lookup(_ identity: MessageIdentity, session: IMAPSession) async throws
    -> MailEnvelope?
  {
    guard let uid = identity.localID else { throw IntegrationError.staleMessage }
    let raw = try await fetch(uid: uid, session: session)
    guard let raw else { return nil }
    guard stableHash(raw) == identity.contentHash else { throw IntegrationError.staleMessage }
    return .init(identity: identity, raw: raw)
  }
  static func fetch(uid: Int, session: IMAPSession) async throws -> Data? {
    let rows = try await session.command("UID FETCH \(uid) (UID RFC822.SIZE BODY.PEEK[])")
    let matching = rows.filter { row in
      isFetch(row) && number("UID", in: row) == uid
    }
    guard matching.count <= 1 else { throw IntegrationError.ambiguous }
    guard let row = matching.first else { return nil }
    guard let size = number("RFC822.SIZE", in: row), size <= 2_000_000,
      row.filter({ $0.isAtom("BODY[]") }).count == 1,
      let body = row.firstIndex(where: { $0.isAtom("BODY[]") }), body + 1 < row.count,
      case .literal(let data) = row[body + 1], data.count == size
    else { throw IMAPError.malformedResponse }
    return data
  }
  static func number(_ name: String, in row: [IMAPToken]) -> Int? {
    guard row.filter({ $0.isAtom(name) }).count == 1,
      let index = row.firstIndex(where: { $0.isAtom(name) }), index + 1 < row.count,
      let text = row[index + 1].text, let value = Int(text), value >= 0
    else { return nil }
    return value
  }
  static func isFetch(_ row: [IMAPToken]) -> Bool {
    guard row.count >= 6, row[0].isAtom("*"), let sequence = row[1].text.flatMap(UInt32.init),
      sequence > 0, row[2].isAtom("FETCH"), row[3] == .open, row.last == .close
    else { return false }
    return true
  }
}

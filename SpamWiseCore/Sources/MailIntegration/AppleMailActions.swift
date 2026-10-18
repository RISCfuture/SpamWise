import Foundation
public import SpamWiseCore

/// Where a message is searched for before it is read or changed.
enum MessageSearchScope {
  /// Only the mailbox where the message was recorded; automatic actions never look further.
  case recordedMailbox
  /// The recorded mailbox first, then the account's Inbox, Junk and a bounded mailbox walk.
  case account
}

/// A uniquely resolved message: its exact current location and its verified envelope.
struct ResolvedMessage {
  let location: MailMessageLocation
  let envelope: MailEnvelope
}

extension MailCommand {
  var destination: MailboxRole? {
    switch self {
      case .moveToJunk: .junk
      case .moveToInbox: .inbox
      case .orangeFlag, .orangeBackground, .markRead, .open: nil
    }
  }
}

extension AppleMailAdapter {
  private static let requiredObservations = 2
  private static let probeSubjectPrefix = "[SpamWise Probe]"

  private static func movedIdentity(_ receipt: ActionReceipt) throws -> MessageIdentity {
    guard receipt.confirmed, let identity = receipt.updatedIdentity else {
      throw IntegrationError.actionUnconfirmed
    }
    return identity
  }
  /// Chooses the candidate with the recorded content, using the local ID to break ties.
  static func select(_ identity: MessageIdentity, from rows: [MailRow]) throws -> ResolvedMessage? {
    var seen = Set<Int>()
    let unique = rows.filter { seen.insert($0.location.localID).inserted }
    guard !unique.isEmpty else { return nil }
    let readable = unique.compactMap { row in
      row.envelope.map { ResolvedMessage(location: row.location, envelope: $0) }
    }
    let matching = readable.filter { $0.envelope.identity.contentHash == identity.contentHash }
    if matching.count == 1 { return matching[0] }
    if let exact = matching.first(where: { $0.location.localID == identity.localID }) {
      return exact
    }
    if !matching.isEmpty { throw IntegrationError.ambiguous }
    throw readable.count < unique.count ? IntegrationError.messageTooLarge : .staleMessage
  }
  private static func containsMatch(_ identity: MessageIdentity, in rows: [MailRow]) -> Bool {
    rows.contains { $0.envelope?.identity.contentHash == identity.contentHash }
  }

  /// Resolves the message anywhere in its account and rejects changed content.
  public func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope? {
    try await resolve(identity, scope: .account).envelope
  }
  /// Opens exactly one verified message in Mail's own viewer.
  public func open(_ identity: MessageIdentity) async throws {
    let target = try await resolve(identity, scope: .account)
    guard try await invoke(.apply(.open, target: target.location)) == .boolean(true) else {
      throw IntegrationError.scriptFailed
    }
  }
  /// Acts only while the message remains in its recorded mailbox, then observes the result.
  public func perform(_ action: MailAction, for identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    try await perform(action, for: identity, scope: .recordedMailbox)
  }
  /// Acts on a user-corrected message wherever it now is in its account, then observes the result.
  public func performCorrection(_ action: MailAction, for identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    try await perform(action, for: identity, scope: .account)
  }
  /// Marks read only after rechecking the exact message and its account's Junk membership.
  public func markReadInJunk(_ identity: MessageIdentity) async throws -> ActionReceipt {
    let target = try await resolve(identity, scope: .recordedMailbox)
    try Task.checkCancellation()
    return .init(confirmed: try await applyChange(.markRead, to: target.location))
  }
  /// Explicit UI probe: only a selected Inbox message named [SpamWise Probe] is eligible.
  public func testDisposableMessage() async throws -> String {
    let selected = try await selectedMessage()
    guard selected.identity.messageID != nil else { throw IntegrationError.missingMessageID }
    guard let account = selected.identity.accountID,
      try MIMEParser().parse(selected.raw).subject.hasPrefix(Self.probeSubjectPrefix),
      try await observedIdentity(of: selected.identity, in: .inbox) != nil
    else { throw IntegrationError.notProbeMessage }
    let junk = try Self.movedIdentity(await perform(.moveToJunk, for: selected.identity))
    let inbox = try Self.movedIdentity(await perform(.moveToInbox, for: junk))
    guard try await perform(.orangeFlag, for: inbox).confirmed,
      try await observedIdentity(of: inbox, in: .inbox) != nil
    else { throw IntegrationError.actionUnconfirmed }
    return account
  }

  func resolve(_ identity: MessageIdentity, scope: MessageSearchScope) async throws
    -> ResolvedMessage
  {
    guard let account = identity.accountID, !account.isEmpty else {
      throw IntegrationError.accountUnresolved
    }
    guard identity.messageID != nil || identity.localID != nil else {
      throw IntegrationError.messageNotFound
    }
    var rows: [MailRow] = []
    if let mailbox = identity.mailbox {
      rows = try await candidates(for: identity, account: account, mailbox: mailbox)
      if scope == .recordedMailbox || Self.containsMatch(identity, in: rows) {
        guard let resolved = try Self.select(identity, from: rows) else {
          throw IntegrationError.messageMoved
        }
        return resolved
      }
      try Task.checkCancellation()
    } else if scope == .recordedMailbox {
      throw IntegrationError.mailboxUnresolved
    }
    rows += try await candidates(for: identity, account: account, mailbox: nil)
    guard let resolved = try Self.select(identity, from: rows) else {
      throw IntegrationError.messageNotFound
    }
    return resolved
  }
  private func candidates(for identity: MessageIdentity, account: String, mailbox: String?)
    async throws -> [MailRow]
  {
    let request = MailRequest.find(
      accountID: account,
      messageID: identity.messageID,
      localID: identity.localID,
      mailbox: mailbox
    )
    guard let values = try await invoke(request).list else { throw IntegrationError.scriptFailed }
    return try values.map(MailRow.init)
  }
  private func perform(
    _ action: MailAction,
    for identity: MessageIdentity,
    scope: MessageSearchScope
  ) async throws -> ActionReceipt {
    guard let command = MailCommand(action) else { return .init(confirmed: true) }
    if command.destination != nil, identity.messageID == nil, scope == .recordedMailbox {
      throw IntegrationError.missingMessageID
    }
    let target = try await resolve(identity, scope: scope)
    try Task.checkCancellation()
    guard try await applyChange(command, to: target.location) else {
      return .init(confirmed: false)
    }
    guard let destination = command.destination else { return .init(confirmed: true) }
    guard target.location.messageID != nil else { return .init(confirmed: false) }
    return await observeMove(of: target.envelope.identity, to: destination)
  }
  /// Reports whether Mail confirmed the change; cancellation or timeout after sending is unknown.
  private func applyChange(_ command: MailCommand, to location: MailMessageLocation) async throws
    -> Bool
  {
    do {
      return try await invoke(.apply(command, target: location)) == .boolean(true)
    } catch is CancellationError {
      return false
    } catch IntegrationError.timedOut {
      return false
    }
  }
  /// Polls until Mail shows the moved message in its destination twice in a row.
  private func observeMove(of identity: MessageIdentity, to role: MailboxRole) async
    -> ActionReceipt
  {
    let clock = ContinuousClock(), deadline = clock.now + moveSettlingTime
    var observed: MessageIdentity?, consecutive = 0
    while consecutive < Self.requiredObservations, clock.now < deadline {
      do {
        try Task.checkCancellation()
        try await Task.sleep(for: observationInterval)
        observed = try await observedIdentity(of: identity, in: role)
        consecutive = observed == nil ? 0 : consecutive + 1
      } catch is CancellationError {
        return .init(confirmed: false)
      } catch {
        consecutive = 0
      }
    }
    guard consecutive >= Self.requiredObservations, let observed else {
      return .init(confirmed: false)
    }
    return .init(confirmed: true, updatedIdentity: observed)
  }
  private func observedIdentity(of identity: MessageIdentity, in role: MailboxRole) async throws
    -> MessageIdentity?
  {
    guard let account = identity.accountID, let messageID = identity.messageID else { return nil }
    let request = MailRequest.observe(accountID: account, role: role, messageID: messageID)
    guard let values = try await invoke(request).list else { throw IntegrationError.scriptFailed }
    return try values.map(MailRow.init).compactMap(\.envelope).first {
      $0.identity.accountID == account && $0.identity.contentHash == identity.contentHash
    }?.identity
  }
}

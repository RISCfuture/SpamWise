import Foundation
public import SpamWiseCore

/// Where a message is searched for before it is read or changed.
enum MessageSearchScope {
  /// Only the mailbox where the message was recorded; automatic actions never look further.
  case recordedMailbox
  /// The recorded mailbox first, then the account's Inbox, Junk and a bounded mailbox walk.
  case account
}

/// When a move's receipt reports it confirmed.
enum MoveConfirmation {
  /// Once Mail shows the message in its destination twice in a row; the receipt carries a
  /// recheck for when the settling window ends.
  case observed
  /// Only after the settling window, once the message is still the destination's one copy.
  case settled
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
      case .orangeFlag, .orangeBackground, .clearOrangeFlag, .clearOrangeBackground, .markRead,
        .clearJunkMark, .open:
        nil
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
    try await interactively { try await resolve(identity, scope: .account).envelope }
  }
  /// Opens exactly one verified message in Mail's own viewer.
  public func open(_ identity: MessageIdentity) async throws {
    try await interactively {
      let target = try await resolve(identity, scope: .account)
      guard try await invoke(.apply(.open, target: target.location)) == .boolean(true) else {
        throw IntegrationError.scriptFailed
      }
    }
  }
  /**
   Acts only while the message remains in its recorded mailbox, then observes the result.

   An orange flag or background already on the message is reported as applied without change,
   and clearing Review removes only one that SpamWise set. A Review change Mail doesn't confirm
   is applied once the message shows it within the settling window, though an annotation added
   by a request Mail didn't answer stays the user's.

   - Throws: `ActionNotAttempted` when the message can't be resolved, the record of Review
     marks SpamWise set can't be read before clearing one, or Mail refuses before changing it, as
     when it has left its mailbox or another flag or color is already set.
   */
  public func perform(_ action: MailAction, for identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    try await perform(action, for: identity, scope: .recordedMailbox)
  }
  /**
   Acts on a user-corrected message wherever it now is in its account, then observes the result.

   A moved message without a Message-ID is observed among the destination's messages of its size
   and confirmed by its content.

   - Throws: `ActionNotAttempted` when the message can't be resolved, or Mail refuses before
     changing it.
   */
  public func performCorrection(_ action: MailAction, for identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    try await interactively { try await perform(action, for: identity, scope: .account) }
  }
  /// Marks read only after rechecking the exact message and its account's Junk membership.
  public func markReadInJunk(_ identity: MessageIdentity) async throws -> ActionReceipt {
    let target = try await resolve(identity, scope: .recordedMailbox)
    try Task.checkCancellation()
    return .init(confirmed: try await applyChange(.markRead, to: target.location) == .applied)
  }
  /// Marks a corrected message read in Junk without waiting behind sweeps and automatic actions.
  public func markCorrectionReadInJunk(_ identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    try await interactively { try await markReadInJunk(identity) }
  }
  /**
   Clears Mail's junk mark on a corrected message after rechecking it and its account's Inbox
   membership, and reads the mark back.

   - Throws: `ActionNotAttempted` when the message can't be resolved where it was recorded,
     or Mail refuses before changing it because it has left the Inbox.
   */
  public func clearJunkMarkInInbox(_ identity: MessageIdentity) async throws -> JunkMarkChange {
    try await interactively {
      let target = try await notAttempted { try await resolve(identity, scope: .recordedMailbox) }
      try Task.checkCancellation()
      return switch try await requestChange(.clearJunkMark, to: target.location) {
        case .applied: .cleared
        case .alreadyApplied: .absent
        case .unconfirmed, .unanswered: .unconfirmed
      }
    }
  }
  /// Explicit UI probe: only a selected Inbox message named [SpamWise Probe] with a Message-ID is eligible.
  public func testDisposableMessage() async throws -> String {
    try await interactively { try await probe() }
  }

  private func probe() async throws -> String {
    let selected = try await selectedMessage()
    guard let account = selected.identity.accountID,
      try MIMEParser().parse(selected.raw).subject.hasPrefix(Self.probeSubjectPrefix),
      selected.identity.messageID != nil,
      try await observedIdentity(of: selected.identity, in: .inbox) != nil
    else { throw IntegrationError.notProbeMessage }
    let junk = try Self.movedIdentity(await settledMove(.moveToJunk, of: selected.identity))
    let inbox = try Self.movedIdentity(await settledMove(.moveToInbox, of: junk))
    guard try await perform(.orangeFlag, for: inbox).confirmed,
      try await settledIdentity(of: inbox, in: .inbox) != nil
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
  /// Moves the probe and confirms it only once the full settling window has passed.
  private func settledMove(_ action: MailAction, of identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    try await perform(action, for: identity, scope: .recordedMailbox, confirmation: .settled)
  }
  private func perform(
    _ action: MailAction,
    for identity: MessageIdentity,
    scope: MessageSearchScope,
    confirmation: MoveConfirmation = .observed
  ) async throws -> ActionReceipt {
    guard let command = MailCommand(action), try await needsCommand(command, on: identity) else {
      return .init(confirmed: true)
    }
    let target = try await notAttempted {
      if command.destination != nil, identity.messageID == nil, scope == .recordedMailbox {
        throw IntegrationError.missingMessageID
      }
      return try await resolve(identity, scope: scope)
    }
    try Task.checkCancellation()
    let change = try await observedChange(command, to: target.location)
    await record(change, of: command, on: identity)
    switch change {
      case .unconfirmed, .unanswered: return .init(confirmed: false)
      case .alreadyApplied: return .init(confirmed: true)
      case .applied: break
    }
    guard let destination = command.destination else { return .init(confirmed: true) }
    return await observeMove(of: target, to: destination, confirmation: confirmation)
  }
  /// Whether `command` has anything to change: clearing Review applies only to a mark SpamWise set.
  private func needsCommand(_ command: MailCommand, on identity: MessageIdentity) async throws
    -> Bool
  {
    guard command.removesReview else { return true }
    return try await notAttempted { try await hasRecordedReview(removedBy: command, on: identity) }
  }
  /// Requests a change, rethrowing the handler's refusals before it changes anything as
  /// ``ActionNotAttempted``.
  private func requestChange(_ command: MailCommand, to location: MailMessageLocation)
    async throws -> MailChange
  {
    do {
      return try await applyChange(command, to: location)
    } catch let error as IntegrationError where error.precedesMailChange {
      throw ActionNotAttempted(cause: error)
    }
  }
  /**
   Requests a change; when Mail doesn't confirm a Review change, reads the message until it shows
   the change or ``moveSettlingTime`` passes, without sending the change again.

   An unanswered request may have found the annotation already on the message, so an annotation
   it adds that later shows stays the user's.
   */
  private func observedChange(_ command: MailCommand, to location: MailMessageLocation)
    async throws -> MailChange
  {
    let change = try await requestChange(command, to: location)
    guard [.unconfirmed, .unanswered].contains(change), command.reviewAnnotation != nil else {
      return change
    }
    guard await observesReview(command, on: location) else { return .unconfirmed }
    return change == .unanswered && !command.removesReview ? .alreadyApplied : .applied
  }
  private func observesReview(_ command: MailCommand, on location: MailMessageLocation) async
    -> Bool
  {
    let clock = ContinuousClock(), deadline = clock.now + moveSettlingTime
    while clock.now < deadline {
      do {
        try await Task.sleep(for: min(observationInterval, deadline - clock.now))
        if try await invoke(.reviewState(command, target: location)) == .boolean(true) {
          return true
        }
      } catch is CancellationError {
        return false
      } catch {}
    }
    return false
  }
  /// Reports what Mail confirmed; cancellation or timeout after sending is unanswered.
  private func applyChange(_ command: MailCommand, to location: MailMessageLocation) async throws
    -> MailChange
  {
    let reply: ScriptValue
    do {
      reply = try await invoke(.apply(command, target: location))
    } catch is CancellationError {
      return .unanswered
    } catch IntegrationError.timedOut {
      return .unanswered
    }
    switch reply {
      case .boolean(true): return .applied
      case .string(MailScripts.alreadyAnnotated): return .alreadyApplied
      default: return .unconfirmed
    }
  }
  /**
   Polls until Mail shows the moved message in its destination twice in a row.

   Providers can revert or relocate a move once their server syncs, so the move is confirmed as
   settled only after ``moveSettlingTime``: an observed confirmation carries a recheck due then,
   and a settled one waits for the window and requires the destination's one copy.
   */
  private func observeMove(
    of target: ResolvedMessage,
    to role: MailboxRole,
    confirmation: MoveConfirmation
  ) async -> ActionReceipt {
    let clock = ContinuousClock(), deadline = clock.now + moveSettlingTime
    let identity = target.envelope.identity, byteCount = target.location.byteCount
    var observed: MessageIdentity?, consecutive = 0
    while clock.now < deadline,
      confirmation == .settled || consecutive < Self.requiredObservations
    {
      do {
        try Task.checkCancellation()
        try await Task.sleep(for: min(observationInterval, deadline - clock.now))
        observed = try await observedIdentity(of: identity, in: role, byteCount: byteCount)
        consecutive = observed == nil ? 0 : consecutive + 1
      } catch is CancellationError {
        return .init(confirmed: false)
      } catch {
        consecutive = 0
      }
    }
    switch confirmation {
      case .observed:
        guard consecutive >= Self.requiredObservations, let observed else {
          return .init(confirmed: false)
        }
        let settlement = MoveSettlement(due: deadline) {
          (try? await self.settledIdentity(of: observed, in: role, byteCount: byteCount)) != nil
        }
        return .init(confirmed: true, updatedIdentity: observed, settlement: settlement)
      case .settled:
        guard !Task.isCancelled, observed != nil,
          let settled = try? await settledIdentity(of: identity, in: role, byteCount: byteCount)
        else { return .init(confirmed: false) }
        return .init(confirmed: true, updatedIdentity: settled)
    }
  }
  /// The moved message when it is the only copy with its content in the account's `role` mailbox.
  private func settledIdentity(
    of identity: MessageIdentity,
    in role: MailboxRole,
    byteCount: Int = -1
  ) async throws -> MessageIdentity? {
    let copies = try await copies(of: identity, in: role, byteCount: byteCount)
    return copies.count == 1 ? copies[0] : nil
  }
  private func observedIdentity(
    of identity: MessageIdentity,
    in role: MailboxRole,
    byteCount: Int = -1
  )
    async throws -> MessageIdentity?
  {
    try await copies(of: identity, in: role, byteCount: byteCount).first
  }
  /**
   The account's `role` mailbox copies with the identity's content, found by Message-ID or, for
   mail without one, by `byteCount`; none when neither is known.
   */
  private func copies(of identity: MessageIdentity, in role: MailboxRole, byteCount: Int)
    async throws -> [MessageIdentity]
  {
    guard let account = identity.accountID, identity.messageID != nil || byteCount >= 0 else {
      return []
    }
    let request = MailRequest.observe(
      accountID: account,
      role: role,
      messageID: identity.messageID,
      byteCount: byteCount
    )
    guard let values = try await invoke(request).list else { throw IntegrationError.scriptFailed }
    var seen = Set<Int>()
    return try values.map(MailRow.init).filter { seen.insert($0.location.localID).inserted }
      .compactMap(\.envelope).map(\.identity).filter {
        $0.accountID == account && $0.contentHash == identity.contentHash
      }
  }
}

extension IntegrationError {
  /// Whether the action handler raises this only from the checks that precede any change.
  fileprivate var precedesMailChange: Bool {
    switch self {
      case .accountUnresolved, .mailboxUnresolved, .folderLimit, .messageMoved, .staleMessage,
        .existingAnnotation:
        true
      default: false
    }
  }
}

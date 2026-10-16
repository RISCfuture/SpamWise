import Foundation
import NIOIMAP
import SpamWiseCore

/// The outcome of storing Review on one message.
struct ReviewMarking {
  /// Whether the server confirmed the Review flag.
  var receipt: ActionReceipt
  /// Whether SpamWise set `\Flagged` as the Review fallback, so clearing Review may remove it.
  var setFlagged: Bool
}

/// A message confirmed at its recorded UIDVALIDITY and content hash.
struct IMAPRevalidation {
  /// The mailbox as selected for the check.
  var selection: IMAPMailboxSelection
  /// The message UID within the selection.
  var uid: Int
  /// The message, or nil when the UID no longer exists.
  var envelope: MailEnvelope?
}

extension IMAPAdapter {
  private static let reviewKeyword = Flag("$SpamWiseReview")

  /// Rethrows failures from steps that precede any mail command as ``ActionNotAttempted``.
  static func notAttempted<Value>(_ step: () async throws -> Value) async throws -> Value {
    do {
      return try await step()
    } catch let error as ActionNotAttempted {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ActionNotAttempted(cause: error)
    }
  }

  static func move(
    _ identity: MessageIdentity,
    for action: MailAction,
    session: IMAPSession
  )
    async throws -> ActionReceipt
  {
    let destination = try await notAttempted {
      try requireMove(session)
      guard
        let destination = action == .moveToInbox
          ? "INBOX" : try await roles(session: session).junk
      else { throw IMAPError.unsupported }
      return destination
    }
    guard destination != identity.mailbox else {
      _ = try await notAttempted {
        try await revalidatePresent(identity, writable: false, session: session)
      }
      return .init(confirmed: true)
    }
    guard let moved = try await moveAndVerify(identity, to: destination, session: session) else {
      return .init(confirmed: false)
    }
    return .init(confirmed: true, updatedIdentity: moved)
  }

  /// Moves an exact, revalidated message and confirms it at the destination COPYUID reports.
  /// Returns nil when the server sent no usable COPYUID mapping, so the outcome is unknown.
  static func moveAndVerify(
    _ identity: MessageIdentity,
    to destination: String,
    session: IMAPSession
  ) async throws -> MessageIdentity? {
    let target = try await notAttempted {
      let uid = try await revalidatePresent(identity, writable: true, session: session).uid
      return (uid: try uidSet(uid), mailbox: try mailboxName(destination), source: uid)
    }
    let reply = try await session.command(.uidMove(target.uid, target.mailbox))
    guard let mapping = try moveMapping(reply, uid: target.source) else { return nil }
    var moved = identity
    moved.localID = mapping.uid
    moved.mailboxValidity = mapping.validity
    moved.mailbox = destination
    let observed = try await select(destination, writable: false, session: session)
    guard observed.validity == mapping.validity,
      try await lookup(moved, session: session) != nil
    else { throw IntegrationError.staleMessage }
    return moved
  }

  /**
   Stores the Review flag, reporting whether SpamWise newly set the `\Flagged` fallback.

   Where `\Flagged` stands in for the Review keyword and the message is already flagged, the
   flag is the user's: nothing is stored, and the message already shows as flagged.
   */
  static func markForReview(_ identity: MessageIdentity, session: IMAPSession)
    async throws -> ReviewMarking
  {
    let target = try await notAttempted {
      let revalidated = try await revalidatePresent(identity, writable: true, session: session)
      guard let flag = reviewFlag(permitted: revalidated.selection.permanentFlags) else {
        throw IMAPError.unsupported
      }
      let userFlagged =
        flag == .flagged
        ? try await flags(uid: revalidated.uid, session: session).contains(.flagged) : false
      return (uid: revalidated.uid, flag: flag, userFlagged: userFlagged)
    }
    guard !target.userFlagged else {
      return ReviewMarking(receipt: .init(confirmed: true), setFlagged: false)
    }
    let reply = try await session.command(
      .uidStore(try uidSet(target.uid), [], .flags(.add(silent: false, list: [target.flag])))
    )
    let confirmed = reply.fetches.contains {
      $0.uid == target.uid && $0.flags?.contains(target.flag) == true
    }
    return ReviewMarking(
      receipt: .init(confirmed: confirmed),
      setFlagged: confirmed && target.flag == .flagged
    )
  }

  /**
   Removes the flag ``markForReview(_:session:)`` stores; a mailbox that admits neither has
   nothing to clear.

   - Parameter removesFlagged: Whether SpamWise set the `\Flagged` fallback on this message.
     Without that evidence a `\Flagged` fallback is the user's own flag and stays.
   */
  static func clearReview(
    _ identity: MessageIdentity,
    removesFlagged: Bool,
    session: IMAPSession
  ) async throws -> ActionReceipt {
    let target = try await notAttempted {
      let revalidated = try await revalidatePresent(identity, writable: true, session: session)
      return (
        uid: revalidated.uid,
        flag: reviewFlag(permitted: revalidated.selection.permanentFlags)
      )
    }
    guard let flag = target.flag, flag != .flagged || removesFlagged else {
      return .init(confirmed: true)
    }
    let reply = try await session.command(
      .uidStore(try uidSet(target.uid), [], .flags(.remove(silent: false, list: [flag])))
    )
    let confirmed = reply.fetches.contains {
      $0.uid == target.uid && $0.flags?.contains(flag) == false
    }
    return .init(confirmed: confirmed)
  }

  /// The Review keyword when the mailbox admits it, else `\Flagged`, else nil.
  private static func reviewFlag(permitted: [PermanentFlag]) -> Flag? {
    if permitted.contains(.wildcard) || permitted.contains(.flag(reviewKeyword)) {
      return reviewKeyword
    }
    return permitted.contains(.flag(.flagged)) ? .flagged : nil
  }

  /// Selects the identity's mailbox and confirms UIDVALIDITY and exact content before any use.
  static func revalidate(
    _ identity: MessageIdentity,
    writable: Bool,
    session: IMAPSession
  ) async throws -> IMAPRevalidation {
    guard let mailbox = identity.mailbox, let uid = identity.localID else {
      throw IntegrationError.staleMessage
    }
    let selection = try await select(mailbox, writable: writable, session: session)
    guard selection.validity == identity.mailboxValidity else {
      throw IntegrationError.staleMessage
    }
    return IMAPRevalidation(
      selection: selection,
      uid: uid,
      envelope: try await lookup(identity, session: session)
    )
  }

  /// Revalidates a message that must still exist before a mail command addresses it.
  private static func revalidatePresent(
    _ identity: MessageIdentity,
    writable: Bool,
    session: IMAPSession
  ) async throws -> IMAPRevalidation {
    let revalidated = try await revalidate(identity, writable: writable, session: session)
    guard revalidated.envelope != nil else { throw IntegrationError.staleMessage }
    return revalidated
  }

  private static func lookup(_ identity: MessageIdentity, session: IMAPSession) async throws
    -> MailEnvelope?
  {
    guard let uid = identity.localID else { throw IntegrationError.staleMessage }
    guard let raw = try await fetch(uid: uid, session: session) else { return nil }
    guard stableHash(raw) == identity.contentHash else { throw IntegrationError.staleMessage }
    return .init(identity: identity, raw: raw)
  }

  /// Builds the envelope for a fetched message; UID, UIDVALIDITY and mailbox address it, Message-ID and content identify it.
  static func envelope(
    _ raw: Data,
    account: String,
    uid: Int,
    mailbox: String,
    validity: UInt64
  ) -> MailEnvelope {
    let identity = MessageIdentity(
      accountID: account,
      messageID: (try? MIMEParser().parse(raw))?.header("message-id"),
      localID: uid,
      mailboxValidity: validity,
      mailbox: mailbox,
      contentHash: stableHash(raw)
    )
    return .init(identity: identity, raw: raw)
  }
}

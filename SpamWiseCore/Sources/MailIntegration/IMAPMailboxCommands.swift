import Foundation
import NIOCore
import NIOIMAP
import SpamWiseCore

/// A mailbox opened by SELECT or EXAMINE.
struct IMAPMailboxSelection {
  /// UIDVALIDITY of the mailbox's UID namespace.
  var validity: UInt64
  /// Message count reported by EXISTS.
  var count: Int
  /// Flags the server stores permanently in this mailbox; a wildcard admits new keywords.
  var permanentFlags: [PermanentFlag]
  /// The UID the server predicts for the next message, when reported.
  var uidNext: Int?

  /// Whether the mailbox holds no messages.
  var isEmpty: Bool {
    // `count` is the number EXISTS reported, not a collection with its own `isEmpty`.
    // swiftlint:disable:next empty_count
    count == 0
  }
}

/// Server-designated special-use mailboxes; names retain their wire encoding.
struct IMAPMailboxRoles {
  var junk: String?
  var sent: String?
}

extension IMAPAdapter {
  private static let junkAttribute = MailboxInfo.Attribute(#"\Junk"#)
  private static let sentAttribute = MailboxInfo.Attribute(#"\Sent"#)
  private static let trashAttribute = MailboxInfo.Attribute(#"\Trash"#)

  /// True when the server can move a message atomically by UID.
  static func supportsMove(_ capabilities: Set<String>) -> Bool {
    capabilities.contains("MOVE") || capabilities.contains("IMAP4REV2")
  }

  static func requireMove(_ session: IMAPSession) throws {
    guard supportsMove(session.capabilities) else { throw IMAPError.unsupported }
  }

  static func select(_ mailbox: String, writable: Bool, session: IMAPSession) async throws
    -> IMAPMailboxSelection
  {
    let name = try mailboxName(mailbox)
    let reply = try await session.command(writable ? .select(name) : .examine(name))
    let validities = Set(
      reply.codes.compactMap { code -> UInt64? in
        if case .uidValidity(let value) = code { UInt64(value) } else { nil }
      }
    )
    let counts = reply.untagged.compactMap { payload -> Int? in
      if case .mailboxData(.exists(let count)) = payload { count } else { nil }
    }
    let uidNexts = Set(
      reply.codes.compactMap { code -> Int? in
        if case .uidNext(let value) = code { Int(value) } else { nil }
      }
    )
    guard validities.count == 1, let validity = validities.first, validity > 0,
      let count = counts.last, count >= 0, count <= UInt32.max, uidNexts.count <= 1
    else { throw IMAPError.malformedResponse }
    if writable, reply.codes.contains(.readOnly) { throw IMAPError.rejected }
    return IMAPMailboxSelection(
      validity: validity,
      count: count,
      permanentFlags: permanentFlags(in: reply),
      uidNext: uidNexts.first
    )
  }

  static func roles(session: IMAPSession) async throws -> IMAPMailboxRoles {
    let capabilities = session.capabilities
    guard capabilities.contains("SPECIAL-USE") || capabilities.contains("IMAP4REV2") else {
      return IMAPMailboxRoles()
    }
    let reply = try await session.command(
      .list(nil, reference: MailboxName([]), .pattern([ByteBuffer(string: "*")]), [.specialUse])
    )
    var junk: Set<String> = [], sent: Set<String> = []
    for case .mailboxData(.list(let info)) in reply.untagged {
      guard let mailbox = String(bytes: info.path.name.bytes, encoding: .utf8) else {
        throw IMAPError.malformedResponse
      }
      do { try IMAPWireText.validate(mailbox) } catch { throw IMAPError.malformedResponse }
      guard !info.attributes.contains(.noSelect), !info.attributes.contains(trashAttribute) else {
        continue
      }
      if info.attributes.contains(junkAttribute) { junk.insert(mailbox) }
      if info.attributes.contains(sentAttribute) { sent.insert(mailbox) }
    }
    guard junk.count <= 1, sent.count <= 1 else { throw IntegrationError.ambiguous }
    return IMAPMailboxRoles(junk: junk.first, sent: sent.first)
  }

  /// Fetches one message by UID without setting Seen; nil when the UID no longer exists.
  static func fetch(uid: Int, session: IMAPSession) async throws -> Data? {
    let reply = try await session.command(
      .uidFetch(try uidSet(uid), [.uid, .rfc822Size, .bodySection(peek: true, .complete, nil)], [])
    )
    let matching = reply.fetches.filter { $0.uid == uid }
    guard matching.count <= 1 else { throw IntegrationError.ambiguous }
    guard let message = matching.first else { return nil }
    guard let size = message.size, size <= IMAPPipeline.maximumBodyBytes, let body = message.body,
      body.count == size
    else { throw IMAPError.malformedResponse }
    return body
  }

  /// The destination UIDVALIDITY and UID a COPYUID response code assigns to `uid`, when present.
  static func moveMapping(_ reply: IMAPReply, uid: Int) throws -> (validity: UInt64, uid: Int)? {
    let mappings = reply.codes.compactMap { code -> ResponseCodeCopy? in
      if case .uidCopy(let mapping) = code { mapping } else { nil }
    }
    guard mappings.count <= 1, let mapping = mappings.first else { return nil }
    guard mapping.sourceUIDs.count == 1, mapping.destinationUIDs.count == 1,
      let source = mapping.sourceUIDs.first, let destination = mapping.destinationUIDs.first,
      source.lowerBound == source.upperBound, Int(source.lowerBound) == uid,
      destination.lowerBound == destination.upperBound
    else { return nil }
    return (UInt64(mapping.destinationUIDValidity), Int(destination.lowerBound))
  }

  static func mailboxName(_ mailbox: String) throws -> MailboxName {
    try IMAPWireText.validate(mailbox)
    return MailboxName(ByteBuffer(string: mailbox))
  }

  static func uidSet(_ uid: Int) throws -> LastCommandSet<UID> {
    guard let value = UInt32(exactly: uid), value > 0 else { throw IntegrationError.staleMessage }
    return .range(MessageIdentifierRange(UID(rawValue: value)))
  }

  private static func permanentFlags(in reply: IMAPReply) -> [PermanentFlag] {
    for case .permanentFlags(let flags) in reply.codes { return flags }
    for case .mailboxData(.flags(let flags)) in reply.untagged {
      return flags.map(PermanentFlag.flag)
    }
    return []
  }
}

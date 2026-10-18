import Foundation
import SpamWiseCore

/// One message row returned by the Mail handler library, with its source when readable.
struct MailRow: Sendable {
  let location: MailMessageLocation
  let source: String?
  /// The message envelope, or nil when its source is missing, empty or over the size limit.
  var envelope: MailEnvelope? {
    guard let source, !source.isEmpty, source.utf8.count <= MailScripts.maximumMessageBytes
    else { return nil }
    let raw = Data(source.utf8)
    return .init(
      identity: .init(
        accountID: location.accountID,
        messageID: location.messageID,
        localID: location.localID,
        mailbox: location.mailbox,
        contentHash: stableHash(raw)
      ),
      raw: raw
    )
  }

  init(_ value: ScriptValue) throws {
    guard let fields = value.list, fields.count == 6,
      let account = fields[0].string, !account.isEmpty,
      let mailbox = fields[1].string, !mailbox.isEmpty,
      let localID = fields[2].integer, let messageID = fields[3].string,
      let byteCount = fields[4].integer
    else { throw IntegrationError.scriptFailed }
    if fields[5] == .boolean(false) {
      source = nil
    } else if let source = fields[5].string {
      self.source = source
    } else {
      throw IntegrationError.scriptFailed
    }
    location = .init(
      accountID: account,
      mailbox: mailbox,
      localID: localID,
      messageID: messageID.isEmpty ? nil : messageID,
      byteCount: byteCount
    )
  }
}

extension AppleMailAdapter {
  static func decodePage(
    _ value: ScriptValue,
    accountID: String? = nil,
    mailbox: String? = nil,
    offset: Int,
    limit: Int
  ) throws -> MailPage {
    guard let result = value.list, result.count == 2,
      let total = result[0].integer, total >= 0, let values = result[1].list
    else { throw IntegrationError.scriptFailed }
    let remaining = max(0, total - max(0, offset))
    let requested = min(max(1, min(MailScripts.maximumPageSize, limit)), remaining)
    guard values.count <= requested, requested == 0 || !values.isEmpty else {
      throw IntegrationError.scriptFailed
    }
    let rows = try values.map(MailRow.init)
    guard
      rows.allSatisfy({
        (accountID == nil || $0.location.accountID == accountID)
          && (mailbox == nil || $0.location.mailbox == mailbox)
      })
    else { throw IntegrationError.mailboxUnresolved }
    return MailPage(messages: rows.compactMap(\.envelope), total: total, visitedCount: rows.count)
  }
}

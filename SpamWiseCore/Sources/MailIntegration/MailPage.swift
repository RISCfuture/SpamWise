public import SpamWiseCore

/// One bounded mailbox page, including entries whose source could not be read.
public struct MailPage: Sendable {
  /// Readable envelopes; unavailable entries never reach classification or mail actions.
  public let messages: [MailEnvelope]
  /// Current observed mailbox size; not a server acknowledgement.
  public let total: Int
  /// Mailbox positions visited, including unavailable entries.
  public let visitedCount: Int
  /// Entries requiring another attempt on a later sweep.
  public var unavailableCount: Int { visitedCount - messages.count }
}

extension AppleMailAdapter {
  static func decodePage(
    _ value: ScriptValue,
    accountID: String,
    mailbox: String? = nil,
    offset: Int,
    limit: Int
  ) throws -> MailPage {
    guard let result = value.list, result.count == 2,
      let total = result[0].integer, total >= 0, let rows = result[1].list,
      rows.count == min(max(1, min(maximumPageSize, limit)), max(0, total - max(0, offset)))
    else { throw IntegrationError.scriptFailed }
    var messages: [MailEnvelope] = []
    for row in rows {
      guard let fields = row.list, fields.count == 5,
        let account = fields[0].string, !account.isEmpty,
        let box = fields[1].string, !box.isEmpty,
        fields[2].integer != nil, fields[3].string != nil
      else { throw IntegrationError.scriptFailed }
      guard account == accountID, mailbox == nil || box == mailbox else {
        throw IntegrationError.ambiguous
      }
      if fields[4] == .boolean(false) { continue }
      guard let source = fields[4].string else { throw IntegrationError.scriptFailed }
      guard !source.isEmpty, source.utf8.count <= maximumMessageBytes else { continue }
      messages.append(try envelope(row))
    }
    return MailPage(messages: messages, total: total, visitedCount: rows.count)
  }
}

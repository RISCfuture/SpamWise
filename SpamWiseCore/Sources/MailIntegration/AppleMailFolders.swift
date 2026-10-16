public import Foundation
public import SpamWiseCore

extension AppleMailAdapter {
  /// Lists exact mailbox paths without fetching message content.
  public func folders() async throws -> [MailFolder] {
    guard let rows = try await runFolderScript(MailScripts.folders).list, rows.count <= 1000
    else { throw IntegrationError.scriptFailed }
    return try rows.map { row in
      guard let fields = row.list, fields.count == 2, let account = fields[0].string,
        let names = fields[1].list, !names.isEmpty, names.count <= 16,
        names.allSatisfy({ $0.string != nil })
      else { throw IntegrationError.scriptFailed }
      return MailFolder(accountID: account, path: names.compactMap(\.string))
    }
  }
  /// Reads one selected folder page; unresolved or renamed paths remain untouched.
  public func folderPage(_ folder: MailFolder, offset: Int, limit: Int, since: Date? = nil)
    async throws -> MailPage
  {
    guard
      let fields = try await runFolderScript(
        MailScripts.folderPage(folder, offset: offset, limit: limit, since: since)
      ).list,
      fields.count == 2, let total = fields[0].integer, total >= 0,
      let rows = fields[1].list, rows.count <= max(1, min(1000, limit))
    else { throw IntegrationError.scriptFailed }
    let messages = try rows.map(Self.envelope)
    guard
      messages.allSatisfy({
        $0.identity.accountID == folder.accountID && $0.identity.mailbox == folder.path.last
      })
    else { throw IntegrationError.ambiguous }
    return MailPage(messages: messages, total: total)
  }
}

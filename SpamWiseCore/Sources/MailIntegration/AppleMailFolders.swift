public import Foundation
public import SpamWiseCore

extension AppleMailAdapter {
  private static func isAddressable(_ folder: MailFolder) -> Bool {
    !folder.accountID.isEmpty && !folder.path.isEmpty
      && folder.path.count <= MailScripts.maximumFolderDepth
      && folder.path.allSatisfy {
        !$0.isEmpty && $0.utf8.count <= MailScripts.maximumFolderNameBytes
      }
  }
  /// Lists exact mailbox paths without fetching message content.
  public func folders() async throws -> [MailFolder] {
    guard let rows = try await invoke(.folders).list, rows.count <= MailScripts.maximumFolders
    else { throw IntegrationError.scriptFailed }
    return try rows.map { row in
      guard let fields = row.list, fields.count == 2, let account = fields[0].string,
        let names = fields[1].list, !names.isEmpty,
        names.count <= MailScripts.maximumFolderDepth, names.allSatisfy({ $0.string != nil })
      else { throw IntegrationError.scriptFailed }
      return MailFolder(accountID: account, path: names.compactMap(\.string))
    }
  }
  /// Reads one selected folder page; unresolved or renamed paths remain untouched.
  public func folderPage(_ folder: MailFolder, offset: Int, limit: Int, since: Date? = nil)
    async throws -> MailPage
  {
    guard Self.isAddressable(folder) else { throw IntegrationError.folderUnresolved }
    return try Self.decodePage(
      await invoke(.folderPage(folder, offset: offset, limit: limit, since: since)),
      accountID: folder.accountID,
      mailbox: folder.path.last,
      offset: offset,
      limit: limit
    )
  }
}

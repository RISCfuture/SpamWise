import Foundation
import MailIntegration
import SpamWiseCore

extension AppleMailAdapter {
  /// Writes up to `limit` raw messages from `role`'s mailboxes to `directory` without overwriting files, returning the count.
  func export(role: MailboxRole, to directory: URL, limit: Int = 500) async throws -> Int {
    let messages = try await messages(limit: limit, role: role)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for message in messages {
      try message.raw.write(
        to: directory.appending(path: message.identity.key + ".eml"),
        options: .withoutOverwriting
      )
    }
    return messages.count
  }
}

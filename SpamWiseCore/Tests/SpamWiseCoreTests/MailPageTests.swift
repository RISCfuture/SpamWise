import Foundation
import Testing
import SpamWiseCore
@testable import MailIntegration

private let oversized = MailReply.message(
  localID: 1,
  messageID: "oversized",
  source: String(repeating: "x", count: MailScripts.maximumMessageBytes + 1)
)
private let readable = MailReply.message(
  localID: 2,
  messageID: "readable",
  source: "From: person@example.org\nSubject: Later mail\n\nHello"
)
private let unreadable = MailReply.message(localID: 3, messageID: "missing", source: nil)

private func decode(_ page: ScriptValue, accountID: String = "account", offset: Int = 0) throws
  -> MailPage
{
  try AppleMailAdapter.decodePage(page, accountID: accountID, offset: offset, limit: 20)
}

@Test
func `skips unreadable messages in an Inbox page and counts their positions`() async throws {
  let adapter = AppleMailAdapter(
    runner: StubAppleEvents([.accountPage: [MailReply.page(total: 3, [oversized, readable])]])
  )
  let page = try await adapter.inboxPage(accountID: "account", offset: 0, limit: 20)
  #expect(page.messages.map(\.identity.localID) == [2])
  #expect(page.visitedCount == 2)
  #expect(page.unavailableCount == 1)
}

@Test
func `skips unreadable messages in the selection`() async throws {
  let adapter = AppleMailAdapter(
    runner: StubAppleEvents([.selectedRows: [MailReply.selection(unreadable, readable)]])
  )
  let selection = try await adapter.selectedMessages()
  #expect(selection.messages.map(\.identity.localID) == [2])
  #expect(selection.unavailableCount == 1)
}

@Test
func `visits a page whose messages are all unreadable`() throws {
  let page = try decode(MailReply.page(total: 3, [unreadable]), offset: 2)
  #expect(page.messages.isEmpty)
  #expect(page.visitedCount == 1)
}

@Test(arguments: ["other", ""])
func `rejects a page from another or unnamed account`(_ accountID: String) {
  #expect(throws: IntegrationError.mailboxUnresolved) {
    try decode(MailReply.page(total: 1, [unreadable]), accountID: accountID)
  }
}

@Test
func `rejects a page that omits messages the mailbox reports`() {
  #expect(throws: IntegrationError.scriptFailed) { try decode(MailReply.page(total: 1, [])) }
}

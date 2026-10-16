import Foundation
import SpamWiseCore

actor RecordingAdapter: MailClientAdapter {
  var actions: [MailAction] = []
  var fail = false
  var updatedIdentity: MessageIdentity?
  var lookups = 0
  var message: MailEnvelope?
  var readRequests = 0
  var failRead = true
  func markReadInJunk(_ identity: MessageIdentity) async throws -> ActionReceipt {
    readRequests += 1
    if failRead { throw IntegrationError.staleMessage }
    return .init(confirmed: true)
  }
  func allowMarkRead() { failRead = false }
  func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope? {
    lookups += 1
    return message
  }
  func retain(_ envelope: MailEnvelope) { message = envelope }
  func recentMessages(limit: Int) async throws -> [MailEnvelope] { [] }
  func importHistory() async throws -> [String: HistoryIndex] { [:] }
  func perform(_ action: MailAction, for identity: MessageIdentity) async throws -> ActionReceipt {
    if fail { throw IntegrationError.permissionDenied }
    actions.append(action); return .init(confirmed: true, updatedIdentity: updatedIdentity)
  }
  func deny() { fail = true }
  func moveIdentity(to identity: MessageIdentity) { updatedIdentity = identity }
}
func testStore() throws -> Store {
  try Store(
    url: FileManager.default.temporaryDirectory.appending(
      path: "SpamWise-tests/\(UUID())/state.store"
    )
  )
}
func envelope(_ name: String = "filler-spam") throws -> MailEnvelope {
  let raw = try fixture(name)
  return MailEnvelope(
    identity: .init(accountID: "account-A", contentHash: stableHash(raw)),
    raw: raw
  )
}
func enableActions(_ store: Store) async throws {
  try await StateRepository.update(store) { state in
    state.settings.dryRun = false; state.settings.route = .mailRule
    state.settings.validatedAccounts = ["account-A"]
  }
}

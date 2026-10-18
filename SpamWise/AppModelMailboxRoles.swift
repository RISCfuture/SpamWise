import Foundation
import SpamWiseCore
import MailIntegration

extension AppModel {
  /// Reads each discovered account's Inbox and Junk roles and records the definitive results.
  ///
  /// An account whose check fails keeps its previous validation, and an account Mail no longer
  /// reports loses it while validated IMAP accounts keep theirs. Returns the validated count.
  func validateMailboxRoles() async throws -> Int {
    var results: [String: Bool] = [:]
    for account in accounts {
      try Task.checkCancellation()
      if let destinations = try? await adapter.destinations(accountID: account.id) {
        results[account.id] = destinations.isUnambiguous
      }
    }
    if let store {
      try await StateRepository.recordAppleMailRoles(
        results,
        in: store,
        reportedAccounts: Set(accounts.map(\.id))
      )
    }
    return accounts.count { results[$0.id] ?? state.settings.validatedAccounts.contains($0.id) }
  }
  /// Reads one account's mailbox roles and records whether they resolve uniquely.
  func readDestinations(accountID: String) async throws -> MailDestinations {
    let destinations = try await adapter.destinations(accountID: accountID)
    if let store {
      try await StateRepository.recordMailboxRoles(
        [accountID: destinations.isUnambiguous],
        in: store
      )
    }
    return destinations
  }
  func testDisposableMessage() {
    run { [self] in
      do {
        moveTestStatus =
          String(
            localized:
              "Testing the selected message; allowing 30 seconds after each move for Mail to sync…"
          )
        _ = try await adapter.testDisposableMessage()
        moveTestStatus =
          String(localized: "Junk, Inbox restoration, and orange flag verified in Mail.")
      } catch { moveTestStatus = Self.describe(error); throw error }
    }
  }
}

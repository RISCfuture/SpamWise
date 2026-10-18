import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// Read-only review of an account's Junk mailbox, with Good corrections that restore mail.
@MainActor @Observable final class JunkReviewModel {
  /// Messages listed per page.
  static let pageSize = 20
  /// The page shown.
  private(set) var messages: [ReviewMessage] = []
  /// Messages in the reviewed Junk mailbox.
  private(set) var total = 0
  /// Loading pages and restoring messages.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let mail: MailConnectionModel

  /// Accounts whose Junk can be reviewed.
  var accounts: [MailAccount] { mail.accounts }

  init(services: AppServices, mail: MailConnectionModel) {
    self.services = services
    self.mail = mail
  }

  /// Rereads Mail's accounts so the account list is current.
  func discoverAccounts() {
    operation.run(retryable: true) { [self] in
      try await mail.discoverAccounts()
      return nil
    }
  }

  /// Shows the page of `accountID`'s Junk mailbox starting at `offset`.
  func load(accountID: String, offset: Int) {
    operation.run(retryable: true) { [self] in
      let page = try await services.appleMail.accountPage(
        accountID: accountID,
        offset: offset,
        limit: Self.pageSize,
        role: .junk
      )
      messages = await ReviewMessage.load(page.messages)
      total = page.total
      return page.unavailableCount > 0
        ? ScanCoordinator.unreadableStatus(page.unavailableCount) : nil
    }
  }

  /// Empties the list, as when another account is chosen.
  func clear() {
    messages = []
    total = 0
  }

  /// Corrects `envelope` as Good and moves it back to Inbox.
  func restore(_ envelope: MailEnvelope) {
    operation.run { [self] in
      let record = try await services.requirePipeline().correct(
        envelope: envelope,
        label: .inbox,
        adapter: services.appleMail
      )
      if record.outcome == .applied {
        messages.removeAll { $0.id == envelope.identity.key }
      }
      return String(localized: "Correction saved. Mail action: \(record.outcome.localizedTitle).")
    }
  }
}

import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/**
 Read-only review of one account’s Junk mailbox, with Good corrections that restore mail.

 The review is emptied when it closes, so it opens with no account. Choosing an account loads
 its first page, and a page change takes effect only once that page has loaded.
 */
@MainActor
@Observable
final class JunkReviewModel {
  /// Messages listed per page.
  static let pageSize = 20
  /// The account whose Junk is shown, if one is chosen.
  private(set) var accountID: String?
  /// The zero-based index of the page shown.
  private(set) var pageIndex = 0
  /// The messages on the page shown.
  private(set) var rows: [JunkReviewRow] = []
  /// Messages in the account’s Junk mailbox.
  private(set) var total = 0
  /// Whether a page of the chosen account has loaded.
  private(set) var hasLoaded = false
  /// Loading accounts and pages.
  let loading = TrackedOperation()
  /// Restoring messages to the Inbox.
  let restoring = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let mail: MailConnectionModel
  @ObservationIgnored private let shared: SharedStateModel

  /// Accounts whose Junk can be reviewed.
  var accounts: [MailAccount] { mail.accounts }
  /// The number of pages in the account’s Junk, at least one.
  var pageCount: Int { max(1, (total + Self.pageSize - 1) / Self.pageSize) }
  var hasPreviousPage: Bool { accountID != nil && pageIndex > 0 }
  var hasNextPage: Bool { accountID != nil && pageIndex + 1 < pageCount }

  init(services: AppServices, mail: MailConnectionModel, shared: SharedStateModel) {
    self.services = services
    self.mail = mail
    self.shared = shared
  }

  /// Describes skipped messages, which are usually too large to read.
  nonisolated static func unreadableStatus(_ count: Int) -> String {
    let limit = Int64(MIMEParser.maximumMessageBytes).formatted(.byteCount(style: .file))
    return String(
      localized:
        "\(count) messages couldn’t be read and were skipped, such as messages over \(limit)."
    )
  }

  private static func restoredStatus(_ outcome: ActionOutcome) -> String {
    switch outcome {
      case .applied: String(localized: "Marked as Good and moved to the Inbox.")
      case .dryRun:
        String(localized: "Marked as Good. Dry run is on, so the message stays in Junk.")
      case .paused:
        String(localized: "Marked as Good. Filtering is paused, so the message stays in Junk.")
      case .failed, .integrationUnavailable:
        String(localized: "Marked as Good, but Mail couldn’t move the message. Move it in Mail.")
      default:
        String(localized: "Marked as Good. Mail action: \(outcome.localizedTitle).")
    }
  }

  /// Rereads Mail’s accounts so the account list is current.
  func discoverAccounts() {
    loading.run(retryable: true) { [self] in
      try await mail.discoverAccounts()
      return nil
    }
  }

  /// Shows the first page of `accountID`’s Junk, or nothing when no account is chosen.
  func choose(accountID: String?) {
    self.accountID = accountID
    pageIndex = 0
    rows = []
    total = 0
    hasLoaded = false
    loading.status = nil
    restoring.status = nil
    if accountID != nil { showPage(0) }
  }

  /// Loads page `index` of the chosen account; the page shown changes only if it loads.
  func showPage(_ index: Int) {
    guard let accountID, index >= 0 else { return }
    loading.run(retryable: true) { [self] in
      let page = try await services.appleMail.accountPage(
        accountID: accountID,
        offset: index * Self.pageSize,
        limit: Self.pageSize,
        role: .junk
      )
      let loaded = await rows(for: page.messages)
      guard self.accountID == accountID else { return nil }
      rows = loaded
      total = page.total
      pageIndex = index
      hasLoaded = true
      return page.unavailableCount > 0 ? Self.unreadableStatus(page.unavailableCount) : nil
    }
  }

  /// The Block rule a Good correction of `row` would override, if one matches its sender.
  func blockingRule(for row: JunkReviewRow) -> SenderRule? {
    guard let sender = row.message.sender else { return nil }
    let domain = DomainResolver().domain(ofAddress: sender)
    return Gates.matchingRule(address: sender, domain: domain, rules: shared.state.rules)
      .flatMap { $0.disposition == .block ? $0 : nil }
  }

  /// Corrects `row` as Good and moves it back to the Inbox.
  func restore(_ row: JunkReviewRow) {
    let envelope = row.message.envelope
    restoring.run { [self] in
      let record = try await services.requirePipeline().correct(
        envelope: envelope,
        label: .inbox,
        adapter: services.appleMail
      )
      if record.outcome == .applied, let index = rows.firstIndex(where: { $0.id == row.id }) {
        rows.remove(at: index)
        total = max(0, total - 1)
      }
      return Self.restoredStatus(record.outcome)
    }
  }

  /// Shows `rows` as a loaded page of `accountID`, for previews.
  func preview(accountID: String, rows: [JunkReviewRow], total: Int) {
    self.accountID = accountID
    self.rows = rows
    self.total = total
    hasLoaded = true
  }

  private func rows(for envelopes: [MailEnvelope]) async -> [JunkReviewRow] {
    let messages = await ReviewMessage.load(envelopes)
    let byMessage = Dictionary(
      grouping: await records(identityKeys: Set(messages.map(\.id))),
      by: \.identity.key
    )
    return messages.map { message in
      JunkReviewRow(
        message: message,
        provenance: JunkProvenance(records: byMessage[message.id] ?? [])
      )
    }
  }

  /// Activity for the messages, or none when it can’t be read; explanations then show unknown.
  private func records(identityKeys: Set<String>) async -> [DecisionRecord] {
    guard let store = services.store else { return [] }
    return (try? await StateRepository.records(store, identityKeys: identityKeys)) ?? []
  }
}

/// One message in Junk, with why it’s there.
struct JunkReviewRow: Identifiable, Sendable {
  let message: ReviewMessage
  let provenance: JunkProvenance
  var id: String { message.id }
}

/// Who put a message in Junk, as far as SpamWise’s Activity shows.
enum JunkProvenance: Equatable, Sendable {
  /// SpamWise moved the message to Junk for this reason.
  case spamWise(DecisionReason)
  /// The user corrected the message to Junk.
  case userCorrection
  /// SpamWise saw the message but didn’t leave it in Junk; another filter or the server did.
  case elsewhere
  /// SpamWise has no record of the message.
  case unknown

  /**
   The provenance shown by `records`, newest first: the latest move SpamWise made or requested
   decides it.
   */
  init(records: [DecisionRecord]) {
    guard !records.isEmpty else {
      self = .unknown
      return
    }
    let latestMove = records.first {
      [.applied, .requested].contains($0.outcome)
        && [.moveToJunk, .moveToInbox].contains($0.decision.action)
    }
    guard let latestMove, latestMove.decision.action == .moveToJunk else {
      self = .elsewhere
      return
    }
    self =
      latestMove.path == .correction ? .userCorrection : .spamWise(latestMove.decision.reason)
  }
}

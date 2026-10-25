import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// Previews of Inbox mail received before automatic filtering started, applied only on request.
@MainActor
@Observable
final class OlderMailModel {
  /// Previewed records awaiting the user's decision to apply them, by account.
  private(set) var previews: [String: [UUID]] = [:]
  /// What each account's awaiting previews decided, as of the preview.
  private(set) var summaries: [String: OlderMailSummary] = [:]
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private var operations: [String: TrackedOperation] = [:]

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  /// When automatic filtering of `accountID`'s Inbox starts.
  func inboxStart(accountID: String) -> Date? {
    shared.scanHealth[accountID]?.inboxStart
  }

  /// The previewing and applying of `accountID`'s older mail.
  func operation(for accountID: String) -> TrackedOperation {
    if let operation = operations[accountID] { return operation }
    let operation = TrackedOperation()
    operations[accountID] = operation
    return operation
  }

  /// Classifies one page of older Inbox mail as a dry run.
  func preview(accountID: String, page: Int) {
    operation(for: accountID).run { [self] in
      guard !shared.settings.dryRun, let start = inboxStart(accountID: accountID) else {
        return nil
      }
      previews[accountID] = nil; summaries[accountID] = nil
      let older = try await services.appleMail.inboxPage(
        accountID: accountID,
        offset: page * ScanCoordinator.pageLimit,
        limit: ScanCoordinator.pageLimit,
        before: start
      )
      let records = try await services.sweeper(transport: .appleMail, source: services.appleMail)
        .preview(older.messages) { [shared] _ in await shared.refresh() }
      let previewed = records.filter { $0.outcome == .dryRun }
      previews[accountID] = previewed.map(\.id)
      summaries[accountID] = OlderMailSummary(previewed)
      return older.unavailableCount > 0
        ? ScanCoordinator.unreadableStatus(older.unavailableCount)
        : String(
          localized:
            "Older mail preview finished. No mail actions requested. Review it in Activity, then apply."
        )
    }
  }

  /// Requests the previewed decisions' mail actions.
  func apply(accountID: String) {
    guard let previewed = previews[accountID] else { return }
    operation(for: accountID).run { [self] in
      let pipeline = try services.requirePipeline()
      previews[accountID] = nil; summaries[accountID] = nil
      var requested = 0
      for recordID in previewed {
        try Task.checkCancellation()
        let record = try? await pipeline.applyPreview(
          recordID: recordID,
          adapter: services.appleMail
        )
        if let record, [.requested, .applied].contains(record.outcome) { requested += 1 }
      }
      return String(localized: "Requested mail actions for \(requested) previewed messages.")
    }
  }
}

/// How many previewed older messages each kind of decision covers.
struct OlderMailSummary: Equatable {
  /// Messages the preview sends to Junk.
  let junk: Int
  /// Messages the preview marks for Review.
  let review: Int
  /// Messages the preview leaves in the Inbox.
  let inbox: Int

  /// Every previewed decision.
  var total: Int { junk + review + inbox }

  /// What applying the preview does to mail, leaving out kinds that cover no message.
  var consequences: String {
    [
      junk > 0 ? String(localized: "\(junk) messages move to Junk.") : nil,
      review > 0 ? String(localized: "\(review) messages are marked for Review.") : nil,
      inbox > 0 ? String(localized: "\(inbox) messages stay in the Inbox.") : nil,
      String(localized: "Messages you corrected since the preview stay as they are.")
    ]
    .compactMap(\.self).joined(separator: " ")
  }

  /// Counts the decisions of `records`; an unclassified record counts as staying in the Inbox.
  init(_ records: [DecisionRecord]) {
    junk = records.count { $0.decision.label == .junk }
    review = records.count { $0.decision.label == .review }
    inbox = records.count - junk - review
  }
}

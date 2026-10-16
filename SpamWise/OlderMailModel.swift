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
      previews[accountID] = nil
      let older = try await services.appleMail.inboxPage(
        accountID: accountID,
        offset: page * ScanCoordinator.pageLimit,
        limit: ScanCoordinator.pageLimit,
        before: start
      )
      let records = try await services.sweeper(transport: .appleMail, source: services.appleMail)
        .preview(older.messages) { [shared] _ in await shared.refresh() }
      previews[accountID] = records.filter { $0.outcome == .dryRun }.map(\.id)
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
      previews[accountID] = nil
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

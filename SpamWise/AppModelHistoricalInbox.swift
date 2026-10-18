import Foundation
import SpamWiseCore
import MailIntegration

extension AppModel {
  func inboxStart(accountID: String) -> Date? {
    scanHealth[accountID]?.inboxStart
  }
  func previewHistoricalInbox(accountID: String, page: Int) {
    guard pipeline != nil, !state.settings.dryRun, let start = inboxStart(accountID: accountID)
    else { return }
    run { [self] in
      historicalPreview[accountID] = nil
      let older = try await adapter.inboxPage(
        accountID: accountID,
        offset: page * Self.defaultScanLimit,
        limit: Self.defaultScanLimit,
        before: start
      )
      let records = try await preview(older.messages)
      historicalPreview[accountID] = records.filter { $0.outcome == .dryRun }.map(\.id)
      status = String(
        localized:
          "Older mail preview finished. No mail actions requested. Review it in Activity, then apply."
      )
      if older.unavailableCount > 0 { status = Self.unreadableStatus(older.unavailableCount) }
    }
  }
  func applyHistoricalPreview(accountID: String) {
    guard let pipeline, let previewed = historicalPreview[accountID] else { return }
    run { [self] in
      historicalPreview[accountID] = nil
      var requested = 0
      for recordID in previewed {
        try Task.checkCancellation()
        let record = try? await pipeline.applyPreview(recordID: recordID, adapter: adapter)
        if let record, [.requested, .applied].contains(record.outcome) { requested += 1 }
      }
      status = String(
        localized: "Requested mail actions for \(requested, format: .number) previewed messages."
      )
    }
  }
}

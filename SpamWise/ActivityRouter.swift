import Foundation
import Observation

/// A modal the Activity window presents; the window shows one at a time.
enum ActivitySheet: Identifiable, Equatable {
  /// This week's Review digest.
  case digest
  /// Results of correcting the messages selected in Mail.
  case selectionCorrections
  /// The read-only Junk folder review.
  case junkReview
  /// A message's plain text.
  case messagePreview(MessagePreview)
  /// Activity statistics and exports.
  case statistics
  /// Configuration history.
  case audit
  /// The reviewed corpus.
  case corpus
  /// The Activity date-range filter.
  case dateFilter
  /// Exporting a backup or restoring one.
  case backup(BackupTask)

  var id: String {
    switch self {
      case .digest: "digest"
      case .selectionCorrections: "selectionCorrections"
      case .junkReview: "junkReview"
      case .messagePreview(let preview): "messagePreview.\(preview.id)"
      case .statistics: "statistics"
      case .audit: "audit"
      case .corpus: "corpus"
      case .dateFilter: "dateFilter"
      case .backup(let task): "backup.\(task.rawValue)"
    }
  }
}

/// A message's text, read once for display.
struct MessagePreview: Identifiable, Hashable {
  let id = UUID()
  let text: String
}

/**
 Routes every Activity modal through one presentation.

 Presenting a sheet while another is up replaces it, so a request from the menu bar, a
 notification or the Tools menu is shown rather than lost.
 */
@MainActor
@Observable
final class ActivityRouter {
  /// The sheet the Activity window shows.
  var sheet: ActivitySheet?
  /// Whether the Activity window shows the selected decision's inspector.
  var showsInspector = false
  /// Whether the Activity window asks to confirm turning off dry run.
  var confirmsLiveFiltering = false
  /// Whether the Activity window closes once settings load, because macOS opened SpamWise at
  /// login or to check mail for a Mail rule.
  var closesWindowAtLaunch = false

  /// Whether the Activity window can ask to confirm turning off dry run, which it can't over a sheet.
  var canConfirmLiveFiltering: Bool { sheet == nil }

  func present(_ sheet: ActivitySheet) { self.sheet = sheet }

  /// Asks in the Activity window to confirm turning off dry run, unless a sheet is up.
  func confirmLiveFiltering() {
    guard canConfirmLiveFiltering else { return }
    confirmsLiveFiltering = true
  }
}

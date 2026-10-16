import SwiftUI
import SpamWiseCore

extension AppModel {
  func handle(_ url: URL) {
    guard url.scheme == "spamwise", url.host == "check-inbox" else { return }
    scan(dryRun: state.settings.dryRun, automatic: true)
  }
  func revealRule() {
    guard let url = Bundle.main.url(forResource: "SpamWiseRule", withExtension: "scpt") else {
      status = String(localized: "Rule script missing from app bundle"); return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}

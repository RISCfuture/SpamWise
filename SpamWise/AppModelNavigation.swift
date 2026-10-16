import SwiftUI
import SpamWiseCore

extension AppModel {
  func handle(_ url: URL) {
    guard url.scheme == "spamwise" else { return }
    switch url.host {
      case "check-inbox": scan(dryRun: state.settings.dryRun, automatic: true)
      case "review": showDigest = true
      case "activity": break
      default: return
    }
  }
  func revealRule() {
    guard let url = Bundle.main.url(forResource: "SpamWiseRule", withExtension: "scpt") else {
      status = String(localized: "Rule script missing from app bundle"); return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}

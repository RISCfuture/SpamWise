import Foundation
import SpamWiseCore
import MailIntegration

extension AppModel {
  /// Every saved folder plan, with whether its folder appeared in the latest folder list.
  var folderPlanStatuses: [FolderPlanStatus] {
    FolderPlans.statuses(
      state.settings.mailOptions.folderPlans,
      resolving: folders.isEmpty ? nil : folders
    )
  }
  func discoverFolders() {
    run { [self] in
      try await discoverAccounts()
      folders = try await adapter.folders()
    }
  }
  func saveFolderPlan(_ plan: MailFolderPlan) {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      try await FolderPlans.save(plan, source: adapter, in: store)
      status = String(
        localized: "Folder plan saved. Existing dry-run and account validation still apply."
      )
    }
  }
  /// Turns automatic processing of a saved plan on or off, even when its folder no longer resolves.
  func setFolderPlan(_ planID: String, enabled: Bool) {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      try await FolderPlans.setEnabled(enabled, planID: planID, in: store)
    }
  }
  /// Removes a saved plan without changing its folder or the mail in it.
  func removeFolderPlan(_ planID: String) {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      try await FolderPlans.remove(planID: planID, in: store)
      status = String(localized: "Folder plan removed. The folder and its mail are unchanged.")
    }
  }
  func refilterFolder(_ folder: MailFolder, since: Date, offset: Int = 0) {
    guard pipeline != nil else { return }
    run { [self] in
      let preview = try await mailSweeper(source: adapter).previewFolder(
        folder,
        since: since,
        offset: offset,
        limit: Self.defaultScanLimit
      )
      status = String(localized: "Folder preview finished. No mail actions requested.")
      if preview.unavailableCount > 0 { status = Self.unreadableStatus(preview.unavailableCount) }
    }
  }
}

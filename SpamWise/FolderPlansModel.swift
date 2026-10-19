import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// Mail.app folders that SpamWise filters or learns from, and previews of their mail.
@MainActor
@Observable
final class FolderPlansModel {
  /// Folders Mail reported at the latest discovery.
  private(set) var folders: [MailFolder] = []
  /// Discovering folders, and enabling or removing saved plans.
  let plans = TrackedOperation()
  /// Saving the plan being edited; its failure explains why the plan wasn't saved.
  let saving = TrackedOperation()
  /// Previewing a page of a folder's mail; stopping it leaves other work running.
  let preview = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private let mail: MailConnectionModel

  /// Every saved folder plan, with whether its folder appeared in the latest folder list.
  var statuses: [FolderPlanStatus] {
    FolderPlans.statuses(
      shared.settings.mailOptions.folderPlans,
      resolving: folders.isEmpty ? nil : folders
    )
  }

  init(services: AppServices, shared: SharedStateModel, mail: MailConnectionModel) {
    self.services = services
    self.shared = shared
    self.mail = mail
  }

  /// Rereads Mail's accounts and folders.
  func discoverFolders() {
    plans.run(retryable: true) { [self] in
      try await mail.discoverAccounts()
      folders = try await services.appleMail.folders()
      return nil
    }
  }

  /// Validates and saves `plan`, replacing the saved plan for its folder.
  func save(_ plan: MailFolderPlan) {
    saving.run { [self] in
      try await FolderPlans.save(plan, source: services.appleMail, in: services.requireStore())
      return String(localized: "Folder plan saved. Dry run and Pause apply to it too.")
    }
  }

  /// Turns automatic processing of a saved plan on or off, even when its folder no longer resolves.
  func setEnabled(_ enabled: Bool, planID: String) {
    plans.run { [self] in
      try await FolderPlans.setEnabled(enabled, planID: planID, in: services.requireStore())
      return nil
    }
  }

  /// Removes a saved plan without changing its folder or the mail in it.
  func remove(_ planID: String) {
    plans.run { [self] in
      try await FolderPlans.remove(planID: planID, in: services.requireStore())
      return String(localized: "Folder plan removed. The folder and its mail are unchanged.")
    }
  }

  /// Recomputes decisions for one page of `folder` without replaying mail actions.
  func previewPage(of folder: MailFolder, since start: Date, page: Int) {
    preview.run { [self] in
      let result = try await services.sweeper(
        transport: .appleMail,
        source: services.appleMail
      ).previewFolder(
        folder,
        since: start,
        offset: page * ScanCoordinator.pageLimit,
        limit: ScanCoordinator.pageLimit
      )
      return result.unavailableCount > 0
        ? ScanCoordinator.unreadableStatus(result.unavailableCount)
        : String(localized: "Folder preview finished. No mail actions requested.")
    }
  }
}

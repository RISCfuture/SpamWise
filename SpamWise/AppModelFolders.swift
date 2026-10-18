import Foundation
import SpamWiseCore
import MailIntegration

extension AppModel {
  func discoverFolders() {
    run { [self] in
      try await discoverAccounts()
      folders = try await adapter.folders()
    }
  }
  func saveFolderPlan(_ plan: MailFolderPlan) {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      var validated = plan
      if plan.purpose != .filter {
        guard plan.folder.path.last == TrainingFolders.name(for: plan.purpose) else {
          throw IntegrationError.unavailable
        }
        let current = state.settings.mailOptions.folderPlans.first { $0.id == plan.id }
        if current?.trainingBaselineValidated != true || current?.purpose != plan.purpose {
          let page = try await adapter.folderPage(plan.folder, offset: 0, limit: 1)
          guard page.total == 0 else { throw IntegrationError.unavailable }
        }
        validated.trainingBaselineValidated = true
      }
      let saved = validated
      try await StateRepository.editSettings(store) { settings in
        settings.mailOptions.folderPlans.removeAll { $0.id == saved.id }
        guard settings.mailOptions.folderPlans.count < 20 else {
          throw IntegrationError.unavailable
        }
        settings.mailOptions.folderPlans.append(saved)
      }
      status = String(
        localized: "Folder plan saved. Existing dry-run and account validation still apply."
      )
    }
  }
  func refilterFolder(_ folder: MailFolder, since: Date, offset: Int = 0) {
    guard let pipeline else { return }
    run { [self] in
      let page = try await adapter.folderPage(folder, offset: offset, limit: 20, since: since)
      try await classify(
        ScanBatch(adapter: adapter, messages: page.messages, retryAccountID: folder.accountID),
        with: pipeline,
        dryRun: true,
        automatic: false
      )
      status = String(localized: "Folder preview finished. No mail actions requested.")
      if page.unavailableCount > 0 { status = Self.unreadableStatus(page.unavailableCount) }
    }
  }
  func scanConfiguredFolders(with pipeline: Pipeline, dryRun: Bool, limit: Int) async throws {
    guard let store else { throw IntegrationError.unavailable }
    let plans = Array(state.settings.mailOptions.folderPlans.filter(\.enabled).prefix(20))
    for plan in plans
    where state.settings.mailOptions.accountIDs?.contains(plan.folder.accountID) ?? true {
      try Task.checkCancellation()
      guard !state.settings.paused else { return }
      let cursorKey = "folder:" + plan.id
      do {
        let health = try await MailHealthRepository.load(store, key: cursorKey)
        let offset = health?.nextOffset ?? 0
        let page = try await adapter.folderPage(
          plan.folder,
          offset: offset,
          limit: limit,
          since: plan.purpose == .filter ? plan.startDate : nil
        )
        if plan.purpose == .filter {
          try await classify(
            ScanBatch(
              adapter: adapter,
              messages: page.messages,
              retryAccountID: plan.folder.accountID
            ),
            with: pipeline,
            dryRun: dryRun,
            automatic: true
          )
        } else {
          try await trainFolderPage(page, plan: plan, pipeline: pipeline)
          try await TrainingFolders.observe(
            page.messages.map(\.identity),
            planID: plan.id,
            sweepComplete: offset + page.visitedCount >= page.total || page.visitedCount == 0,
            canReleaseClaims: page.unavailableCount == 0 && (health?.unavailableInSweep ?? 0) == 0,
            store: store
          )
        }
        try Task.checkCancellation()
        try await MailHealthRepository.update(
          store,
          accountID: cursorKey,
          name: plan.folder.displayName
        ) {
          $0.complete(
            count: page.visitedCount,
            total: page.total,
            unavailable: page.unavailableCount
          )
        }
      } catch is CancellationError { throw CancellationError() } catch {
        let failure = Self.describe(error)
        try await MailHealthRepository.update(
          store,
          accountID: cursorKey,
          name: plan.folder.displayName
        ) { $0.failure = failure }
      }
      await refresh()
    }
  }
  private func trainFolderPage(_ page: MailPage, plan: MailFolderPlan, pipeline: Pipeline)
    async throws
  {
    guard let store, plan.trainingBaselineValidated else { throw IntegrationError.unavailable }
    for envelope in page.messages {
      try Task.checkCancellation()
      let current = try await StateRepository.load(store, StateSlices([.training]))
      let key = TrainingFolders.key(planID: plan.id, identity: envelope.identity)
      guard current.trainingClaims[key] == nil else { continue }
      _ = try await pipeline.correct(
        envelope: envelope,
        label: plan.purpose == .trainGood ? .inbox : .junk,
        adapter: adapter,
        trainingPlanID: plan.id
      )
    }
  }
}

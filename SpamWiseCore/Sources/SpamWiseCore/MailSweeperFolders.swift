import Foundation

extension MailSweeper {
  /// Sweeps one page of each enabled folder plan in scope; returns the number that failed.
  func sweepFolders(dryRun: Bool, limit: Int, onEvent: @escaping EventHandler) async throws
    -> Int
  {
    let settings = try await currentSettings()
    let selected = settings.mailOptions.accountIDs
    let plans = settings.mailOptions.folderPlans.filter(\.enabled).prefix(FolderPlans.limit)
    var failures = 0
    for plan in plans where selected?.contains(plan.folder.accountID) ?? true {
      try Task.checkCancellation()
      guard try await !currentSettings().paused else { return failures }
      do {
        try await sweepFolder(plan, dryRun: dryRun, limit: limit, onEvent: onEvent)
        await onEvent(.folderSwept(plan))
      } catch {
        try Self.rethrowCancellation(error)
        failures += 1
        let description = describe(error)
        try await MailHealthRepository.update(
          store,
          accountID: Self.healthKey(for: plan),
          name: plan.folder.displayName
        ) { $0.recordFailure(description) }
        await onEvent(.folderFailed(plan, error))
      }
    }
    return failures
  }

  /// Handles the plan's next page and advances its cursor past every visited position.
  private func sweepFolder(
    _ plan: MailFolderPlan,
    dryRun: Bool,
    limit: Int,
    onEvent: @escaping EventHandler
  ) async throws {
    let key = Self.healthKey(for: plan)
    let health = try await MailHealthRepository.load(store, key: key)
    let offset = health?.nextOffset ?? 0
    let page = try await source.folderPage(
      plan.folder,
      offset: offset,
      limit: limit,
      since: plan.purpose == .filter ? plan.startDate : nil
    )
    coverage = SweepCoverage()
    if plan.purpose == .filter {
      let processed = try await process(
        page,
        accountID: plan.folder.accountID,
        dryRun: dryRun,
        ingestsHistory: false,
        onEvent: onEvent
      )
      guard processed.completed else { return }
    } else {
      guard try await train(page, plan: plan) else { return }
      try await TrainingFolders.observe(
        page.messages.map(\.identity),
        planID: plan.id,
        sweepComplete: offset + page.visitedCount >= page.total || page.visitedCount == 0,
        canReleaseClaims: page.unavailableCount == 0 && (health?.unavailableInSweep ?? 0) == 0,
        store: store
      )
    }
    try Task.checkCancellation()
    let coverage = coverage
    try await MailHealthRepository.update(store, accountID: key, name: plan.folder.displayName) {
      $0.coverage = coverage
      $0.complete(count: page.visitedCount, total: page.total, unavailable: page.unavailableCount)
    }
  }

  /**
   Applies each unclaimed placement on a training page as a correction.

   A placement that cannot be corrected is recorded with a claim, so it is not retried every
   sweep, and the rest of the page continues.

   - Returns: False when filtering paused or the plan stopped applying part way through.
   */
  private func train(_ page: MailPage, plan: MailFolderPlan) async throws -> Bool {
    guard plan.trainingBaselineValidated else { throw TrainingFolderError.planInactive }
    let label: MailLabel = plan.purpose == .trainGood ? .inbox : .junk
    for envelope in page.messages {
      try Task.checkCancellation()
      let claims = try await StateRepository.load(store, StateSlices([.training])).trainingClaims
      guard claims[TrainingFolders.key(planID: plan.id, identity: envelope.identity)] == nil
      else { coverage.classified += 1; continue }
      do {
        _ = try await pipeline.correct(
          envelope: envelope,
          label: label,
          adapter: source,
          trainingPlanID: plan.id
        )
        coverage.classified += 1
      } catch {
        try Self.rethrowCancellation(error)
        guard try await isActive(plan) else { return false }
        try await recordTrainingFailure(envelope, plan: plan, error: error)
        coverage.unclassified += 1
      }
    }
    coverage.unclassified += page.unavailableCount
    return true
  }

  /// Whether filtering is running and the plan is still enabled for training.
  private func isActive(_ plan: MailFolderPlan) async throws -> Bool {
    let settings = try await currentSettings()
    return !settings.paused
      && settings.mailOptions.folderPlans.contains { $0.id == plan.id && $0.enabled }
  }

  private func recordTrainingFailure(
    _ envelope: MailEnvelope,
    plan: MailFolderPlan,
    error: any Error
  ) async throws {
    try await TrainingFolders.recordFailure(
      envelope,
      planID: plan.id,
      reason: error is any MessageParsingError ? .messageUnreadable : .processingFailed,
      detail: describe(error),
      store: store
    )
  }
}

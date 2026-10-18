import Foundation

/// Deliberate placement processing restricted to explicitly enabled, initially empty training folders.
public enum TrainingFolders {
  /// Required dedicated name, kept distinct from ordinary Junk or Inbox membership.
  public static func name(for purpose: MailFolderPurpose) -> String? {
    switch purpose {
      case .filter: nil
      case .trainGood: "SpamWise Train Good"
      case .trainJunk: "SpamWise Train Junk"
    }
  }
  /// Stable correction claim for one observed placement.
  public static func key(planID: String, identity: MessageIdentity) -> String {
    planID + ":" + identity.key
  }
  static func claimKey(
    planID: String?,
    label: MailLabel,
    identity: MessageIdentity,
    state: AppState
  ) throws -> String? {
    guard let planID else { return nil }
    guard !state.settings.paused,
      let plan = state.settings.mailOptions.folderPlans.first(where: { $0.id == planID }),
      plan.enabled, plan.trainingBaselineValidated,
      plan.folder.accountID == identity.accountID,
      plan.folder.path.last == identity.mailbox,
      plan.folder.path.last == name(for: plan.purpose),
      (plan.purpose == .trainGood && label == .inbox)
        || (plan.purpose == .trainJunk && label == .junk)
    else { throw IntegrationError.unavailable }
    let key = key(planID: planID, identity: identity)
    guard state.trainingClaims[key] == nil else { throw IntegrationError.staleMessage }
    return key
  }
  /// Resets observations at traversal boundaries; only readable traversals can release completed claims.
  public static func observe(
    _ identities: [MessageIdentity],
    planID: String,
    sweepComplete: Bool,
    canReleaseClaims: Bool = true,
    store: Store
  ) async throws {
    try await StateRepository.transaction(store) { transaction in
      try transaction.load(StateSlices([.training]))
      let claimed = Set(
        transaction.state.trainingClaims.filter { $0.key.hasPrefix(planID + ":") }.values
      )
      if sweepComplete { try transaction.load(StateSlices(records: .only(claimed))) }
      try transaction.state.observeTraining(
        identities.map { key(planID: planID, identity: $0) },
        planID: planID,
        sweepComplete: sweepComplete,
        canReleaseClaims: canReleaseClaims
      )
      try transaction.commit()
    }
  }
}

extension AppState {
  fileprivate mutating func observeTraining(
    _ keys: [String],
    planID: String,
    sweepComplete: Bool,
    canReleaseClaims: Bool
  ) throws {
    var observed = trainingObservations[planID] ?? []
    observed.formUnion(keys)
    guard observed.count <= RetentionLimits.trainingObservations else {
      throw IntegrationError.unavailable
    }
    trainingObservations[planID] = observed
    guard sweepComplete else { return }
    let outcomes = Dictionary(
      records.map { ($0.id, $0.outcome) },
      uniquingKeysWith: { _, last in last }
    )
    trainingClaims = trainingClaims.filter { key, recordID in
      !canReleaseClaims || !key.hasPrefix(planID + ":") || observed.contains(key)
        || ![ActionOutcome.applied, .noAction, .dryRun].contains(outcomes[recordID] ?? .requested)
    }
    trainingObservations[planID] = []
  }
}

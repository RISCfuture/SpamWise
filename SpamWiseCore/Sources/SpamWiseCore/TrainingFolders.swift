public import Foundation

/// Failures that prevent a training-folder placement from being applied.
public protocol TrainingFolderFailure: Error {}

/// Why a placement in a training folder was not applied as a correction.
public enum TrainingFolderError: TrainingFolderFailure, Sendable, Equatable, LocalizedError {
  /// Filtering is paused, or the plan is missing, turned off or has no validated empty baseline.
  case planInactive
  /// The message is not in the plan's dedicated folder, or its label differs from the plan's.
  case placementMismatch
  /// The placement was already applied or recorded.
  case alreadyClaimed
  /// The folder holds more messages than SpamWise tracks for one training plan.
  case observationLimitReached
  /// A general description of the skipped placement.
  public var errorDescription: String? {
    String(localized: "The training folder placement couldn’t be applied.", bundle: .module)
  }
  /// The condition that skipped this placement.
  public var failureReason: String? {
    switch self {
      case .planInactive:
        String(
          localized: "Filtering is paused, or the training folder plan is off or unvalidated.",
          bundle: .module
        )
      case .placementMismatch:
        String(
          localized: "The message isn’t in the training folder its plan names.",
          bundle: .module
        )
      case .alreadyClaimed:
        String(localized: "This placement was already applied.", bundle: .module)
      case .observationLimitReached:
        String(
          localized: "The training folder holds more messages than SpamWise tracks.",
          bundle: .module
        )
    }
  }
}

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
  ) throws(TrainingFolderError) -> String? {
    guard let planID else { return nil }
    guard !state.settings.paused,
      let plan = state.settings.mailOptions.folderPlans.first(where: { $0.id == planID }),
      plan.enabled, plan.trainingBaselineValidated
    else { throw .planInactive }
    guard plan.folder.accountID == identity.accountID,
      plan.folder.path.last == identity.mailbox,
      plan.folder.path.last == name(for: plan.purpose),
      (plan.purpose == .trainGood && label == .inbox)
        || (plan.purpose == .trainJunk && label == .junk)
    else { throw .placementMismatch }
    let key = key(planID: planID, identity: identity)
    guard state.trainingClaims[key] == nil else { throw .alreadyClaimed }
    return key
  }
  /**
   Records a placement that could not be applied as a correction, claiming it so later sweeps
   skip it.

   The claim is released like any other once the message leaves the folder, so placing it there
   again retries it. A placement that already holds a claim keeps it.
   */
  public static func recordFailure(
    _ envelope: MailEnvelope,
    planID: String,
    reason: DecisionReason,
    detail: String,
    store: Store
  ) async throws {
    let key = key(planID: planID, identity: envelope.identity)
    try await StateRepository.update(store, loading: StateSlices([.training])) { state in
      guard state.trainingClaims[key] == nil else { return }
      var record = DecisionRecord(
        identity: envelope.identity,
        decision: .init(label: nil, action: .none, reason: reason),
        outcome: .unclassified,
        path: .selection,
        revision: state.revision
      )
      record.actionError = detail
      state.record(record)
      state.trainingClaims[key] = record.id
    }
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
      throw TrainingFolderError.observationLimitReached
    }
    trainingObservations[planID] = observed
    guard sweepComplete else { return }
    let outcomes = Dictionary(
      records.map { ($0.id, $0.outcome) },
      uniquingKeysWith: { _, last in last }
    )
    trainingClaims = trainingClaims.filter { key, recordID in
      !canReleaseClaims || !key.hasPrefix(planID + ":") || observed.contains(key)
        || ![ActionOutcome.applied, .noAction, .dryRun, .unclassified].contains(
          outcomes[recordID] ?? .requested
        )
    }
    trainingObservations[planID] = []
  }
}

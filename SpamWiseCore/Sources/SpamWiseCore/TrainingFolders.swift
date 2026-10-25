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
    }
  }
}

/// Deliberate placement processing restricted to explicitly enabled, initially empty training folders.
public enum TrainingFolders {
  /// Health note for a training folder whose traversal found more messages than SpamWise tracks.
  public static var observationLimitNote: String {
    String(
      localized: "The training folder holds more messages than SpamWise tracks.",
      bundle: .module
    )
  }
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
  /**
   Records the placements on one page of a training folder's traversal, and at its end releases
   the claims of placements the traversal no longer found.

   A claim is released once nothing more can come of its correction, so placing the message in
   the folder again applies it again; that includes a correction whose move failed before any
   command was sent. Claims stay while their correction awaits dispatch or a move recheck, or
   when its move may have been sent without being confirmed, and every claim stays after a
   traversal that met unreadable messages or more messages than SpamWise tracks.

   - Parameters:
     - identities: The messages on the page.
     - planID: The training plan whose folder was read.
     - sweepComplete: Whether the page ends the traversal.
     - canReleaseClaims: Whether the traversal read every message in the folder.
     - settling: Records whose moves are still to be rechecked after their settling window.
     - store: The store holding the claims.
   - Returns: Whether the traversal has found more messages than SpamWise tracks.
   */
  @discardableResult
  public static func observe(
    _ identities: [MessageIdentity],
    planID: String,
    sweepComplete: Bool,
    canReleaseClaims: Bool = true,
    settling: Set<UUID> = [],
    store: Store
  ) async throws -> Bool {
    try await StateRepository.transaction(store) { transaction in
      try transaction.load(StateSlices([.training]))
      let claimed = Set(
        transaction.state.trainingClaims.filter { $0.key.hasPrefix(planID + ":") }.values
      )
      if sweepComplete { try transaction.load(StateSlices(records: .only(claimed))) }
      let overflowed = transaction.state.observeTraining(
        identities.map { key(planID: planID, identity: $0) },
        planID: planID,
        sweepComplete: sweepComplete,
        canReleaseClaims: canReleaseClaims,
        settling: settling
      )
      try transaction.commit()
      return overflowed
    }
  }
}

extension AppState {
  /// Records observed placement keys up to the retention limit, returning whether any were left out.
  fileprivate mutating func observeTraining(
    _ keys: [String],
    planID: String,
    sweepComplete: Bool,
    canReleaseClaims: Bool,
    settling: Set<UUID>
  ) -> Bool {
    var observed = trainingObservations[planID] ?? []
    var overflowed = trainingObservationOverflows.contains(planID)
    for key in keys where !observed.contains(key) {
      guard observed.count < RetentionLimits.trainingObservations else {
        overflowed = true
        break
      }
      observed.insert(key)
    }
    guard sweepComplete else {
      trainingObservations[planID] = observed
      if overflowed { trainingObservationOverflows.insert(planID) }
      return overflowed
    }
    if canReleaseClaims && !overflowed {
      releaseTrainingClaims(of: planID, keeping: observed, settling: settling)
    }
    trainingObservations[planID] = []
    trainingObservationOverflows.remove(planID)
    return overflowed
  }

  /// Releases the plan's claims that `observed` lacks, except those whose correction may still act or may have acted unconfirmed.
  private mutating func releaseTrainingClaims(
    of planID: String,
    keeping observed: Set<String>,
    settling: Set<UUID>
  ) {
    let held = settling.union(records.filter(\.holdsTrainingClaim).map(\.id))
    trainingClaims = trainingClaims.filter { key, recordID in
      !key.hasPrefix(planID + ":") || observed.contains(key) || held.contains(recordID)
    }
  }

  /// Removes the claims and observations of a training plan.
  mutating func forgetTraining(of planID: String) {
    trainingClaims = trainingClaims.filter { !$0.key.hasPrefix(planID + ":") }
    trainingObservations[planID] = nil
    trainingObservationOverflows.remove(planID)
  }
}

extension DecisionRecord {
  /// Whether this correction awaits dispatch, or may have sent a move whose result is unknown.
  fileprivate var holdsTrainingClaim: Bool {
    outcome == .pending || (decision.action != .none && mayHaveSentUnconfirmedAction)
  }

  private var mayHaveSentUnconfirmedAction: Bool {
    outcome == .requested || (outcome == .failed && !actionNeverSent)
  }
}

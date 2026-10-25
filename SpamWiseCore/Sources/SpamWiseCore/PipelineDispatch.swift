import Foundation

/// How a persisted decision's mail action is dispatched.
enum DispatchMode: Sendable {
  /// An automatic action, applied only where the message was recorded, at most once per message.
  case automatic
  /// A user correction's ordered steps, applied wherever the message now is in its account, or
  /// only where it was recorded when the account isn't searched.
  case correction(steps: [MailAction], searchesAccount: Bool = true)

  /// Whether steps may find the message outside the mailbox where it was recorded.
  var searchesAccount: Bool {
    switch self {
      case .automatic: false
      case .correction(_, let searchesAccount): searchesAccount
    }
  }

  func steps(for record: DecisionRecord) -> [MailAction] {
    switch self {
      case .automatic: record.decision.action == .none ? [] : [record.decision.action]
      case .correction(let steps, _): steps
    }
  }
}

extension Pipeline {
  private static func supports(_ steps: [MailAction], adapter: (any MailClientAdapter)?) async
    -> Bool
  {
    guard let adapter else { return true }
    for step in steps where !(await adapter.supports(step)) { return false }
    return true
  }

  static func notAttemptedDescription(_ error: any Error) -> String {
    actionFailureDescription(ActionNotAttempted(cause: error))
  }

  private static func actionFailureDescription(_ error: any Error) -> String {
    if let error = error as? any MailIntegrationFailure & LocalizedError {
      return [error.errorDescription, error.failureReason].compactMap(\.self)
        .joined(separator: " ")
    }
    return String(
      localized: "The Mail action failed or was cancelled; its result is unknown. Not retried.",
      bundle: .module
    )
  }

  /**
   Claims and performs a persisted decision's action, recording the observed outcome.

   Once any mail command may have been sent, this never throws: an outcome that cannot be saved
   is returned as observed, and the persisted claim prevents a repeat. A claim is released when
   dispatch stops before any command was sent. Cancellation interrupts neither the saved outcome
   nor the release.

   - Throws: When the decision cannot be claimed, including a correction that is no longer
     pending because it was resolved as not attempted.
   */
  func dispatch(
    _ original: DecisionRecord,
    adapter: (any MailClientAdapter)?,
    forceDryRun: Bool,
    mode: DispatchMode = .automatic
  ) async throws -> DecisionRecord {
    let steps = mode.steps(for: original)
    let claim = try await claim(
      original,
      supported: await Self.supports(steps, adapter: adapter),
      hasAdapter: adapter != nil,
      forceDryRun: forceDryRun,
      mode: mode
    )
    guard claim.record.outcome == .requested, let adapter else { return claim.record }
    if let abandoned = await abandonedBeforeAction(claim) { return abandoned }
    var completed: DecisionRecord, settlements: [MoveSettlement]
    switch await perform(steps, on: claim.record, adapter: adapter, mode: mode) {
      case .notAttempted(let record): return await release(claim, as: record)
      case let .attempted(record, pending): (completed, settlements) = (record, pending)
    }
    completed.actionSettled = completed.outcome == .applied && settlements.isEmpty
    guard (try? await saveObservedOutcome(completed)) != nil else { return completed }
    for settlement in settlements { scheduleCheck(of: settlement, recordID: completed.id) }
    return await followUp(completed, adapter: adapter, marksJunkRead: claim.marksJunkRead)
  }

  private func claim(
    _ original: DecisionRecord,
    supported: Bool,
    hasAdapter: Bool,
    forceDryRun: Bool,
    mode: DispatchMode
  ) async throws -> ActionClaim {
    let key = original.identity.key, steps = mode.steps(for: original)
    let decide: @Sendable (inout AppState) throws -> ActionClaim = { state in
      guard let index = state.records.firstIndex(where: { $0.id == original.id }) else {
        throw DecisionRecordError.notFound
      }
      var record = state.records[index]
      if case .correction = mode, record.outcome != .pending { throw UnstartedCorrection() }
      let replaced = state.claimedActions[key]
      if case .automatic = mode, replaced == record.id {
        record.outcome = .duplicate
        return ActionClaim(record: record, replacedClaim: replaced, marksJunkRead: false)
      }
      if state.supersedes(record, claimed: false) {
        record.outcome = .superseded
      } else if state.settings.paused {
        record.outcome = .paused
      } else if steps.isEmpty {
        record.outcome = .noAction
      } else if !supported {
        record.outcome = .noAction
        record.actionError = String(
          localized: "This mail connection can’t perform the action, so it was not attempted.",
          bundle: .module
        )
      } else if forceDryRun || state.settings.dryRun {
        record.outcome = .dryRun
      } else if case .automatic = mode, replaced != nil {
        record.outcome = .duplicate
      } else if !hasAdapter
        || !state.settings.validatedAccounts.contains(record.identity.accountID ?? "")
      {
        record.outcome = .integrationUnavailable
      } else {
        record.outcome = .requested
        record.actionNeverSent = false
        state.claimedActions[key] = record.id
      }
      state.records[index] = record
      if !forceDryRun { state.retries.removeAll { $0.identity.key == key } }
      return ActionClaim(
        record: record,
        replacedClaim: replaced,
        marksJunkRead: state.settings.mailOptions.markJunkRead
      )
    }
    return try await StateRepository.transaction(store) { transaction in
      let related =
        original.path == .correction ? try transaction.recordIDs(identityKey: key) : []
      try transaction.load(
        StateSlices(
          records: .only(related.union([original.id])),
          retries: .only([key]),
          claims: .only([key])
        )
      )
      let claim = try decide(&transaction.state)
      try transaction.commit()
      return claim
    }
  }

  /// Releases the claim when a newer decision replaced it, filtering stopped or the task ended before any command.
  private func abandonedBeforeAction(_ claim: ActionClaim) async -> DecisionRecord? {
    var record = claim.record
    if Task.isCancelled {
      record.outcome = .failed
      record.actionError = Self.notAttemptedDescription(CancellationError())
    } else {
      do {
        let current = try await StateRepository.load(
          store,
          StateSlices(claims: .only([record.identity.key]))
        )
        if current.supersedes(record, claimed: true) {
          record.outcome = .superseded
        } else if current.settings.paused {
          record.outcome = .paused
        } else if current.settings.dryRun {
          record.outcome = .dryRun
        } else {
          return nil
        }
      } catch {
        record.outcome = .failed
        record.actionError = Self.notAttemptedDescription(error)
      }
    }
    return await release(claim, as: record)
  }

  /**
   Saves the outcome of an action that may have been sent, retrying while storage is busy, even
   when the dispatching task is cancelled.
   */
  func saveObservedOutcome(_ record: DecisionRecord) async throws {
    try await Task { try await saveAfterAction(record) }.value
  }

  /**
   Saves `stopped`, marked as never sent, and restores the claim this dispatch replaced, in one
   transaction that cancellation does not interrupt.

   Nothing was sent, so at-most-once still holds. When the save fails the claim stays, which
   only prevents a later attempt.
   */
  private func release(_ claim: ActionClaim, as stopped: DecisionRecord) async -> DecisionRecord {
    var unsent = stopped
    unsent.actionNeverSent = true
    let record = unsent, key = record.identity.key, replaced = claim.replacedClaim, store = store
    let slices = StateSlices(records: .only([record.id]), claims: .only([key]))
    try? await Task {
      try await StateRepository.update(store, loading: slices) { state in
        state.record(record)
        if state.claimedActions[key] == record.id { state.claimedActions[key] = replaced }
      }
    }.value
    return record
  }

  /// Performs each step on the identity the previous step observed, stopping at the first unconfirmed one.
  private func perform(
    _ steps: [MailAction],
    on claimed: DecisionRecord,
    adapter: any MailClientAdapter,
    mode: DispatchMode
  ) async -> Performance {
    var record = claimed, settlements: [MoveSettlement] = []
    record.outcome = .applied
    for (index, step) in steps.enumerated() {
      guard !Task.isCancelled else {
        record.outcome = .failed
        record.actionError = Self.notAttemptedDescription(CancellationError())
        return index == 0 ? .notAttempted(record) : .attempted(record, settlements: settlements)
      }
      do {
        let receipt =
          if mode.searchesAccount {
            try await adapter.performCorrection(step, for: record.identity)
          } else {
            try await adapter.perform(step, for: record.identity)
          }
        guard receipt.confirmed else {
          record.outcome = .requested
          record.actionError = String(
            localized: "Mail didn’t confirm the change. Its result is unknown; not retried.",
            bundle: .module
          )
          break
        }
        if let identity = receipt.updatedIdentity { record.identity = identity }
        if let settlement = receipt.settlement { settlements.append(settlement) }
      } catch {
        record.outcome = .failed
        record.actionError = Self.actionFailureDescription(error)
        return index == 0 && error is ActionNotAttempted
          ? .notAttempted(record) : .attempted(record, settlements: settlements)
      }
    }
    return .attempted(record, settlements: settlements)
  }

  /// A claim written for one dispatch, with the claim it replaced.
  private struct ActionClaim: Sendable {
    var record: DecisionRecord
    var replacedClaim: UUID?
    /// Whether the mark-as-read setting was on when the claim was written.
    var marksJunkRead: Bool
  }

  private enum Performance: Sendable {
    /// The adapter refused before any mail command was sent.
    case notAttempted(DecisionRecord)
    /// At least one mail command may have been sent; moves confirmed before they settled carry
    /// their later checks.
    case attempted(DecisionRecord, settlements: [MoveSettlement])
  }
}

extension AppState {
  /**
   Whether a newer decision replaces `record`.

   An automatic decision is replaced once settings, rules or corrections change the revision. A
   user's correction stands until it is undone or a newer correction of its message is saved,
   and once it holds its message's claim, until another decision takes that claim, so changes
   to other messages and to settings made meanwhile leave it in force.

   - Parameters:
     - record: The decision to check; this state must hold its message's claim and, for a
       correction that has not claimed it yet, every retained record of its message.
     - claimed: Whether `record` has already claimed its message.
   */
  func supersedes(_ record: DecisionRecord, claimed: Bool) -> Bool {
    guard record.path == .correction else { return revision != record.revision }
    let key = record.identity.key
    if claimed { return claimedActions[key] != record.id }
    return records.contains { other in
      guard other.identity.key == key else { return false }
      return other.id == record.id
        ? other.correctionUndone
        : other.path == .correction && other.revision > record.revision && !other.correctionUndone
    }
  }
}

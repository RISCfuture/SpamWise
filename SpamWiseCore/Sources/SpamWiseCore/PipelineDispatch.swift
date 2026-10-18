import Foundation

/// How a persisted decision's mail action is dispatched.
enum DispatchMode: Sendable {
  /// An automatic action, applied only where the message was recorded, at most once per message.
  case automatic
  /// A user correction's ordered steps, applied wherever the message now is in its account.
  case correction(steps: [MailAction])

  func steps(for record: DecisionRecord) -> [MailAction] {
    switch self {
      case .automatic: record.decision.action == .none ? [] : [record.decision.action]
      case .correction(let steps): steps
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

  private static func notAttemptedDescription(_ error: any Error) -> String {
    actionFailureDescription(ActionNotAttempted(cause: error))
  }

  private static func actionFailureDescription(_ error: any Error) -> String {
    if let error = error as? any MailIntegrationFailure & LocalizedError {
      return [error.errorDescription, error.failureReason].compactMap { $0 }
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
   dispatch stops before any command was sent.

   - Throws: When the decision cannot be claimed.
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
    let completed: DecisionRecord
    switch await perform(steps, on: claim.record, adapter: adapter, mode: mode) {
      case .notAttempted(let record): return await release(claim, as: record)
      case .attempted(let record): completed = record
    }
    guard (try? await saveAfterAction(completed)) != nil else { return completed }
    do {
      return try await markJunkRead(completed, adapter: adapter)
    } catch {
      var unconfirmed = completed
      unconfirmed.readStatusOutcome = .requested
      unconfirmed.readStatusError = String(
        localized: "Mark-as-read status could not be saved. The confirmed Junk move is retained.",
        bundle: .module
      )
      return unconfirmed
    }
  }

  private func claim(
    _ original: DecisionRecord,
    supported: Bool,
    hasAdapter: Bool,
    forceDryRun: Bool,
    mode: DispatchMode
  ) async throws -> ActionClaim {
    let key = original.identity.key, steps = mode.steps(for: original)
    let slices = StateSlices(
      records: .only([original.id]),
      retries: .only([key]),
      claims: .only([key])
    )
    return try await StateRepository.update(store, loading: slices) { state -> ActionClaim in
      guard let index = state.records.firstIndex(where: { $0.id == original.id }) else {
        throw DecisionRecordError.notFound
      }
      var record = state.records[index]
      let replaced = state.claimedActions[key]
      if state.revision != record.revision {
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
        state.claimedActions[key] = record.id
      }
      state.records[index] = record
      if !forceDryRun { state.retries.removeAll { $0.identity.key == key } }
      return ActionClaim(record: record, replacedClaim: replaced)
    }
  }

  /// Releases the claim when policy changed, filtering stopped or the task ended before any command.
  private func abandonedBeforeAction(_ claim: ActionClaim) async -> DecisionRecord? {
    var record = claim.record
    if Task.isCancelled {
      record.outcome = .failed
      record.actionError = Self.notAttemptedDescription(CancellationError())
    } else {
      do {
        let current = try await StateRepository.load(store, StateSlices())
        if current.revision != record.revision {
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
   Saves `record` and restores the claim this dispatch replaced, in one transaction.

   Nothing was sent, so at-most-once still holds. When the save fails the claim stays, which
   only prevents a later attempt.
   */
  private func release(_ claim: ActionClaim, as record: DecisionRecord) async -> DecisionRecord {
    let key = record.identity.key
    let slices = StateSlices(records: .only([record.id]), claims: .only([key]))
    try? await StateRepository.update(store, loading: slices) { state in
      state.record(record)
      if state.claimedActions[key] == record.id { state.claimedActions[key] = claim.replacedClaim }
    }
    return record
  }

  /// Performs each step on the identity the previous step observed, stopping at the first unconfirmed one.
  private func perform(
    _ steps: [MailAction],
    on claimed: DecisionRecord,
    adapter: any MailClientAdapter,
    mode: DispatchMode
  ) async -> Performance {
    var record = claimed
    record.outcome = .applied
    for (index, step) in steps.enumerated() {
      guard !Task.isCancelled else {
        record.outcome = .failed
        record.actionError = Self.notAttemptedDescription(CancellationError())
        return index == 0 ? .notAttempted(record) : .attempted(record)
      }
      do {
        let receipt =
          if case .correction = mode {
            try await adapter.performCorrection(step, for: record.identity)
          } else {
            try await adapter.perform(step, for: record.identity)
          }
        guard receipt.confirmed else {
          record.outcome = .requested
          break
        }
        if let identity = receipt.updatedIdentity { record.identity = identity }
      } catch {
        record.outcome = .failed
        record.actionError = Self.actionFailureDescription(error)
        return index == 0 && error is ActionNotAttempted
          ? .notAttempted(record) : .attempted(record)
      }
    }
    return .attempted(record)
  }

  /// A claim written for one dispatch, with the claim it replaced.
  private struct ActionClaim: Sendable {
    var record: DecisionRecord
    var replacedClaim: UUID?
  }

  private enum Performance: Sendable {
    /// The adapter refused before any mail command was sent.
    case notAttempted(DecisionRecord)
    /// At least one mail command may have been sent.
    case attempted(DecisionRecord)
  }
}

import Foundation

/// A mail step that follows a confirmed move, claimed and recorded apart from the move.
struct FollowUpStep: Sendable {
  /// Where the step's outcome is recorded; nil until the step is claimed.
  let outcome: any WritableKeyPath<DecisionRecord, ActionOutcome?> & Sendable
  /// Where the step's failure is recorded.
  let failure: any WritableKeyPath<DecisionRecord, String?> & Sendable
  /// Whether the settings ask for the step.
  let isEnabled: @Sendable (Settings) -> Bool
  /// Reported when the step's claim or result can't be saved.
  let notSaved: @Sendable () -> String
  /// Reported when the step failed or may have been sent without an answer.
  let failed: @Sendable () -> String
  /// Sends the step for the claimed record and returns the outcome the mail client showed.
  let send: @Sendable (DecisionRecord) async throws -> ActionOutcome
}

extension FollowUpStep {
  /// Marks a message read after its confirmed move to Junk, when the setting asks.
  static func markRead(_ adapter: any MailClientAdapter) -> Self {
    Self(
      outcome: \.readStatusOutcome,
      failure: \.readStatusError,
      isEnabled: { $0.mailOptions.markJunkRead },
      notSaved: {
        String(
          localized: "Mark-as-read status could not be saved. The confirmed Junk move is retained.",
          bundle: .module
        )
      },
      failed: {
        String(
          localized:
            "Couldn’t confirm mark-as-read. The Junk move remains recorded; this step will not retry.",
          bundle: .module
        )
      },
      send: { record in
        let receipt =
          record.path == .correction
          ? try await adapter.markCorrectionReadInJunk(record.identity)
          : try await adapter.markReadInJunk(record.identity)
        return receipt.confirmed ? .applied : .requested
      }
    )
  }

  /// Clears Mail's own junk mark after a Good correction's confirmed move to Inbox.
  static func clearJunkMark(_ adapter: any MailClientAdapter) -> Self {
    Self(
      outcome: \.junkMarkOutcome,
      failure: \.junkMarkError,
      isEnabled: { _ in true },
      notSaved: {
        String(
          localized:
            "Clearing Mail’s junk mark could not be saved. The confirmed move to Inbox is retained.",
          bundle: .module
        )
      },
      failed: {
        String(
          localized:
            "Couldn’t confirm that Mail’s junk mark was cleared. The move to Inbox remains recorded; this step will not retry.",
          bundle: .module
        )
      },
      send: { record in
        switch try await adapter.clearJunkMarkInInbox(record.identity) {
          case .cleared: .applied
          case .absent: .noAction
          case .unconfirmed: .requested
        }
      }
    )
  }
}

extension Pipeline {
  /**
   Runs the step that follows a confirmed move: marking a Junk move read when the setting asks,
   or clearing Mail's junk mark after a Good correction's move to Inbox.

   - Parameter marksJunkRead: Whether the mark-as-read setting was on when the move was claimed.
   */
  func followUp(_ completed: DecisionRecord, adapter: any MailClientAdapter, marksJunkRead: Bool)
    async -> DecisionRecord
  {
    guard completed.outcome == .applied, !Task.isCancelled else { return completed }
    switch completed.decision.action {
      case .moveToJunk:
        return await perform(.markRead(adapter), after: completed, requested: marksJunkRead)
      case .moveToInbox where completed.path == .correction:
        return await perform(.clearJunkMark(adapter), after: completed, requested: true)
      default: return completed
    }
  }

  /**
   Claims `step` for `original` at most once, then sends it unless a newer decision, Pause or
   dry run intervened, recording its outcome apart from the move.

   A step whose claim cannot be saved is never sent and is reported without an outcome, with an
   error only when `requested` says the user asked for the step; a result that cannot be saved
   is reported as requested.
   */
  private func perform(_ step: FollowUpStep, after original: DecisionRecord, requested: Bool)
    async -> DecisionRecord
  {
    let claim: StateSelection<String> = .only([original.identity.key])
    let claimed: DecisionRecord?
    do {
      claimed = try await StateRepository.update(
        store,
        loading: StateSlices(records: .only([original.id]), claims: claim)
      ) { state -> DecisionRecord? in
        guard step.isEnabled(state.settings), !state.settings.paused, !state.settings.dryRun,
          !state.supersedes(original, claimed: true),
          let index = state.records.firstIndex(where: { $0.id == original.id }),
          state.records[index][keyPath: step.outcome] == nil
        else { return nil }
        state.records[index][keyPath: step.outcome] = .requested
        return state.records[index]
      }
    } catch {
      guard requested else { return original }
      var unsaved = original
      unsaved[keyPath: step.failure] = step.notSaved()
      return unsaved
    }
    guard let claimed else { return original }
    let outcome: ActionOutcome, failure: String?
    do {
      try Task.checkCancellation()
      let state = try await StateRepository.load(store, StateSlices(claims: claim))
      guard !state.supersedes(claimed, claimed: true), !state.settings.paused,
        !state.settings.dryRun
      else {
        return await finish(step, of: claimed, outcome: .superseded, failure: nil)
      }
      (outcome, failure) = (try await step.send(claimed), nil)
    } catch {
      (outcome, failure) = (.failed, step.failed())
    }
    return await finish(step, of: claimed, outcome: outcome, failure: failure)
  }

  /// Saves the step's result, or returns `record` still requested when it cannot be saved.
  private func finish(
    _ step: FollowUpStep,
    of record: DecisionRecord,
    outcome: ActionOutcome,
    failure: String?
  ) async -> DecisionRecord {
    do {
      return try await StateRepository.update(
        store,
        loading: StateSlices(records: .only([record.id]))
      ) { state in
        guard let index = state.records.firstIndex(where: { $0.id == record.id }) else {
          throw DecisionRecordError.notFound
        }
        state.records[index][keyPath: step.outcome] = outcome
        state.records[index][keyPath: step.failure] = failure
        return state.records[index]
      }
    } catch {
      var unconfirmed = record
      unconfirmed[keyPath: step.failure] = step.notSaved()
      return unconfirmed
    }
  }
}

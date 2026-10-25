import Foundation

extension Pipeline {
  private static var readStatusNotSaved: String {
    String(
      localized: "Mark-as-read status could not be saved. The confirmed Junk move is retained.",
      bundle: .module
    )
  }

  /**
   Marks a confirmed Junk move read when the setting asks, recording the step separately.

   A step whose request cannot be saved is never sent and is reported without an outcome, with
   an error only when `settingOn` says the user asked for the step; a result that cannot be
   saved is reported as requested.

   - Parameter settingOn: Whether the mark-as-read setting was on when the move was claimed.
   */
  func markJunkRead(_ original: DecisionRecord, adapter: any MailClientAdapter, settingOn: Bool)
    async -> DecisionRecord
  {
    guard original.outcome == .applied, original.decision.action == .moveToJunk,
      !Task.isCancelled
    else { return original }
    let claim: StateSelection<String> = .only([original.identity.key])
    let claimed: DecisionRecord?
    do {
      claimed = try await StateRepository.update(
        store,
        loading: StateSlices(records: .only([original.id]), claims: claim)
      ) { state -> DecisionRecord? in
        guard state.settings.mailOptions.markJunkRead,
          !state.settings.paused, !state.settings.dryRun,
          !state.supersedes(original, claimed: true),
          let index = state.records.firstIndex(where: { $0.id == original.id }),
          state.records[index].readStatusOutcome == nil
        else { return nil }
        state.records[index].readStatusOutcome = .requested
        return state.records[index]
      }
    } catch {
      guard settingOn else { return original }
      var unsaved = original
      unsaved.readStatusError = Self.readStatusNotSaved
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
        return await finishReadStatus(claimed, outcome: .superseded, failure: nil)
      }
      let receipt =
        claimed.path == .correction
        ? try await adapter.markCorrectionReadInJunk(claimed.identity)
        : try await adapter.markReadInJunk(claimed.identity)
      outcome = receipt.confirmed ? .applied : .requested
      failure = nil
    } catch {
      outcome = .failed
      failure = String(
        localized:
          "Couldn’t confirm mark-as-read. The Junk move remains recorded; this step will not retry.",
        bundle: .module
      )
    }
    return await finishReadStatus(claimed, outcome: outcome, failure: failure)
  }
  /// Saves the read-status result, or returns `record` still requested when it cannot be saved.
  private func finishReadStatus(_ record: DecisionRecord, outcome: ActionOutcome, failure: String?)
    async -> DecisionRecord
  {
    do {
      return try await StateRepository.update(
        store,
        loading: StateSlices(records: .only([record.id]))
      ) { state in
        guard let index = state.records.firstIndex(where: { $0.id == record.id }) else {
          throw DecisionRecordError.notFound
        }
        state.records[index].readStatusOutcome = outcome
        state.records[index].readStatusError = failure
        return state.records[index]
      }
    } catch {
      var unconfirmed = record
      unconfirmed.readStatusError = Self.readStatusNotSaved
      return unconfirmed
    }
  }
}

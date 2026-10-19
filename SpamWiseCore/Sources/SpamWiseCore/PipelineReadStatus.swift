import Foundation

extension Pipeline {
  /**
   Whether `record`'s Junk decision still stands in `state`, which holds its message's claim.

   An automatic decision stands until settings, rules or corrections change the revision. A
   user's correction stands until another decision claims its message, so corrections of other
   messages made meanwhile leave it in force.
   */
  private static func decisionStands(_ record: DecisionRecord, in state: AppState) -> Bool {
    record.path == .correction
      ? state.claimedActions[record.identity.key] == record.id
      : state.revision == record.revision
  }

  func markJunkRead(_ original: DecisionRecord, adapter: any MailClientAdapter) async throws
    -> DecisionRecord
  {
    guard original.outcome == .applied, original.decision.action == .moveToJunk,
      !Task.isCancelled
    else { return original }
    let claim: StateSelection<String> = .only([original.identity.key])
    let claimed = try await StateRepository.update(
      store,
      loading: StateSlices(records: .only([original.id]), claims: claim)
    ) { state -> DecisionRecord? in
      guard state.settings.mailOptions.markJunkRead,
        !state.settings.paused, !state.settings.dryRun, Self.decisionStands(original, in: state),
        let index = state.records.firstIndex(where: { $0.id == original.id }),
        state.records[index].readStatusOutcome == nil
      else { return nil }
      state.records[index].readStatusOutcome = .requested
      return state.records[index]
    }
    guard let claimed else { return original }
    let outcome: ActionOutcome, failure: String?
    do {
      try Task.checkCancellation()
      let state = try await StateRepository.load(store, StateSlices(claims: claim))
      guard Self.decisionStands(claimed, in: state), !state.settings.paused,
        !state.settings.dryRun
      else {
        return try await finishReadStatus(claimed, outcome: .superseded, failure: nil)
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
    return try await finishReadStatus(claimed, outcome: outcome, failure: failure)
  }
  private func finishReadStatus(_ record: DecisionRecord, outcome: ActionOutcome, failure: String?)
    async throws -> DecisionRecord
  {
    try await StateRepository.update(store, loading: StateSlices(records: .only([record.id]))) {
      state in
      guard let index = state.records.firstIndex(where: { $0.id == record.id }) else {
        throw DecisionRecordError.notFound
      }
      state.records[index].readStatusOutcome = outcome
      state.records[index].readStatusError = failure
      return state.records[index]
    }
  }
}

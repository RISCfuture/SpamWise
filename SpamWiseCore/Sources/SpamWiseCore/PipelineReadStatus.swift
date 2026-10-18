import Foundation

extension Pipeline {
  func markJunkRead(_ original: DecisionRecord, adapter: any MailClientAdapter) async throws
    -> DecisionRecord
  {
    guard original.outcome == .applied, original.decision.action == .moveToJunk,
      !Task.isCancelled
    else { return original }
    let claimed = try await StateRepository.update(
      store,
      loading: StateSlices(records: .only([original.id]))
    ) { state -> DecisionRecord? in
      guard state.settings.mailOptions.markJunkRead,
        !state.settings.paused, !state.settings.dryRun, state.revision == original.revision,
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
      let state = try await StateRepository.load(store, StateSlices())
      guard state.revision == claimed.revision, !state.settings.paused, !state.settings.dryRun
      else {
        return try await finishReadStatus(claimed, outcome: .superseded, failure: nil)
      }
      let receipt = try await adapter.markReadInJunk(claimed.identity)
      outcome = receipt.confirmed ? .applied : .requested
      failure = nil
    } catch {
      outcome = .failed
      failure = String(
        localized:
          "Couldn’t confirm mark-as-read. The Junk move remains recorded; this step will not retry."
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
        throw IntegrationError.unavailable
      }
      state.records[index].readStatusOutcome = outcome
      state.records[index].readStatusError = failure
      return state.records[index]
    }
  }
}

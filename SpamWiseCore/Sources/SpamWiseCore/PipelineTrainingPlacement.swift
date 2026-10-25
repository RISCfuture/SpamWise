import Foundation

extension Pipeline {
  /**
   Moves a training-folder placement whose correction was saved during dry run, once filtering
   acts on mail.

   The saved correction's rule, example and learning stay as they are. A new record of the same
   correction takes over the placement's claim and dispatches only the move its label implies;
   a placement made by hand carries no SpamWise annotation to clear.

   - Parameters:
     - recordID: The dry-run correction that holds the placement's claim.
     - key: The placement's training claim.
     - adapter: The integration that performs the move.
   - Returns: The dispatched record, or nil when the claim no longer belongs to a dry-run
     correction the user still stands by, or filtering is paused, in dry run or not validated for
     the message's account.
   */
  func dispatchTrainingPlacement(
    claimedBy recordID: UUID,
    key: String,
    adapter: any MailClientAdapter
  ) async throws -> DecisionRecord? {
    let claimed = try await StateRepository.update(
      store,
      loading: StateSlices([.training], records: .only([recordID]))
    ) { state -> (record: DecisionRecord, step: MailAction)? in
      guard state.trainingClaims[key] == recordID,
        let saved = state.records.first(where: { $0.id == recordID }),
        saved.path == .correction, saved.outcome == .dryRun,
        let label = saved.standingCorrection, state.acts(onAccount: saved.identity.accountID)
      else { return nil }
      var placement = saved
      placement.id = UUID(); placement.date = .now
      placement.revision = state.revision
      placement.outcome = .pending; placement.actionError = nil
      state.record(placement)
      state.trainingClaims[key] = placement.id
      return (placement, Self.correctionAction(label, review: state.settings.review))
    }
    guard let claimed else { return nil }
    do {
      return try await dispatch(
        claimed.record,
        adapter: adapter,
        forceDryRun: false,
        mode: .correction(steps: [claimed.step])
      )
    } catch {
      return await recordUnstarted(claimed.record, cause: error)
    }
  }
}

extension DecisionRecord {
  /// The correction's label, or nil once it is undone or corrected again.
  fileprivate var standingCorrection: MailLabel? {
    guard !correctionUndone, correctedLabel == decision.label else { return nil }
    return decision.label
  }
}

extension AppState {
  /// Whether filtering is running live and may act on mail in `accountID`.
  fileprivate func acts(onAccount accountID: String?) -> Bool {
    !settings.paused && !settings.dryRun
      && settings.validatedAccounts.contains(accountID ?? "")
  }
}

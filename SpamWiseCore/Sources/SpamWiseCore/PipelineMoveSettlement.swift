import Foundation

extension Pipeline {
  /// Marks an applied move unconfirmed unless a later decision or correction for the message explains where it went.
  private static func markUnsettled(_ recordID: UUID, in store: Store) async throws {
    try await StateRepository.transaction(store) { transaction in
      try transaction.load(StateSlices(records: .only([recordID])))
      guard let moved = transaction.state.records.first(where: { $0.id == recordID }),
        moved.outcome == .applied
      else { return }
      let key = moved.identity.key
      try transaction.load(
        StateSlices(
          records: .only(try transaction.recordIDs(identityKey: key)),
          claims: .only([key])
        )
      )
      guard !isSuperseded(moved, in: transaction.state) else { return }
      var unsettled = moved
      unsettled.outcome = .requested
      unsettled.actionError = String(
        localized:
          "Mail showed the move, but the message later left its destination. Its result is unknown; not retried.",
        bundle: .module
      )
      transaction.state.record(unsettled)
      try transaction.commit()
    }
  }

  /**
   Whether a correction of an automatic decision, a later claim or a newer record for the same
   message may have moved it since. A correction's own label doesn't supersede its move.
   */
  private static func isSuperseded(_ moved: DecisionRecord, in state: AppState) -> Bool {
    (moved.path != .correction && moved.correctedLabel != nil)
      || state.claimedActions[moved.identity.key] != moved.id
      || state.records.contains { $0.id != moved.id && $0.date > moved.date }
  }

  /// Marks the move unconfirmed, retrying while storage is busy; a move that still can't be marked keeps its applied outcome.
  private static func recordUnsettled(_ recordID: UUID, in store: Store) async {
    for _ in 1...maximumPostActionSaveAttempts {
      do {
        try await markUnsettled(recordID, in: store)
        return
      } catch let error as StoreError where error.retryable {
        continue
      } catch {
        return
      }
    }
  }

  /**
   Rechecks a move once its provider's settling window ends, without holding up dispatch.

   When the moved message is no longer the destination's one copy, an applied outcome becomes
   requested: the command was sent but its result is unknown. Nothing is sent again. A record
   that a correction or later decision for the same message has superseded keeps its outcome,
   because that later action may have moved the message.
   */
  func scheduleCheck(of settlement: MoveSettlement, recordID: UUID) {
    let store = self.store, checkID = UUID()
    let check = Task {
      try? await Task.sleep(until: settlement.due)
      if !Task.isCancelled, await !settlement.verify() {
        await Self.recordUnsettled(recordID, in: store)
      }
      self.finishSettlement(checkID)
    }
    moveSettlements[checkID] = (recordID, check)
  }

  /// Records whose moves this pipeline has yet to recheck after their settling window.
  func settlingRecordIDs() -> Set<UUID> { Set(moveSettlements.values.map(\.recordID)) }

  /// Waits until every scheduled move recheck has finished.
  public func settleMoves() async {
    while let settlement = moveSettlements.values.first { await settlement.check.value }
  }

  private func finishSettlement(_ checkID: UUID) {
    moveSettlements[checkID] = nil
  }
}

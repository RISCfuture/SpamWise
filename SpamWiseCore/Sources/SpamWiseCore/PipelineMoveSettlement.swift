import Foundation

extension Pipeline {
  private static func markUnsettled(_ recordID: UUID, in store: Store) async {
    try? await StateRepository.update(store, loading: StateSlices(records: .only([recordID]))) {
      state in
      guard let index = state.records.firstIndex(where: { $0.id == recordID }),
        state.records[index].outcome == .applied
      else { return }
      state.records[index].outcome = .requested
      state.records[index].actionError = String(
        localized:
          "Mail showed the move, but the message later left its destination. Its result is unknown; not retried.",
        bundle: .module
      )
    }
  }

  /**
   Rechecks a move once its provider's settling window ends, without holding up dispatch.

   When the moved message is no longer the destination's one copy, an applied outcome becomes
   requested: the command was sent but its result is unknown. Nothing is sent again.
   */
  func scheduleCheck(of settlement: MoveSettlement, recordID: UUID) {
    let store = self.store, checkID = UUID()
    moveSettlements[checkID] = Task {
      try? await Task.sleep(until: settlement.due)
      if !Task.isCancelled, await !settlement.verify() {
        await Self.markUnsettled(recordID, in: store)
      }
      self.finishSettlement(checkID)
    }
  }

  /// Waits until every scheduled move recheck has finished.
  public func settleMoves() async {
    while let check = moveSettlements.values.first { await check.value }
  }

  private func finishSettlement(_ checkID: UUID) {
    moveSettlements[checkID] = nil
  }
}

import Foundation

extension Pipeline {
  private static let maximumPostActionSaveAttempts = 3
  /// Reads settings, `identity`'s action claim and the record that holds it.
  func claimState(for identity: MessageIdentity) async throws -> AppState {
    try await StateRepository.transaction(store) { transaction in
      try transaction.loadClaim(for: identity)
      return transaction.state
    }
  }
  /// Reads only what classifying `identity` needs: its claim, rules, examples and relationships.
  func classificationState(for identity: MessageIdentity) async throws -> AppState {
    try await StateRepository.transaction(store) { transaction in
      try transaction.loadClaim(for: identity)
      var parts: StateSlices.Parts = [.rules, .contentRules, .corrections, .contacts]
      if Self.collectsLearning(transaction.state.settings.advancedOptions) {
        parts.insert(.learning)
      }
      try transaction.load(
        StateSlices(parts, histories: identity.accountID.map { .only([$0]) } ?? .none)
      )
      return transaction.state
    }
  }
  func save(_ record: DecisionRecord) async throws {
    try await StateRepository.update(store, loading: StateSlices(records: .only([record.id]))) {
      state in state.record(record)
    }
  }
  /// Saves the observed outcome of a dispatched action, retrying while storage is busy.
  func saveAfterAction(_ record: DecisionRecord) async throws {
    var attempt = 1
    while true {
      do {
        try await save(record)
        return
      } catch let error as StoreError
        where error.retryable && attempt < Self.maximumPostActionSaveAttempts
      {
        attempt += 1
      }
    }
  }
  /// Saves a failure, replacing earlier spending-limit deferrals of the same message.
  func saveFailure(_ record: DecisionRecord) async throws {
    try await StateRepository.transaction(store) { transaction in
      let deferred =
        record.deferredBySpendingLimit
        ? try transaction.recordIDs(identityKey: record.identity.key) : []
      try transaction.load(StateSlices(records: .only(deferred.union([record.id]))))
      if record.deferredBySpendingLimit {
        transaction.state.records.removeAll {
          $0.deferredBySpendingLimit && $0.identity.key == record.identity.key
        }
      }
      transaction.state.record(record)
      try transaction.commit()
    }
  }
}

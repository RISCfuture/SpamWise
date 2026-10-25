public import Foundation

extension Pipeline {
  /**
   Seconds a correction may stay pending without its message's action claim before it reads as
   not attempted.

   Nothing reaches Mail between saving a correction and claiming its steps: the claim waits at
   most five seconds for the store lock, and recording that the steps never started waits at
   most three times as long. Ten minutes is far past that, and past Mail's 30-second call limit
   and move-settling window, so only a correction whose process ended, or whose storage stayed
   locked through every attempt, stays pending this long.
   */
  public static let unstartedCorrectionAgeSec: TimeInterval = 600

  /**
   Records each correction left pending without its message's action claim for longer than
   ``unstartedCorrectionAgeSec`` as failed and not attempted.

   Nothing is dispatched, and a correction resolved this way is never claimed afterward. A
   pending correction that holds its message's claim may have sent a command, so it keeps its
   outcome.

   - Parameter now: The time each correction's age is measured at.
   - Returns: The corrections resolved as not attempted.
   - Throws: A storage error when the corrections can't be read or saved; nothing is saved then.
   */
  @discardableResult
  public func resolveUnstartedCorrections(now: Date = .now) async throws -> [DecisionRecord] {
    let cutoff = now.addingTimeInterval(-Self.unstartedCorrectionAgeSec)
    let reason = Self.notAttemptedDescription(UnstartedCorrection())
    return try await StateRepository.transaction(store) { transaction in
      let ids = try transaction.pendingCorrectionIDs(savedBefore: cutoff)
      guard !ids.isEmpty else { return [] }
      try transaction.load(StateSlices(records: .only(ids)))
      try transaction.load(
        StateSlices(claims: .only(Set(transaction.state.records.map(\.identity.key))))
      )
      let resolved = transaction.state.resolveUnclaimedRecords(reason: reason)
      try transaction.commit()
      return resolved
    }
  }
}

/// A saved correction whose mail steps never started and are not retried.
struct UnstartedCorrection: LocalizedError {
  /// Why the correction's mail steps were not attempted.
  var failureReason: String? {
    String(
      localized: "The correction was saved, but its Mail steps never started. Not retried.",
      bundle: .module
    )
  }
}

extension AppState {
  /// Whether `record` holds its message's action claim.
  fileprivate func holdsClaim(_ record: DecisionRecord) -> Bool {
    claimedActions[record.identity.key] == record.id
  }

  /// Marks each loaded record that doesn't hold its message's claim as failed for `reason`.
  fileprivate mutating func resolveUnclaimedRecords(reason: String) -> [DecisionRecord] {
    var resolved: [DecisionRecord] = []
    for index in records.indices where !holdsClaim(records[index]) {
      records[index].outcome = .failed
      records[index].actionError = reason
      resolved.append(records[index])
    }
    return resolved
  }
}

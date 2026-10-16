import Foundation

extension Pipeline {
  /// Records that filtering was paused, without classifying the message or settling it.
  func paused(
    identity: MessageIdentity,
    sender: String?,
    subject: String?,
    revision: Int
  ) async throws -> DecisionRecord {
    let record = DecisionRecord(
      identity: identity,
      sender: sender,
      subject: subject,
      decision: .init(label: nil, action: .none, reason: .paused),
      outcome: .paused,
      revision: revision
    )
    try await save(record)
    return record
  }
  /**
   Flags a message without one readable sender for Review, since gates and the classifier both
   depend on the sender address.

   The flag only annotates mail in place, so a message that an attacker can make unreadable still
   reaches the user's attention without risking good mail.
   */
  func reviewUnreadableSender(
    _ envelope: MailEnvelope,
    state: AppState,
    adapter: (any MailClientAdapter)?,
    forceDryRun: Bool,
    discovered: Bool
  ) async -> DecisionRecord {
    let identity = envelope.identity
    guard inFlight.insert(identity.key).inserted else {
      var record = failure(identity: identity, reason: .duplicateCallback)
      record.outcome = .duplicate; return record
    }
    defer { inFlight.remove(identity.key) }
    if !forceDryRun, let id = state.claimedActions[identity.key] {
      let claimed = await claimedResult(id, identity: identity, state: state)
      await remember(claimed, discoveredAs: identity)
      return claimed
    }
    let settles = discovered || !forceDryRun || state.settings.dryRun
    do {
      if state.settings.paused {
        return try await paused(
          identity: identity,
          sender: nil,
          subject: nil,
          revision: state.revision
        )
      }
      let record = DecisionRecord(
        identity: identity,
        decision: .init(
          label: .review,
          action: state.settings.review.action,
          reason: .unreadableSender
        ),
        outcome: .pending,
        path: .unreadableSender,
        revision: state.revision
      )
      try await save(record)
      let dispatched = try await dispatch(record, adapter: adapter, forceDryRun: forceDryRun)
      if settles { await remember(dispatched, discoveredAs: identity) }
      return dispatched
    } catch {
      let record = failure(
        identity: identity,
        reason: DecisionReason(failure: error),
        revision: state.revision
      )
      try? await saveFailure(record)
      if settles {
        await remember(record, discoveredAs: identity, failure: Self.failureKind(error))
      }
      return record
    }
  }
}

extension DecisionReason {
  /// The reason recorded when processing fails with `error`.
  init(failure error: any Error) {
    self =
      switch error {
        case is any BudgetFailure: .spendingLimitReached
        case let error as ClassificationError: .classificationFailed(error)
        case is CancellationError: .classificationFailed(.cancelled)
        case is any MessageParsingError: .messageUnreadable
        case is any StorageFailure, is DecodingError, is EncodingError: .storageUnavailable
        default: .processingFailed
      }
  }
}

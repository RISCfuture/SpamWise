public import Foundation

extension Pipeline {
  static func failureKind(_ error: any Error) -> ProcessingFailure {
    switch error {
      case let error as ClassificationError:
        error.retryable || error == .cancelled ? .transient : .persistent
      case is any MessageParsingError: .unparseable
      default: .transient
    }
  }
  /**
   Parses a message once, returning it with attachment coverage findings.

   With attachment text extraction off, only attached text left out of the message is reported.
   */
  static func inspect(_ raw: Data, settings: AdvancedSettings) throws -> (
    DocumentInspection, [String]
  ) {
    let extracting = settings.textAttachments == true
    let inspection = try DocumentInspection(raw: raw, includeTextAttachments: extracting)
    return (
      inspection,
      inspection.coverage.compactMap { item in
        switch item.status {
          case .extracted:
            extracting ? "Attachment text extracted; payload safety not assessed" : nil
          case .omitted: "Attached text omitted from the message body; content unknown"
          case .unsupported:
            extracting ? "Unsupported attachment format; content and safety unknown" : nil
          case .unavailable: "Attachment decoding unavailable; content and safety unknown"
        }
      }
    )
  }
  /**
   Processes a discovered batch in the supplied order, stopping when filtering is paused.

   - Parameters:
     - envelopes: Messages to process; repeated identities are processed once.
     - adapter: The client that can act on these messages.
     - dryRun: Whether to suppress mail actions regardless of settings.
     - skipsSettled: Whether this is automatic discovery, which skips identities the
       processed-message index has settled, rechecks each one just before processing it so a
       concurrent process's result is not classified again, and settles every result. An
       index entry that cannot be written is retried after each message and stops the batch
       when it still fails.
     - progress: Called after each processed message with the running count.
     - onCompletion: Called once every envelope has been handled, unless the batch stopped
       because filtering is paused.
   - Returns: The records of the processed messages.
   - Throws: When a processed decision could not be persisted, or on cancellation.
   */
  @discardableResult public func processBatch(
    _ envelopes: [MailEnvelope],
    adapter: (any MailClientAdapter)?,
    dryRun: Bool,
    skipsSettled: Bool,
    progress: @Sendable (Int) async -> Void = { _ in },
    onCompletion: @Sendable () async throws -> Void = {}
  ) async throws -> [DecisionRecord] {
    var handled: Set<String> = [], revision = 0
    if skipsSettled {
      try await prepareDiscovery()
      revision = try await StateRepository.load(store, StateSlices()).revision
      handled = try await settledKeys(among: envelopes, revision: revision)
    }
    var records: [DecisionRecord] = []
    for envelope in envelopes where handled.insert(envelope.identity.key).inserted {
      try Task.checkCancellation()
      if skipsSettled, try await !settledKeys(among: [envelope], revision: revision).isEmpty {
        continue
      }
      let record = await process(
        envelope,
        adapter: adapter,
        forceDryRun: dryRun,
        discovered: skipsSettled
      )
      guard record.outcome != .paused else { return records }
      revision = max(revision, record.revision)
      if record.outcome != .duplicate {
        let saved = StateSlices(records: .only([record.id]))
        guard try await !StateRepository.load(store, saved).records.isEmpty else {
          throw DecisionRecordError.notFound
        }
      }
      if skipsSettled { try await recordUnrecordedResults() }
      records.append(record)
      await progress(records.count)
    }
    try await onCompletion()
    return records
  }
  /**
   Requests the action a dry-run preview recorded, subject to every live action gate.

   A preview made under an earlier revision is superseded rather than acted on.
   */
  public func applyPreview(recordID: UUID, adapter: any MailClientAdapter) async throws
    -> DecisionRecord
  {
    let records = try await StateRepository.load(store, StateSlices(records: .only([recordID])))
      .records
    guard let record = records.first(where: { $0.id == recordID }) else {
      throw DecisionRecordError.notFound
    }
    guard record.outcome == .dryRun, record.correctedLabel == nil else {
      throw DecisionRecordError.notPreview
    }
    let dispatched = try await dispatch(record, adapter: adapter, forceDryRun: false)
    await remember(dispatched, discoveredAs: record.identity)
    return dispatched
  }

  /**
   Classifies an unclassified message again now, subject to every live action gate.

   The new result replaces the message's processed-message entry, so a classification settles
   it for automatic discovery.

   - Throws: ``DecisionRecordError`` when the record is gone, was classified, or its message
     can no longer be read.
   */
  public func retryUnclassified(recordID: UUID, adapter: any MailClientAdapter) async throws
    -> DecisionRecord
  {
    let records = try await StateRepository.load(store, StateSlices(records: .only([recordID])))
      .records
    guard let record = records.first(where: { $0.id == recordID }) else {
      throw DecisionRecordError.notFound
    }
    guard record.outcome == .unclassified else { throw DecisionRecordError.notUnclassified }
    guard let envelope = try await adapter.lookup(record.identity) else {
      throw DecisionRecordError.messageUnavailable
    }
    return await process(envelope, adapter: adapter)
  }

  private func settledKeys(among envelopes: [MailEnvelope], revision: Int) async throws
    -> Set<String>
  {
    try await ProcessedMessageRepository.settledKeys(
      among: envelopes.map(\.identity.key),
      revision: revision,
      in: store
    )
  }

  private func prepareDiscovery() async throws {
    if !importedLegacyActivity {
      try await ProcessedMessageRepository.importLegacyActivity(in: store)
      importedLegacyActivity = true
    }
    try await recordUnrecordedResults()
  }

  private func recordUnrecordedResults() async throws {
    for (key, result) in unrecordedResults {
      try await ProcessedMessageRepository.record(
        result.record,
        key: key,
        failure: result.failure,
        in: store
      )
      if unrecordedResults[key]?.record.id == result.record.id { unrecordedResults[key] = nil }
    }
  }

  func claimedResult(_ id: UUID, identity: MessageIdentity, state: AppState) async
    -> DecisionRecord
  {
    if let previous = state.records.first(where: { $0.id == id }) { return previous }
    var record = failure(
      identity: identity,
      reason: .actionAlreadyClaimed,
      revision: state.revision
    )
    record.decision.label =
      (try? await ProcessedMessageRepository.entries(for: [identity.key], in: store))?[
        identity.key
      ]?.label
    record.outcome = .duplicate
    return record
  }

  /// Records a discovered result in the processed-message index; spending-limit deferrals stay
  /// unrecorded so every sweep retries them.
  func remember(
    _ record: DecisionRecord,
    discoveredAs identity: MessageIdentity,
    failure: ProcessingFailure? = nil
  ) async {
    guard identity.accountID != nil, !record.deferredBySpendingLimit else { return }
    do {
      try await ProcessedMessageRepository.record(
        record,
        key: identity.key,
        failure: failure,
        in: store
      )
      unrecordedResults[identity.key] = nil
    } catch {
      unrecordedResults[identity.key] = (record, failure)
    }
  }

}

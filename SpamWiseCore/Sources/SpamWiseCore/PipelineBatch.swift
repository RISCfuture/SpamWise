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
       concurrent process's result is not classified again, and settles every result. A
       message with an uncorrected dry-run decision under the current revision is dispatched
       with that decision instead of being classified again. An index entry that cannot be
       written is retried after each message and stops the batch when it still fails.
     - progress: Called after each processed message with the running count.
     - onCompletion: Called once every envelope has been handled, unless the batch stopped
       because filtering is paused.
   - Returns: The records of the processed messages.
   - Throws: A storage error when a processed decision could not be persisted, or
     cancellation.
   */
  @discardableResult
  public func processBatch(
    _ envelopes: [MailEnvelope],
    adapter: (any MailClientAdapter)?,
    dryRun: Bool,
    skipsSettled: Bool,
    progress: @Sendable (Int) async -> Void = { _ in },
    onCompletion: @Sendable () async throws -> Void = {}
  ) async throws -> [DecisionRecord] {
    var handled: Set<String> = [], pass = DiscoveryPass(revision: 0, dryRun: dryRun)
    if skipsSettled {
      try await prepareDiscovery()
      let state = try await StateRepository.load(store, StateSlices())
      pass = DiscoveryPass(revision: state.revision, dryRun: dryRun || state.settings.dryRun)
      handled = try await settledKeys(among: envelopes, pass: pass)
    }
    var records: [DecisionRecord] = []
    for envelope in envelopes where handled.insert(envelope.identity.key).inserted {
      try Task.checkCancellation()
      if skipsSettled, try await !settledKeys(among: [envelope], pass: pass).isEmpty {
        continue
      }
      let record: DecisionRecord
      if skipsSettled, let reused = try await dispatchPreview(of: envelope, adapter, dryRun) {
        record = reused
      } else {
        record = await process(
          envelope,
          adapter: adapter,
          forceDryRun: dryRun,
          discovered: skipsSettled
        )
      }
      guard record.outcome != .paused else { return records }
      pass.revision = max(pass.revision, record.revision)
      try await requirePersisted(record)
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

  /**
   Stops the batch when a decision never reached the store, as when `process` failed to save it.

   - Throws: The storage error that prevents reading the decision back, or
     ``StoreError/lockUnavailable`` when storage is readable again but was busy when `process`
     saved.
   */
  private func requirePersisted(_ record: DecisionRecord) async throws {
    guard record.outcome != .duplicate else { return }
    let saved = StateSlices(records: .only([record.id]))
    guard try await !StateRepository.load(store, saved).records.isEmpty else {
      throw StoreError.lockUnavailable
    }
  }

  private func settledKeys(among envelopes: [MailEnvelope], pass: DiscoveryPass) async throws
    -> Set<String>
  {
    try await ProcessedMessageRepository.settledKeys(
      among: envelopes.map(\.identity.key),
      revision: pass.revision,
      dryRun: pass.dryRun,
      in: store
    )
  }

  /**
   Dispatches the uncorrected dry-run decision recorded for `envelope` under the current
   revision, so mail previewed during a dry run is acted on without a new classification.

   The decision is moved to the identity discovery found, which differs only in where the
   message now is. Every action gate applies as for a new decision, including its action claim.

   - Returns: The dispatched record, or nil when there is no such decision.
   */
  private func dispatchPreview(
    of envelope: MailEnvelope,
    _ adapter: (any MailClientAdapter)?,
    _ dryRun: Bool
  ) async throws -> DecisionRecord? {
    let key = envelope.identity.key
    guard
      var preview = try await StateRepository.reusablePreviews(for: [envelope], in: store)[key],
      preview.outcome == .dryRun, inFlight.insert(key).inserted
    else { return nil }
    defer { inFlight.remove(key) }
    if preview.identity != envelope.identity {
      preview.identity = envelope.identity
      try await save(preview)
    }
    do {
      let record = try await dispatch(preview, adapter: adapter, forceDryRun: dryRun)
      await remember(record, discoveredAs: envelope.identity)
      return record
    } catch DecisionRecordError.notFound {
      return nil
    }
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

/// The policy revision and dry-run state an automatic discovery batch settles results under.
private struct DiscoveryPass {
  var revision: Int
  /// Whether the batch suppresses mail actions, by request or by setting.
  let dryRun: Bool
}

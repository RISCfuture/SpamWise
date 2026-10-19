public import Foundation

/// Persists decisions before claiming actions and fails open on errors.
public actor Pipeline {
  private static let maximumRetryAttempts = 3
  private static let initialRetryDelaySec = 30.0
  private static let retryBackoffFactor = 2.0
  private static let retryLifetimeSec = 86_400.0
  let store: Store
  let classifier: any Classifier
  let rdap: RDAPLookup?
  let threatDetector: (any ThreatDetector)?
  var inFlight: Set<String> = []
  /// Processed-message index entries whose write failed, keyed by identity, awaiting another attempt.
  var unrecordedResults: [String: (record: DecisionRecord, failure: ProcessingFailure?)] = [:]
  var importedLegacyActivity = false
  /**
   Creates a pipeline that persists to `store` and classifies with `classifier`.

   Without `rdap` it never looks up domain registration age, and without `threatDetector` its
   records carry no threat assessment.
   */
  public init(
    store: Store,
    classifier: any Classifier,
    rdap: RDAPLookup? = nil,
    threatDetector: (any ThreatDetector)? = nil
  ) {
    self.store = store; self.classifier = classifier; self.rdap = rdap
    self.threatDetector = threatDetector
  }
  private static func isRetryable(_ error: any Error) -> Bool {
    (error as? ClassificationError)?.retryable == true || (error as? StoreError)?.retryable == true
  }
  /**
   Classifies, persists, then conditionally dispatches one message, failing open on errors.

   - Parameters:
     - envelope: The message to process.
     - adapter: The client that can act on the message.
     - forceDryRun: Whether to suppress mail actions regardless of settings.
     - timeout: Seconds allowed for classification.
     - discovered: Whether automatic discovery found the message. Its result is then recorded
       in the processed-message index even when a forced dry run previews it while filtering
       is live, where a dry-run result settles the message only for later dry-run passes.
       Other forced previews are recorded only while the dry-run setting is on.
   */
  public func process(
    _ envelope: MailEnvelope,
    adapter: (any MailClientAdapter)? = nil,
    forceDryRun: Bool = false,
    timeout: Double = 15,
    discovered: Bool = false
  ) async -> DecisionRecord {
    let start = Date()
    let current: AppState
    do { current = try await claimState(for: envelope.identity) } catch {
      return await unprocessed(
        envelope,
        reason: DecisionReason(failure: error),
        failure: Self.failureKind(error),
        settles: discovered || !forceDryRun
      )
    }
    let settings = current.settings.paused ? AdvancedSettings() : current.settings.advancedOptions
    let parsed: (inspection: DocumentInspection, findings: [String])
    do {
      parsed = try Self.inspect(envelope.raw, settings: settings)
    } catch ParseError.unreadableSender {
      return await reviewUnreadableSender(
        envelope,
        state: current,
        adapter: adapter,
        forceDryRun: forceDryRun,
        discovered: discovered
      )
    } catch {
      return await unprocessed(
        envelope,
        reason: .messageUnreadable,
        failure: .unparseable,
        settles: true,
        revision: current.revision
      )
    }
    var message = parsed.inspection.message, findings = parsed.findings
    if settings.imageOCR, let text = await EmbeddedImageOCR().text(from: parsed.inspection.images) {
      message.text += "\nEmbedded image text (untrusted):\n" + text
    }
    if !current.settings.mailOptions.localOnly, settings.externalEvidence?.localRspamd == true {
      findings.append(
        await RspamdLookup()
          .lookup(raw: envelope.raw, timeout: max(0, timeout - Date().timeIntervalSince(start)))
          .summary
      )
    }
    return await process(
      message,
      identity: envelope.identity,
      adapter: adapter,
      forceDryRun: forceDryRun,
      timeout: max(0, timeout - Date().timeIntervalSince(start)),
      auxiliaryFindings: findings,
      discovered: discovered
    )
  }
  /**
   Classifies, persists, then conditionally dispatches one parsed message, failing open on errors.

   - Parameters:
     - message: The parsed message to process.
     - identity: The message's client identity.
     - adapter: The client that can act on the message.
     - forceDryRun: Whether to suppress mail actions regardless of settings.
     - timeout: Seconds allowed for classification.
     - attempt: The retry attempt this call represents.
     - auxiliaryFindings: Additional evidence summaries supplied to the classifier.
     - discovered: Whether automatic discovery found the message; see
       ``process(_:adapter:forceDryRun:timeout:discovered:)``.
   */
  public func process(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    adapter: (any MailClientAdapter)? = nil,
    forceDryRun: Bool = false,
    timeout: Double = 15,
    attempt: Int = 0,
    auxiliaryFindings: [String] = [],
    discovered: Bool = false
  ) async -> DecisionRecord {
    guard inFlight.insert(identity.key).inserted else {
      var record = failure(identity: identity, reason: .duplicateCallback)
      record.outcome = .duplicate; return record
    }
    defer { inFlight.remove(identity.key) }
    let start = Date()
    var revision: Int?
    var settles = discovered || !forceDryRun
    do {
      try Task.checkCancellation()
      let state = try await classificationState(for: identity)
      revision = state.revision
      settles = settles || state.settings.dryRun
      if !forceDryRun, let id = state.claimedActions[identity.key] {
        let claimed = await claimedResult(id, identity: identity, state: state)
        await remember(claimed, discoveredAs: identity)
        return claimed
      }
      if state.settings.paused {
        return try await paused(
          identity: identity,
          sender: message.fromAddress,
          subject: message.subject,
          revision: state.revision
        )
      }
      let classification = try await classify(
        message,
        identity: identity,
        state: state,
        budget: (start, timeout),
        auxiliaryFindings: auxiliaryFindings
      )
      try Task.checkCancellation()
      guard Date().timeIntervalSince(start) < timeout else { throw ClassificationError.timeout }
      var record = try classification.record(
        of: message,
        identity: identity,
        settings: state.settings,
        revision: state.revision,
        latency: Date().timeIntervalSince(start)
      )
      // Persist the explanation before an external action can be claimed.
      try await save(record)
      record = try await dispatch(record, adapter: adapter, forceDryRun: forceDryRun)
      if settles { await remember(record, discoveredAs: identity) }
      return record
    } catch {
      let record = failure(
        identity: identity,
        sender: message.fromAddress,
        subject: message.subject,
        reason: DecisionReason(failure: error),
        revision: revision ?? 0
      )
      try? await saveFailure(record)
      if settles {
        await remember(record, discoveredAs: identity, failure: Self.failureKind(error))
      }
      await scheduleRetry(
        error: error,
        message: message,
        identity: identity,
        revision: revision,
        retry: (attempt, forceDryRun)
      )
      return record
    }
  }
  /// Queues a retry; an unknown revision means classification never started, so the current one applies.
  private func scheduleRetry(
    error: any Error,
    message: ParsedMessage,
    identity: MessageIdentity,
    revision: Int?,
    retry: (attempt: Int, dryRun: Bool)
  ) async {
    let (attempt, forceDryRun) = retry
    guard !forceDryRun else { return }
    if Self.isRetryable(error), attempt < Self.maximumRetryAttempts, !Task.isCancelled {
      let retryMessage = message.boundedForRetention(keepingHeaders: true)
      try? await StateRepository.update(store, loading: StateSlices(retries: .all)) { state in
        let retryRevision = revision ?? state.revision
        guard state.revision == retryRevision else { return }
        state.retries.removeAll { $0.id == identity.key }
        guard state.retries.count < RetentionLimits.retries else { return }
        state.retries.append(
          RetryJob(
            identity: identity,
            message: retryMessage,
            revision: retryRevision,
            attempt: attempt + 1,
            due: Date().addingTimeInterval(
              Self.initialRetryDelaySec * pow(Self.retryBackoffFactor, Double(attempt))
            ),
            expires: Date().addingTimeInterval(Self.retryLifetimeSec),
            dryRun: forceDryRun
          )
        )
      }
    }
  }
  /// Consumes eligible retries while rejecting expired or superseded work.
  public func retryDue(adapter: any MailClientAdapter, now: Date = .now, accountID: String? = nil)
    async
  {
    guard !Task.isCancelled else { return }
    guard
      let jobs = try? await StateRepository.update(
        store,
        loading: StateSlices(retries: .all),
        { state -> [RetryJob] in
          guard !state.settings.paused else { return [] }
          let jobs = state.retries.filter {
            $0.due <= now && $0.expires > now && $0.revision == state.revision
              && (accountID == nil || $0.identity.accountID == accountID)
          }
          state.retries.removeAll {
            (accountID == nil || $0.identity.accountID == accountID)
              && ($0.expires <= now || $0.revision != state.revision)
          }
          return jobs
        }
      )
    else { return }
    for job in jobs {
      guard !Task.isCancelled else { return }
      guard await claimRetry(job, now: now) else { continue }
      _ = await process(
        job.message,
        identity: job.identity,
        adapter: adapter,
        forceDryRun: job.dryRun,
        attempt: job.attempt
      )
    }
  }
  private func claimRetry(_ job: RetryJob, now: Date) async -> Bool {
    (try? await StateRepository.update(store, loading: StateSlices(retries: .only([job.id]))) {
      state in
      guard !Task.isCancelled, !state.settings.paused, state.revision == job.revision,
        let index = state.retries.firstIndex(where: {
          $0.id == job.id && $0.revision == job.revision && $0.attempt == job.attempt
            && $0.due == job.due && $0.expires == job.expires && $0.expires > now
        })
      else { return false }
      state.retries.remove(at: index)
      return true
    }) ?? false
  }
  private func unprocessed(
    _ envelope: MailEnvelope,
    reason: DecisionReason,
    failure kind: ProcessingFailure,
    settles: Bool,
    revision: Int = 0
  ) async -> DecisionRecord {
    let record = failure(identity: envelope.identity, reason: reason, revision: revision)
    try? await save(record)
    if settles { await remember(record, discoveredAs: envelope.identity, failure: kind) }
    return record
  }
  func failure(
    identity: MessageIdentity,
    sender: String? = nil,
    subject: String? = nil,
    reason: DecisionReason,
    revision: Int = 0
  ) -> DecisionRecord {
    DecisionRecord(
      identity: identity,
      sender: sender,
      subject: subject,
      decision: .init(label: nil, action: .none, reason: reason),
      outcome: .unclassified,
      revision: revision
    )
  }
}

public import Foundation

/// Persists decisions before claiming actions and fails open on errors.
public actor Pipeline {
  /// Scans a raw message with the local Rspamd service within a budget in seconds.
  public typealias RspamdScan = @Sendable (Data, TimeInterval) async -> ExternalEvidenceFinding
  /// Builds the Spamhaus lookup for one configuration.
  public typealias SpamhausLookupFactory = @Sendable (SpamhausConfiguration) -> SpamhausDomainLookup

  private static let maximumRetryAttempts = 3
  private static let initialRetryDelaySec = 30.0
  private static let retryBackoffFactor = 2.0
  private static let retryLifetimeSec = 86_400.0
  /// A quarter of the four characters each body token stands for.
  private static let imageTextCharactersPerBodyToken = 1
  private static let imageTextNotice = "Text found in images (untrusted):"
  let store: Store
  let classifier: any Classifier
  let rdap: RDAPLookup?
  let rspamdScan: RspamdScan
  let spamhaus: SpamhausLookupFactory
  let threatDetector: (any ThreatDetector)?
  let imageOCR: EmbeddedImageOCR
  var inFlight: Set<String> = []
  /// Processed-message index entries whose write failed, keyed by identity, awaiting another attempt.
  var unrecordedResults: [String: (record: DecisionRecord, failure: ProcessingFailure?)] = [:]
  /// Scheduled rechecks of moves confirmed before their provider settled, with the record each
  /// rechecks, keyed by check.
  var moveSettlements: [UUID: (recordID: UUID, check: Task<Void, Never>)] = [:]
  /// Image text of messages the spending limit deferred, which their later sweeps reuse.
  var deferredImageTexts = DeferredImageTexts()
  /**
   Creates a pipeline that persists to `store` and classifies with `classifier`.

   - Parameters:
     - store: The shared state that records decisions and claims actions.
     - classifier: The model that classifies mail no rule or relationship decides.
     - rdap: Looks up domain registration age when that setting is on; without it the age is
       never looked up.
     - rspamdScan: Scans a message when the local Rspamd setting is on; by default through the
       fixed loopback endpoint.
     - spamhaus: Builds the domain blocklist lookup when that setting is on; by default with the
       live transports and the Spamhaus key from the shared Keychain.
     - threatDetector: Assesses threats in each classified message; without it records carry no
       threat assessment.
     - imageOCR: Recognizes text in embedded images when that setting is on; by default with
       on-device Vision.
   */
  public init(
    store: Store,
    classifier: any Classifier,
    rdap: RDAPLookup? = nil,
    rspamdScan: @escaping RspamdScan = { await RspamdLookup().lookup(raw: $0, timeout: $1) },
    spamhaus: @escaping SpamhausLookupFactory = Pipeline.liveSpamhaus,
    threatDetector: (any ThreatDetector)? = nil,
    imageOCR: EmbeddedImageOCR = EmbeddedImageOCR()
  ) {
    self.store = store; self.classifier = classifier; self.rdap = rdap
    self.rspamdScan = rspamdScan; self.spamhaus = spamhaus
    self.threatDetector = threatDetector; self.imageOCR = imageOCR
  }
  /// The Spamhaus lookup over the live transports, reading its key from the shared Keychain.
  public static func liveSpamhaus(_ configuration: SpamhausConfiguration) -> SpamhausDomainLookup {
    SpamhausDomainLookup(
      configuration: configuration,
      key: { try APIKeychain(service: APIKeychain.spamhausService).read() }
    )
  }
  /**
   `body` after the text found in its images, which comes first so prompt shortening keeps it,
   bounded to a quarter of the body budget so it cannot crowd out the body.
   */
  private static func leadingImageText(_ text: String, body: String, bodyTokenBudget: Int)
    -> String
  {
    let limit = bodyTokenBudget * imageTextCharactersPerBodyToken
    return imageTextNotice + "\n" + text.prefix(limit) + "\n\n" + body
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
    var message = parsed.inspection.message
    let imageText =
      settings.imageOCR ? await imageText(in: parsed.inspection.images, of: envelope.raw) : nil
    if let text = imageText?.text {
      message.text = Self.leadingImageText(
        text,
        body: message.text,
        bodyTokenBudget: current.settings.bodyTokenBudget
      )
    }
    let record = await processParsed(
      message,
      identity: envelope.identity,
      adapter: adapter,
      forceDryRun: forceDryRun,
      timeout: max(0, timeout - Date().timeIntervalSince(start)),
      attempt: 0,
      auxiliaryFindings: parsed.findings,
      discovered: discovered,
      raw: envelope.raw
    )
    if let imageText { retain(imageText, after: record) }
    return record
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
    await processParsed(
      message,
      identity: identity,
      adapter: adapter,
      forceDryRun: forceDryRun,
      timeout: timeout,
      attempt: attempt,
      auxiliaryFindings: auxiliaryFindings,
      discovered: discovered,
      raw: nil
    )
  }
  /// Processes a parsed message, scanning `raw` with the local Rspamd service when it is given.
  private func processParsed(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    adapter: (any MailClientAdapter)?,
    forceDryRun: Bool,
    timeout: Double,
    attempt: Int,
    auxiliaryFindings: [String],
    discovered: Bool,
    raw: Data?
  ) async -> DecisionRecord {
    guard inFlight.insert(identity.key).inserted else {
      var record = failure(identity: identity, reason: .duplicateCallback)
      record.outcome = .duplicate; return record
    }
    defer { inFlight.remove(identity.key) }
    let start = Date()
    var revision: Int?, pending: DecisionRecord?, findings = auxiliaryFindings
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
        auxiliaryFindings: &findings,
        raw: raw
      )
      try Task.checkCancellation()
      var record = try classification.record(
        of: message,
        identity: identity,
        settings: state.settings,
        revision: state.revision,
        latency: Date().timeIntervalSince(start)
      )
      // Persist the explanation before an external action can be claimed.
      try await save(
        record,
        of: message,
        classification: classification,
        recordsStatistics: discovered || !forceDryRun
      )
      pending = record
      record = try await dispatch(record, adapter: adapter, forceDryRun: forceDryRun)
      if settles { await remember(record, discoveredAs: identity) }
      return record
    } catch {
      let unclassified = failure(
        identity: identity,
        sender: message.fromAddress,
        subject: message.subject,
        reason: DecisionReason(failure: error),
        revision: revision ?? 0
      )
      let record = await recordFailure(error, of: pending, otherwise: unclassified)
      if settles {
        await remember(unclassified, discoveredAs: identity, failure: Self.failureKind(error))
      }
      await scheduleRetry(
        error: error,
        message: message,
        identity: identity,
        revision: revision,
        retry: (attempt, forceDryRun, findings)
      )
      return record
    }
  }
  /**
   Records a processing failure: on `pending`, the saved decision whose action never started,
   or else as `unclassified`.
   */
  func recordFailure(
    _ error: any Error,
    of pending: DecisionRecord?,
    otherwise unclassified: DecisionRecord
  ) async -> DecisionRecord {
    guard var record = pending else {
      try? await saveFailure(unclassified)
      return unclassified
    }
    record.outcome = .failed
    record.actionError = Self.notAttemptedDescription(error)
    try? await saveObservedOutcome(record)
    return record
  }
  /// Queues a retry; an unknown revision means classification never started, so the current one applies.
  private func scheduleRetry(
    error: any Error,
    message: ParsedMessage,
    identity: MessageIdentity,
    revision: Int?,
    retry: (attempt: Int, dryRun: Bool, findings: [String])
  ) async {
    let (attempt, forceDryRun, findings) = retry
    guard !forceDryRun else { return }
    if Self.isRetryable(error), attempt < Self.maximumRetryAttempts, !Task.isCancelled {
      let retryMessage = message.boundedForRetention(keepingHeaders: true)
      let retryFindings = findings.prefix(RetentionLimits.retryFindings).map {
        String($0.prefix(RetentionLimits.retryFindingCharacters))
      }
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
            auxiliaryFindings: retryFindings
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
        forceDryRun: false,
        attempt: job.attempt,
        auxiliaryFindings: job.auxiliaryFindings
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

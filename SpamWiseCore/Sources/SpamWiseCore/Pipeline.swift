public import Foundation

/// Persists decisions before claiming actions and fails open on errors.
public actor Pipeline {
  private static let maximumRetryAttempts = 3
  private static let maximumRetryCharacters = 16_000
  private static let maximumRetries = 100
  private static let initialRetryDelaySec = 30.0
  private static let retryBackoffFactor = 2.0
  private static let retryLifetimeSec = 86_400.0
  let store: Store
  let classifier: any Classifier
  let rdap: RDAPLookup?
  private var inFlight: Set<String> = []
  /// Creates a Pipeline with the supplied configuration.
  public init(store: Store, classifier: any Classifier, rdap: RDAPLookup? = nil) {
    self.store = store; self.classifier = classifier; self.rdap = rdap
  }
  /// Classifies, persists, then conditionally dispatches one message, failing open on errors.
  public func process(
    _ envelope: MailEnvelope,
    adapter: (any MailClientAdapter)? = nil,
    forceDryRun: Bool = false,
    timeout: Double = 15
  ) async -> DecisionRecord {
    let start = Date()
    do {
      var message = try MIMEParser().parse(envelope.raw)
      let current = try await StateRepository.load(store)
      let settings = current.settings.paused ? AdvancedSettings() : current.settings.advancedOptions
      if settings.imageOCR, let text = await EmbeddedImageOCR().text(from: envelope.raw) {
        message.text += "\nEmbedded image text (untrusted):\n" + text
      }
      var findings: [String] = []
      if !current.settings.mailOptions.localOnly, let path = settings.externalEvidence?.rspamcPath {
        findings.append(await RspamdLookup(executablePath: path).lookup(raw: envelope.raw).summary)
      }
      return await process(
        message,
        identity: envelope.identity,
        adapter: adapter,
        forceDryRun: forceDryRun,
        timeout: max(0, timeout - Date().timeIntervalSince(start)),
        auxiliaryFindings: findings
      )
    } catch {
      let record = failure(
        identity: envelope.identity,
        reason: "unclassified: message parsing failed"
      )
      try? await save(record); return record
    }
  }
  /// Classifies, persists, then conditionally dispatches one message, failing open on errors.
  public func process(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    adapter: (any MailClientAdapter)? = nil,
    forceDryRun: Bool = false,
    timeout: Double = 15,
    attempt: Int = 0,
    auxiliaryFindings: [String] = []
  ) async -> DecisionRecord {
    guard inFlight.insert(identity.key).inserted else {
      var record = failure(identity: identity, reason: "Duplicate callback already in progress")
      record.outcome = .duplicate; return record
    }
    defer { inFlight.remove(identity.key) }
    let start = Date()
    var revision = 0
    do {
      try Task.checkCancellation()
      let state = try await StateRepository.load(store); revision = state.revision
      if let id = state.claimedActions[identity.key],
        let previous = state.records.first(where: { $0.id == id })
      {
        return previous
      }
      if state.settings.paused {
        return try await paused(message, identity: identity, revision: revision)
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
      let decision = try Decision.evaluate(
        classification.verdict,
        strength: state.settings.strength,
        review: state.settings.review
      )
      var record = DecisionRecord(
        identity: identity,
        sender: message.fromAddress,
        subject: message.subject,
        evidence: classification.evidence,
        verdict: classification.verdict,
        decision: decision,
        outcome: .pending,
        path: classification.path,
        latency: Date().timeIntervalSince(start),
        revision: revision
      )
      // Persist the explanation before an external action can be claimed.
      try await save(record)
      record = try await dispatch(record, adapter: adapter, forceDryRun: forceDryRun)
      return record
    } catch {
      let reason: String
      if let error = error as? ClassificationError {
        reason = error.rawValue
      } else if error is ContentRuleError {
        reason = "content rule invalid or exceeded its evaluation deadline"
      } else if error is BudgetError {
        reason = "spending limit reached; no provider request was made"
      } else if error is CancellationError {
        reason = "cancelled"
      } else {
        reason = "persistence or integration unavailable"
      }
      let record = failure(
        identity: identity,
        sender: message.fromAddress,
        subject: message.subject,
        reason: "unclassified: " + reason,
        revision: revision
      )
      try? await save(record)
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
  private func paused(_ message: ParsedMessage, identity: MessageIdentity, revision: Int)
    async throws -> DecisionRecord
  {
    let record = DecisionRecord(
      identity: identity,
      sender: message.fromAddress,
      subject: message.subject,
      decision: .init(label: nil, action: .none, reason: "Filtering paused"),
      outcome: .paused,
      revision: revision
    )
    try await save(record)
    return record
  }
  private func scheduleRetry(
    error: any Error,
    message: ParsedMessage,
    identity: MessageIdentity,
    revision: Int,
    retry: (attempt: Int, dryRun: Bool)
  ) async {
    let (attempt, forceDryRun) = retry
    guard !forceDryRun else { return }
    if let error = error as? ClassificationError, error.retryable,
      attempt < Self.maximumRetryAttempts, !Task.isCancelled
    {
      var bounded = message; bounded.text = String(message.text.prefix(Self.maximumRetryCharacters))
      let retryMessage = bounded
      let retryRevision = revision
      try? await StateRepository.update(store) { state in
        guard state.revision == retryRevision else { return }
        state.retries.removeAll { $0.id == identity.key }
        guard state.retries.count < Self.maximumRetries else { return }
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
    guard
      let jobs = try? await StateRepository.update(
        store,
        { state -> [RetryJob] in
          guard !state.settings.paused else { return [] }
          let jobs = state.retries.filter {
            $0.due <= now && $0.expires > now && $0.revision == state.revision
              && (accountID == nil || $0.identity.accountID == accountID)
          }
          state.retries.removeAll {
            (accountID == nil || $0.identity.accountID == accountID)
              && ($0.due <= now || $0.expires <= now || $0.revision != state.revision)
          }
          return jobs
        }
      )
    else { return }
    for job in jobs {
      guard !Task.isCancelled else { return }
      _ = await process(
        job.message,
        identity: job.identity,
        adapter: adapter,
        forceDryRun: job.dryRun,
        attempt: job.attempt
      )
    }
  }
  func dispatch(
    _ original: DecisionRecord,
    adapter: (any MailClientAdapter)?,
    forceDryRun: Bool,
    correction: Bool = false
  ) async throws -> DecisionRecord {
    let claimed = try await StateRepository.update(store) { state -> DecisionRecord in
      guard let i = state.records.firstIndex(where: { $0.id == original.id }) else {
        throw IntegrationError.unavailable
      }
      var record = state.records[i]
      if state.revision != record.revision {
        record.outcome = .superseded
      } else if state.settings.paused {
        record.outcome = .paused
      } else if record.decision.action == .none {
        record.outcome = .noAction
      } else if forceDryRun || state.settings.dryRun {
        record.outcome = .dryRun
      } else if !correction && state.claimedActions[record.identity.key] != nil {
        record.outcome = .duplicate
      } else if adapter == nil || record.identity.accountID == nil
        || !state.settings.validatedAccounts.contains(record.identity.accountID ?? "")
        || state.settings.route == .unverified
      {
        record.outcome = .integrationUnavailable
      } else {
        record.outcome = .requested
        state.claimedActions[record.identity.key] = record.id
      }
      state.records[i] = record
      if !forceDryRun { state.retries.removeAll { $0.identity.key == record.identity.key } }
      return record
    }
    guard claimed.outcome == .requested, let adapter else { return claimed }
    var completed = claimed
    do {
      try Task.checkCancellation()
      let current = try await StateRepository.load(store)
      guard current.revision == claimed.revision, !current.settings.paused, !current.settings.dryRun
      else { completed.outcome = .superseded; try await save(completed); return completed }
      let receipt = try await adapter.perform(claimed.decision.action, for: claimed.identity)
      completed.outcome = receipt.confirmed ? .applied : .requested
      if receipt.confirmed, let identity = receipt.updatedIdentity {
        completed.identity = identity
      }
    } catch {
      completed.outcome = .failed
      if let error = error as? IntegrationError {
        completed.actionError = [error.errorDescription, error.failureReason].compactMap { $0 }
          .joined(separator: " ")
      } else {
        completed.actionError =
          "Action failed or was cancelled; delivery status unknown. Not retried."
      }
    }
    try await save(completed)
    return completed
  }
  private func save(_ record: DecisionRecord) async throws {
    try await StateRepository.update(store) { state in
      state.record(record)
    }
  }
  private func failure(
    identity: MessageIdentity,
    sender: String = "Unknown",
    subject: String = "Unclassified message",
    reason: String,
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

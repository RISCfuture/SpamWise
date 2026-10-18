extension Pipeline {
  /// Corrects an explicitly selected message without first invoking a classifier.
  public func correct(
    envelope: MailEnvelope,
    label: MailLabel,
    scope: RuleScope = .address,
    adapter: (any MailClientAdapter)? = nil,
    trainingPlanID: String? = nil
  ) async throws -> DecisionRecord {
    let message = try MIMEParser().parse(envelope.raw)
    let seed = try await StateRepository.update(store, loading: StateSlices()) {
      state -> DecisionRecord in
      let record = DecisionRecord(
        identity: envelope.identity,
        sender: message.fromAddress,
        subject: message.subject,
        evidence: EvidenceBundle(message: message),
        decision: .init(label: nil, action: .none, reason: .selectedForCorrection),
        outcome: .noAction,
        path: .selection,
        revision: state.revision
      )
      state.record(record)
      return record
    }
    return try await correct(
      recordID: seed.id,
      label: label,
      scope: scope,
      adapter: adapter,
      trainingPlanID: trainingPlanID
    )
  }
}

/// Per-message correction status for a bounded selected-message operation.
public struct MailCorrectionResult: Identifiable, Sendable {
  /// Original account-scoped identity.
  public let id: String
  /// Subject of the selected message.
  public let subject: String
  /// Persisted correction and independent mail outcome, absent if saving failed.
  public let record: DecisionRecord?
  /// Sanitized error when no correction could be saved.
  public let error: String?
  /// Creates one user-visible result without combining storage and move success.
  public init(id: String, subject: String, record: DecisionRecord?, error: String? = nil) {
    self.id = id; self.subject = subject; self.record = record; self.error = error
  }
}

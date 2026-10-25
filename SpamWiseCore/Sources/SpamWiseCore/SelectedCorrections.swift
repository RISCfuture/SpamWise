extension Pipeline {
  /**
   Corrects an explicitly selected message without first invoking a classifier.

   The message's record is saved with the correction, so a correction that fails leaves no
   record. A Review annotation that SpamWise left on the message is removed like one on a
   corrected Activity record.
   */
  public func correct(
    envelope: MailEnvelope,
    label: MailLabel,
    scope: RuleScope = .address,
    adapter: (any MailClientAdapter)? = nil,
    trainingPlanID: String? = nil
  ) async throws -> DecisionRecord {
    let message = try MIMEParser().parse(envelope.raw)
    let selection = try await StateRepository.transaction(store) { transaction in
      try transaction.loadClaim(for: envelope.identity)
      let state = transaction.state
      var seed = DecisionRecord(
        identity: envelope.identity,
        sender: message.fromAddress,
        subject: message.subject,
        evidence: EvidenceBundle(
          message: message,
          trustedAuthServers: state.settings.mailOptions.trustedAuthServers(
            for: envelope.identity.accountID
          )
        ),
        decision: .init(label: nil, action: .none, reason: .selectedForCorrection),
        outcome: .noAction,
        path: .selection,
        revision: state.revision
      )
      seed.sampleID = LearningSample.identity(for: message)
      let claimed = state.claimedActions[envelope.identity.key].flatMap { id in
        state.records.first { $0.id == id }
      }
      return (seed: seed, annotation: claimed?.reviewAnnotation)
    }
    var request = CorrectionRequest(
      recordID: selection.seed.id,
      label: label,
      scope: scope,
      trainingPlanID: trainingPlanID
    )
    request.seed = selection.seed
    request.reviewAnnotation = selection.annotation
    return try await correct(request, adapter: adapter, message: message)
  }
}

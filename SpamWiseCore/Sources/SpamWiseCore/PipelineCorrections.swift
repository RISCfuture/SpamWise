public import Foundation

extension Pipeline {
  private static func correctionAction(_ label: MailLabel, review: ReviewTreatment) -> MailAction {
    switch label {
      case .inbox: .moveToInbox
      case .junk: .moveToJunk
      case .review: review == .orangeFlag ? .orangeFlag : .orangeBackground
    }
  }
  static func collectsLearning(_ options: AdvancedSettings) -> Bool {
    options.fingerprints || options.bayes || options.learnedWeights
  }
  /// Atomically saves a correction and then attempts the separately recorded mail action.
  public func correct(
    recordID: UUID,
    label: MailLabel,
    scope: RuleScope = .address,
    adapter: (any MailClientAdapter)? = nil,
    trainingPlanID: String? = nil
  ) async throws -> DecisionRecord {
    guard label != .review || scope == .address else { throw ClassificationError.invalidOutput }
    let slices = StateSlices(
      CorrectionUndo.slices.parts.union(.training),
      records: .only([recordID]),
      reviewedLabels: CorrectionUndo.slices.reviewedLabels
    )
    let record = try await StateRepository.update(store, loading: slices) {
      state -> DecisionRecord in
      guard let index = state.records.firstIndex(where: { $0.id == recordID }) else {
        throw IntegrationError.unavailable
      }
      let previous = state.records[index]
      let before = state
      let trainingKey = try TrainingFolders.claimKey(
        planID: trainingPlanID,
        label: label,
        identity: previous.identity,
        state: state
      )
      guard let address = previous.sender.flatMap(MIMEParser.address) else {
        throw IntegrationError.unavailable
      }
      let domain = DomainResolver().domain(ofAddress: address)
      guard scope != .domain || domain != nil else { throw IntegrationError.unavailable }
      let rule = SenderRule(
        scope: scope,
        value: scope == .address ? address : domain!,
        disposition: label == .inbox ? .allow : .block
      )
      if label == .review {
        state.rules.removeAll { $0.scope == .address && $0.value == address }
      } else {
        state.rules = Gates.replacing(rule, in: state.rules)
      }
      var example = CorrectionExample(
        sender: address,
        domain: domain,
        subject: previous.subject ?? "",
        excerpt: "",
        label: label,
        promptScope: previous.identity.accountID.map(CorrectionExample.PromptScope.account)
      )
      example.sampleID =
        state.reviewedLabels.first { $0.id == previous.identity.contentHash }?
        .sampleID ?? previous.identity.contentHash
      state.corrections.append(example)
      state.corrections = Array(state.corrections.suffix(RetentionLimits.corrections))
      state.invalidatePendingWork(
        .correction,
        detail: String(localized: "\(scope.rawValue): \(address) → \(label.rawValue)")
      )
      state.records[index].correctedLabel = label
      var correction = DecisionRecord(
        identity: previous.identity,
        sender: address,
        subject: previous.subject,
        evidence: previous.evidence,
        decision: .init(
          label: label,
          action: Self.correctionAction(label, review: state.settings.review),
          reason: .userCorrection(scope: scope)
        ),
        outcome: .pending,
        path: .correction,
        revision: state.revision
      )
      correction.correctedLabel = label
      state.correctionUndo = CorrectionUndo(
        state: before,
        source: previous,
        recordID: correction.id,
        revision: state.revision
      )
      state.record(correction)
      if let trainingKey { state.trainingClaims[trainingKey] = correction.id }
      return correction
    }
    try await recordReviewedLabel(record, label: label, adapter: adapter)
    return try await dispatch(record, adapter: adapter, forceDryRun: false, correction: true)
  }
  private func recordReviewedLabel(
    _ record: DecisionRecord,
    label: MailLabel,
    adapter: (any MailClientAdapter)?
  ) async throws {
    let options = try await StateRepository.load(store, StateSlices()).settings.advancedOptions
    var message: ParsedMessage?
    if options.retainReviewedContent || Self.collectsLearning(options),
      let envelope = try? await adapter?.lookup(record.identity)
    {
      message = try? MIMEParser().parse(envelope.raw).boundedForRetention()
    }
    let reviewedMessage = message
    try await StateRepository.transaction(store) { transaction in
      var parts: StateSlices.Parts = [.corrections, .undo]
      if Self.collectsLearning(transaction.state.settings.advancedOptions) {
        parts.insert(.learning)
      }
      try transaction.load(StateSlices(parts, reviewedLabels: .all))
      guard transaction.state.revision == record.revision else { return }
      transaction.state.recordLabel(label, for: record, message: reviewedMessage)
      try transaction.commit()
    }
  }
}

extension AppState {
  fileprivate mutating func recordLabel(
    _ label: MailLabel,
    for record: DecisionRecord,
    message: ParsedMessage?
  ) {
    let previousSampleID =
      reviewedLabels.first { $0.id == record.identity.contentHash }?.sampleID
      ?? record.identity.contentHash
    let sampleID = message.map(LearningSample.identity) ?? previousSampleID
    for index in corrections.indices where corrections[index].sampleID == previousSampleID {
      corrections[index].sampleID = sampleID
      if let message { corrections[index].quote(message.text) }
    }
    reviewedLabels.removeAll { $0.id == record.identity.contentHash }
    reviewedLabels.append(
      ReviewedLabel(
        identity: record.identity,
        label: label,
        message: settings.advancedOptions.retainReviewedContent ? message : nil,
        sampleID: sampleID
      )
    )
    reviewedLabels = Array(reviewedLabels.suffix(RetentionLimits.reviewedLabels))
    if Pipeline.collectsLearning(settings.advancedOptions), let message {
      learning.recordCorrection(
        message: message,
        evidence: record.evidence ?? EvidenceBundle(message: message),
        label: label
      )
    }
    if correctionUndo?.recordID == record.id { correctionUndo?.confirmed = true }
  }
}

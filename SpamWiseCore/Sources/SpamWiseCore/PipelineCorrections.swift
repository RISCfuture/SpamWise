public import Foundation

extension Pipeline {
  /// Atomically saves a correction and then attempts the separately recorded mail action.
  public func correct(
    recordID: UUID,
    label: MailLabel,
    scope: RuleScope = .address,
    adapter: (any MailClientAdapter)? = nil
  ) async throws -> DecisionRecord {
    guard label != .review || scope == .address else { throw ClassificationError.invalidOutput }
    let record = try await StateRepository.update(store) { state -> DecisionRecord in
      guard let i = state.records.firstIndex(where: { $0.id == recordID }) else {
        throw IntegrationError.unavailable
      }
      let previous = state.records[i]
      guard let address = MIMEParser.address(previous.sender) else {
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
      state.corrections.append(
        CorrectionExample(
          sender: address,
          domain: domain,
          subject: previous.subject,
          gist: previous.decision.reason,
          label: label
        )
      )
      state.corrections = Array(state.corrections.suffix(200))
      state.revision += 1
      state.retries.removeAll()  // Any old prompt/evidence generation is stale after a correction.
      state.records[i].correctedLabel = label
      var correction = DecisionRecord(
        identity: previous.identity,
        sender: address,
        subject: previous.subject,
        evidence: previous.evidence,
        decision: .init(
          label: label,
          action: Self.correctionAction(label, review: state.settings.review),
          reason: "User correction (\(scope.rawValue))"
        ),
        outcome: .pending,
        path: "correction",
        revision: state.revision
      )
      correction.correctedLabel = label
      state.record(correction)
      return correction
    }
    try await recordReviewedLabel(record, label: label, adapter: adapter)
    return try await dispatch(record, adapter: adapter, forceDryRun: false, correction: true)
  }
  private static func correctionAction(_ label: MailLabel, review: ReviewTreatment) -> MailAction {
    switch label {
      case .inbox: .moveToInbox
      case .junk: .moveToJunk
      case .review: review == .orangeFlag ? .orangeFlag : .orangeBackground
    }
  }
  private func recordReviewedLabel(
    _ record: DecisionRecord,
    label: MailLabel,
    adapter: (any MailClientAdapter)?
  ) async throws {
    let options = try await StateRepository.load(store).settings.advancedOptions
    var message: ParsedMessage?
    if options.retainReviewedContent || Self.collectsLearning(options),
      let envelope = try? await adapter?.lookup(record.identity)
    {
      message = try? MIMEParser().parse(envelope.raw)
      let boundedText = String(message?.text.prefix(16_000) ?? "")
      message?.text = boundedText
      message?.headers = [:]
      let boundedURLs = Array(message?.urls.prefix(40) ?? []).map { String($0.prefix(2048)) }
      message?.urls = boundedURLs
    }
    let reviewedMessage = message
    try await StateRepository.update(store) { state in
      guard state.revision == record.revision else { return }
      var labels = state.reviewedLabels ?? []
      labels.removeAll { $0.id == record.identity.contentHash }
      labels.append(
        ReviewedLabel(
          identity: record.identity,
          label: label,
          message: state.settings.advancedOptions.retainReviewedContent ? reviewedMessage : nil,
          sampleID: reviewedMessage.map(LearningSample.identity)
        )
      )
      state.reviewedLabels = Array(labels.suffix(500))
      if Self.collectsLearning(state.settings.advancedOptions), let reviewedMessage {
        var learning = state.learning ?? LearningState()
        learning.recordCorrection(
          message: reviewedMessage,
          evidence: record.evidence ?? EvidenceBundle(message: reviewedMessage),
          label: label
        )
        state.learning = learning
      }
    }
  }
  private static func collectsLearning(_ options: AdvancedSettings) -> Bool {
    options.fingerprints || options.bayes || options.learnedWeights
  }
}

public import Foundation

extension Pipeline {
  private static let maximumCorrections = 200
  private static let maximumReviewedCharacters = 16_000
  private static let maximumReviewedURLs = 40
  private static let maximumURLCharacters = 2048
  private static let maximumReviewedLabels = 500
  private static func correctionAction(_ label: MailLabel, review: ReviewTreatment) -> MailAction {
    switch label {
      case .inbox: .moveToInbox
      case .junk: .moveToJunk
      case .review: review == .orangeFlag ? .orangeFlag : .orangeBackground
    }
  }
  private static func collectsLearning(_ options: AdvancedSettings) -> Bool {
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
    let record = try await StateRepository.update(store) { state -> DecisionRecord in
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
        gist: previous.decision.reason.diagnosticDescription,
        label: label
      )
      example.sampleID =
        state.reviewedLabels?.first { $0.id == previous.identity.contentHash }?
        .sampleID ?? previous.identity.contentHash
      state.corrections.append(example)
      state.corrections = Array(state.corrections.suffix(Self.maximumCorrections))
      state.revision += 1
      state.retries.removeAll()  // Any old prompt/evidence generation is stale after a correction.
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
      state.audit(
        .correction,
        detail: String(localized: "\(scope.rawValue): \(address) → \(label.rawValue)")
      )
      if let trainingKey {
        if state.trainingClaims == nil { state.trainingClaims = [:] }
        state.trainingClaims?[trainingKey] = correction.id
      }
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
    let options = try await StateRepository.load(store).settings.advancedOptions
    var message: ParsedMessage?
    if options.retainReviewedContent || Self.collectsLearning(options),
      let envelope = try? await adapter?.lookup(record.identity)
    {
      message = try? MIMEParser().parse(envelope.raw)
      let boundedText = String(message?.text.prefix(Self.maximumReviewedCharacters) ?? "")
      message?.text = boundedText
      message?.headers = [:]
      let boundedURLs = Array(message?.urls.prefix(Self.maximumReviewedURLs) ?? [])
        .map { String($0.prefix(Self.maximumURLCharacters)) }
      message?.urls = boundedURLs
    }
    let reviewedMessage = message
    try await StateRepository.update(store) { state in
      guard state.revision == record.revision else { return }
      var labels = state.reviewedLabels ?? []
      let previousSampleID =
        labels.first { $0.id == record.identity.contentHash }?.sampleID
        ?? record.identity.contentHash
      let sampleID = reviewedMessage.map(LearningSample.identity) ?? previousSampleID
      for index in state.corrections.indices
      where state.corrections[index].sampleID == previousSampleID {
        state.corrections[index].sampleID = sampleID
      }
      labels.removeAll { $0.id == record.identity.contentHash }
      labels.append(
        ReviewedLabel(
          identity: record.identity,
          label: label,
          message: state.settings.advancedOptions.retainReviewedContent ? reviewedMessage : nil,
          sampleID: sampleID
        )
      )
      state.reviewedLabels = Array(labels.suffix(Self.maximumReviewedLabels))
      if Self.collectsLearning(state.settings.advancedOptions), let reviewedMessage {
        var learning = state.learning ?? LearningState()
        learning.recordCorrection(
          message: reviewedMessage,
          evidence: record.evidence ?? EvidenceBundle(message: reviewedMessage),
          label: label
        )
        state.learning = learning
      }
      if state.correctionUndo?.recordID == record.id {
        let digest = try CorrectionUndo.digest(state)
        state.correctionUndo?.expectedDigest = digest
      }
    }
  }
}

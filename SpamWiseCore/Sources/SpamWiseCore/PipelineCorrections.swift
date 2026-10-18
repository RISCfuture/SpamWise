public import Foundation

extension Pipeline {
  private static let correctionSlices = StateSlices(
    CorrectionUndo.slices.parts.union(.training),
    reviewedLabels: CorrectionUndo.slices.reviewedLabels
  )
  /// The principal action recorded for a correction to `label`.
  static func correctionAction(_ label: MailLabel, review: ReviewTreatment) -> MailAction {
    switch label {
      case .inbox: .moveToInbox
      case .junk: .moveToJunk
      case .review: review.action
    }
  }
  /**
   The ordered mail steps that leave a corrected message in the state its new label defines.

   Review means Inbox with the Review annotation, so a Review correction first returns the
   message to Inbox. Good and Junk corrections of a message SpamWise annotated for Review
   remove that annotation.
   */
  static func correctionSteps(
    _ label: MailLabel,
    previous: DecisionRecord,
    review: ReviewTreatment
  ) -> [MailAction] {
    let annotation = previous.reviewAnnotation
    switch label {
      case .inbox: return [.moveToInbox] + [annotation?.clearingAnnotation].compactMap(\.self)
      case .junk: return [annotation?.clearingAnnotation].compactMap(\.self) + [.moveToJunk]
      case .review:
        let replaced = annotation == review.action ? nil : annotation?.clearingAnnotation
        return [.moveToInbox] + [replaced].compactMap(\.self) + [review.action]
    }
  }
  static func collectsLearning(_ options: AdvancedSettings) -> Bool {
    options.fingerprints || options.bayes || options.learnedWeights
  }
  /**
   Atomically saves a correction's rule, example, reviewed label and learning, then attempts
   its separately recorded mail steps.

   Message text for the label and learning is read before saving and only when a setting
   needs it; when it is unavailable the correction is saved without it. Problems with the mail
   steps are reported through the returned record's outcome.

   - Throws: ``CorrectionError`` when the record or its sender cannot be corrected, or a
     storage error when the correction cannot be saved; nothing is saved either way.
   */
  public func correct(
    recordID: UUID,
    label: MailLabel,
    scope: RuleScope = .address,
    adapter: (any MailClientAdapter)? = nil,
    trainingPlanID: String? = nil
  ) async throws -> DecisionRecord {
    try await correct(
      CorrectionRequest(
        recordID: recordID,
        label: label,
        scope: scope,
        trainingPlanID: trainingPlanID
      ),
      adapter: adapter,
      message: nil
    )
  }
  /// Corrects a record, reading its message through `adapter` when `message` is nil and a setting needs it.
  func correct(
    _ request: CorrectionRequest,
    adapter: (any MailClientAdapter)?,
    message: ParsedMessage?
  ) async throws -> DecisionRecord {
    guard request.label != .review || request.scope == .address else {
      throw CorrectionError.reviewRequiresAddressScope
    }
    let reviewed = await reviewedMessage(
      recordID: request.recordID,
      known: message,
      adapter: adapter
    )
    let correction = try await StateRepository.update(
      store,
      loading: StateSlices(
        Self.correctionSlices.parts,
        records: .only([request.recordID]),
        reviewedLabels: Self.correctionSlices.reviewedLabels
      )
    ) { state in
      try state.applyCorrection(request, message: reviewed)
    }
    return try await dispatch(
      correction.record,
      adapter: adapter,
      forceDryRun: false,
      mode: .correction(steps: correction.steps)
    )
  }
  /**
   The sender rule that still decides mail from a corrected sender against its new label.

   A Review correction leaves a matching domain rule in force; the caller can warn about it.
   */
  public func overridingRule(for correction: DecisionRecord) async throws -> SenderRule? {
    guard let label = correction.correctedLabel, let sender = correction.sender else { return nil }
    let rules = try await StateRepository.load(store, StateSlices([.rules])).rules
    return AppState.decisiveRule(for: sender, in: rules).flatMap { rule in
      switch (label, rule.disposition) {
        case (.review, _), (.inbox, .block), (.junk, .allow): rule
        case (.inbox, .allow), (.junk, .block): nil
      }
    }
  }
  /// Bounded message text for the reviewed label and learning, or nil when no setting needs it.
  private func reviewedMessage(
    recordID: UUID,
    known: ParsedMessage?,
    adapter: (any MailClientAdapter)?
  ) async -> ParsedMessage? {
    guard
      let state = try? await StateRepository.load(store, StateSlices(records: .only([recordID]))),
      state.settings.advancedOptions.retainReviewedContent
        || Self.collectsLearning(state.settings.advancedOptions)
    else { return nil }
    if let known { return known.boundedForRetention() }
    guard let identity = state.records.first(where: { $0.id == recordID })?.identity,
      let envelope = try? await adapter?.lookup(identity)
    else { return nil }
    return try? MIMEParser().parse(envelope.raw).boundedForRetention()
  }
}

/// One correction a user requested.
struct CorrectionRequest: Sendable {
  /// The Activity record being corrected.
  var recordID: UUID
  /// The label the user chose.
  var label: MailLabel
  /// Whether the rule covers the sender's address or its whole domain.
  var scope: RuleScope
  /// The training folder whose placement this correction claims, if any.
  var trainingPlanID: String?
}

extension DecisionRecord {
  /// The Review annotation SpamWise applied or requested for this message, if any.
  var reviewAnnotation: MailAction? {
    guard decision.action.clearingAnnotation != nil, [.applied, .requested].contains(outcome)
    else { return nil }
    return decision.action
  }
}

extension AppState {
  /// The sender rule ``Gates`` applies first for `sender`: its address rule, else its domain rule.
  static func decisiveRule(for sender: String, in rules: [SenderRule]) -> SenderRule? {
    let address = sender.lowercased()
    let domain = DomainResolver().domain(ofAddress: address)
    return [(RuleScope.address, address), (.domain, domain)].lazy.compactMap { scope, value in
      rules.filter { $0.scope == scope && $0.value == value }.max { $0.updatedAt < $1.updatedAt }
    }.first
  }
  fileprivate mutating func applyCorrection(
    _ request: CorrectionRequest,
    message: ParsedMessage?
  ) throws -> (record: DecisionRecord, steps: [MailAction]) {
    let label = request.label, scope = request.scope
    guard let index = records.firstIndex(where: { $0.id == request.recordID }) else {
      throw CorrectionError.recordNotFound
    }
    let previous = records[index], before = self
    let trainingKey = try TrainingFolders.claimKey(
      planID: request.trainingPlanID,
      label: label,
      identity: previous.identity,
      state: self
    )
    guard let address = previous.sender.flatMap(MIMEParser.address) else {
      throw CorrectionError.unreadableSender
    }
    let domain = DomainResolver().domain(ofAddress: address)
    try applyCorrectionRule(label: label, scope: scope, address: address, domain: domain)
    let linkedSampleID =
      reviewedLabels.first { $0.id == previous.identity.contentHash }?.sampleID
      ?? previous.identity.contentHash
    let sampleID = previous.sampleID ?? message.map(LearningSample.identity) ?? linkedSampleID
    var example = CorrectionExample(
      sender: address,
      domain: domain,
      subject: previous.subject ?? "",
      excerpt: "",
      label: label,
      promptScope: previous.identity.accountID.map(CorrectionExample.PromptScope.account)
    )
    example.sampleID = sampleID
    corrections.append(example)
    corrections = Array(corrections.suffix(RetentionLimits.corrections))
    invalidatePendingWork(.corrected(scope: scope, sender: address, label: label))
    records[index].correctedLabel = label
    var correction = DecisionRecord(
      identity: previous.identity,
      sender: address,
      subject: previous.subject,
      evidence: previous.evidence,
      decision: .init(
        label: label,
        action: Pipeline.correctionAction(label, review: settings.review),
        reason: .userCorrection(scope: scope)
      ),
      outcome: .pending,
      path: .correction,
      revision: revision
    )
    correction.correctedLabel = label
    correction.sampleID = sampleID
    correctionUndo = CorrectionUndo(
      state: before,
      source: previous,
      recordID: correction.id,
      revision: revision
    )
    record(correction)
    recordLabel(label, for: correction, linkedSampleID: linkedSampleID, message: message)
    if let trainingKey { trainingClaims[trainingKey] = correction.id }
    return (
      correction,
      Pipeline.correctionSteps(label, previous: previous, review: settings.review)
    )
  }
  /**
   Saves the rule a correction implies.

   A domain rule replaces the sender's contradicting address rule, which would otherwise take
   precedence. Review removes the sender's address rule and saves no new one.
   */
  private mutating func applyCorrectionRule(
    label: MailLabel,
    scope: RuleScope,
    address: String,
    domain: String?
  ) throws {
    guard label != .review else {
      rules.removeAll { $0.scope == .address && $0.value == address }
      return
    }
    let value: String
    switch scope {
      case .address: value = address
      case .domain:
        guard let domain else { throw CorrectionError.noRegistrableDomain(sender: address) }
        value = domain
    }
    let rule = SenderRule(
      scope: scope,
      value: value,
      disposition: label == .inbox ? .allow : .block
    )
    rules = Gates.replacing(rule, in: rules)
    if scope == .domain {
      rules.removeAll {
        $0.scope == .address && $0.value == address && $0.disposition != rule.disposition
      }
    }
  }
  /// Records the correction's reviewed label and learning under the record's sample identity.
  private mutating func recordLabel(
    _ label: MailLabel,
    for record: DecisionRecord,
    linkedSampleID: String,
    message: ParsedMessage?
  ) {
    let sampleID = record.sampleID ?? linkedSampleID
    for index in corrections.indices
    where [linkedSampleID, sampleID].contains(corrections[index].sampleID) {
      corrections[index].sampleID = sampleID
      if let message { corrections[index].quote(message.text) }
    }
    let reviewed = ReviewedLabel(
      identity: record.identity,
      label: label,
      message: settings.advancedOptions.retainReviewedContent ? message : nil,
      sampleID: sampleID
    )
    if correctionUndo?.recordID == record.id { correctionUndo?.confirmed = true }
    guard insertReviewedLabel(reviewed) else { return }
    if Pipeline.collectsLearning(settings.advancedOptions), let message {
      learning.recordCorrection(
        message: message,
        evidence: record.evidence ?? EvidenceBundle(message: message),
        label: label,
        sampleID: sampleID
      )
    }
  }
}

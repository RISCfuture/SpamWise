import Foundation

extension Pipeline {
  private static let maximumClassificationTimeSec = 15.0
  private static let maximumDomainLookupTimeSec = 3.0
  private static let minimumDomainLookupTimeSec = 0.01
  private static let domainLookupBudgetDivisor = 3.0
  private static let contactFreshnessSec = 86_400.0
  func classify(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    state: AppState,
    budget: (start: Date, timeout: Double),
    auxiliaryFindings: [String]
  ) async throws -> Classification {
    var evidence = relationshipEvidence(message, identity: identity, state: state)
    evidence.auxiliaryFindings = auxiliaryFindings.isEmpty ? nil : auxiliaryFindings
    let verdict: Verdict, path: String
    if let gate = try await deterministicGate(message, evidence: evidence, state: state) {
      path = "gate"
      verdict = Verdict(
        label: gate.disposition == .allow ? .inbox : .junk,
        confidence: 100,
        reason: gate.reason,
        usage: .init(estimated: false)
      )
    } else if state.settings.advancedOptions.fingerprints,
      state.learning?.campaignMatch(for: message) != nil
    {
      path = "fingerprint"
      verdict = Verdict(
        label: .junk,
        confidence: 100,
        reason: "gate: anchored match to explicitly junked campaign",
        usage: .init(estimated: false)
      )
    } else {
      path = "model"
      let advanced = state.settings.advancedOptions
      evidence = await enrich(
        message,
        evidence: evidence,
        settings: advanced,
        localOnly: state.settings.mailOptions.localOnly,
        timeout: budget.timeout
      )
      if advanced.bayes || advanced.learnedWeights,
        let estimate = state.learning?.estimate(message: message, evidence: evidence)
      {
        if advanced.bayes { evidence.bayesLogOdds = estimate.bayesLogOdds }
        if advanced.learnedWeights { evidence.learnedMargin = estimate.logisticMargin }
      }
      let remaining = min(
        Self.maximumClassificationTimeSec,
        budget.timeout - Date().timeIntervalSince(budget.start)
      )
      guard remaining > 0 else { throw ClassificationError.timeout }
      let input = ClassificationInput(
        message: message,
        evidence: evidence,
        policy: state.settings.policy,
        corrections: advanced.retrieveExamples
          ? CorrectionRetrieval.examples(
            for: message,
            from: state.corrections,
            limit: state.settings.correctionLimit
          )
          : state.corrections,
        correctionLimit: state.settings.correctionLimit,
        bodyTokenBudget: state.settings.bodyTokenBudget,
        timeout: remaining
      )
      let classifier = self.classifier
      verdict = try await withDeadline(seconds: remaining) {
        try await classifier.classify(input)
      }.validated()
      if advanced.bayes {
        try await trainPrediction(
          message,
          evidence: evidence,
          verdict: verdict,
          revision: state.revision
        )
      }
    }
    return Classification(verdict: verdict, evidence: evidence, path: path)
  }
  private func deterministicGate(
    _ message: ParsedMessage,
    evidence: EvidenceBundle,
    state: AppState
  ) async throws -> GateResult? {
    if let senderRule = Gates.evaluate(
      address: message.fromAddress,
      domain: evidence.fromDomain,
      rules: state.rules,
      contact: nil,
      history: .init()
    ) {
      return senderRule
    }
    if let rule = try ContentRules.matches(state.contentRules ?? [], message: message).first {
      try await StateRepository.update(store) { current in
        guard current.revision == state.revision else { return }
        if current.contentRuleHits == nil { current.contentRuleHits = [:] }
        current.contentRuleHits?[rule.id, default: 0] += 1
      }
      return GateResult(rule.disposition, "gate: user content rule \(rule.id.uuidString)")
    }
    return Gates.evaluate(
      address: message.fromAddress,
      domain: evidence.fromDomain,
      rules: [],
      contact: evidence.contact,
      history: evidence.senderHistory
    )
  }
  private func trainPrediction(
    _ message: ParsedMessage,
    evidence: EvidenceBundle,
    verdict: Verdict,
    revision: Int
  ) async throws {
    let contradiction =
      (verdict.label == .junk && (evidence.bayesLogOdds ?? 0) < 0)
      || (verdict.label == .inbox && (evidence.bayesLogOdds ?? 0) > 0)
      || (verdict.label == .inbox
        && evidence.authResults.contains { $0.trusted && $0.result == "fail" })
    try await StateRepository.update(store) { current in
      guard current.revision == revision else { return }
      var learning = current.learning ?? LearningState()
      learning.admitPrediction(
        message: message,
        evidence: evidence,
        verdict: verdict,
        hasContradiction: contradiction
      )
      current.learning = learning
    }
  }
  private func enrich(
    _ message: ParsedMessage,
    evidence: EvidenceBundle,
    settings advanced: AdvancedSettings,
    localOnly: Bool,
    timeout: Double
  ) async -> EvidenceBundle {
    var evidence = evidence
    guard !localOnly else { return evidence }
    let domain = DomainResolver().domain(ofAddress: message.fromAddress)
    if let domain, let rdap {
      evidence.domainAgeDays = try? await withDeadline(
        seconds: min(
          Self.maximumDomainLookupTimeSec,
          max(Self.minimumDomainLookupTimeSec, timeout / Self.domainLookupBudgetDivisor)
        )
      ) {
        await rdap.ageDays(domain: domain)
      }
    }
    if let configuration = advanced.externalEvidence, configuration.domainBlocklist {
      let domains =
        [domain].compactMap { $0 }
        + message.urls.compactMap {
          URL(string: $0)?.host.flatMap { DomainResolver().registrableDomain($0) }
        }
      let lookup = SpamhausDomainLookup(
        configuration: .init(
          termsAcknowledged: configuration.termsAcknowledged,
          resolverAddress: configuration.resolverAddress
        )
      )
      let findings = await lookup.lookup(domains: domains)
      evidence.auxiliaryFindings = (evidence.auxiliaryFindings ?? []) + findings.map(\.summary)
    }
    return evidence
  }
  private func relationshipEvidence(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    state: AppState
  ) -> EvidenceBundle {
    let domain = DomainResolver().domain(ofAddress: message.fromAddress)
    let excluded =
      state.settings.mailOptions.trustExclusions.contains(message.fromAddress)
      || (state.settings.mailOptions.excludeOwnAddresses
        && state.ownAddresses?.contains(message.fromAddress) == true)
    let history =
      excluded
      ? SenderHistory()
      : state.histories[identity.accountID ?? ""]?.summary(
        address: message.fromAddress,
        domain: domain
      ) ?? .init()
    let contact: Bool? =
      !excluded
        && state.contactsUpdatedAt.map { Date().timeIntervalSince($0) < Self.contactFreshnessSec }
          == true
      ? state.contactAddresses?.contains(message.fromAddress) : nil
    return EvidenceBundle(message: message, history: history, contact: contact)
  }
  struct Classification {
    var verdict: Verdict
    var evidence: EvidenceBundle
    var path: String
  }
}

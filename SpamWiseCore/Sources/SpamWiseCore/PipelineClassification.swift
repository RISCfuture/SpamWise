import Foundation

extension Pipeline {
  struct Classification {
    var verdict: Verdict
    var evidence: EvidenceBundle
    var path: String
  }
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
    if let gate = Gates.evaluate(
      address: message.fromAddress,
      domain: evidence.fromDomain,
      rules: state.rules,
      contact: evidence.contact,
      history: evidence.senderHistory
    ) {
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
        timeout: budget.timeout
      )
      if advanced.bayes || advanced.learnedWeights,
        let estimate = state.learning?.estimate(message: message, evidence: evidence)
      {
        if advanced.bayes { evidence.bayesLogOdds = estimate.bayesLogOdds }
        if advanced.learnedWeights { evidence.learnedMargin = estimate.logisticMargin }
      }
      let remaining = min(15, budget.timeout - Date().timeIntervalSince(budget.start))
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
    timeout: Double
  ) async -> EvidenceBundle {
    var evidence = evidence
    let domain = DomainResolver().domain(ofAddress: message.fromAddress)
    if let domain, let rdap {
      evidence.domainAgeDays = try? await withDeadline(
        seconds: min(3, max(0.01, timeout / 3))
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
    let history =
      state.histories[identity.accountID ?? ""]?.summary(
        address: message.fromAddress,
        domain: domain
      ) ?? .init()
    let contact: Bool? =
      state.contactsUpdatedAt.map { Date().timeIntervalSince($0) < 86_400 } == true
      ? state.contactAddresses?.contains(message.fromAddress) : nil
    return EvidenceBundle(message: message, history: history, contact: contact)
  }
}

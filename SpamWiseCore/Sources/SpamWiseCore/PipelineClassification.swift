import Foundation

extension Pipeline {
  private static let maximumClassificationTimeSec = 15.0
  private static let maximumDomainLookupTimeSec = 3.0
  private static let minimumDomainLookupTimeSec = 0.01
  private static let domainLookupBudgetDivisor = 3.0
  private static let contactFreshnessSec = 86_400.0
  private static let maximumRuleNoteCharacters = 120
  private static func decodingFindings(_ message: ParsedMessage) -> [String] {
    guard let issues = message.decodingIssues else { return [] }
    return [
      "Message decoding degraded (\(issues.map(\.rawValue).joined(separator: ", "))); "
        + "affected text may be garbled"
    ]
  }
  private static func deterministicVerdict(_ label: MailLabel, _ reason: DecisionReason) -> Verdict
  {
    Verdict(
      label: label,
      confidence: 100,
      reason: reason.diagnosticDescription,
      usage: .init(estimated: false)
    )
  }
  func classify(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    state: AppState,
    budget: (start: Date, timeout: Double),
    auxiliaryFindings: [String]
  ) async throws -> Classification {
    var evidence = relationshipEvidence(message, identity: identity, state: state)
    evidence.record(findings: Self.decodingFindings(message) + auxiliaryFindings)
    let verdict: Verdict, path: DecisionPath, reason: DecisionReason
    if let gate = try await deterministicGate(message, evidence: evidence, state: state) {
      (path, reason) = (.gate, .gate(gate.reason))
      verdict = Self.deterministicVerdict(gate.disposition == .allow ? .inbox : .junk, reason)
    } else if state.settings.advancedOptions.fingerprints,
      state.learning?.campaignMatch(for: message, evidence: evidence) != nil
    {
      (path, reason) = (.fingerprint, .campaign)
      verdict = Self.deterministicVerdict(.review, reason)
    } else {
      path = .model
      verdict = try await modelVerdict(message, evidence: &evidence, state: state, budget: budget)
      reason = .model(verdict.reason)
    }
    let threats = try await assessThreats(
      message: message,
      identity: identity,
      evidence: evidence,
      localOnly: state.settings.mailOptions.localOnly,
      remainingTimeSec: budget.timeout - Date().timeIntervalSince(budget.start)
    )
    return Classification(
      verdict: verdict,
      reason: reason,
      evidence: evidence,
      path: path,
      threats: threats
    )
  }
  private func modelVerdict(
    _ message: ParsedMessage,
    evidence: inout EvidenceBundle,
    state: AppState,
    budget: (start: Date, timeout: Double)
  ) async throws -> Verdict {
    let advanced = state.settings.advancedOptions
    evidence = await enrich(
      message,
      evidence: evidence,
      settings: advanced,
      localOnly: state.settings.mailOptions.localOnly,
      timeout: budget.timeout - Date().timeIntervalSince(budget.start)
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
    let verdict = try await withDeadline(seconds: remaining) {
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
    return verdict
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
    let contentRules = ContentRules.evaluate(state.contentRules ?? [], message: message)
    try? await record(contentRules, revision: state.revision)
    if let rule = contentRules.decisive {
      let note = rule.note.trimmingCharacters(in: .whitespacesAndNewlines)
      return GateResult(
        rule.disposition,
        .contentRule(
          id: rule.id,
          disposition: rule.disposition,
          note: note.isEmpty ? nil : String(note.prefix(Self.maximumRuleNoteCharacters))
        )
      )
    }
    return Gates.evaluate(
      address: message.fromAddress,
      domain: evidence.fromDomain,
      rules: [],
      contact: evidence.contact,
      history: evidence.senderHistory,
      authentication: evidence.senderAuthentication
    )
  }
  private func record(_ contentRules: ContentRuleEvaluation, revision: Int) async throws {
    let winner = contentRules.decisive?.id,
      skipped = contentRules.skipped.keys.map { ($0, 1) }
    guard winner != nil || !skipped.isEmpty else { return }
    try await StateRepository.update(store) { current in
      guard current.revision == revision else { return }
      if let winner {
        current.contentRuleHits = (current.contentRuleHits ?? [:]).merging(
          [winner: 1],
          uniquingKeysWith: +
        )
      }
      if !skipped.isEmpty {
        current.contentRuleSkips = (current.contentRuleSkips ?? [:]).merging(
          skipped,
          uniquingKeysWith: +
        )
      }
    }
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
    guard !localOnly, !Task.isCancelled, timeout.isFinite, timeout > 0 else { return evidence }
    let start = Date()
    let domain = DomainResolver().domain(ofAddress: message.fromAddress)
    if advanced.domainRegistrationLookup == true, let domain, let rdap {
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
      let lookup = SpamhausDomainLookup(
        configuration: .init(
          termsAcknowledged: configuration.termsAcknowledged,
          resolverAddress: configuration.resolverAddress,
          transport: configuration.spamhausTransport ?? .publicDNS
        ),
        key: { try APIKeychain(service: APIKeychain.spamhausService).read() }
      )
      let findings = await lookup.lookup(
        domains: evidence.reputationDomains,
        timeout: max(0, timeout - Date().timeIntervalSince(start))
      )
      evidence.record(findings: findings.map(\.summary))
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
    var reason: DecisionReason
    var evidence: EvidenceBundle
    var path: DecisionPath
    var threats: ThreatAssessment
  }
}

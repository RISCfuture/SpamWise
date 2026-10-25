import Foundation

extension Pipeline {
  private static let maximumClassificationTimeSec = 15.0
  private static let maximumDomainLookupTimeSec = 3.0
  private static let minimumDomainLookupTimeSec = 0.01
  private static let domainLookupBudgetDivisor = 3.0
  private static let contactFreshnessSec = 86_400.0
  private static let maximumRuleNoteCharacters = 120
  private static let unconfirmedContentAllowFinding =
    "A user content Allow rule matched, but trusted authentication did not confirm the sender"

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
  /// The scope of the sender's matching Allow rule when trusted authentication did not confirm it.
  private static func unconfirmedAllowRule(
    _ message: ParsedMessage,
    rules: [SenderRule],
    evidence: EvidenceBundle
  ) -> RuleScope? {
    guard evidence.senderAuthentication != .alignedPass,
      let rule = Gates.matchingRule(
        address: message.fromAddress,
        domain: evidence.fromDomain,
        rules: rules
      ), rule.disposition == .allow
    else { return nil }
    return rule.scope
  }
  /**
   The sender rule, content rule or authenticated relationship that decides the message, with
   the content-rule counts the evaluation adds.

   Content fields are sender-controlled, so a content Allow rule decides only when trusted
   authentication confirms the sender. Otherwise it reaches the classifier as evidence and, like
   an unconfirmed address Allow rule, ends the evaluation.
   */
  private static func deterministicGate(
    _ message: ParsedMessage,
    evidence: inout EvidenceBundle,
    state: AppState
  ) -> (gate: GateResult?, tally: ContentRuleTally) {
    if let senderRule = Gates.evaluate(
      address: message.fromAddress,
      domain: evidence.fromDomain,
      rules: state.rules,
      contact: nil,
      history: .init(),
      authentication: evidence.senderAuthentication
    ) {
      return (senderRule, ContentRuleTally())
    }
    let contentRules = ContentRules.evaluate(state.contentRules, message: message)
    var tally = ContentRuleTally(skipped: Array(contentRules.skipped.keys))
    if let rule = contentRules.decisive {
      guard rule.disposition == .block || evidence.senderAuthentication == .alignedPass else {
        evidence.record(findings: [unconfirmedContentAllowFinding])
        return (nil, tally)
      }
      tally.winner = rule.id
      let note = rule.note.trimmingCharacters(in: .whitespacesAndNewlines)
      let reason = GateReason.contentRule(
        id: rule.id,
        disposition: rule.disposition,
        note: note.isEmpty ? nil : String(note.prefix(maximumRuleNoteCharacters))
      )
      return (GateResult(rule.disposition, reason), tally)
    }
    let relationship = Gates.evaluate(
      address: message.fromAddress,
      domain: evidence.fromDomain,
      rules: [],
      contact: evidence.contact,
      history: evidence.senderHistory,
      authentication: evidence.senderAuthentication
    )
    return (relationship, tally)
  }
  /// Whether the model's verdict contradicts the Bayes estimate or failed authentication.
  private static func contradictsSignals(_ classification: Classification) -> Bool {
    let label = classification.verdict.label, evidence = classification.evidence
    return (label == .junk && (evidence.bayesLogOdds ?? 0) < 0)
      || (label == .inbox && (evidence.bayesLogOdds ?? 0) > 0)
      || (label == .inbox && evidence.senderAuthentication == .failed)
  }
  /**
   Classifies a parsed message with its gates, fingerprints or the model.

   - Parameters:
     - auxiliaryFindings: Evidence summaries for the classifier; gains the local Rspamd finding
       once the scan runs, so a retry of this message keeps it.
     - raw: The message as received, for the local Rspamd scan; nil skips the scan.
   */
  func classify(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    state: AppState,
    budget: (start: Date, timeout: Double),
    auxiliaryFindings: inout [String],
    raw: Data?
  ) async throws -> Classification {
    await observeReceivingServers(message, identity: identity, settings: state.settings)
    var evidence = relationshipEvidence(message, identity: identity, state: state)
    evidence.record(findings: Self.decodingFindings(message) + auxiliaryFindings)
    let screening = Self.deterministicGate(message, evidence: &evidence, state: state)
    let verdict: Verdict, path: DecisionPath, reason: DecisionReason
    var trainsPrediction = false
    if let gate = screening.gate {
      (path, reason) = (.gate, .gate(gate.reason))
      verdict = Self.deterministicVerdict(gate.disposition == .allow ? .inbox : .junk, reason)
    } else if state.settings.advancedOptions.fingerprints,
      state.learning.campaignMatch(for: message, evidence: evidence) != nil
    {
      (path, reason) = (.fingerprint, .campaign)
      verdict = Self.deterministicVerdict(.review, reason)
    } else {
      path = .model
      verdict = try await modelVerdict(
        message,
        identity: identity,
        evidence: &evidence,
        state: state,
        budget: budget,
        raw: raw,
        findings: &auxiliaryFindings
      )
      reason = .model(verdict.reason)
      trainsPrediction = state.settings.advancedOptions.bayes && verdict != .oversizedContext
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
      threats: threats,
      contentRuleTally: screening.tally,
      trainsPrediction: trainsPrediction
    )
  }
  /**
   Saves a classified record with the content-rule counts and Bayes training its classification
   adds, which apply only while the policy it was classified under is current.

   - Parameter recordsStatistics: Whether the classification counts toward content-rule
     statistics and training; a manual preview's does not.
   */
  func save(
    _ record: DecisionRecord,
    of message: ParsedMessage,
    classification: Classification,
    recordsStatistics: Bool
  ) async throws {
    let tally = recordsStatistics ? classification.contentRuleTally : ContentRuleTally()
    let trains = recordsStatistics && classification.trainsPrediction
    var parts: StateSlices.Parts = []
    if !tally.isEmpty { parts.insert(.contentRules) }
    if trains { parts.insert(.learning) }
    try await StateRepository.update(
      store,
      loading: StateSlices(parts, records: .only([record.id]))
    ) { state in
      state.record(record)
      guard state.revision == record.revision else { return }
      state.count(tally)
      if trains {
        state.learning.admitPrediction(
          message: message,
          evidence: classification.evidence,
          verdict: classification.verdict,
          hasContradiction: Self.contradictsSignals(classification)
        )
      }
    }
  }
  /// Gathers the model's evidence and asks the classifier, once the spending limit leaves room.
  private func modelVerdict(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    evidence: inout EvidenceBundle,
    state: AppState,
    budget: (start: Date, timeout: Double),
    raw: Data?,
    findings: inout [String]
  ) async throws -> Verdict {
    let advanced = state.settings.advancedOptions
    let preflight = classificationInput(message, evidence, identity, state, timeout: 0)
    guard await spendingAdmits(preflight) else { throw SpendingLimitError.limitReached }
    evidence = await enrich(
      message,
      evidence: evidence,
      raw: raw,
      findings: &findings,
      settings: advanced,
      localOnly: state.settings.mailOptions.localOnly,
      timeout: budget.timeout - Date().timeIntervalSince(budget.start)
    )
    if advanced.bayes || advanced.learnedWeights {
      let estimate = state.learning.estimate(message: message, evidence: evidence)
      if advanced.bayes { evidence.bayesLogOdds = estimate.bayesLogOdds }
      if advanced.learnedWeights { evidence.learnedMargin = estimate.logisticMargin }
    }
    let remaining = min(
      Self.maximumClassificationTimeSec,
      budget.timeout - Date().timeIntervalSince(budget.start)
    )
    guard remaining > 0 else { throw ClassificationError.timeout }
    let input = classificationInput(message, evidence, identity, state, timeout: remaining)
    let classifier = self.classifier
    do {
      return try await withDeadline(seconds: remaining) {
        try await classifier.classify(input)
      }.validated()
    } catch ClassificationError.evidenceExceedsPrompt {
      return .oversizedContext
    }
  }
  private func classificationInput(
    _ message: ParsedMessage,
    _ evidence: EvidenceBundle,
    _ identity: MessageIdentity,
    _ state: AppState,
    timeout: Double
  ) -> ClassificationInput {
    ClassificationInput(
      message: message,
      evidence: evidence,
      categoryPreferences: state.settings.categoryPreferences,
      policy: state.settings.policy,
      corrections: CorrectionRetrieval.examples(
        for: message,
        from: state.corrections.filter { $0.isQuotable(inAccount: identity.accountID) },
        limit: state.settings.correctionLimit,
        senderAuthenticated: evidence.senderAuthentication == .alignedPass
      ),
      correctionLimit: state.settings.correctionLimit,
      bodyTokenBudget: state.settings.bodyTokenBudget,
      timeout: timeout
    )
  }
  /// Whether the classifier's spending limit leaves room for `input`; a failed check leaves it to the classifier.
  private func spendingAdmits(_ input: ClassificationInput) async -> Bool {
    guard let admission = classifier as? any SpendingAdmission else { return true }
    return (try? await admission.admits(input)) ?? true
  }
  /**
   Evidence with the optional local scan and network lookups, none of which run in local-only
   mode; the local scan's finding is also added to `findings`.
   */
  private func enrich(
    _ message: ParsedMessage,
    evidence: EvidenceBundle,
    raw: Data?,
    findings: inout [String],
    settings advanced: AdvancedSettings,
    localOnly: Bool,
    timeout: Double
  ) async -> EvidenceBundle {
    var evidence = evidence
    guard !localOnly, !Task.isCancelled, timeout.isFinite, timeout > 0 else { return evidence }
    let start = Date()
    if let raw, advanced.externalEvidence?.localRspamd == true {
      let finding = await rspamdScan(raw, timeout).summary
      findings.append(finding)
      evidence.record(findings: [finding])
    }
    let domain = DomainResolver().domain(ofAddress: message.fromAddress)
    if advanced.domainRegistrationLookup, let domain, let rdap {
      evidence.domainAgeDays = try? await withDeadline(
        seconds: min(
          Self.maximumDomainLookupTimeSec,
          max(
            Self.minimumDomainLookupTimeSec,
            (timeout - Date().timeIntervalSince(start)) / Self.domainLookupBudgetDivisor
          )
        )
      ) {
        await rdap.ageDays(domain: domain)
      }
    }
    if let configuration = advanced.externalEvidence, configuration.domainBlocklist {
      let lookup = spamhaus(
        SpamhausConfiguration(
          termsAcknowledged: configuration.termsAcknowledged,
          resolverAddress: configuration.resolverAddress,
          transport: configuration.spamhausTransport ?? .publicDNS
        )
      )
      let blocklisted = await lookup.lookup(
        domains: evidence.reputationDomains,
        timeout: max(0, timeout - Date().timeIntervalSince(start))
      )
      evidence.record(findings: blocklisted.map(\.summary))
    }
    return evidence
  }
  /**
   Evidence with the account's relationships and its trusted receiving servers' results.

   Relationships and a matching Allow rule decide a message only for an authenticated sender;
   the evidence records them either way so the classifier receives those it did not decide.
   */
  private func relationshipEvidence(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    state: AppState
  ) -> EvidenceBundle {
    let domain = DomainResolver().domain(ofAddress: message.fromAddress)
    let excluded =
      state.settings.mailOptions.trustExclusions.contains(message.fromAddress)
      || (state.settings.mailOptions.excludeOwnAddresses
        && state.ownAddresses.contains(message.fromAddress))
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
    var evidence = EvidenceBundle(
      message: message,
      history: history,
      contact: contact,
      trustedAuthServers: state.settings.mailOptions.trustedAuthServers(for: identity.accountID)
    )
    evidence.unconfirmedAllowRule = Self.unconfirmedAllowRule(
      message,
      rules: state.rules,
      evidence: evidence
    )
    return evidence
  }
  struct Classification: Sendable {
    var verdict: Verdict
    var reason: DecisionReason
    var evidence: EvidenceBundle
    var path: DecisionPath
    var threats: ThreatAssessment?
    /// Content-rule counts this classification adds once its record is saved.
    var contentRuleTally: ContentRuleTally
    /// Whether the verdict is offered to Bayes training once its record is saved.
    var trainsPrediction: Bool

    /// The pending decision record that applies the current policy to this classification.
    func record(
      of message: ParsedMessage,
      identity: MessageIdentity,
      settings: Settings,
      revision: Int,
      latency: Double
    ) throws -> DecisionRecord {
      let decision = try Decision.evaluate(
        verdict,
        reason: reason,
        strength: settings.strength,
        review: settings.review,
        concealsContent: path == .model && message.concealsContent,
        preference: path == .model ? settings.categoryPreferences[verdict.category] : nil
      )
      var record = DecisionRecord(
        identity: identity,
        sender: message.fromAddress,
        subject: message.subject,
        evidence: evidence,
        verdict: verdict,
        threats: threats,
        decision: decision,
        outcome: .pending,
        path: path,
        latency: latency,
        revision: revision
      )
      record.sampleID = LearningSample.identity(for: message)
      return record
    }
  }
}

/// Content-rule statistics one classification adds.
struct ContentRuleTally: Sendable {
  /// The rule that decided the message.
  var winner: UUID?
  /// Rules that were invalid or timed out.
  var skipped: [UUID] = []

  var isEmpty: Bool { winner == nil && skipped.isEmpty }
}

extension AppState {
  fileprivate mutating func count(_ tally: ContentRuleTally) {
    if let winner = tally.winner { contentRuleHits[winner, default: 0] += 1 }
    contentRuleSkips.merge(tally.skipped.map { ($0, 1) }, uniquingKeysWith: +)
  }
}

import Foundation

public actor Pipeline {
    private let store: Store
    private let classifier: any Classifier
    private let rdap: RDAPLookup?
    private var inFlight: Set<String> = []
    public init(store: Store, classifier: any Classifier, rdap: RDAPLookup? = nil) {
        self.store = store; self.classifier = classifier; self.rdap = rdap
    }
    public func process(_ envelope: MailEnvelope, adapter: (any MailClientAdapter)? = nil, forceDryRun: Bool = false, timeout: Double = 15) async -> DecisionRecord {
        do {
            let message = try MIMEParser().parse(envelope.raw)
            return await process(message, identity: envelope.identity, adapter: adapter, forceDryRun: forceDryRun, timeout: timeout)
        } catch {
            let record = failure(identity: envelope.identity, reason: "unclassified: message parsing failed")
            try? await save(record); return record
        }
    }
    public func process(_ message: ParsedMessage, identity: MessageIdentity, adapter: (any MailClientAdapter)? = nil, forceDryRun: Bool = false, timeout: Double = 15, attempt: Int = 0) async -> DecisionRecord {
        guard inFlight.insert(identity.key).inserted else {
            var record = failure(identity: identity, reason: "Duplicate callback already in progress"); record.outcome = .duplicate; return record
        }
        defer { inFlight.remove(identity.key) }
        let start = Date()
        var revision = 0
        do {
            try Task.checkCancellation()
            let state = try await StateRepository.load(store); revision = state.revision
            if let id = state.claimedActions[identity.key], let previous = state.records.first(where: { $0.id == id }) { return previous }
            if state.settings.paused {
                let record = DecisionRecord(identity: identity, sender: message.fromAddress, subject: message.subject, decision: .init(label: nil, action: .none, reason: "Filtering paused"), outcome: .paused, revision: revision)
                try await save(record); return record
            }
            let domain = DomainResolver().domain(ofAddress: message.fromAddress)
            let history = state.histories[identity.accountID ?? ""]?.summary(address: message.fromAddress, domain: domain) ?? .init()
            let contact: Bool? = state.contactsUpdatedAt.map { Date().timeIntervalSince($0) < 86_400 } == true ? state.contactAddresses?.contains(message.fromAddress) : nil
            var evidence = EvidenceBundle(message: message, history: history, contact: contact)
            let verdict: Verdict, path: String
            if let gate = Gates.evaluate(address: message.fromAddress, domain: domain, rules: state.rules, contact: contact, history: history) {
                path = "gate"; verdict = Verdict(label: gate.disposition == .allow ? .inbox : .junk, confidence: 100, reason: gate.reason, usage: .init(estimated: false))
            } else {
                path = "model"
                if let domain, let rdap {
                    evidence.domainAgeDays = try? await withDeadline(seconds: min(3, max(0.01, timeout / 3))) { await rdap.ageDays(domain: domain) }
                }
                let remaining = min(15, timeout - Date().timeIntervalSince(start))
                guard remaining > 0 else { throw ClassificationError.timeout }
                let input = ClassificationInput(message: message, evidence: evidence, policy: state.settings.policy, corrections: state.corrections, correctionLimit: state.settings.correctionLimit, bodyTokenBudget: state.settings.bodyTokenBudget, timeout: remaining)
                let classifier = self.classifier
                verdict = try await withDeadline(seconds: remaining) { try await classifier.classify(input) }.validated()
            }
            try Task.checkCancellation()
            guard Date().timeIntervalSince(start) < timeout else { throw ClassificationError.timeout }
            let decision = try Decision.evaluate(verdict, strength: state.settings.strength, review: state.settings.review)
            var record = DecisionRecord(identity: identity, sender: message.fromAddress, subject: message.subject, evidence: evidence, verdict: verdict, decision: decision, outcome: .pending, path: path, latency: Date().timeIntervalSince(start), revision: revision)
            // Persist the explanation before an external action can be claimed.
            try await save(record)
            record = try await dispatch(record, adapter: adapter, forceDryRun: forceDryRun)
            return record
        } catch {
            let reason: String
            if let error = error as? ClassificationError { reason = error.rawValue }
            else if error is CancellationError { reason = "cancelled" }
            else { reason = "persistence or integration unavailable" }
            let record = failure(identity: identity, sender: message.fromAddress, subject: message.subject, reason: "unclassified: " + reason, revision: revision)
            try? await save(record)
            if let error = error as? ClassificationError, error.retryable, attempt < 3, !Task.isCancelled {
                var bounded = message; bounded.text = String(message.text.prefix(16_000))
                let retryMessage = bounded
                let retryRevision = revision
                try? await StateRepository.update(store) { state in
                    guard state.revision == retryRevision else { return }
                    state.retries.removeAll { $0.id == identity.key }
                    guard state.retries.count < 100 else { return }
                    state.retries.append(RetryJob(identity: identity, message: retryMessage, revision: retryRevision, attempt: attempt + 1, due: Date().addingTimeInterval(30 * pow(2, Double(attempt))), expires: Date().addingTimeInterval(86_400), dryRun: forceDryRun))
                }
            }
            return record
        }
    }
    public func retryDue(adapter: any MailClientAdapter, now: Date = .now) async {
        guard let jobs = try? await StateRepository.update(store, { state -> [RetryJob] in
            let jobs = state.retries.filter { $0.due <= now && $0.expires > now && $0.revision == state.revision }
            state.retries.removeAll { $0.due <= now || $0.expires <= now || $0.revision != state.revision }
            return jobs
        }) else { return }
        for job in jobs {
            guard !Task.isCancelled else { return }
            _ = await process(job.message, identity: job.identity, adapter: adapter, forceDryRun: job.dryRun, attempt: job.attempt)
        }
    }
    public func correct(recordID: UUID, label: MailLabel, scope: RuleScope = .address, adapter: (any MailClientAdapter)? = nil) async throws -> DecisionRecord {
        guard label != .review else { throw ClassificationError.invalidOutput }
        let record = try await StateRepository.update(store) { state -> DecisionRecord in
            guard let i = state.records.firstIndex(where: { $0.id == recordID }) else { throw IntegrationError.unavailable }
            let previous = state.records[i]
            guard let address = MIMEParser.address(previous.sender) else { throw IntegrationError.unavailable }
            let domain = DomainResolver().domain(ofAddress: address)
            guard scope != .domain || domain != nil else { throw IntegrationError.unavailable }
            let rule = SenderRule(scope: scope, value: scope == .address ? address : domain!, disposition: label == .inbox ? .allow : .block)
            state.rules = Gates.replacing(rule, in: state.rules)
            state.corrections.append(CorrectionExample(sender: address, domain: domain, subject: previous.subject, gist: previous.decision.reason, label: label))
            state.corrections = Array(state.corrections.suffix(200))
            state.revision += 1
            state.retries.removeAll() // Any old prompt/evidence generation is stale after a correction.
            state.records[i].correctedLabel = label
            var correction = DecisionRecord(identity: previous.identity, sender: address, subject: previous.subject, evidence: previous.evidence,
                decision: .init(label: label, action: label == .inbox ? .moveToInbox : .moveToJunk, reason: "User correction (\(scope.rawValue))"), outcome: .pending, path: "correction", revision: state.revision)
            correction.correctedLabel = label
            state.records.append(correction)
            return correction
        }
        return try await dispatch(record, adapter: adapter, forceDryRun: false, correction: true)
    }
    private func dispatch(_ original: DecisionRecord, adapter: (any MailClientAdapter)?, forceDryRun: Bool, correction: Bool = false) async throws -> DecisionRecord {
        let claimed = try await StateRepository.update(store) { state -> DecisionRecord in
            guard let i = state.records.firstIndex(where: { $0.id == original.id }) else { throw IntegrationError.unavailable }
            var record = state.records[i]
            if state.revision != record.revision { record.outcome = .superseded }
            else if state.settings.paused { record.outcome = .paused }
            else if record.decision.action == .none { record.outcome = .noAction }
            else if forceDryRun || state.settings.dryRun { record.outcome = .dryRun }
            else if !correction && state.claimedActions[record.identity.key] != nil { record.outcome = .duplicate }
            else if adapter == nil || record.identity.accountID == nil || !state.settings.validatedAccounts.contains(record.identity.accountID ?? "") || state.settings.route == .unverified { record.outcome = .integrationUnavailable }
            else {
                record.outcome = .requested
                state.claimedActions[record.identity.key] = record.id
            }
            state.records[i] = record
            state.retries.removeAll { $0.identity.key == record.identity.key }
            return record
        }
        guard claimed.outcome == .requested, let adapter else { return claimed }
        var completed = claimed
        do {
            try Task.checkCancellation()
            let current = try await StateRepository.load(store)
            guard current.revision == claimed.revision, !current.settings.paused, !current.settings.dryRun else { completed.outcome = .superseded; try await save(completed); return completed }
            let receipt = try await adapter.perform(claimed.decision.action, for: claimed.identity)
            completed.outcome = receipt.confirmed ? .applied : .requested
        } catch {
            completed.outcome = .failed
            completed.actionError = (error as? IntegrationError)?.localizedDescription ?? "Action failed or was cancelled; delivery status unknown. Not retried."
        }
        try await save(completed)
        return completed
    }
    private func save(_ record: DecisionRecord) async throws {
        try await StateRepository.update(store) { state in
            if let i = state.records.firstIndex(where: { $0.id == record.id }) { state.records[i] = record }
            else { state.records.append(record) }
            // Keep claims permanently, even when old display records age out.
            state.records = Array(state.records.suffix(5000))
        }
    }
    private func failure(identity: MessageIdentity, sender: String = "Unknown", subject: String = "Unclassified message", reason: String, revision: Int = 0) -> DecisionRecord {
        DecisionRecord(identity: identity, sender: sender, subject: subject, decision: .init(label: nil, action: .none, reason: reason), outcome: .unclassified, revision: revision)
    }
}

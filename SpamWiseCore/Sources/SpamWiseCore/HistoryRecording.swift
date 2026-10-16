public import Foundation

/// Why an Inbox message may contribute relationship history.
public enum InboxEligibility: Sendable {
  /// SpamWise's latest decision kept the message in the Inbox.
  case classified
  /// The user corrected or reviewed the message as wanted Inbox mail.
  case confirmed
}

extension HistoryIndex {
  private static let receiptSubjects = ["order confirmation", "your receipt"]
  private static let receiptAmountPattern = #"(?:\$|USD|EUR)\s*\d"#

  /// Whether a message reads like an order receipt: a receipt subject and an order amount.
  public static func isLikelyReceipt(_ message: ParsedMessage) -> Bool {
    let subject = message.subject.lowercased(), body = message.text.lowercased()
    return receiptSubjects.contains { subject.contains($0) } && body.contains("order")
      && body.range(of: receiptAmountPattern, options: [.regularExpression, .caseInsensitive])
        != nil
  }

  /// The To and Cc addresses of a sent reply; empty when the headers carry no In-Reply-To.
  public static func repliedAddresses(in headers: [String: [String]]) -> [String] {
    guard headers["in-reply-to"] != nil else { return [] }
    return ((headers["to"] ?? []) + (headers["cc"] ?? [])).flatMap {
      Mailbox.list($0).map(\.address)
    }
  }

  /// The `received` key: the exact address at a shared mailbox provider, otherwise the domain.
  static func receivedKey(address: String, domain: String?) -> String {
    guard let domain, !SharedMailboxDomains.contains(domain) else { return address }
    return domain
  }
  private static func incrementing(_ counts: [String: Int]?, _ address: String) -> [String: Int] {
    var counts = counts ?? [:]
    counts[address, default: 0] += 1
    return counts
  }

  /**
   Merges newly read history envelopes into this index, counting each message at most once.

   Sent mail contributes only its reply headers. Inbox mail contributes only when `eligible`
   lists it; unparseable envelopes and messages already counted are skipped without parsing. The
   update time changes only when something new was counted.

   - Parameters:
     - sent: Sent messages; headers alone suffice.
     - inbox: Inbox messages with their full source.
     - eligible: Inbox eligibility by identity key; no other Inbox message contributes, and only
       confirmed receipts can authenticate their sender.
     - trustedAuthServers: Reporting servers whose authentication results a receipt must pass.
     - now: The update time recorded on the index.
   */
  public mutating func ingest(
    sent: [MailEnvelope],
    inbox: [MailEnvelope] = [],
    eligible: [String: InboxEligibility] = [:],
    trustedAuthServers: Set<String> = [],
    now: Date = .now
  ) {
    let before = self
    for envelope in sent {
      guard let headers = try? MIMEParser().headers(envelope.raw),
        importedIDs.insert("sent:" + envelope.identity.key).inserted
      else { continue }
      for address in Self.repliedAddresses(in: headers) { replied[address, default: 0] += 1 }
    }
    for envelope in inbox where !isCounted(envelope, eligibility: eligible[envelope.identity.key]) {
      guard let eligibility = eligible[envelope.identity.key],
        let message = try? MIMEParser().parse(envelope.raw)
      else { continue }
      recordReceived(
        message,
        identityKey: envelope.identity.key,
        eligibility: eligibility,
        trustedAuthServers: trustedAuthServers
      )
    }
    guard self != before || availability != .partial else { return }
    availability = .partial; updatedAt = now
  }

  /// Whether an Inbox message already counted as far as its eligibility allows.
  private func isCounted(_ envelope: MailEnvelope, eligibility: InboxEligibility?) -> Bool {
    let key = envelope.identity.key
    return importedIDs.contains("inbox:" + key)
      && (eligibility != .confirmed || importedIDs.contains("confirmed:" + key))
  }

  /**
   Counts an eligible incoming message once toward its sender's relationship history.

   A receipt counts only for its exact address and never for a shared mailbox provider. It also
   counts once as authenticated after the user confirmed it and trusted servers report an aligned
   authentication pass, even when the message was first counted before that confirmation.
   */
  private mutating func recordReceived(
    _ message: ParsedMessage,
    identityKey: String,
    eligibility: InboxEligibility,
    trustedAuthServers: Set<String>
  ) {
    let address = message.fromAddress
    guard let domain = DomainResolver().domain(ofAddress: address) else { return }
    let isReceipt = Self.isLikelyReceipt(message) && !SharedMailboxDomains.contains(domain)
    if importedIDs.insert("inbox:" + identityKey).inserted {
      received[Self.receivedKey(address: address, domain: domain), default: 0] += 1
      if isReceipt { senderReceipts = Self.incrementing(senderReceipts, address) }
    }
    guard isReceipt, eligibility == .confirmed,
      EvidenceBundle(message: message, trustedAuthServers: trustedAuthServers)
        .senderAuthentication == .alignedPass,
      importedIDs.insert("confirmed:" + identityKey).inserted
    else { return }
    authenticatedSenderReceipts = Self.incrementing(authenticatedSenderReceipts, address)
  }
}

/// Merges history into the stored per-account indexes.
public enum HistoryRepository {
  /// Merges envelopes into the account's stored index, keeping everything it already counted.
  public static func ingest(
    accountID: String,
    sent: [MailEnvelope],
    inbox: [MailEnvelope] = [],
    eligible: [String: InboxEligibility] = [:],
    trustedAuthServers: Set<String> = [],
    in store: Store
  ) async throws {
    try await StateRepository.update(
      store,
      loading: StateSlices([.historyImports], histories: .only([accountID]))
    ) { state in
      state.histories[accountID, default: HistoryIndex()].ingest(
        sent: sent,
        inbox: inbox,
        eligible: eligible,
        trustedAuthServers: trustedAuthServers
      )
    }
  }
}

extension AppState {
  /**
   Inbox eligibility, by identity key, of messages whose latest decision, correction or reviewed
   label is Inbox and that have no pending retry.

   A reviewed label takes precedence over the Activity record of the same message.
   */
  public var historyEligibleInbox: [String: InboxEligibility] {
    Self.historyEligibleInbox(
      decisions: records.filter { $0.outcome != .superseded }.map {
        InboxDecision(
          key: $0.identity.key,
          corrected: $0.correctedLabel,
          decided: $0.decision.label
        )
      },
      reviewedLabels: reviewedLabels,
      retries: retries
    )
  }
  /// Inbox eligibility from decisions in date order, with reviewed labels and retries applied.
  static func historyEligibleInbox(
    decisions: [InboxDecision],
    reviewedLabels: [ReviewedLabel],
    retries: [RetryJob]
  ) -> [String: InboxEligibility] {
    var latest: [String: (label: MailLabel?, eligibility: InboxEligibility)] = [:]
    for decision in decisions {
      latest[decision.key] =
        decision.corrected.map { ($0, .confirmed) } ?? (decision.decided, .classified)
    }
    for reviewed in reviewedLabels {
      latest[reviewed.identity.key] = (reviewed.label, .confirmed)
    }
    for retry in retries { latest[retry.identity.key] = nil }
    return latest.compactMapValues { $0.label == .inbox ? $0.eligibility : nil }
  }
}

/// The labels of one retained decision that determine its message's Inbox eligibility.
struct InboxDecision: Sendable {
  /// Account-scoped message identity key.
  let key: String
  /// The user's explicit correction, if any.
  let corrected: MailLabel?
  /// The decided label, when classified.
  let decided: MailLabel?
}

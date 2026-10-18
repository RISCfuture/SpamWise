import Foundation

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

  private static func isReceipt(_ message: ParsedMessage) -> Bool {
    let subject = message.subject.lowercased(), body = message.text.lowercased()
    return receiptSubjects.contains { subject.contains($0) } && body.contains("order")
      && body.range(of: receiptAmountPattern, options: [.regularExpression, .caseInsensitive])
        != nil
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
   Counts an eligible incoming message once toward its sender's relationship history.

   A receipt counts only for its exact address and never for a shared mailbox provider. It also
   counts once as authenticated after the user confirmed it and trusted servers report an aligned
   authentication pass, even when the message was first counted before that confirmation.

   - Parameter identityKey: The message's account-scoped identity key, which deduplicates counts.
   */
  public mutating func recordReceived(
    _ message: ParsedMessage,
    identityKey: String,
    eligibility: InboxEligibility,
    trustedAuthServers: Set<String>
  ) {
    let address = message.fromAddress
    guard let domain = DomainResolver().domain(ofAddress: address) else { return }
    let isReceipt = Self.isReceipt(message) && !SharedMailboxDomains.contains(domain)
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
  /// Counts the To and Cc recipients of a sent reply as correspondents.
  public mutating func recordSent(headers: [String: [String]]) {
    guard headers["in-reply-to"] != nil else { return }
    for value in (headers["to"] ?? []) + (headers["cc"] ?? []) {
      for address in Mailbox.list(value).map(\.address) {
        replied[address, default: 0] += 1
      }
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
    var latest: [String: (label: MailLabel?, eligibility: InboxEligibility)] = [:]
    for record in records where record.outcome != .superseded {
      latest[record.identity.key] =
        record.correctedLabel.map { ($0, .confirmed) } ?? (record.decision.label, .classified)
    }
    for reviewed in reviewedLabels ?? [] {
      latest[reviewed.identity.key] = (reviewed.label, .confirmed)
    }
    for retry in retries { latest[retry.identity.key] = nil }
    return latest.compactMapValues { $0.label == .inbox ? $0.eligibility : nil }
  }
}

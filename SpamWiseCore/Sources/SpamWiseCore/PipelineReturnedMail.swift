import Foundation

extension Pipeline {
  /// Whether an envelope read from an Inbox page names that Inbox: IMAP calls it INBOX, while Mail names each account's Inbox itself.
  private static func isInInbox(_ identity: MessageIdentity) -> Bool {
    guard let mailbox = identity.mailbox else { return false }
    return identity.mailboxValidity == nil || mailbox.uppercased() == "INBOX"
  }

  private static func isSettledUncorrectedJunkMove(_ record: DecisionRecord) -> Bool {
    record.decision.action == .moveToJunk && record.outcome == .applied && record.actionSettled
      && record.correctedLabel == nil
  }

  /**
   Treats messages found in Inbox after a confirmed SpamWise Junk move as implicit Good corrections.

   Such a message was rescued by the user, through Mail's Not Junk or a move in Mail or another
   client. Its identity key and action claim are unchanged, so it is never classified or junked
   again; the correction also records the sender as wanted, and its Inbox step acts only on the
   message where it was just seen. A move not yet recorded as settled is left alone, because its
   provider may have reverted it. Failures leave the message and its records as they are.

   - Parameter envelopes: Messages just read from their accounts' Inboxes.
   - Returns: The correction records that were saved.
   */
  public func correctMailReturnedFromJunk(
    _ envelopes: [MailEnvelope],
    adapter: (any MailClientAdapter)?
  ) async -> [DecisionRecord] {
    var corrections: [DecisionRecord] = []
    for envelope in envelopes where Self.isInInbox(envelope.identity) {
      guard !Task.isCancelled else { break }
      guard let recordID = try? await adoptReturnedIdentity(envelope.identity),
        let correction = try? await correct(
          CorrectionRequest(
            recordID: recordID,
            label: .inbox,
            scope: .address,
            searchesAccount: false
          ),
          adapter: adapter,
          message: try? MIMEParser().parse(envelope.raw)
        )
      else { continue }
      corrections.append(correction)
    }
    return corrections
  }

  /// Points a confirmed, settled Junk move's record at the message's Inbox location; nil when the message was not moved by SpamWise.
  private func adoptReturnedIdentity(_ identity: MessageIdentity) async throws -> UUID? {
    try await StateRepository.transaction(store) { transaction -> UUID? in
      try transaction.loadClaim(for: identity)
      guard let id = transaction.state.claimedActions[identity.key],
        let index = transaction.state.records.firstIndex(where: { $0.id == id }),
        Self.isSettledUncorrectedJunkMove(transaction.state.records[index]),
        transaction.state.records[index].identity.mailbox != identity.mailbox
      else { return nil }
      transaction.state.records[index].identity = identity
      try transaction.commit()
      return id
    }
  }
}

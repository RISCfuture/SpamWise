import Foundation

extension Pipeline {
  private static func isInIMAPInbox(_ identity: MessageIdentity) -> Bool {
    identity.mailboxValidity != nil && identity.mailbox?.uppercased() == "INBOX"
  }

  private static func isUncorrectedJunkMove(_ record: DecisionRecord) -> Bool {
    record.decision.action == .moveToJunk && record.outcome == .applied
      && record.correctedLabel == nil
  }

  /**
   Treats IMAP messages found in Inbox after a confirmed SpamWise Junk move as implicit Good corrections.

   Such a message was rescued in another client. Its identity key and action claim are unchanged, so
   it is never classified or junked again; the correction also records the sender as wanted.
   Failures leave the message and its records as they are.

   - Returns: The correction records that were saved.
   */
  public func correctMailReturnedFromJunk(
    _ envelopes: [MailEnvelope],
    adapter: (any MailClientAdapter)?
  ) async -> [DecisionRecord] {
    var corrections: [DecisionRecord] = []
    for envelope in envelopes where Self.isInIMAPInbox(envelope.identity) {
      guard !Task.isCancelled else { break }
      guard let recordID = try? await adoptReturnedIdentity(envelope.identity),
        let correction = try? await correct(recordID: recordID, label: .inbox, adapter: adapter)
      else { continue }
      corrections.append(correction)
    }
    return corrections
  }

  /// Points a confirmed Junk move's record at the message's Inbox location; nil when the message was not moved by SpamWise.
  private func adoptReturnedIdentity(_ identity: MessageIdentity) async throws -> UUID? {
    try await StateRepository.transaction(store) { transaction -> UUID? in
      try transaction.loadClaim(for: identity)
      guard let id = transaction.state.claimedActions[identity.key],
        let index = transaction.state.records.firstIndex(where: { $0.id == id }),
        Self.isUncorrectedJunkMove(transaction.state.records[index]),
        transaction.state.records[index].identity.mailbox != identity.mailbox
      else { return nil }
      transaction.state.records[index].identity = identity
      try transaction.commit()
      return id
    }
  }
}

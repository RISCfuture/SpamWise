import Foundation

/// One sender's mail found in the user's Junk folders, offered at setup as an unwanted example.
public struct JunkFolderSender: Sendable, Identifiable {
  /// The sender's registrable domain, or its exact address at a shared mailbox provider.
  public let id: String
  /// The display name of the sender's newest message, or ``id`` when it has none.
  public let name: String
  /// How many of the scanned Junk messages came from this sender.
  public let messageCount: Int
  /// The sender's newest scanned message, imported as the example.
  public let representative: ParsedMessage
  /// Whether the sender is a contact or a correspondent, so the user may want its mail.
  public let possiblyWanted: Bool
}

/**
 Turns the user's existing Junk folders into reviewed examples of unwanted mail.

 Junk folders hold years of the user's own judgments, so one representative per sender gives a
 first-run classifier examples of what this user rejects. Importing creates no sender rules,
 moves no mail and goes through ``CorpusManagement``'s reviewed-import limits.
 */
public enum JunkFolderBootstrap {
  /// The most senders offered for import, leaving reviewed-label room for later corrections.
  public static let maximumSenders = 100

  /**
   Groups Junk messages by sender, most frequent first.

   - Parameters:
     - messages: Parsed Junk messages, newest first.
     - state: State with Contacts and history loaded, which mark possibly wanted senders.
   */
  public static func senders(in messages: [ParsedMessage], state: AppState) -> [JunkFolderSender] {
    let groups = Dictionary(grouping: messages.filter { !$0.fromAddress.isEmpty }, by: senderKey)
    return groups.map { key, messages in
      let newest = messages[0]
      return JunkFolderSender(
        id: key,
        name: newest.fromDisplayName.isEmpty ? key : newest.fromDisplayName,
        messageCount: messages.count,
        representative: newest,
        possiblyWanted: messages.contains { state.isKnownCorrespondent($0.fromAddress) }
      )
    }
    .sorted { ($0.messageCount, $1.id) > ($1.messageCount, $0.id) }
    .prefix(maximumSenders).map(\.self)
  }

  /// Imports each sender's representative as a reviewed Junk example, in supported batches.
  public static func importExamples(from senders: [JunkFolderSender], store: Store) async throws {
    let messages = senders.map(\.representative)
    for start in stride(from: 0, to: messages.count, by: CorpusManagement.maximumBatch) {
      try await CorpusManagement.importMessages(
        Array(messages[start..<min(start + CorpusManagement.maximumBatch, messages.count)]),
        label: .junk,
        store: store
      )
    }
  }

  private static func senderKey(_ message: ParsedMessage) -> String {
    let address = message.fromAddress.lowercased()
    guard let domain = DomainResolver().domain(ofAddress: address),
      !SharedMailboxDomains.contains(domain)
    else { return address }
    return domain
  }
}

extension AppState {
  /// Whether `address` is a contact or a correspondent in any account's history.
  fileprivate func isKnownCorrespondent(_ address: String) -> Bool {
    let address = address.lowercased()
    return contactAddresses?.contains(address) == true
      || histories.values.contains { history in
        history.replied[address, default: 0] > 0 || history.senderReceipts?[address] ?? 0 > 0
      }
  }
}

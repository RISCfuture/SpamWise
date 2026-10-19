public import Classifier
public import Foundation
public import MessageModel
public import Signals

/// Retrieves bounded explicit examples using deterministic lexical similarity.
public enum CorrectionRetrieval {
  private static let maximumExamples = 100
  private static let senderMatchBonus = 1.0
  private static let domainMatchBonus = 0.25
  /**
   Selects relevant corrections; sender and content matches outrank recency.

   - Parameters:
     - message: The message the examples are for.
     - corrections: The saved corrections to choose from.
     - limit: The most examples to return; never more than 100.
     - senderAuthenticated: Whether trusted authentication confirmed the From domain.
       Only then do examples from the same sender or domain rank higher, because a forged From
       address must not pull in the examples of the sender it imitates.
   */
  public static func examples(
    for message: ParsedMessage,
    from corrections: [CorrectionExample],
    limit: Int = 40,
    senderAuthenticated: Bool = false
  ) -> [CorrectionExample] {
    let candidates = LearningText.uniqueCorrections(corrections)
    let query = Set(LearningText.tokens(message.subject + " " + message.text))
    let documents = candidates.map { Set(LearningText.tokens($0.subject + " " + $0.excerpt)) }
    var frequencies: [String: Int] = [:]
    for document in documents {
      for token in document { frequencies[token, default: 0] += 1 }
    }
    let domain =
      senderAuthenticated ? DomainResolver().domain(ofAddress: message.fromAddress) : nil
    let sender = senderAuthenticated ? message.fromAddress.lowercased() : nil
    let scored = zip(candidates, documents).map { example, tokens in
      let overlap = query.intersection(tokens).sorted().reduce(0.0) {
        $0 + log(1 + Double(candidates.count) / Double(frequencies[$1, default: 1]))
      }
      let similarity = overlap / sqrt(Double(max(1, query.count * tokens.count)))
      let senderBonus = example.sender.lowercased() == sender ? senderMatchBonus : 0
      let domainBonus = domain != nil && example.domain == domain ? domainMatchBonus : 0
      return ScoredCorrection(example: example, score: similarity + senderBonus + domainBonus)
    }
    return scored.sorted {
      $0.score == $1.score ? LearningText.newer($0.example, $1.example) : $0.score > $1.score
    }.prefix(min(maximumExamples, max(0, limit))).map(\.example)
  }
  private struct ScoredCorrection {
    let example: CorrectionExample
    let score: Double
  }
}

/// A proposed domain preference that requires explicit user application.
public struct PolicySuggestion: Codable, Sendable, Equatable, Identifiable {
  /// Stable identity of the proposed domain and disposition.
  public var id: String { domain + ":" + label.rawValue }
  /// Domain shared by the supporting corrections.
  public let domain: String
  /// Suggested binary label; Review never proposes a blocking rule.
  public let label: MailLabel
  /// Explicit corrections supporting this suggestion.
  public let correctionIDs: [UUID]
}

/// Finds repeated preferences without modifying policy or sender rules.
public enum PolicyDistiller {
  private static let minimumCorrections = 3
  private static let minimumAddresses = 2
  private static let maximumSuggestions = 10
  /**
   Requires at least three distinct corrections from at least two addresses and no contrary label.

   Shared mailbox providers and domains that already have a domain rule are never suggested.
   */
  public static func suggestions(
    from corrections: [CorrectionExample],
    rules: [SenderRule],
    limit: Int = 10
  ) -> [PolicySuggestion] {
    let decided = Set(rules.filter { $0.scope == .domain }.map(\.value))
    let groups = Dictionary(grouping: LearningText.uniqueCorrections(corrections)) { $0.domain }
    return groups.compactMap { domain, examples -> PolicySuggestion? in
      guard let domain, !domain.isEmpty, !decided.contains(domain.lowercased()),
        !SharedMailboxDomains.contains(domain), examples.count >= minimumCorrections,
        Set(examples.map { $0.sender.lowercased() }).count >= minimumAddresses,
        let label = examples.first?.label, label != .review,
        examples.allSatisfy({ $0.label == label })
      else { return nil }
      return PolicySuggestion(
        domain: domain,
        label: label,
        correctionIDs: examples.map(\.id).sorted { $0.uuidString < $1.uuidString }
      )
    }.sorted {
      $0.correctionIDs.count == $1.correctionIDs.count
        ? $0.id < $1.id : $0.correctionIDs.count > $1.correctionIDs.count
    }.prefix(min(maximumSuggestions, max(0, limit))).map { $0 }
  }
}

enum LearningText {
  private static let maximumTextCharacters = 8000
  private static let maximumTokenCharacters = 40
  private static let minimumTokenCharacters = 3
  private static let maximumTokens = 512
  private static let maximumCorrections = 1000
  static let stopWords: Set<String> = [
    "the", "and", "for", "you", "your", "this", "that", "with", "from", "are", "was", "will",
    "have",
    "has", "our", "not", "can", "all", "but", "into", "www", "com", "http", "https"
  ]

  static func tokens(_ text: String) -> [String] {
    String(text.prefix(maximumTextCharacters)).lowercased().split { !$0.isLetter && !$0.isNumber }
      .map { String($0.prefix(maximumTokenCharacters)) }
      .filter { $0.count >= minimumTokenCharacters && !stopWords.contains($0) }.prefix(
        maximumTokens
      )
      .map { $0 }
  }

  /// Selects distinct tokens with the smallest stable hashes, independent of spelling and order.
  static func hashSample(_ text: String, limit: Int) -> [String] {
    Set(tokens(text)).map { (stableHash(Data($0.utf8)), $0) }.sorted(by: <).prefix(limit).map(
      \.1
    )
  }

  static func newer(_ lhs: CorrectionExample, _ rhs: CorrectionExample) -> Bool {
    lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date > rhs.date
  }

  static func uniqueCorrections(_ corrections: [CorrectionExample]) -> [CorrectionExample] {
    var seen: Set<String> = []
    return corrections.sorted(by: newer).prefix(maximumCorrections).filter {
      seen.insert(
        $0.sender.lowercased() + "\n" + $0.subject.lowercased() + "\n" + $0.excerpt.lowercased()
      ).inserted
    }
  }
}

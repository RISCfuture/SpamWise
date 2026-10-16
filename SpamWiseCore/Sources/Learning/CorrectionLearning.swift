public import Classifier
public import Foundation
public import MessageModel

/// Retrieves bounded explicit examples using deterministic lexical similarity.
public enum CorrectionRetrieval {
  /// Selects relevant corrections; sender and content matches outrank recency.
  public static func examples(
    for message: ParsedMessage,
    from corrections: [CorrectionExample],
    limit: Int = 40
  ) -> [CorrectionExample] {
    let candidates = LearningText.uniqueCorrections(corrections)
    let query = Set(LearningText.tokens(message.subject + " " + message.text))
    let documents = candidates.map { Set(LearningText.tokens($0.subject + " " + $0.gist)) }
    var frequencies: [String: Int] = [:]
    for document in documents {
      for token in document { frequencies[token, default: 0] += 1 }
    }
    let domain = DomainResolver().domain(ofAddress: message.fromAddress)
    let scored = zip(candidates, documents).map { example, tokens in
      let overlap = query.intersection(tokens).sorted().reduce(0.0) {
        $0 + log(1 + Double(candidates.count) / Double(frequencies[$1, default: 1]))
      }
      let similarity = overlap / sqrt(Double(max(1, query.count * tokens.count)))
      let senderBonus = example.sender.lowercased() == message.fromAddress.lowercased() ? 1.0 : 0
      let domainBonus = domain != nil && example.domain == domain ? 0.25 : 0
      return (example, similarity + senderBonus + domainBonus)
    }
    return scored.sorted {
      $0.1 == $1.1 ? LearningText.newer($0.0, $1.0) : $0.1 > $1.1
    }.prefix(min(100, max(0, limit))).map(\.0)
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
  /// Requires at least three distinct corrections from at least two addresses and no contrary label.
  public static func suggestions(from corrections: [CorrectionExample], limit: Int = 10)
    -> [PolicySuggestion]
  {
    let groups = Dictionary(grouping: LearningText.uniqueCorrections(corrections)) { $0.domain }
    return groups.compactMap { domain, examples -> PolicySuggestion? in
      guard let domain, !domain.isEmpty, examples.count >= 3,
        Set(examples.map { $0.sender.lowercased() }).count >= 2,
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
    }.prefix(min(10, max(0, limit))).map { $0 }
  }
}

enum LearningText {
  static let stopWords: Set<String> = [
    "the", "and", "for", "you", "your", "this", "that", "with", "from", "are", "was", "will",
    "have",
    "has", "our", "not", "can", "all", "but", "into", "www", "com", "http", "https"
  ]

  static func tokens(_ text: String) -> [String] {
    String(text.prefix(8000)).lowercased().split { !$0.isLetter && !$0.isNumber }
      .map { String($0.prefix(40)) }.filter { $0.count >= 3 && !stopWords.contains($0) }.prefix(512)
      .map { $0 }
  }

  static func newer(_ lhs: CorrectionExample, _ rhs: CorrectionExample) -> Bool {
    lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date > rhs.date
  }

  static func uniqueCorrections(_ corrections: [CorrectionExample]) -> [CorrectionExample] {
    var seen: Set<String> = []
    return corrections.sorted(by: newer).prefix(1000).filter {
      seen.insert(
        $0.sender.lowercased() + "\n" + $0.subject.lowercased() + "\n" + $0.gist.lowercased()
      ).inserted
    }
  }
}

import Classifier
import Foundation
import MessageModel
import Signals

enum CampaignContent {
  static let minimumOverlap = 0.8
  private static let authenticatedSenderPrefix = "dmarc:"
  private static let maximumBodyCharacters = 8000
  private static let minimumBodyCharacters = 100
  private static let minimumWords = 20
  private static let minimumDistinctWords = 16
  private static let wordsPerShingle = 5
  private static let maximumShingles = 128
  private static let minimumShingles = 12
  private static let footerMarkers = [
    "unsubscribe", "privacy policy", "manage preferences", "manage your preferences",
    "view in browser",
    "all rights reserved", "copyright", "you are receiving", "you received this", "if you no longer"
  ]

  /// Builds a signature; Junk signatures additionally require an authenticated sender anchor.
  static func fingerprint(
    message: ParsedMessage,
    shingles: [String],
    evidence: EvidenceBundle,
    label: MailLabel,
    date: Date
  ) -> CampaignFingerprint? {
    let anchors = authenticatedAnchors(message, evidence: evidence)
    guard label != .junk || !anchors.isEmpty else { return nil }
    return CampaignFingerprint(
      id: LearningSample.identity(for: message),
      date: date,
      label: label,
      anchors: anchors,
      shingles: shingles
    )
  }

  /// Returns bounded body shingles, or nil when the body is too short or generic to compare.
  static func shingles(_ message: ParsedMessage) -> [String]? {
    let body = String(message.text.prefix(maximumBodyCharacters)).components(separatedBy: .newlines)
      .filter { line in
        !footerMarkers.contains { line.lowercased().contains($0) }
      }.joined(separator: " ")
    let words = LearningText.tokens(body)
    guard body.count >= minimumBodyCharacters, words.count >= minimumWords,
      Set(words).count >= minimumDistinctWords
    else { return nil }
    let shingles = Set(
      (0..<(words.count - wordsPerShingle + 1)).map {
        stableHash(Data(words[$0..<($0 + wordsPerShingle)].joined(separator: " ").utf8))
      }
    ).sorted().prefix(maximumShingles).map { $0 }
    return shingles.count >= minimumShingles ? shingles : nil
  }

  /// Anchors the From domain only when a trusted server reports DMARC pass, which requires alignment.
  static func authenticatedAnchors(_ message: ParsedMessage, evidence: EvidenceBundle) -> [String] {
    guard evidence.authResults.contains(where: isTrustedDMARCPass),
      let domain = DomainResolver().domain(ofAddress: message.fromAddress)
    else { return [] }
    return [authenticatedSenderPrefix + domain]
  }

  static func overlap(_ lhs: [String], _ rhs: [String]) -> Double {
    let left = Set(lhs), right = Set(rhs)
    return Double(left.intersection(right).count) / Double(max(1, left.union(right).count))
  }

  /// Inbox and Review signatures both suppress near-duplicate Junk inference.
  static func isSuppressed(message: ParsedMessage, fingerprints: [CampaignFingerprint]) -> Bool {
    shingles(message).map { isSuppressed($0, fingerprints: fingerprints) } ?? false
  }

  static func match(
    message: ParsedMessage,
    evidence: EvidenceBundle,
    fingerprints: [CampaignFingerprint]
  ) -> CampaignMatch? {
    let anchors = Set(authenticatedAnchors(message, evidence: evidence))
    guard !anchors.isEmpty, let shingles = shingles(message),
      !isSuppressed(shingles, fingerprints: fingerprints)
    else { return nil }
    return fingerprints.filter { $0.label == .junk && !anchors.isDisjoint(with: $0.anchors) }
      .compactMap { fingerprint -> CampaignMatch? in
        let similarity = overlap(fingerprint.shingles, shingles)
        return similarity >= minimumOverlap
          ? CampaignMatch(fingerprintID: fingerprint.id, similarity: similarity) : nil
      }.sorted {
        $0.similarity == $1.similarity
          ? $0.fingerprintID < $1.fingerprintID : $0.similarity > $1.similarity
      }.first
  }

  private static func isTrustedDMARCPass(_ result: AuthResult) -> Bool {
    result.trusted && result.mechanism == "dmarc" && result.result == "pass"
  }

  private static func isSuppressed(_ shingles: [String], fingerprints: [CampaignFingerprint])
    -> Bool
  {
    fingerprints.contains { $0.label != .junk && overlap($0.shingles, shingles) >= minimumOverlap }
  }
}

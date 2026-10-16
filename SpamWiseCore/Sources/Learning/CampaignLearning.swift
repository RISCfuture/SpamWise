import Classifier
import Foundation
import MessageModel

enum CampaignContent {
  static let minimumOverlap = 0.8
  private static let footerMarkers = [
    "unsubscribe", "privacy policy", "manage preferences", "manage your preferences",
    "view in browser",
    "all rights reserved", "copyright", "you are receiving", "you received this", "if you no longer"
  ]

  static func fingerprint(message: ParsedMessage, label: MailLabel, date: Date)
    -> CampaignFingerprint?
  {
    let body = String(message.text.prefix(8000)).components(separatedBy: .newlines).filter { line in
      !footerMarkers.contains { line.lowercased().contains($0) }
    }.joined(separator: " ")
    let words = LearningText.tokens(body)
    guard body.count >= 100, words.count >= 20, Set(words).count >= 16 else { return nil }
    let shingles = Set(
      (0..<(words.count - 4)).map {
        stableHash(Data(words[$0..<($0 + 5)].joined(separator: " ").utf8))
      }
    ).sorted().prefix(128).map { $0 }
    guard shingles.count >= 12 else { return nil }
    let anchors = anchors(message)
    guard !anchors.isEmpty else { return nil }
    return CampaignFingerprint(
      id: LearningSample.identity(for: message),
      date: date,
      label: label,
      anchors: anchors,
      shingles: shingles
    )
  }

  static func anchors(_ message: ParsedMessage) -> [String] {
    let resolver = DomainResolver()
    var anchors = message.urls.prefix(100).compactMap { URL(string: $0)?.host }.compactMap(
      resolver.registrableDomain
    )
    .prefix(20).map { "link:" + $0 }
    if let domain = resolver.domain(ofAddress: message.fromAddress) {
      anchors.append("sender:" + domain)
    }
    return Array(Set(anchors)).sorted()
  }

  static func overlap(_ lhs: [String], _ rhs: [String]) -> Double {
    let left = Set(lhs), right = Set(rhs)
    return Double(left.intersection(right).count) / Double(max(1, left.union(right).count))
  }

  static func isSuppressed(message: ParsedMessage, fingerprints: [CampaignFingerprint]) -> Bool {
    guard let candidate = fingerprint(message: message, label: .inbox, date: .distantPast) else {
      return false
    }
    return fingerprints.contains {
      $0.label != .junk && overlap($0.shingles, candidate.shingles) >= minimumOverlap
    }
  }

  static func match(message: ParsedMessage, fingerprints: [CampaignFingerprint]) -> CampaignMatch? {
    guard let candidate = fingerprint(message: message, label: .junk, date: .distantPast),
      !isSuppressed(message: message, fingerprints: fingerprints)
    else { return nil }
    return fingerprints.filter {
      $0.label == .junk && !Set($0.anchors).isDisjoint(with: candidate.anchors)
    }
    .compactMap { fingerprint -> CampaignMatch? in
      let similarity = overlap(fingerprint.shingles, candidate.shingles)
      return similarity >= minimumOverlap
        ? CampaignMatch(fingerprintID: fingerprint.id, similarity: similarity) : nil
    }.sorted {
      $0.similarity == $1.similarity
        ? $0.fingerprintID < $1.fingerprintID : $0.similarity > $1.similarity
    }.first
  }
}

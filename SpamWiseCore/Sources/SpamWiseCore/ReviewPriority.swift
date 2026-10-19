import Foundation

/// Transparent review ordering, without claiming calibrated mistake probabilities.
public enum ReviewPriority {
  /// A human-readable reason for appearing earlier in the digest.
  public static func reason(_ record: DecisionRecord) -> String {
    switch rank(record) {
      case 0: String(localized: "Mail action needs attention", bundle: .module)
      case 1: String(localized: "Model and local evidence disagree", bundle: .module)
      default:
        String(localized: "Uncertain classification; confidence is uncalibrated", bundle: .module)
    }
  }
  /// Orders action failures, evidence disagreements, then lower model confidence and recency.
  public static func precedes(_ first: DecisionRecord, _ second: DecisionRecord) -> Bool {
    if rank(first) != rank(second) { return rank(first) < rank(second) }
    let firstConfidence = first.verdict?.confidence ?? 0,
      secondConfidence = second.verdict?.confidence ?? 0
    if firstConfidence != secondConfidence { return firstConfidence < secondConfidence }
    return first.date > second.date
  }
  private static func rank(_ record: DecisionRecord) -> Int {
    if [.failed, .requested, .integrationUnavailable].contains(record.outcome) { return 0 }
    if let label = record.verdict?.label {
      let evidence = record.evidence
      let signals = [evidence?.bayesLogOdds, evidence?.learnedMargin].compactMap(\.self)
      if signals.contains(where: { (label == .junk && $0 < 0) || (label == .inbox && $0 > 0) }) {
        return 1
      }
    }
    return 2
  }
}

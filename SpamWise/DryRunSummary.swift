import Foundation
import SpamWiseCore

/// What a dry run of recent mail decided, as setup presents it.
struct DryRunSummary: Equatable {
  /// The previewed messages, newest first.
  let rows: [Row]
  /// Messages that would move to Junk.
  let junk: Int
  /// Messages that would be flagged for Review.
  let review: Int
  /// Messages that could not be read.
  let unreadable: Int
  /// Why some messages weren't classified, when the setup choices explain it.
  let blocker: Blocker?

  /// Whether the dry run found no mail at all.
  var isEmpty: Bool { rows.isEmpty && unreadable == 0 }

  init(_ preview: MailPreview) {
    rows = preview.records.map(Row.init)
    junk = rows.count { $0.verdict == .junk }
    review = rows.count { $0.verdict == .review }
    unreadable = preview.unavailableCount
    blocker = Blocker.allCases.first { blocker in
      preview.records.contains { Blocker($0.decision.reason) == blocker }
    }
  }

  /// One previewed message.
  struct Row: Equatable, Identifiable {
    let id: UUID
    let subject: String?
    let sender: String?
    let verdict: Verdict

    init(_ record: DecisionRecord) {
      id = record.id
      subject = record.subject
      sender = record.sender
      verdict = Verdict(record)
    }
  }

  /// Where a previewed message would go.
  enum Verdict: Equatable {
    case good, junk, review, notClassified

    init(_ record: DecisionRecord) {
      guard record.outcome != .unclassified else {
        self = .notClassified
        return
      }
      switch record.decision.label {
        case .inbox: self = .good
        case .junk: self = .junk
        case .review: self = .review
        case nil: self = .notClassified
      }
    }
  }

  /// A setup choice that left messages unclassified, most actionable first.
  enum Blocker: CaseIterable, Equatable {
    /// Mail sharing with the selected provider is off.
    case consentRequired
    /// The selected provider has no saved API key.
    case missingKey
    /// The selected provider can't run here.
    case providerUnavailable
    /// This month's spending limit was reached.
    case spendingLimitReached

    init?(_ reason: DecisionReason) {
      switch reason {
        case .classificationFailed(.consentRequired): self = .consentRequired
        case .classificationFailed(.missingCredential): self = .missingKey
        case .classificationFailed(.configuration): self = .providerUnavailable
        case .spendingLimitReached: self = .spendingLimitReached
        default: return nil
      }
    }
  }
}

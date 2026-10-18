import Foundation
import SpamWiseCore

/// The messages selected in Mail for one correction, read before any of them is corrected.
struct SelectionBatch {
  let label: MailLabel
  let scope: RuleScope
  /// The readable and unreadable selected messages, in Mail’s order.
  let messages: [ReviewMessage]
  /// Messages whose sender couldn’t be verified, which a Junk correction skips.
  var unverifiedIDs: Set<String>
  /// Selected messages Mail couldn’t hand over, such as those over the size limit.
  let unreadableCount: Int

  /// Every selected message, including those Mail couldn’t hand over.
  var selectedCount: Int { messages.count + unreadableCount }

  /// Why `message` is left uncorrected, or nil to correct it.
  func skipReason(for message: ReviewMessage) -> SelectionSkipReason? {
    if !message.isReadable { return .unreadable }
    if unverifiedIDs.contains(message.id) { return .unverifiedSender }
    guard scope == .domain else { return nil }
    guard let sender = message.sender, let domain = DomainResolver().domain(ofAddress: sender)
    else { return .noDomain }
    return SharedMailboxDomains.contains(domain) ? .sharedDomain(domain) : nil
  }

  /// What the finished batch did, for the menu bar and the results sheet.
  func summary(of results: [SelectionCorrectionResult]) -> String {
    let records = results.compactMap(\.record)
    let corrected = records.count, total = selectedCount
    let unmoved = records.filter { [.failed, .integrationUnavailable].contains($0.outcome) }.count
    let failed = results.filter(\.failed).count
    let skipped = results.count - corrected - failed
    var parts = [correctedSummary(corrected, of: total)]
    if unmoved > 0 { parts.append(String(localized: "Mail couldn’t move \(unmoved) of them.")) }
    if skipped > 0 { parts.append(String(localized: "Skipped \(skipped).")) }
    if failed > 0 { parts.append(String(localized: "\(failed) couldn’t be corrected.")) }
    if unreadableCount > 0 { parts.append(JunkReviewModel.unreadableStatus(unreadableCount)) }
    return parts.joined(separator: " ")
  }

  /// What a cancelled batch did before it stopped.
  func stoppedSummary(after count: Int) -> String {
    String(localized: "Stopped after \(count) of \(selectedCount) messages.")
  }

  private func correctedSummary(_ count: Int, of total: Int) -> String {
    switch label {
      case .inbox: String(localized: "Marked \(count) of \(total) messages as Good.")
      case .junk: String(localized: "Marked \(count) of \(total) messages as Junk.")
      case .review: String(localized: "Marked \(count) of \(total) messages for Review.")
    }
  }
}

/// Why a selected message was left uncorrected.
enum SelectionSkipReason: Equatable {
  /// Mail’s copy of the message couldn’t be parsed.
  case unreadable
  /// The user chose not to block senders that couldn’t be verified.
  case unverifiedSender
  /// The sender has no domain a domain rule could name.
  case noDomain
  /// The sender’s domain is a mail provider shared by unrelated people.
  case sharedDomain(String)

  var localizedDescription: String {
    switch self {
      case .unreadable: String(localized: "Skipped: SpamWise couldn’t read this message.")
      case .unverifiedSender:
        String(localized: "Skipped: SpamWise couldn’t verify the sender, so it wasn’t blocked.")
      case .noDomain:
        String(localized: "Skipped: the sender has no domain that a rule can name.")
      case .sharedDomain(let domain):
        String(
          localized:
            "Skipped: unrelated people use \(domain). Correct this sender’s address from Activity instead."
        )
    }
  }
}

/// What a selected-message correction did with one message.
struct SelectionCorrectionResult: Identifiable {
  let message: ReviewMessage
  let outcome: Outcome

  var id: String { message.id }
  /// The saved correction, when there is one.
  var record: DecisionRecord? {
    if case .corrected(let record, _) = outcome { record } else { nil }
  }
  var failed: Bool {
    if case .failed = outcome { true } else { false }
  }

  /// This result without `rule` as its conflict, once the rule is removed.
  func withoutConflict(_ rule: SenderRule) -> Self {
    guard case .corrected(let record, let conflict) = outcome, conflict?.id == rule.id else {
      return self
    }
    return Self(message: message, outcome: .corrected(record, conflict: nil))
  }

  enum Outcome {
    /// The correction was saved; `conflict` still decides the sender’s mail.
    case corrected(DecisionRecord, conflict: SenderRule?)
    /// The message was deliberately left alone.
    case skipped(SelectionSkipReason)
    /// The correction couldn’t be saved.
    case failed(String)
  }
}

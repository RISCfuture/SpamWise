import Foundation
import SpamWiseCore

extension AuditEvent {
  /// What changed, described in the reader's language.
  var localizedDescription: String { change.localizedDescription }
}

extension AuditEvent.Change {
  /// What changed, described in the reader's language.
  var localizedDescription: String {
    switch self {
      case .settingsChanged(let fields):
        String(localized: "Settings changed: \(fields.formatted(.list(type: .and)))")
      case let .senderRuleSaved(scope, value, disposition):
        Self.savedRule(scope: scope, value: value, disposition: disposition)
      case let .senderRuleRemoved(scope, value):
        switch scope {
          case .address: String(localized: "Removed the rule for sender \(value)")
          case .domain: String(localized: "Removed the rule for domain \(value)")
        }
      case .senderRulesImported(let count):
        String(localized: "Imported sender rules: \(count, format: .number)")
      case let .contentRuleSaved(field, pattern, disposition):
        switch disposition {
          case .allow:
            String(localized: "Allowed mail whose \(field.localizedTitle) matches “\(pattern)”")
          case .block:
            String(localized: "Blocked mail whose \(field.localizedTitle) matches “\(pattern)”")
        }
      case let .contentRuleRemoved(field, pattern):
        String(localized: "Removed the content rule for \(field.localizedTitle) “\(pattern)”")
      case .contentRulesImported(let count):
        String(localized: "Imported content rules: \(count, format: .number)")
      case let .corrected(scope, sender, label):
        Self.correction(scope: scope, sender: sender, label: label)
      case .backupRestored: String(localized: "Restored portable learning state; actions paused")
      case let .corpusImported(count, label):
        String(
          localized:
            "Imported reviewed examples labeled \(label.localizedTitle): \(count, format: .number)"
        )
      case .corpusRelabeled(let label):
        String(localized: "Relabeled a reviewed example as \(label.localizedTitle)")
      case .corpusForgotten: String(localized: "Forgot a reviewed example and its learning")
      case .learningRebuilt: String(localized: "Rebuilt learning from the current reviewed labels")
      case .correctionUndone:
        String(localized: "Undid correction rules and learning; Mail action unchanged")
      case .recorded(let text): text
    }
  }

  private static func savedRule(scope: RuleScope, value: String, disposition: RuleDisposition)
    -> String
  {
    switch (scope, disposition) {
      case (.address, .allow): String(localized: "Allowed sender \(value)")
      case (.address, .block): String(localized: "Blocked sender \(value)")
      case (.domain, .allow): String(localized: "Allowed domain \(value)")
      case (.domain, .block): String(localized: "Blocked domain \(value)")
    }
  }

  private static func correction(scope: RuleScope, sender: String, label: MailLabel) -> String {
    switch (label, scope) {
      case (.inbox, .address): String(localized: "Marked mail from \(sender) as Good")
      case (.inbox, .domain):
        String(localized: "Marked all mail from the domain of \(sender) as Good")
      case (.junk, .address): String(localized: "Marked mail from \(sender) as Junk")
      case (.junk, .domain):
        String(localized: "Marked all mail from the domain of \(sender) as Junk")
      case (.review, _): String(localized: "Marked mail from \(sender) for Review")
    }
  }
}

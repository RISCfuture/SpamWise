import Foundation
import SpamWiseCore

extension AuditEvent {
  /// What changed, described in the reader's language.
  var localizedDescription: String { change.localizedDescription }
}

/// The names of changed settings as Settings shows them, from their stored field paths.
enum SettingsFieldTitles {
  /// Distinct titles for `paths`, such as “Dry run” for `dryRun`, in first-seen order.
  static func titles(for paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths.map(title(for:)).filter { seen.insert($0).inserted }
  }

  private static func title(for path: String) -> String {
    let components = path.split(separator: ".").map(String.init)
    switch components.first {
      case "advanced": return advancedTitle(components.dropFirst().first)
      case "mailPreferences": return mailTitle(components.dropFirst().first)
      default: return generalTitle(components.first)
    }
  }

  private static func generalTitle(_ field: String?) -> String {
    switch field {
      case "strength": String(localized: "Filtering strength")
      case "review": String(localized: "Review marking")
      case "dryRun": String(localized: "Dry run")
      case "paused": String(localized: "Pause")
      case "policy": String(localized: "Your policy")
      case "correctionLimit": String(localized: "Correction examples")
      case "bodyTokenBudget": String(localized: "Message text sent")
      case "onboardingComplete": String(localized: "Setup")
      case "validatedAccounts": String(localized: "Validated accounts")
      default: String(localized: "Other settings")
    }
  }

  private static func advancedTitle(_ field: String?) -> String {
    switch field {
      case "backend", "modelID": String(localized: "Classifier")
      case "mailSharingConsent": String(localized: "Provider consent")
      case "domainRegistrationLookup": String(localized: "Domain age lookup")
      case "transport": String(localized: "Mail connection")
      case "fingerprints", "bayes", "learnedWeights": String(localized: "Learning")
      case "imageOCR", "textAttachments", "externalEvidence": String(localized: "Evidence")
      case "weeklyDigest": String(localized: "Weekly Review digest")
      case "retainReviewedContent": String(localized: "Reviewed message text")
      default: String(localized: "Advanced settings")
    }
  }

  private static func mailTitle(_ field: String?) -> String {
    switch field {
      case "localOnly": String(localized: "Local-only mode")
      case "accountIDs": String(localized: "Accounts to filter")
      case "trustExclusions", "excludeOwnAddresses": String(localized: "Trusted senders")
      case "trustedAuthServers": String(localized: "Trusted receiving servers")
      case "folderPlans": String(localized: "Folder plans")
      case "markJunkRead": String(localized: "Mark Junk as read")
      case "notifications": String(localized: "Notifications")
      default: String(localized: "Mail settings")
    }
  }
}

extension AuditEvent.Change {
  /// What changed, described in the reader's language.
  var localizedDescription: String {
    switch self {
      case .settingsChanged(let fields):
        String(
          localized:
            "Settings changed: \(SettingsFieldTitles.titles(for: fields).formatted(.list(type: .and)))"
        )
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

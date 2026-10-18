import SwiftUI
import SpamWiseCore

/// The questions a decision correction raises: an unverified sender, or a rule that overrides it.
struct CorrectionPrompts: View {
  let corrections: CorrectionsModel
  let row: DecisionRecord

  var body: some View {
    if let pending = corrections.pendingDecision, pending.record.id == row.id {
      UnverifiedSenderPrompt(
        message: UnverifiedSenderPrompt.message(sender: row.displaySender),
        confirmTitle: pending.scope == .domain ? "Block Domain Anyway" : "Block Sender Anyway",
        cancel: corrections.cancelPendingDecision,
        confirm: corrections.confirmPendingDecision
      )
    }
    if let conflict = corrections.conflict, conflict.recordID == row.id {
      RuleConflictPrompt(
        rule: conflict.rule,
        keep: corrections.keepConflictingRule,
        remove: corrections.removeConflictingRule
      )
    }
    OperationStatusView(operation: corrections.ruleRemoval)
  }
}

/// A warning that blocking an unverified sender may also block the real sender, with a choice.
struct UnverifiedSenderPrompt: View {
  let message: String
  let confirmTitle: LocalizedStringKey
  var skipTitle: LocalizedStringKey?
  let cancel: () -> Void
  var skip: () -> Void = {}
  let confirm: () -> Void

  var body: some View {
    InlineWarning(text: message, identifier: "correction.warning") {
      Button("Cancel", action: cancel)
      if let skipTitle { Button(skipTitle, action: skip) }
      Button(confirmTitle, action: confirm).accessibilityIdentifier("correction.warning.confirm")
    }
  }

  static func message(sender: String) -> String {
    String(
      localized:
        "SpamWise couldn’t verify that this message came from \(sender). If the address is forged, blocking it also sends the real sender’s mail to Junk."
    )
  }
}

/// A warning that a sender rule still overrides a correction, with the choice to remove it.
struct RuleConflictPrompt: View {
  let rule: SenderRule
  let keep: (() -> Void)?
  let remove: () -> Void

  var body: some View {
    InlineWarning(text: rule.overridingDescription, identifier: "correction.conflict") {
      if let keep { Button("Keep Rule", action: keep) }
      Button("Remove Rule", action: remove).accessibilityIdentifier("correction.conflict.remove")
    }
  }
}

/// A tinted warning followed by the buttons that resolve it.
struct InlineWarning<Actions: View>: View {
  let text: String
  let identifier: String
  @ViewBuilder let actions: Actions

  var body: some View {
    VStack(alignment: .leading) {
      Label {
        Text(text).accessibilityIdentifier(identifier)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
          .accessibilityLabel("Warning")
      }
      HStack { actions }
    }
  }
}

extension SenderRule {
  /// How this rule still decides a sender’s mail after a correction it overrides.
  var overridingDescription: String {
    switch disposition {
      case .block:
        String(localized: "Your Block rule for \(value) still sends this sender’s mail to Junk.")
      case .allow:
        String(
          localized: "Your Allow rule for \(value) still sends this sender’s mail to the Inbox."
        )
    }
  }
}

#Preview("Unverified sender") {
  Form {
    UnverifiedSenderPrompt(
      message: UnverifiedSenderPrompt.message(sender: "alice@friend.example"),
      confirmTitle: "Block Sender Anyway",
      cancel: {},
      confirm: {}
    )
  }.formStyle(.grouped)
}
#Preview("Overriding rule") {
  Form {
    RuleConflictPrompt(
      rule: SenderRule(scope: .domain, value: "shop.example", disposition: .block),
      keep: {},
      remove: {}
    )
  }.formStyle(.grouped)
}

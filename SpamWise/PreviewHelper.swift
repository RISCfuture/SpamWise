import SwiftUI
import SpamWiseCore

@MainActor enum PreviewHelper {
  static func model(onboarding: Bool = false, paused: Bool = false) -> AppModel {
    let model = AppModel(preview: true)
    model.state.settings.onboardingComplete = !onboarding
    model.state.settings.paused = paused
    model.state.records = [record]
    return model
  }
  static var record: DecisionRecord {
    DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "preview"),
      sender: "newsletter@example.org",
      subject: "Your weekly digest",
      verdict: .init(label: .review, confidence: 73, reason: "Relationship is unknown"),
      decision: .init(label: .review, action: .orangeFlag, reason: "Relationship is unknown"),
      outcome: .dryRun,
      path: "model"
    )
  }
}

#Preview("Activity") { ContentView(model: PreviewHelper.model()) }
#Preview("Paused") { ContentView(model: PreviewHelper.model(paused: true)) }
#Preview("Onboarding") { OnboardingView(model: PreviewHelper.model(onboarding: true)) }
#Preview("Key") { KeyEntryView(model: PreviewHelper.model()) }
#Preview("Mail permissions") { MailConnectionView(model: PreviewHelper.model()) }
#Preview("Settings") { SettingsView(model: PreviewHelper.model()) }
#Preview("Policy") { PolicyView(model: PreviewHelper.model()) }
#Preview("Decision") { DecisionDetailView(model: PreviewHelper.model(), row: PreviewHelper.record) }
#Preview("Verdict") { VerdictBadge(record: PreviewHelper.record) }
#Preview("Help") { HelpButton(page: "getting-started") }

import Foundation
import Testing
import SpamWiseCore
@testable import SpamWiseCommon

@Suite
struct `Classifier readiness` {
  @Test
  func `asks for a cloud provider's key, then consent, before it is ready`() {
    var settings = SpamWiseCore.Settings()
    settings.advancedOptions.select(.geminiFlash)
    #expect(readiness(settings, savedKeys: []) == .needsKey)
    #expect(readiness(settings, savedKeys: [.claude]) == .needsKey)
    #expect(readiness(settings, savedKeys: [.gemini]) == .needsConsent)
    settings.advancedOptions.mailSharingConsent = [.claude]
    #expect(readiness(settings, savedKeys: [.gemini]) == .needsConsent)
    settings.advancedOptions.mailSharingConsent = [.gemini]
    #expect(readiness(settings, savedKeys: [.gemini]) == .ready)
  }

  @Test
  func `blocks a configured cloud provider when filtering stays on this Mac`() {
    var settings = SpamWiseCore.Settings()
    settings.advancedOptions.mailSharingConsent = [.claude]
    settings.mailOptions.localOnly = true
    #expect(readiness(settings, savedKeys: [.claude]) == .blockedByLocalOnly)
  }

  @Test
  func `needs only Apple Intelligence for the on-device model`() {
    var settings = SpamWiseCore.Settings()
    settings.advancedOptions.select(.appleOnDevice)
    settings.mailOptions.localOnly = true
    #expect(readiness(settings, savedKeys: []) == .ready)
    #expect(readiness(settings, onDeviceAvailable: false, savedKeys: []) == .unavailable)
    settings.advancedOptions.select(.applePrivateCloudCompute)
    #expect(readiness(settings, savedKeys: []) == .unavailable)
  }

  private func readiness(
    _ settings: SpamWiseCore.Settings,
    onDeviceAvailable: Bool = true,
    savedKeys: Set<ModelBackend>
  ) -> ClassifierReadiness {
    ClassifierReadiness(
      settings: settings,
      onDeviceAvailable: onDeviceAvailable,
      savedKeys: savedKeys
    )
  }
}

@Suite
struct `Setup dry-run summary` {
  @Test
  func `counts Junk and Review and shows each message's verdict`() {
    let summary = DryRunSummary(
      MailPreview(
        records: [
          record(.junk, outcome: .dryRun), record(.review, outcome: .dryRun),
          record(.inbox, outcome: .noAction), record(.junk, outcome: .dryRun),
          record(nil, outcome: .unclassified, reason: .classificationFailed(.timeout))
        ],
        unavailableCount: 2
      )
    )
    #expect(summary.junk == 2)
    #expect(summary.review == 1)
    #expect(summary.unreadable == 2)
    #expect(summary.rows.map(\.verdict) == [.junk, .review, .good, .junk, .notClassified])
    #expect(summary.blocker == nil)
    #expect(!summary.isEmpty)
  }

  @Test
  func `explains missing consent before other setup problems`() {
    let summary = DryRunSummary(
      MailPreview(
        records: [
          record(nil, outcome: .unclassified, reason: .spendingLimitReached),
          record(nil, outcome: .unclassified, reason: .classificationFailed(.consentRequired))
        ],
        unavailableCount: 0
      )
    )
    #expect(summary.blocker == .consentRequired)
    #expect(summary.rows.allSatisfy { $0.verdict == .notClassified })
  }

  private func record(
    _ label: MailLabel?,
    outcome: ActionOutcome,
    reason: DecisionReason = .model("Test")
  ) -> DecisionRecord {
    DecisionRecord(
      identity: .init(accountID: "account", contentHash: UUID().uuidString),
      decision: .init(label: label, action: .none, reason: reason),
      outcome: outcome
    )
  }
}

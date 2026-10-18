import Foundation
import SpamWiseCore

@MainActor enum PreviewHelper {

  static var record: DecisionRecord {
    DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "preview"),
      sender: "newsletter@example.org",
      subject: "Your weekly digest",
      verdict: .init(label: .review, confidence: 73, reason: "Relationship is unknown"),
      decision: .init(
        label: .review,
        action: .orangeFlag,
        reason: .model("Relationship is unknown")
      ),
      outcome: .dryRun,
      path: .model
    )
  }

  static var failedRecord: DecisionRecord {
    var record = DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "failed-preview"),
      sender: "offers@shop.example",
      subject: "An unwanted offer",
      verdict: .init(label: .junk, confidence: 99, reason: "Repeated unwanted promotion"),
      decision: .init(
        label: .junk,
        action: .moveToJunk,
        reason: .model("Repeated unwanted promotion")
      ),
      outcome: .failed,
      path: .model
    )
    record.actionError = "Mail could not confirm the action."
    return record
  }

  static var sharedProviderRecord: DecisionRecord {
    let raw = Data("From: friend@gmail.com\r\nSubject: Dinner\r\n\r\nSee you at seven".utf8)
    return DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "shared-provider-preview"),
      sender: "friend@gmail.com",
      subject: "Dinner",
      evidence: (try? MIMEParser().parse(raw)).map { EvidenceBundle(message: $0) },
      decision: .init(
        label: .review,
        action: .orangeFlag,
        reason: .model("Relationship is unknown")
      ),
      outcome: .dryRun,
      path: .model
    )
  }

  static var unclassifiedRecord: DecisionRecord {
    DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "unclassified-preview"),
      decision: .init(label: nil, action: .none, reason: .classificationFailed(.consentRequired)),
      outcome: .unclassified
    )
  }

  static var threatAssessment: ThreatAssessment? {
    let raw = Data("From: example@example.org\r\nSubject: Preview\r\n\r\nSynthetic preview".utf8)
    guard let message = try? MIMEParser().parse(raw) else { return nil }
    return try? ThreatAssessment(
      input: .init(message: message, accountID: "preview", evidence: .init(message: message)),
      detector: .init(
        implementation: "Preview",
        model: "Synthetic",
        preprocessing: "Text",
        policy: "Preview"
      ),
      findings: [
        .init(
          kind: .phishing,
          status: .detected,
          reason: "Synthetic credential lure",
          coverage: "Preview text only"
        )
      ]
    )
  }

  static var corrections: [CorrectionExample] {
    [
      CorrectionExample(
        sender: "offers@shop.example",
        domain: "shop.example",
        subject: "Weekend clearance",
        excerpt: "Save on every order this weekend only.",
        label: .junk,
        promptScope: .account("preview")
      ),
      CorrectionExample(
        sender: "newsletter@shop.example",
        domain: "shop.example",
        subject: "A new collection",
        excerpt: "Meet our new autumn collection.",
        label: .junk,
        promptScope: .account("preview")
      ),
      CorrectionExample(
        sender: "offers@shop.example",
        domain: "shop.example",
        subject: "Last chance savings",
        excerpt: "Your last chance to save ends tonight.",
        label: .junk,
        promptScope: .account("preview")
      )
    ]
  }

  static var rule: SenderRule {
    .init(scope: .address, value: "newsletter@example.org", disposition: .allow)
  }
  static func spamhaus(_ transport: SpamhausTransport) -> ExternalEvidenceSettings {
    var configuration = ExternalEvidenceSettings()
    configuration.spamhausTransport = transport
    return configuration
  }

  /// Feature models over preview services, without a store, with fixture Activity and state.
  static func model(
    onboarding: Bool = false,
    paused: Bool = false,
    empty: Bool = false,
    transport: MailTransport = .appleMail,
    backend: ModelBackend = .claude,
    suggestions: Bool = false,
    spendingLimitReached: Bool = false
  ) -> AppModel {
    let model = AppModel(services: .preview(), activityFixtures: empty ? [] : [record])
    let shared = model.shared
    shared.spending = spending(limitReached: spendingLimitReached)
    shared.state.settings.onboardingComplete = !onboarding
    shared.state.settings.paused = paused
    shared.state.settings.advancedOptions.transport = transport
    shared.state.settings.advancedOptions.backend = backend
    shared.state.rules = empty ? [] : [rule]
    shared.state.corrections = suggestions ? corrections : []
    return model
  }

  static func spending(limitReached: Bool) -> MonthlySpending {
    var spending = MonthlySpending(month: .init(containing: .now))
    spending.committedMicroUSD = limitReached ? 5_000_000 : 1_380
    spending.limitMicroUSD = limitReached ? 5_000_000 : nil
    spending.limitReached = limitReached
    return spending
  }
}

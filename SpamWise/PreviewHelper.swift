import Foundation
import SpamWiseCore

@MainActor enum PreviewHelper {

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

  static var failedRecord: DecisionRecord {
    var record = DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "failed-preview"),
      sender: "offers@shop.example",
      subject: "An unwanted offer",
      verdict: .init(label: .junk, confidence: 99, reason: "Repeated unwanted promotion"),
      decision: .init(label: .junk, action: .moveToJunk, reason: "Repeated unwanted promotion"),
      outcome: .failed,
      path: "model"
    )
    record.actionError = "Mail could not confirm the action."
    return record
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
        gist: "An unsolicited weekend promotion",
        label: .junk
      ),
      CorrectionExample(
        sender: "newsletter@shop.example",
        domain: "shop.example",
        subject: "A new collection",
        gist: "An unsolicited collection announcement",
        label: .junk
      ),
      CorrectionExample(
        sender: "offers@shop.example",
        domain: "shop.example",
        subject: "Last chance savings",
        gist: "An unsolicited reminder about a sale",
        label: .junk
      )
    ]
  }

  static var rule: SenderRule {
    .init(scope: .address, value: "newsletter@example.org", disposition: .allow)
  }
  static func model(
    onboarding: Bool = false,
    paused: Bool = false,
    empty: Bool = false,
    transport: MailTransport = .appleMail,
    backend: ModelBackend = .claude,
    suggestions: Bool = false
  ) -> AppModel {
    let model = AppModel(preview: true)
    model.state.settings.onboardingComplete = !onboarding
    model.state.settings.paused = paused
    model.state.settings.advancedOptions.transport = transport
    model.state.settings.advancedOptions.backend = backend
    model.state.records = empty ? [] : [record]
    model.state.rules = empty ? [] : [rule]
    model.state.corrections = suggestions ? corrections : []
    return model
  }

}

#if DEBUG
  import Foundation
  import MailIntegration
  import SpamWiseCore

  struct DeniedAppleEventRunner: AppleEventRunner {
    func run(_ source: String) async throws -> ScriptValue {
      throw IntegrationError.permissionDenied
    }
  }

  enum UITestFixture {
    static func seedCorrections(in store: Store) async throws {
      let message = try MIMEParser().parse(
        Data(
          "From: newsletter@example.org\r\nSubject: Your weekly digest\r\n\r\nA synthetic newsletter."
            .utf8
        )
      )
      var record = DecisionRecord(
        identity: .init(accountID: "ui-test", contentHash: message.hash),
        sender: "newsletter@example.org",
        subject: "Your weekly digest",
        evidence: .init(message: message),
        verdict: .init(label: .junk, confidence: 99, reason: "Unwanted newsletter"),
        decision: .init(label: .junk, action: .moveToJunk, reason: "Unwanted newsletter"),
        outcome: .dryRun,
        path: "model"
      )
      record.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
      let initial = record
      try await StateRepository.update(store) { state in
        guard state.records.isEmpty else { return }
        state.settings.onboardingComplete = true
        state.settings.dryRun = false
        state.settings.route = .mailRule
        state.settings.validatedAccounts = ["ui-test"]
        state.record(initial)
      }
    }
  }
#endif

#if DEBUG
  import Foundation
  import MailIntegration
  import SpamWiseCore

  struct DeniedAppleEventRunner: AppleEventRunner {
    func run(_ source: String) async throws -> ScriptValue {
      throw IntegrationError.permissionDenied
    }
  }

  struct SelectedFixtureAppleEventRunner: AppleEventRunner {
    func run(_ source: String) async throws -> ScriptValue {
      guard source == MailScripts.selected else { throw IntegrationError.permissionDenied }
      return .list([
        .string("ui-test"), .string("Inbox"), .integer(1),
        .string("automation@example.org"), .string(UITestFixture.messageSource)
      ])
    }
  }

  enum UITestFixture {
    static let messageSource =
      "From: newsletter@example.org\r\nSubject: Your weekly digest\r\n\r\nA synthetic newsletter."

    static func seed(arguments: [String], in store: Store) async throws {
      if arguments.contains("--ui-corrections") {
        try await seedCorrections(in: store)
      } else if arguments.contains("--ui-visual-fixture") {
        try await seedVisualState(in: store)
      }
    }

    static func seedCorrections(in store: Store) async throws {
      let message = try MIMEParser().parse(
        Data(messageSource.utf8)
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
      guard let identity = UUID(uuidString: "00000000-0000-0000-0000-000000000001") else {
        preconditionFailure("The correction fixture requires a valid UUID.")
      }
      record.id = identity
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

    @MainActor private static func seedVisualState(in store: Store) async throws {
      let review = PreviewHelper.record, failed = PreviewHelper.failedRecord
      let corrections = PreviewHelper.corrections
      try await StateRepository.update(store) { state in
        guard state.records.isEmpty else { return }
        state.settings.onboardingComplete = true
        state.settings.dryRun = true
        state.corrections = corrections
        state.record(review)
        state.record(failed)
      }
    }
  }
#endif

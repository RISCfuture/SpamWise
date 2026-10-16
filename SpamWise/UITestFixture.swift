#if DEBUG
  import Foundation
  import MailIntegration
  import SpamWiseCore

  struct DeniedAppleEventRunner: AppleEventRunner {
    func run(_: MailRequest) throws -> ScriptValue {
      throw IntegrationError.permissionDenied
    }
  }

  struct SelectedFixtureAppleEventRunner: AppleEventRunner {
    func run(_ request: MailRequest) throws -> ScriptValue {
      guard case .selection = request else { throw IntegrationError.permissionDenied }
      let message = ScriptValue.list([
        .string("ui-test"), .string("Inbox"), .integer(1), .string("automation@example.org"),
        .integer(UITestFixture.messageSource.utf8.count), .string(UITestFixture.messageSource)
      ])
      return .list([.integer(1), .list([message])])
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
        decision: .init(label: .junk, action: .moveToJunk, reason: .model("Unwanted newsletter")),
        outcome: .dryRun,
        path: .model
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
        state.settings.validatedAccounts = ["ui-test"]
        state.record(initial)
      }
    }

    @MainActor
    private static func seedVisualState(in store: Store) async throws {
      let review = PreviewHelper.record, failed = PreviewHelper.failedRecord
      let corrections = PreviewHelper.corrections
      try await MailHealthRepository.update(store, accountID: "ui-test", name: "Example account") {
        $0.complete(count: 20, total: 30, unavailable: 3)
      }
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

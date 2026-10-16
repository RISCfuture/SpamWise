import SwiftUI
import SpamWiseCore

extension AppModel {
  func verifyKey(_ key: String) {
    let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
    run { [self] in
      guard !credential.isEmpty else { throw ClassificationError.missingCredential }
      keyStatus = String(localized: "Verifying Haiku 5.5…")
      do {
        let raw = Data(
          """
          From: setup@example.org
          Subject: API connection check

          Hello. This is a synthetic SpamWise connection test.
          """
          .utf8
        )
        let message = try MIMEParser().parse(raw)
        guard let store else { throw IntegrationError.unavailable }
        let verdict = try await BudgetedClassifier(
          ClaudeClassifier(key: { credential }),
          store: store,
          upperBoundUSD: 0.10
        ).classify(
          .init(message: message, evidence: .init(message: message))
        )
        try APIKeychain().save(credential)
        do {
          let record = DecisionRecord(
            identity: .init(accountID: nil, contentHash: message.hash),
            sender: String(localized: "SpamWise setup"),
            subject: String(localized: "API connection verification"),
            verdict: verdict,
            decision: .init(
              label: .inbox,
              action: .none,
              reason: String(localized: "Haiku 5.5 connection verified")
            ),
            outcome: .noAction,
            path: "verification"
          )
          try await StateRepository.update(store) { $0.record(record) }
        }
        keyStatus = String(localized: "Verified — stored in Keychain")
        status = String(localized: "Haiku 5.5 is ready")
      } catch { keyStatus = Self.describe(error); throw error }
    }
  }
}

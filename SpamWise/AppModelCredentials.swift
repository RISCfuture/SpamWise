import SwiftUI
import SpamWiseCore

extension AppModel {
  private static let verificationMessage = """
    From: setup@example.org
    Subject: API connection check

    Hello. This is a synthetic SpamWise connection test.
    """

  func verifyKey(_ key: String) {
    let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
    run { [self] in
      guard !credential.isEmpty else { throw ClassificationError.missingCredential }
      keyStatus = String(localized: "Verifying Haiku 5.5…")
      do {
        guard let store else { throw IntegrationError.unavailable }
        let message = try MIMEParser().parse(Data(Self.verificationMessage.utf8))
        let verdict = try await verifyCredential(credential, message: message, store: store)
        try APIKeychain().save(credential)
        try await recordVerification(verdict, message: message, store: store)
        keyStatus = String(localized: "Verified — stored in Keychain")
        status = String(localized: "Haiku 5.5 is ready")
      } catch {
        keyStatus = Self.describe(error)
        throw error
      }
    }
  }

  private func verifyCredential(
    _ credential: String,
    message: ParsedMessage,
    store: Store
  ) async throws -> Verdict {
    try await SpendingLimitedClassifier(
      ClaudeClassifier(key: { credential }),
      modelID: ClaudeClassifier.modelID,
      store: store
    ).classify(.init(message: message, evidence: .init(message: message)))
  }

  private func recordVerification(
    _ verdict: Verdict,
    message: ParsedMessage,
    store: Store
  ) async throws {
    let record = DecisionRecord(
      identity: .init(accountID: nil, contentHash: message.hash),
      verdict: verdict,
      decision: .init(label: .inbox, action: .none, reason: .connectionVerified),
      outcome: .noAction,
      path: .verification
    )
    try await StateRepository.update(store) { $0.record(record) }
  }
}

public import Foundation

/// Dry-run previews for Mail extension callbacks, which carry no account identity.
public enum MailExtensionPreview {
  /// Whether settings allow an extension preview.
  ///
  /// The user must have chosen the extension route for Apple Mail and included every
  /// account, because the extension cannot tell which account a message belongs to.
  public static func allows(_ settings: Settings) -> Bool {
    settings.onboardingComplete && !settings.paused && settings.incomingRoute == .mailKit
      && settings.mailOptions.accountIDs == nil
  }

  /// Records a dry-run decision for one received message when settings allow it.
  ///
  /// Otherwise nothing is recorded and nothing is sent to the classifier.
  /// - Returns: The recorded decision, or `nil` when previews are not allowed.
  public static func process(
    raw: Data,
    store: Store,
    classifier: any Classifier,
    timeout: TimeInterval
  ) async throws -> DecisionRecord? {
    guard allows(try await StateRepository.load(store).settings) else { return nil }
    return await Pipeline(store: store, classifier: classifier).process(
      .init(identity: MessageIdentity(accountID: nil, contentHash: stableHash(raw)), raw: raw),
      forceDryRun: true,
      timeout: timeout
    )
  }
}

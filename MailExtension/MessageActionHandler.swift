import Foundation
import MailKit
import SpamWiseCore

final class MessageActionHandler: NSObject, MEMessageActionHandler {
  private static let maximumClassificationTimeSec: TimeInterval = 8
  private static let completionWatchdog = Duration.seconds(9)
  var requiredHeaders: [String] {
    [
      "From", "Message-ID", "Authentication-Results", "Reply-To", "Return-Path", "List-Unsubscribe",
      "Content-Type", "Content-Transfer-Encoding"
    ]
  }
  func decideAction(
    for message: MEMessage,
    completionHandler: @escaping (MEMessageActionDecision?) -> Void
  ) {
    let completion = CompletionOnce(completionHandler)
    guard message.state == .received else { completion.finish(nil); return }
    guard let raw = message.rawData else { completion.finish(.invokeAgainWithBody); return }
    // MailKit provides no account identifier, so this route records dry runs only.
    let identity = MessageIdentity(accountID: nil, contentHash: stableHash(raw))
    let work = Task {
      do {
        let store = try Store(url: Store.sharedURL())
        try await StateRepository.update(store) { state in
          state.lastExtensionCallback = .now; state.lastBodyCallback = .now
        }
        let state = try await StateRepository.load(store)
        guard !state.settings.paused, state.settings.onboardingComplete,
          state.settings.route != .mailRule, state.settings.route != .imap
        else {
          completion.finish(nil); return
        }
        let pipeline = Pipeline(
          store: store,
          classifier: ConfiguredClassifier(store: store)
        )
        _ = await pipeline.process(
          .init(identity: identity, raw: raw),
          forceDryRun: true,
          timeout: min(Self.maximumClassificationTimeSec, state.settings.callbackDeadline)
        )
      } catch { /* Fail open if App Group/Keychain/persistence is unavailable. */  }
      completion.finish(nil)
    }
    Task {
      try? await Task.sleep(for: Self.completionWatchdog)
      if completion.finish(nil) { work.cancel() }
    }
  }
}

import Foundation
import MailKit
import SpamWiseCore

final class MessageActionHandler: NSObject, MEMessageActionHandler {
  private static let maximumClassificationTimeSec: TimeInterval = 8
  private static let completionWatchdog = Duration.seconds(9)
  private static let store = Result { try Store(url: Store.sharedURL()) }
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
    let raw = message.rawData
    let work = Task {
      do {
        let store = try Self.store.get()
        if let raw {
          _ = try await MailExtensionPreview.process(
            raw: raw,
            store: store,
            classifier: ConfiguredClassifier(store: store),
            timeout: Self.maximumClassificationTimeSec
          )
        } else if MailExtensionPreview.allows(
          try await StateRepository.load(store, StateSlices()).settings
        ) {
          completion.finish(.invokeAgainWithBody); return
        }
      } catch { /* Fail open if App Group/Keychain/persistence is unavailable. */  }
      completion.finish(nil)
    }
    Task {
      try? await Task.sleep(for: Self.completionWatchdog)
      if completion.finish(nil) { work.cancel() }
    }
  }
}

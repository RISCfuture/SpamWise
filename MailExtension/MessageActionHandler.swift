import MailKit
import SpamWiseCore

/// Fail open until the shared pipeline and runtime probes are configured.
final class MessageActionHandler: NSObject, MEMessageActionHandler {
    func decideAction(for message: MEMessage, completionHandler: @escaping (MEMessageActionDecision?) -> Void) {
        completionHandler(nil)
    }
}

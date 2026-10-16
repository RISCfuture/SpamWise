import Foundation
import MailKit

/// Leaves every message to Mail: callbacks carry no account identity SpamWise can trust.
final class MessageActionHandler: NSObject, MEMessageActionHandler {
  func decideAction(
    for _: MEMessage,
    completionHandler: @escaping (MEMessageActionDecision?) -> Void
  ) {
    completionHandler(nil)
  }
}

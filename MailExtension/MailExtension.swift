// Xcode's App Intents metadata extraction warns about a target that does not link AppIntents.
import AppIntents
import MailKit

// Mail constructs the principal object on its XPC queue; it has no actor-bound state.
nonisolated final class MailExtension: NSObject, MEExtension {
  nonisolated func handlerForMessageActions() -> any MEMessageActionHandler {
    MessageActionHandler()
  }
}

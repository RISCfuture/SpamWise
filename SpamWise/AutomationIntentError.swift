import AppIntents
import Foundation
import SpamWiseCore

/// Why a SpamWise Shortcuts action couldn’t run; Mail stays unchanged unless an action was requested.
nonisolated enum AutomationIntentError: AutomationFailure, LocalizedError, Equatable,
  CustomLocalizedStringResourceConvertible
{
  /// The shortcut supplied text that isn’t a UUID as the request identifier.
  case invalidRequestID(String)
  /// SpamWise setup isn’t finished.
  case setupIncomplete
  /// SpamWise reads mail over IMAP, and the action works only with Apple Mail.
  case unsupportedTransport
  /// Mail doesn’t have exactly one message selected.
  case selectionCount
  /// SpamWise isn’t allowed to control Mail.
  case permissionDenied
  /// SpamWise couldn’t read or save its data.
  case storageUnavailable
  /// The request was refused to avoid repeating or misapplying earlier work.
  case refused(reason: String?)
  /// Any other failure, with its non-sensitive reason when it has one.
  case failed(reason: String?)

  /// The description, reason and suggestion together, as Shortcuts shows one message.
  var localizedStringResource: LocalizedStringResource {
    "\(OperationFailure.describe(self))"
  }
  var errorDescription: String? { String(localized: "The SpamWise action couldn’t run.") }
  var failureReason: String? {
    switch self {
      case .invalidRequestID(let text): String(localized: "“\(text)” isn’t a UUID.")
      case .setupIncomplete: String(localized: "SpamWise setup isn’t finished.")
      case .unsupportedTransport:
        String(
          localized: "SpamWise is set to read mail over IMAP, and this action works only with Mail."
        )
      case .selectionCount: String(localized: "Mail doesn’t have exactly one message selected.")
      case .permissionDenied: String(localized: "SpamWise isn’t allowed to control Mail.")
      case .storageUnavailable: String(localized: "SpamWise couldn’t read or save its data.")
      case .refused(let reason), .failed(let reason): reason
    }
  }
  var recoverySuggestion: String? {
    switch self {
      case .invalidRequestID:
        String(
          localized:
            "Leave Request UUID empty to start a new request, or enter the UUID of an earlier run to retry it."
        )
      case .setupIncomplete: String(localized: "Open SpamWise and finish setup.")
      case .unsupportedTransport:
        String(localized: "Choose Apple Mail as the connection in SpamWise Settings.")
      case .selectionCount: String(localized: "Select one message in Mail, then try again.")
      case .permissionDenied:
        String(
          localized:
            "Allow SpamWise to control Mail in System Settings → Privacy & Security → Automation."
        )
      case .storageUnavailable: String(localized: "Quit and reopen SpamWise, then try again.")
      case .refused:
        String(
          localized:
            "Check Activity in SpamWise, then leave Request UUID empty to start a new request."
        )
      case .failed: String(localized: "Check Activity in SpamWise for details.")
    }
  }

  /// The specific case for `error`, keeping the reason of failures this type doesn’t name.
  init(_ error: any Error) {
    switch error {
      case let error as Self: self = error
      case IntegrationError.permissionDenied: self = .permissionDenied
      case IntegrationError.selectionCount: self = .selectionCount
      case is any StorageFailure: self = .storageUnavailable
      case let error as any AutomationFailure & LocalizedError:
        self = .refused(reason: error.failureReason)
      case let error as any LocalizedError:
        self = .failed(reason: error.failureReason ?? error.errorDescription)
      default: self = .failed(reason: nil)
    }
  }
}

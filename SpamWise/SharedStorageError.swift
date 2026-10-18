import Foundation
import SpamWiseCore

/// SpamWise’s shared storage didn’t open at launch, so nothing can be saved and mail stays unchanged.
nonisolated enum SharedStorageError: StorageFailure, LocalizedError {
  /// The store could not be opened.
  case unavailable

  var errorDescription: String? { String(localized: "SpamWise can’t open its data.") }
  var failureReason: String? {
    String(localized: "SpamWise can’t save changes or act on mail; mail stays unchanged.")
  }
  var recoverySuggestion: String? {
    String(
      localized:
        "Quit and reopen SpamWise. If the problem continues, restart your Mac or reinstall SpamWise."
    )
  }
}

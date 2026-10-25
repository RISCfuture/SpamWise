import Foundation
import Observation
import ServiceManagement

/// Whether SpamWise opens at login, which the system's login item service records.
@MainActor
@Observable
final class LoginItemModel {
  /// The login item's status as of the latest change or ``refresh()``.
  private(set) var status = SMAppService.mainApp.status
  /// Turns opening at login on or off.
  let operation = TrackedOperation()

  /// Whether SpamWise opens at login, or will once the user approves it.
  var isEnabled: Bool { status == .enabled || requiresApproval }
  /// Whether the user must approve the login item in System Settings.
  var requiresApproval: Bool { status == .requiresApproval }

  /// Registers or unregisters the login item, then reads its status again.
  func setEnabled(_ enabled: Bool) {
    operation.run { [self] in
      defer { refresh() }
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try await SMAppService.mainApp.unregister()
        }
      } catch {
        throw LoginItemError(underlying: error)
      }
      return nil
    }
  }

  /// Reads the login item's status, which the user may have changed in System Settings.
  func refresh() { status = SMAppService.mainApp.status }
}

/// The login item service refused a change.
struct LoginItemError: LocalizedError {
  /// The service's error.
  let underlying: any Error

  var errorDescription: String? { String(localized: "SpamWise couldn’t change its login item.") }
  var failureReason: String? { underlying.localizedDescription }
  var recoverySuggestion: String? {
    String(localized: "Check Login Items in System Settings › General.")
  }
}

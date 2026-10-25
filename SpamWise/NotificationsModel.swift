import Foundation
import Observation
import SpamWiseCore

/// Count-only summary notifications: permission, preferences and delivery.
@MainActor
@Observable
final class NotificationsModel {
  /// Notification permission, as last read.
  private(set) var permission = String(localized: "Notifications not requested")
  /// Turning notifications on or off.
  let save = TrackedOperation()
  /// The latest delivery failure, until a delivery succeeds.
  private(set) var deliveryFailure: OperationFailure?
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private let center = LocalNotifications()

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
    if !services.uiTesting { center.configure() }
  }

  /// Rereads notification permission.
  func refreshPermission() async {
    guard !services.uiTesting else { return }
    permission = await center.status()
  }

  /**
   Turns summary notifications on or off, asking for permission before turning them on.

   Only activity after they are turned on is announced.
   */
  func setEnabled(_ enabled: Bool) {
    save.run { [self] in
      let store = try services.requireStore()
      if enabled {
        guard !services.uiTesting, try await center.authorize() else {
          permission = String(localized: "Notifications denied in System Settings")
          return nil
        }
      }
      let enabledSince: Date? = enabled ? .now : nil
      try await StateRepository.editSettings(store) {
        $0.mailOptions.notifications.enabledSince = enabledSince
      }
      shared.state.settings.mailOptions.notifications.enabledSince = enabledSince
      await shared.refresh()
      await refreshPermission()
      return nil
    }
  }

  /// Calls `open` with the sheet to show when the user clicks a summary notification.
  func onOpen(_ open: @escaping (ActivitySheet?) -> Void) { center.open = open }

  /// Delivers a due summary when notifications are enabled.
  func deliverIfEnabled() async {
    guard shared.settings.mailOptions.notifications.enabledSince != nil,
      let store = services.store
    else { return }
    do {
      try await center.deliver(store: store, settings: shared.settings)
      deliveryFailure = nil
    } catch {
      deliveryFailure = OperationFailure(
        message: String(localized: "Notification delivery failed. Mail decisions are unchanged.")
      )
    }
  }
}

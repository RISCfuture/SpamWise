import AppKit
import UserNotifications
import SpamWiseCore

@MainActor final class LocalNotifications: NSObject, UNUserNotificationCenterDelegate {
  func configure() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: "review",
        actions: [
          UNNotificationAction(
            identifier: "review",
            title: String(localized: "Review in SpamWise"),
            options: .foreground
          )
        ],
        intentIdentifiers: [],
        options: []
      )
    ])
  }
  func authorize() async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
  }
  func status() async -> String {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    return switch settings.authorizationStatus {
      case .notDetermined: String(localized: "Notifications not requested")
      case .denied: String(localized: "Notifications denied in System Settings")
      case .authorized, .provisional, .ephemeral: String(localized: "Notifications allowed")
      @unknown default: String(localized: "Notification status unavailable")
    }
  }
  func deliver(store: Store) async throws {
    let center = UNUserNotificationCenter.current()
    let authorization = await center.notificationSettings().authorizationStatus
    guard authorization == .authorized || authorization == .provisional else { return }
    guard let batch = try await NotificationPlanning.claim(store: store) else { return }
    let settings = try await StateRepository.load(store, StateSlices()).settings
    let options = settings.mailOptions.notifications
    guard !settings.paused, !settings.dryRun, options.enabledSince != nil,
      !options.isQuiet(at: .now)
    else { return }
    let content = UNMutableNotificationContent()
    content.title = String(localized: "SpamWise mail summary")
    content.body = String(
      localized: "Review: \(batch.review). Good: \(batch.good). Open SpamWise to inspect decisions."
    )
    content.categoryIdentifier = batch.review > 0 ? "review" : "activity"
    try await center.add(
      UNNotificationRequest(identifier: "SpamWise-summary", content: content, trigger: nil)
    )
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let destination =
      response.notification.request.content.categoryIdentifier == "review" ? "review" : "activity"
    await MainActor.run {
      if let url = URL(string: "spamwise://" + destination) { NSWorkspace.shared.open(url) }
    }
  }
}

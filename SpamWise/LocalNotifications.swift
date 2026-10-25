import AppKit
import UserNotifications
import SpamWiseCore

@MainActor
final class LocalNotifications: NSObject, UNUserNotificationCenterDelegate {
  private static let reviewCategory = "review"
  /// Shows Activity for a clicked summary, presenting the digest when it announced Review mail.
  var open: (ActivitySheet?) -> Void = { _ in }

  func configure() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: Self.reviewCategory,
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
  /// Posts the summary of a batch that `settings` allow announcing now, if one is due.
  func deliver(store: Store, settings: SpamWiseCore.Settings) async throws {
    let center = UNUserNotificationCenter.current()
    let authorization = await center.notificationSettings().authorizationStatus
    guard authorization == .authorized || authorization == .provisional else { return }
    guard let batch = try await NotificationPlanning.claim(store: store, settings: settings) else {
      return
    }
    let content = UNMutableNotificationContent()
    content.title = String(localized: "SpamWise mail summary")
    content.body = String(
      localized: "Review: \(batch.review). Good: \(batch.good). Open SpamWise to inspect decisions."
    )
    content.categoryIdentifier = batch.review > 0 ? Self.reviewCategory : "activity"
    try await center.add(
      UNNotificationRequest(identifier: "SpamWise-summary", content: content, trigger: nil)
    )
  }
  /// Shows the summary even while SpamWise is the active app, since its batch is already claimed.
  nonisolated func userNotificationCenter(
    _: UNUserNotificationCenter,
    willPresent _: UNNotification,
    withCompletionHandler completionHandler:
      @escaping @Sendable (UNNotificationPresentationOptions)
      -> Void
  ) {
    completionHandler([.banner, .list])
  }
  nonisolated func userNotificationCenter(
    _: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let category = response.notification.request.content.categoryIdentifier
    await respond(toCategory: category)
  }
  private func respond(toCategory category: String) {
    open(category == Self.reviewCategory ? .digest : nil)
  }
}

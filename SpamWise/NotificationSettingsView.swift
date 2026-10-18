import SwiftUI
import SpamWiseCore

struct NotificationSettingsView: View {
  let notifications: NotificationsModel
  let settings: SettingsModel
  @State private var preferences = NotificationPreferences()
  @State private var enabled = false

  var body: some View {
    DisclosureGroup("Notifications") {
      Text(notifications.permission).foregroundStyle(.secondary)
        .accessibilityIdentifier("notifications.status")
      Toggle("Notify me about unresolved Review", isOn: $enabled)
        .accessibilityIdentifier("notifications.enabled")
      if enabled {
        Toggle("Also include good mail", isOn: $preferences.includeGood)
        Stepper(
          "Batch interval: \(Measurement(value: Double(preferences.intervalMin), unit: UnitDuration.minutes), format: .measurement(width: .wide, usage: .asProvided))",
          value: $preferences.intervalMin,
          in: 5...1440,
          step: 5
        )
        HStack {
          Picker("Quiet from", selection: $preferences.quietStartHour) {
            ForEach(0..<24) { Text($0.formatted() + ":00").tag($0) }
          }
          Picker("Until", selection: $preferences.quietEndHour) {
            ForEach(0..<24) { Text($0.formatted() + ":00").tag($0) }
          }
        }
        Text(
          "Local time. Equal hours disable quiet time. Summaries contain counts, never message content."
        )
        .foregroundStyle(.secondary)
      }
      Button("Save notification preferences") { save() }
        .accessibilityIdentifier("notifications.save")
      OperationStatusView(operation: notifications.save)
    }.task {
      preferences = settings.settings.mailOptions.notifications
      enabled = preferences.enabledSince != nil
      await notifications.refreshPermission()
    }
  }

  private func save() {
    var draft = preferences
    draft.enabledSince = enabled ? preferences.enabledSince ?? .now : nil
    preferences = draft
    notifications.savePreferences(draft)
  }
}

#Preview("Disabled notifications") {
  let model = PreviewHelper.model()
  Form { NotificationSettingsView(notifications: model.notifications, settings: model.settings) }
}

#Preview("Enabled notifications") {
  let model = PreviewHelper.model()
  var preferences = NotificationPreferences()
  preferences.enabledSince = .now
  model.shared.state.settings.mailOptions.notifications = preferences
  return Form {
    NotificationSettingsView(notifications: model.notifications, settings: model.settings)
  }
}

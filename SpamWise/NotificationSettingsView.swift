import SwiftUI
import SpamWiseCore

struct NotificationSettingsView: View {
  let model: AppModel
  @State private var preferences = NotificationPreferences()
  @State private var enabled = false
  @State private var permission = ""

  var body: some View {
    DisclosureGroup("Notifications") {
      Text(permission).foregroundStyle(.secondary).accessibilityIdentifier("notifications.status")
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
      Button("Save notification preferences") { save() }.disabled(model.busy)
        .accessibilityIdentifier("notifications.save")
    }.task {
      preferences = model.state.settings.mailOptions.notifications
      enabled = preferences.enabledSince != nil
      permission =
        model.uiTesting
        ? String(localized: "Notifications not requested") : await model.notifications.status()
    }
  }
  private func save() {
    var draft = preferences
    draft.enabledSince = enabled ? preferences.enabledSince ?? .now : nil
    let saved = draft, wantsNotifications = enabled
    model.run {
      guard let store = model.store else { throw IntegrationError.unavailable }
      if wantsNotifications {
        guard !model.uiTesting, try await model.notifications.authorize() else {
          permission = String(localized: "Notifications denied in System Settings")
          return
        }
      }
      try await StateRepository.editSettings(store) { $0.mailOptions.notifications = saved }
      preferences = saved
      permission = await model.notifications.status()
    }
  }
}

#Preview("Disabled notifications") {
  Form { NotificationSettingsView(model: PreviewHelper.model()) }
}

#Preview("Enabled notifications") {
  let model = PreviewHelper.model()
  var preferences = NotificationPreferences(); preferences.enabledSince = .now
  model.state.settings.mailOptions.notifications = preferences
  return Form { NotificationSettingsView(model: model) }
}

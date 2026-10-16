import SwiftUI
import SpamWiseCore

/// Count-only summary notifications; each control saves as it changes.
struct NotificationSettingsView: View {
  private static let intervalStepMin = 5
  let notifications: NotificationsModel
  let settings: SettingsModel

  private var preferences: NotificationPreferences { settings.settings.mailOptions.notifications }
  private var enabled: Binding<Bool> {
    Binding(
      get: { preferences.enabledSince != nil },
      set: { notifications.setEnabled($0) }
    )
  }

  var body: some View {
    @Bindable var interval = settings.notificationIntervalMin
    Section {
      Toggle("Notify me about unresolved Review", isOn: enabled)
        .disabled(notifications.save.isBusy)
        .accessibilityIdentifier("notifications.enabled")
      if preferences.enabledSince != nil {
        Toggle("Also include good mail", isOn: settings.mailBinding(\.notifications.includeGood))
        Stepper(
          "Batch interval: \(Measurement(value: Double(interval.value), unit: UnitDuration.minutes), format: .measurement(width: .wide, usage: .asProvided))",
          value: $interval.value,
          in: NotificationPreferences.intervalRangeMin,
          step: Self.intervalStepMin
        )
        QuietHoursPicker(
          title: "Quiet from",
          selection: settings.mailBinding(\.notifications.quietStartHour)
        )
        QuietHoursPicker(
          title: "Quiet until",
          selection: settings.mailBinding(\.notifications.quietEndHour)
        )
      }
      OperationStatusView(operation: notifications.save)
    } header: {
      Text("Notifications")
    } footer: {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading) {
          Text(notifications.permission)
            .accessibilityIdentifier("notifications.status")
          Text(
            "Notifications show counts, never message content. Set both quiet hours the same to turn quiet hours off."
          )
        }
        .foregroundStyle(.secondary)
        Spacer()
        HelpButton(page: "notifications")
      }
    }
    .task { await notifications.refreshPermission() }
  }
}

/// An hour of the day, shown in the user's clock format.
private struct QuietHoursPicker: View {
  private static let hours = 0..<24
  let title: LocalizedStringKey
  @Binding var selection: Int

  var body: some View {
    Picker(title, selection: $selection) {
      ForEach(Self.hours, id: \.self) { hour in
        Text(Self.date(atHour: hour), format: .dateTime.hour()).tag(hour)
      }
    }
  }

  private static func date(atHour hour: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
  }
}

#Preview("Disabled notifications") {
  let model = PreviewHelper.model()
  Form { NotificationSettingsView(notifications: model.notifications, settings: model.settings) }
    .formStyle(.grouped)
}

#Preview("Enabled notifications") {
  let model = PreviewHelper.model()
  var preferences = NotificationPreferences()
  preferences.enabledSince = .now
  model.shared.state.settings.mailOptions.notifications = preferences
  return Form {
    NotificationSettingsView(notifications: model.notifications, settings: model.settings)
  }
  .formStyle(.grouped)
}

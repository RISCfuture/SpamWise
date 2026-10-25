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
  /// Why no notification arrives while SpamWise leaves mail unchanged.
  private var deliveryNote: LocalizedStringKey? {
    if settings.settings.dryRun {
      "Notifications start once dry run is off."
    } else if settings.settings.paused {
      "Notifications resume when filtering resumes."
    } else {
      nil
    }
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
          "Notify at most every \(Measurement(value: Double(interval.value), unit: UnitDuration.minutes), format: .measurement(width: .wide, usage: .asProvided))",
          value: $interval.value,
          in: NotificationPreferences.intervalRangeMin,
          step: Self.intervalStepMin
        )
        QuietHoursControls(settings: settings)
      }
      OperationStatusView(operation: notifications.save)
    } header: {
      Text("Notifications")
    } footer: {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading) {
          Text(notifications.permission)
            .accessibilityIdentifier("notifications.status")
          if let deliveryNote { Text(deliveryNote) }
          Text("Notifications show counts, never message content.")
        }
        .foregroundStyle(.secondary)
        Spacer()
        HelpButton(page: "notifications")
      }
    }
    .task { await notifications.refreshPermission() }
  }
}

/// Whether notifications wait during quiet hours, and the hours those span.
private struct QuietHoursControls: View {
  private static let defaultHours = QuietHours(NotificationPreferences())
  let settings: SettingsModel
  /// The hours to restore when quiet hours are turned back on.
  @State private var restoredHours: QuietHours?

  private var preferences: NotificationPreferences { settings.settings.mailOptions.notifications }
  private var isOn: Bool { preferences.quietStartHour != preferences.quietEndHour }

  var body: some View {
    Toggle("Quiet hours", isOn: Binding(get: { isOn }, set: { $0 ? turnOn() : turnOff() }))
    if isOn {
      QuietHoursPicker(
        title: "Quiet from",
        selection: settings.mailBinding(\.notifications.quietStartHour),
        excluding: preferences.quietEndHour
      )
      QuietHoursPicker(
        title: "Quiet until",
        selection: settings.mailBinding(\.notifications.quietEndHour),
        excluding: preferences.quietStartHour
      )
    }
  }

  private func turnOn() {
    let hours = restoredHours ?? Self.defaultHours
    settings.editSettings {
      $0.mailOptions.notifications.quietStartHour = hours.start
      $0.mailOptions.notifications.quietEndHour = hours.end
    }
  }

  /// Ends the quiet period where it starts, which leaves no quiet hours.
  private func turnOff() {
    let hours = QuietHours(preferences)
    restoredHours = hours
    settings.editSettings { $0.mailOptions.notifications.quietEndHour = hours.start }
  }
}

/// The local-clock hours a quiet period starts and ends.
private struct QuietHours {
  let start: Int
  let end: Int

  init(_ preferences: NotificationPreferences) {
    start = preferences.quietStartHour
    end = preferences.quietEndHour
  }
}

/// An hour of the day, shown in the user's clock format, other than the hour at the other end of quiet hours.
private struct QuietHoursPicker: View {
  private static let hours = 0..<24
  let title: LocalizedStringKey
  @Binding var selection: Int
  /// The hour at the other end of quiet hours, which isn't offered.
  let excluding: Int

  var body: some View {
    Picker(title, selection: $selection) {
      ForEach(Self.hours.filter { $0 != excluding }, id: \.self) { hour in
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

import Foundation

/// Formats a decision's date as Mail lists messages: the time for today, otherwise a short date and time.
struct ActivityDateStyle: FormatStyle {
  /// The day shown as time only; nil means the day of formatting.
  var today: Date?
  var locale = Locale.autoupdatingCurrent
  var calendar = Calendar.autoupdatingCurrent
  var timeZone = TimeZone.autoupdatingCurrent

  func format(_ value: Date) -> String {
    var calendar = calendar
    calendar.timeZone = timeZone
    let date: Date.FormatStyle.DateStyle =
      calendar.isDate(value, inSameDayAs: today ?? .now) ? .omitted : .numeric
    return Date.FormatStyle(
      date: date,
      time: .shortened,
      locale: locale,
      calendar: calendar,
      timeZone: timeZone
    ).format(value)
  }

  func locale(_ locale: Locale) -> Self {
    var style = self
    style.locale = locale
    return style
  }
}

extension FormatStyle where Self == ActivityDateStyle {
  /// A decision's date: the time for today, otherwise a short date and time.
  static var activityDate: Self { ActivityDateStyle() }
}

import Foundation

extension Settings {
  /**
   Settings with every live-checked or presentation-only preference reset to its default.

   Pause, dry run and mark-as-read are checked again at dispatch time, and the remaining reset
   fields never affect classification, so changing them supersedes no pending work.
   */
  var policyProjection: Settings {
    var projection = self
    let defaults = Settings()
    projection.paused = defaults.paused
    projection.dryRun = defaults.dryRun
    projection.onboardingComplete = defaults.onboardingComplete
    projection.advancedOptions.weeklyDigest = defaults.advancedOptions.weeklyDigest
    projection.advancedOptions.retainReviewedContent =
      defaults.advancedOptions.retainReviewedContent
    projection.mailOptions.markJunkRead = defaults.mailOptions.markJunkRead
    projection.mailOptions.notifications = defaults.mailOptions.notifications
    return projection
  }
  private static func object(_ settings: Settings) -> Any {
    (try? JSONEncoder().encode(settings)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
      ?? [String: Any]()
  }
  private static func differences(_ current: Any, _ previous: Any, path: String) -> [String] {
    if let current = current as? [String: Any], let previous = previous as? [String: Any] {
      return Set(current.keys).union(previous.keys).flatMap { key in
        differences(
          current[key] ?? NSNull(),
          previous[key] ?? NSNull(),
          path: path.isEmpty ? key : path + "." + key
        )
      }
    }
    return canonical(current) == canonical(previous) ? [] : [path]
  }
  private static func canonical(_ value: Any) -> String {
    guard let array = value as? [Any] else { return String(describing: value) }
    return array.map(canonical).sorted().joined(separator: "\u{0}")
  }
  /// Dotted names of the encoded fields whose values differ from `previous`.
  public func changedFields(from previous: Settings) -> [String] {
    Self.differences(Self.object(self), Self.object(previous), path: "").sorted()
  }
}

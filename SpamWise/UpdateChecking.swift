public import Foundation
public import SwiftUI

/**
 How often the downloadable edition looks for a new release on its own.

 Mirrors the cadences the update checker supports. The framework keeps its own
 enumeration because the checker is linked by the downloadable edition alone, so
 the shared interface cannot name the library's type.
 */
public enum UpdateCheckCadence: String, CaseIterable, Identifiable, Sendable {
  /// Checks every hour while SpamWise runs.
  case hourly
  /// Checks once a day.
  case daily
  /// Checks once a week.
  case weekly
  /// Checks only when asked.
  case never

  /// The cadence itself, so a picker can iterate the cases.
  public var id: Self { self }

  var localizedTitle: String {
    switch self {
      case .hourly: String(localized: "Hourly")
      case .daily: String(localized: "Daily")
      case .weekly: String(localized: "Weekly")
      case .never: String(localized: "Never")
    }
  }
}

/**
 The downloadable edition's ability to check GitHub for a newer release, and the
 preferences governing it.

 The App Store edition, previews and tests supply none, and the update command
 and settings appear only when one is present. Conformers forward to observable
 storage, so SwiftUI tracks these properties through the existential.
 */
@MainActor
public protocol UpdateChecking: AnyObject, Sendable {
  /// Whether a check can start now; `false` while one is already running.
  var canCheckForUpdates: Bool { get }

  /// When the last check finished, or `nil` if none has run.
  var lastCheckDate: Date? { get }

  /// How often SpamWise checks on its own.
  var cadence: UpdateCheckCadence { get set }

  /// Whether prereleases count as available updates.
  var includesPrereleases: Bool { get set }

  /// Whether the user has dismissed any version with “Skip This Version”.
  var hasSkippedVersions: Bool { get }

  /// Checks for a newer release and presents the result.
  func checkForUpdatesAndShowUI() async

  /// Forgets every skipped version, so each is offered again.
  func resetSkippedVersions()
}

extension EnvironmentValues {
  /// The edition's update checker, or `nil` where the edition cannot update itself.
  @Entry public var updates: (any UpdateChecking)?
}

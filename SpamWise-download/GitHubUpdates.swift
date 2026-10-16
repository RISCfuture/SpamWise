import Foundation
import GitHubUpdateChecker
import SpamWiseCommon

/**
 Backs the shared Check for Updates command and update settings with the GitHub
 Releases API.

 Only this edition links the checker. The repository comes from this build's
 Info.plist; a build that names none has no checker, and the update controls
 stay hidden.
 */
@MainActor
final class GitHubUpdates: UpdateChecking {
  private let checker: GitHubUpdateChecker

  var canCheckForUpdates: Bool { checker.canCheckForUpdates }

  var lastCheckDate: Date? { checker.lastCheckDate }

  var cadence: UpdateCheckCadence {
    get { UpdateCheckCadence(checker.preferences.updateCadence) }
    set { checker.preferences.updateCadence = newValue.updateCadence }
  }

  var includesPrereleases: Bool {
    get { checker.preferences.checkForPrereleases }
    set { checker.preferences.checkForPrereleases = newValue }
  }

  var hasSkippedVersions: Bool { !checker.preferences.skippedVersions.isEmpty }

  init?(configuration: DirectUpdateConfiguration? = DirectUpdateConfiguration()) {
    guard let configuration else { return nil }
    checker = GitHubUpdateChecker(owner: configuration.owner, repo: configuration.repository)
  }

  /// Starts checking on the chosen cadence; the schedule runs only while SpamWise does.
  func startAutomaticChecks() { checker.startAutomaticChecks() }

  func checkForUpdatesAndShowUI() async { await checker.checkForUpdatesAndShowUI() }

  func resetSkippedVersions() { checker.preferences.resetSkippedVersions() }
}

extension UpdateCheckCadence {
  fileprivate var updateCadence: UpdateCadence {
    switch self {
      case .hourly: .hourly
      case .daily: .daily
      case .weekly: .weekly
      case .never: .never
    }
  }

  fileprivate init(_ cadence: UpdateCadence) {
    switch cadence {
      case .hourly: self = .hourly
      case .daily: self = .daily
      case .weekly: self = .weekly
      case .never: self = .never
    }
  }
}

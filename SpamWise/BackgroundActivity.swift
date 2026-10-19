import Foundation

/**
 Mail work that keeps its pace while SpamWise has no visible window.

 App Nap throttles the timers of an app whose windows are closed or hidden, which would stretch
 Mail's call deadlines and the waits for moved messages to appear. Each run holds a process
 activity that keeps App Nap off until the work ends; the Mac can still sleep when idle.
 */
enum BackgroundActivity {
  /// Runs `work` with App Nap off, naming `reason` to the system.
  static func run<Result>(_ reason: String, _ work: () async throws -> Result) async rethrows
    -> Result
  {
    let activity = ProcessInfo.processInfo.beginActivity(
      options: .userInitiatedAllowingIdleSystemSleep,
      reason: reason
    )
    defer { ProcessInfo.processInfo.endActivity(activity) }
    return try await work()
  }
}

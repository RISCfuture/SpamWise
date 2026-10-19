import SpamWiseCore

/// Repeats a storage operation while another process holds the store's lock, waiting longer
/// before each new attempt.
struct LockRetry {
  private static let firstLoadDelay: Duration = .seconds(1)
  private static let firstLoadRetries = 2
  private static let backoffFactor = 2
  /// Retries for the first read of shared storage, so a briefly busy store isn't reported.
  static let firstLoad = Self(
    delays: Array(
      sequence(first: firstLoadDelay) { $0 * backoffFactor }.prefix(firstLoadRetries)
    )
  )
  /// The wait before each retry; their count bounds the retries.
  let delays: [Duration]

  /// Runs `operation`, retrying only while the store's lock is unavailable.
  func run<T>(_ operation: () async throws -> T) async throws -> T {
    for delay in delays {
      do { return try await operation() } catch StoreError.lockUnavailable {
        try await Task.sleep(for: delay)
      }
    }
    return try await operation()
  }
}

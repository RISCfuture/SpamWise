import Observation

/**
 Runs one piece of background work at a time.

 A request made while the work runs is not dropped: all such requests coalesce into a single
 further run once the current one finishes.
 */
@MainActor @Observable final class CoalescingRunner {
  /// Whether the work is running.
  private(set) var isRunning = false
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var pending: (@MainActor () async -> Void)?

  /// Starts `work` now, or once after the run in progress when one is running.
  func request(_ work: @escaping @MainActor () async -> Void) {
    guard task == nil else {
      pending = work
      return
    }
    start(work)
  }

  /// Cancels the run in progress and any coalesced request.
  func cancel() {
    pending = nil
    task?.cancel()
  }

  private func start(_ work: @escaping @MainActor () async -> Void) {
    isRunning = true
    task = Task { [self] in
      await work()
      task = nil
      if let next = pending {
        pending = nil
        start(next)
      } else {
        isRunning = false
      }
    }
  }
}

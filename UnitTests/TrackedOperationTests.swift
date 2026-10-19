import Foundation
import Testing
import SpamWiseCore
@testable import SpamWiseCommon

@MainActor
@Suite
struct `Tracked user operations` {
  @Test
  func `run one at a time in the order requested`() async {
    let operation = TrackedOperation()
    let gate = Gate()
    var events: [String] = []
    let first = operation.run {
      events.append("first started")
      await gate.wait()
      events.append("first finished")
      return nil
    }
    let second = operation.run {
      events.append("second started")
      return nil
    }
    await gate.waitUntilWaiting()
    #expect(events == ["first started"])
    #expect(operation.isBusy)
    gate.open()
    await first.value
    await second.value
    #expect(events == ["first started", "first finished", "second started"])
    #expect(!operation.isBusy)
  }

  @Test
  func `show a failure until the next run succeeds silently`() async {
    let operation = TrackedOperation()
    await operation.run { throw IntegrationError.unavailable }.value
    #expect(
      operation.failure?.description == OperationFailure.describe(IntegrationError.unavailable)
    )
    #expect(operation.failure?.recovery == nil)
    await operation.run { nil }.value
    #expect(operation.status == nil)
  }

  @Test
  func `offer to rerun only work marked safe to repeat`() async {
    let operation = TrackedOperation()
    var attempts = 0
    await operation.run(retryable: true) {
      attempts += 1
      if attempts == 1 { throw IntegrationError.unavailable }
      return "Read"
    }.value
    #expect(operation.failure?.recovery == .tryAgain)
    operation.retryFailed()
    await operation.run { nil }.value
    #expect(attempts == 2)
  }

  @Test
  func `report cancelled runs instead of dropping them`() async {
    let operation = TrackedOperation()
    var queuedRan = false
    let running = operation.run {
      try await Task.sleep(for: .seconds(60))
      return nil
    }
    let queued = operation.run {
      queuedRan = true
      return nil
    }
    operation.cancel()
    await running.value
    await queued.value
    #expect(!queuedRan)
    #expect(operation.status == .message(OperationFailure.describe(CancellationError())))
  }
}

@MainActor
@Suite
struct `Coalesced background work` {
  @Test
  func `runs once more after requests made while it runs`() async {
    let runner = CoalescingRunner()
    let gate = Gate()
    let finished = Counter()
    var runs = 0
    let work: @MainActor () async -> Void = {
      runs += 1
      if runs == 1 { await gate.wait() }
      finished.increment()
    }
    runner.request(work)
    await gate.waitUntilWaiting()
    runner.request(work)
    runner.request(work)
    gate.open()
    await finished.wait(for: 2)
    while runner.isRunning { await Task.yield() }
    #expect(runs == 2)
  }

  @Test
  func `drops the coalesced request when cancelled`() async {
    let runner = CoalescingRunner()
    let finished = Counter()
    var runs = 0
    let work: @MainActor () async -> Void = {
      runs += 1
      try? await Task.sleep(for: .seconds(60))
      finished.increment()
    }
    runner.request(work)
    runner.request(work)
    runner.cancel()
    await finished.wait(for: 1)
    while runner.isRunning { await Task.yield() }
    #expect(runs == 1)
  }
}

/// Holds work at ``wait()`` until the test opens it.
@MainActor
final class Gate {
  private var waiter: CheckedContinuation<Void, Never>?
  private var isOpen = false

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { waiter = $0 }
  }

  func waitUntilWaiting() async {
    while waiter == nil { await Task.yield() }
  }

  func open() {
    isOpen = true
    waiter?.resume()
    waiter = nil
  }
}

/// Counts finished work and lets a test wait for a total.
@MainActor
final class Counter {
  private(set) var value = 0

  func increment() { value += 1 }

  func wait(for total: Int) async {
    while value < total { await Task.yield() }
  }
}

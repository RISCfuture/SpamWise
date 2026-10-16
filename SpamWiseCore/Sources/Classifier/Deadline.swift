public import Foundation
import Synchronization

private final class DeadlineRace<T: Sendable>: Sendable {
  struct State: Sendable {
    var continuation: CheckedContinuation<T, any Error>?
    var result: Result<T, any Error>?
    var tasks: [Task<Void, Never>] = []
  }
  private let state = Mutex(State())
  func install(_ continuation: CheckedContinuation<T, any Error>) {
    let existing = state.withLock { state -> Result<T, any Error>? in
      if let result = state.result { return result }
      state.continuation = continuation; return nil
    }
    if let existing { continuation.resume(with: existing) }
  }
  func register(_ tasks: [Task<Void, Never>]) {
    let done = state.withLock { state in
      if state.result != nil { return true }; state.tasks = tasks; return false
    }
    if done { tasks.forEach { $0.cancel() } }
  }
  func finish(_ result: Result<T, any Error>) {
    let delivery = state.withLock {
      state -> (CheckedContinuation<T, any Error>?, [Task<Void, Never>]) in
      guard state.result == nil else { return (nil, []) }
      state.result = result; let delivery = (state.continuation, state.tasks)
      state.continuation = nil; state.tasks = []; return delivery
    }
    delivery.1.forEach { $0.cancel() }
    delivery.0?.resume(with: result)
  }
}
/// Returns at the deadline even if a provider ignores cancellation; late results are discarded.
public func withDeadline<T: Sendable>(
  seconds: TimeInterval,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  let race = DeadlineRace<T>()
  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { continuation in
      race.install(continuation)
      let work = Task.detached {
        do { try Task.checkCancellation(); race.finish(.success(try await operation())) } catch {
          race.finish(.failure(error))
        }
      }
      let timer = Task.detached {
        do {
          try await Task.sleep(for: .seconds(max(0.001, seconds)))
          race.finish(.failure(ClassificationError.timeout))
        } catch {}
      }
      race.register([work, timer])
    }
  } onCancel: {
    race.finish(.failure(CancellationError()))
  }
}

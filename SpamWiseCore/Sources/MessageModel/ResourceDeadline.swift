public import Foundation
import Synchronization

/// Failures caused by an operation exceeding its available time.
public protocol OperationDeadlineError: Error {}

/// A resource operation that exceeded its wall-clock deadline.
public enum ResourceDeadlineError: OperationDeadlineError, Sendable, LocalizedError {
  case timeout
  /// Non-sensitive description of the deadline failure.
  public var errorDescription: String? { String(localized: "The operation timed out.") }
}

private final class DeadlineRace<T: Sendable>: Sendable {
  static var minimumTimeoutSec: TimeInterval { 0.001 }
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
  struct State: Sendable {
    var continuation: CheckedContinuation<T, any Error>?
    var result: Result<T, any Error>?
    var tasks: [Task<Void, Never>] = []
  }
}
/// Returns at the deadline even if a provider ignores cancellation; late results are discarded.
public func withResourceDeadline<T: Sendable>(
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
          let minimum = DeadlineRace<T>.minimumTimeoutSec
          try await Task.sleep(for: .seconds(seconds.isFinite ? max(minimum, seconds) : minimum))
          race.finish(.failure(ResourceDeadlineError.timeout))
        } catch {}
      }
      race.register([work, timer])
    }
  } onCancel: {
    race.finish(.failure(CancellationError()))
  }
}

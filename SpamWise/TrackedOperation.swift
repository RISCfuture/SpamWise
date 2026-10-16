import Foundation
import Observation
import SpamWiseCore

/// The visible result of the latest run of one user operation.
enum OperationStatus: Equatable {
  /// Neutral information, such as what a finished operation did.
  case message(String)
  /// A failure the user may need to act on.
  case failure(OperationFailure)
}

/// A failure described for the user, with the action that may resolve it.
struct OperationFailure: Equatable {
  /// The failure's description, reason and any recovery suggestion.
  let description: String
  /// The action offered next to the failure, if any.
  let recovery: Recovery?

  /// Describes `error`, offering `retry` when the operation can safely run again.
  init(_ error: any Error, retry: Recovery? = nil) {
    description = Self.describe(error)
    recovery = error as? IntegrationError == .permissionDenied ? .openAutomationSettings : retry
    DeveloperDiagnostics.record(error)
  }

  /// A failure described by `message`.
  init(message: String, recovery: Recovery? = nil) {
    description = message
    self.recovery = recovery
  }

  /// The error's localized description, reason and recovery suggestion, which carry no secrets.
  nonisolated static func describe(_ error: any Error) -> String {
    if error is CancellationError {
      return String(localized: "Cancelled — no further actions requested.")
    }
    let details = (error as? any LocalizedError).map {
      [$0.errorDescription, $0.failureReason, $0.recoverySuggestion]
        .compactMap(\.self).filter { !$0.isEmpty }
    }
    guard let details, !details.isEmpty else {
      return String(
        localized: "Operation unavailable. Mail stays unchanged; check Help for troubleshooting."
      )
    }
    return details.joined(separator: " ")
  }

  /// An action offered next to a failure.
  enum Recovery: Equatable {
    /// Opens Automation privacy settings.
    case openAutomationSettings
    /// Runs the failed operation again.
    case tryAgain
  }
}

/**
 One kind of user operation, such as saving rules or checking the Mail connection.

 Runs are serialized: a run requested while another is in progress waits for it, so a click is
 never dropped. Each run's result replaces ``status``: its message, nothing on a silent success,
 or its failure. Different operations run independently of each other.
 */
@MainActor
@Observable
final class TrackedOperation {
  /// Whether a run is executing or waiting for an earlier one.
  private(set) var isBusy = false
  /// The latest run's result, cleared when a run starts.
  var status: OperationStatus?
  @ObservationIgnored private var tail: Task<Void, Never>?
  @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var retry: (@MainActor () async throws -> String?)?

  /// The failure of the latest run, if it failed.
  var failure: OperationFailure? {
    if case .failure(let failure) = status { failure } else { nil }
  }

  /**
   Runs `work` after every earlier run of this operation.

   - Parameters:
     - retryable: Whether a failure offers to run `work` again; set it only for work that is
       safe to repeat, such as reads.
     - work: Returns a neutral message to show, or nil to show nothing.
   - Returns: The run, which finishes after its status is set.
   */
  @discardableResult
  func run(
    retryable: Bool = false,
    _ work: @escaping @MainActor () async throws -> String?
  ) -> Task<Void, Never> {
    let id = UUID(), previous = tail
    isBusy = true
    let task = Task { [self] in
      await previous?.value
      await execute(work, retryable: retryable)
      tasks[id] = nil
      isBusy = !tasks.isEmpty
    }
    tasks[id] = task
    tail = task
    return task
  }

  /// Cancels the running and waiting runs; each reports that it was cancelled.
  func cancel() {
    for task in tasks.values { task.cancel() }
  }

  /// Runs the failed work again, when it offered to.
  func retryFailed() {
    guard let retry else { return }
    run(retryable: true, retry)
  }

  private func execute(
    _ work: @escaping @MainActor () async throws -> String?,
    retryable: Bool
  ) async {
    status = nil
    retry = nil
    do {
      try Task.checkCancellation()
      status = try await work().map(OperationStatus.message)
    } catch is CancellationError {
      status = .message(OperationFailure.describe(CancellationError()))
    } catch {
      status = .failure(OperationFailure(error, retry: retryable ? .tryAgain : nil))
      if retryable { retry = work }
    }
  }
}

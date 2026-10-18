public import Foundation
import MessageModel

/// Throws ``ClassificationError/timeout`` after `seconds` even if a provider ignores cancellation, discarding a late result.
public func withDeadline<T: Sendable>(
  seconds: TimeInterval,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  do {
    return try await withResourceDeadline(seconds: seconds, operation: operation)
  } catch ResourceDeadlineError.timeout { throw ClassificationError.timeout }
}

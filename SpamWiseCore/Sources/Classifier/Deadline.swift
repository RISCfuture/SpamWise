public import Foundation
import MessageModel

/// Returns at the deadline even if a provider ignores cancellation; late results are discarded.
public func withDeadline<T: Sendable>(
  seconds: TimeInterval,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  do {
    return try await withResourceDeadline(seconds: seconds, operation: operation)
  } catch ResourceDeadlineError.timeout { throw ClassificationError.timeout }
}

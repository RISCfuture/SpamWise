import Foundation
/// Bridges a legacy callback that may be invoked on any queue. The lock protects
/// exclusive ownership; invocation happens after removal, outside the lock.
public final class CompletionOnce<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var callback: ((Value) -> Void)?
  /// Creates a CompletionOnce with the supplied configuration.
  public init(_ callback: @escaping (Value) -> Void) { self.callback = callback }
  /// Invokes the stored callback at most once across concurrent callers.
  @discardableResult public func finish(_ value: Value) -> Bool {
    let callback = lock.withLock {
      let result = self.callback; self.callback = nil; return result
    }
    guard let callback else { return false }; callback(value); return true
  }
}

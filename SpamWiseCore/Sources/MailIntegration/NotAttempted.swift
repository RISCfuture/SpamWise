import SpamWiseCore

/// Rethrows failures from steps that precede any mail command as ``ActionNotAttempted``.
func notAttempted<Value>(_ step: () async throws -> Value) async throws -> Value {
  do {
    return try await step()
  } catch let error as ActionNotAttempted {
    throw error
  } catch is CancellationError {
    throw CancellationError()
  } catch {
    throw ActionNotAttempted(cause: error)
  }
}

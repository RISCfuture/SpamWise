public import Foundation
import MessageModel
import Darwin

/// Failures while collecting optional local evidence.
public protocol LocalEvidenceError: Error {}

/// A local evidence process failure, never positive spam evidence.
public enum EvidenceProcessError: LocalEvidenceError, Sendable, LocalizedError {
  case inputLimit, outputLimit, timeout, failed
  /// Non-sensitive description suitable for status reporting.
  public var errorDescription: String? { String(localized: "Local evidence is unavailable.") }
  /// The resource or process failure, without message content or process output.
  public var failureReason: String? {
    switch self {
      case .inputLimit: String(localized: "The message exceeds the local evidence input limit.")
      case .outputLimit: String(localized: "The local evidence response exceeds the output limit.")
      case .timeout: String(localized: "The local evidence process timed out.")
      case .failed: String(localized: "The local evidence process could not complete.")
    }
  }
}

/// Injectable, bounded process execution without shell parsing or temporary message files.
public struct EvidenceProcess: Sendable {
  private static let maximumInputBytes = 2_000_000
  private static let maximumOutputBytes = 65_536
  private static let timeoutSec: TimeInterval = 3
  private static let terminationPollInterval = Duration.milliseconds(10)
  /// Local execution with bounded pipes, a three-second deadline and child termination on cancellation.
  public static let live = EvidenceProcess { executable, arguments, input in
    let process = Process(), stdin = Pipe(), stdout = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
      throw EvidenceProcessError.failed
    }
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try process.run()
      let writer = Task.detached {
        defer { try? stdin.fileHandleForWriting.close() }
        try stdin.fileHandleForWriting.write(contentsOf: input)
      }
      defer {
        writer.cancel()
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        try? stdout.fileHandleForReading.close()
      }
      try Task.checkCancellation()
      var output = Data()
      for try await byte in stdout.fileHandleForReading.bytes {
        guard output.count < maximumOutputBytes else { throw EvidenceProcessError.outputLimit }
        output.append(byte)
      }
      while process.isRunning { try await Task.sleep(for: terminationPollInterval) }
      try await writer.value
      guard process.terminationStatus == 0 else { throw EvidenceProcessError.failed }
      return output
    } onCancel: {
      if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
    }
  }

  private let operation: @Sendable (String, [String], Data) async throws -> Data

  /// Installs an execution boundary for local processes or deterministic fixtures.
  public init(_ operation: @escaping @Sendable (String, [String], Data) async throws -> Data) {
    self.operation = operation
  }

  /// Runs a bounded request and rejects excess output even from an injected operation.
  public func run(executable: String, arguments: [String], input: Data) async throws -> Data {
    guard input.count <= Self.maximumInputBytes else { throw EvidenceProcessError.inputLimit }
    do {
      let output = try await withResourceDeadline(seconds: Self.timeoutSec) {
        try await operation(executable, arguments, input)
      }
      guard output.count <= Self.maximumOutputBytes else { throw EvidenceProcessError.outputLimit }
      return output
    } catch ResourceDeadlineError.timeout { throw EvidenceProcessError.timeout }
  }
}

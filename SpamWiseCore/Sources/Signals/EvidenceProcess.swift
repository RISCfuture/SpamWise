public import Foundation
import MessageModel
import Darwin

/// A local evidence process failure, never positive spam evidence.
public enum EvidenceProcessError: Error, Sendable, LocalizedError {
  case inputLimit, outputLimit, timeout, failed
  /// Non-sensitive description suitable for status reporting.
  public var errorDescription: String? { "Local evidence is unavailable." }
}

/// Injectable, bounded process execution without shell parsing or temporary message files.
public struct EvidenceProcess: Sendable {
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
        guard output.count < 65_536 else { throw EvidenceProcessError.outputLimit }
        output.append(byte)
      }
      while process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
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
    guard input.count <= 2_000_000 else { throw EvidenceProcessError.inputLimit }
    do {
      let output = try await withResourceDeadline(seconds: 3) {
        try await operation(executable, arguments, input)
      }
      guard output.count <= 65_536 else { throw EvidenceProcessError.outputLimit }
      return output
    } catch ResourceDeadlineError.timeout { throw EvidenceProcessError.timeout }
  }
}

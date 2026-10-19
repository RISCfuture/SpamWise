import Foundation
import Testing
import SpamWiseCore
@testable import SpamWiseCommon

@Suite
struct `Shortcuts action failures` {
  @Test(arguments: [
    (IntegrationError.permissionDenied as any Error, AutomationIntentError.permissionDenied),
    (IntegrationError.selectionCount(minimum: 1, maximum: 1), .selectionCount),
    (SharedStorageError.unavailable, .storageUnavailable),
    (StoreError.lockUnavailable, .storageUnavailable),
    (
      AutomationError.requestReused,
      .refused(reason: AutomationError.requestReused.failureReason)
    ),
    (IntegrationError.timedOut, .failed(reason: IntegrationError.timedOut.failureReason)),
    (AutomationIntentError.setupIncomplete, .setupIncomplete)
  ])
  func `name the condition that stopped the action`(
    _ underlying: any Error,
    _ expected: AutomationIntentError
  ) {
    #expect(AutomationIntentError(underlying) == expected)
  }

  @Test
  func `start a new request unless the shortcut supplies a UUID`() throws {
    let saved = UUID()
    #expect(try AutomationRequestID.resolve(" \(saved.uuidString)\n") == saved)
    #expect(try AutomationRequestID.resolve(nil) != AutomationRequestID.resolve(" "))
    #expect(throws: AutomationIntentError.invalidRequestID("retry")) {
      try AutomationRequestID.resolve("retry")
    }
  }
}

@Suite
struct `Bounded file imports` {
  private static let maximumBytes = 8

  @Test
  func `read a file at the limit and refuse a larger one`() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fitting = directory.appending(path: "fitting.json")
    let oversized = directory.appending(path: "oversized.json")
    try Data(count: Self.maximumBytes).write(to: fitting)
    try Data(count: Self.maximumBytes + 1).write(to: oversized)

    #expect(try fitting.readSecurityScoped(maximumBytes: Self.maximumBytes).count == 8)
    #expect(throws: FileImportError.tooLarge(name: "oversized.json", maximumBytes: 8)) {
      try oversized.readSecurityScoped(maximumBytes: Self.maximumBytes)
    }
  }
}

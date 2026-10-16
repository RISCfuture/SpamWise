import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Automation request replay` {
  private let store: Store
  private let adapter = RecordingAdapter()
  private let pipeline: Pipeline
  private let selected: MailEnvelope

  init() async throws {
    store = try testStore()
    try await enableActions(store)
    pipeline = Pipeline(store: store, classifier: junkClassifier)
    selected = try envelope()
  }

  private func execute(_ operation: AutomationOperation, _ requestID: UUID) async throws
    -> AutomationReply
  {
    try await pipeline.execute(
      operation,
      requestID: requestID,
      envelope: selected,
      adapter: adapter
    )
  }

  @Test
  func `replays a preview without classifying again`() async throws {
    let requestID = UUID()
    let first = try await execute(.preview, requestID)
    #expect(first.outcome == .dryRun)
    #expect(try await execute(.preview, requestID) == first)
    #expect(try await StateRepository.load(store).records.count == 1)
  }

  @Test
  func `refuses to reuse a request for a different command`() async throws {
    let requestID = UUID()
    _ = try await execute(.preview, requestID)
    await #expect(throws: AutomationError.requestReused) {
      try await execute(.correct(.junk), requestID)
    }
  }

  @Test
  func `replays a correction without repeating its action or example`() async throws {
    let requestID = UUID()
    let corrected = try await execute(.correct(.inbox), requestID)
    #expect(corrected.outcome == .applied)
    #expect(try await execute(.correct(.inbox), requestID) == corrected)
    #expect(await adapter.actions == [.moveToInbox])
    #expect(try await StateRepository.load(store).corrections.count == 1)
  }
}

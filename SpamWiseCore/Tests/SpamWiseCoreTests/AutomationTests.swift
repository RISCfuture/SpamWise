import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Automation request replay` {
  private static let automationRequestsKey = "automation-requests-v1"
  private static let automationRequestLimit = 10_000
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

  /// Replaces the remembered automation requests with as many as fit, claimed at `claimedAt`.
  private func fillAutomationRequests(reply: AutomationReply?, claimedAt: Date) async throws {
    try await store.update(Self.automationRequestsKey, default: [UUID: StoredRequest]()) {
      requests in
      requests = [:]
      while requests.count < Self.automationRequestLimit {
        requests[UUID()] = StoredRequest(fingerprint: "other", reply: reply, claimedAt: claimedAt)
      }
    }
  }

  @Test
  func `replays a preview without classifying again`() async throws {
    let requestID = UUID()
    let first = try await execute(.preview, requestID)
    #expect(first.outcome == .dryRun)
    #expect(try await execute(.preview, requestID) == first)
    #expect(try await StateRepository.load(store).records.count == 1)
  }

  @Test(arguments: [
    (finished: true, ageDays: 31.0, accepted: true),
    (true, 1, true),
    (false, 31, false)
  ])
  func `makes room for new requests by forgetting completed ones`(
    finished: Bool,
    ageDays: Double,
    accepted: Bool
  ) async throws {
    let first = try await execute(.preview, UUID())
    try await fillAutomationRequests(
      reply: finished ? first : nil,
      claimedAt: Date.now.addingTimeInterval(-ageDays * 86_400)
    )
    if accepted {
      let requestID = UUID()
      let next = try await execute(.preview, requestID)
      #expect(next.outcome == .dryRun)
      #expect(try await execute(.preview, requestID) == next)
    } else {
      await #expect(throws: AutomationError.tooManyRequests(limit: Self.automationRequestLimit)) {
        try await execute(.preview, UUID())
      }
    }
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

/// The stored shape of one remembered automation request.
private struct StoredRequest: Codable, Sendable {
  var fingerprint: String
  var reply: AutomationReply?
  var claimedAt: Date
}

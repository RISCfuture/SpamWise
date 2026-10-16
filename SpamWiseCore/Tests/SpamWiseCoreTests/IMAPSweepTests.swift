import Foundation
import Testing
@testable import MailIntegration
import SpamWiseCore

@Suite
struct `sweeps new IMAP Inbox mail` {
  private static func inbox(exists: Int, uidNext: Int? = nil) -> IMAPTranscript {
    IMAPTranscript.authenticated().examine(validity: 33, exists: exists, uidNext: uidNext)
  }
  private static func rows(_ uids: ClosedRange<Int>, size: Int) -> [IMAPTranscript.Row] {
    uids.reversed().map { .init($0, uid: $0, size: size) }
  }
  private static func committedSweep(
    _ server: IMAPTestServer,
    limit: Int,
    store: Store
  ) async throws -> [MailEnvelope] {
    let adapter = await server.adapter()
    let sweep = try await adapter.nextInboxSweep(limit: limit, cursorStore: store)
    try await adapter.commit(sweep, cursorStore: store)
    return sweep.messages
  }

  @Test
  func `starts at the newest existing UID and reads every new message before older pages`()
    async throws
  {
    let store = try testStore()
    let raw = "From: sender@example.com\r\n\r\nHello"
    let boundary = IMAPTestServer(
      Self.inbox(exists: 3).metadata([.init(3, uid: 3, size: 10)])
    )
    #expect(try await Self.committedSweep(boundary, limit: 2, store: store).isEmpty)
    #expect(
      await boundary.commands.filter { $0.contains("FETCH") } == ["FETCH 3 (UID RFC822.SIZE)"]
    )
    var transcript = Self.inbox(exists: 7, uidNext: 8)
      .metadata(Self.rows(1...7, size: raw.utf8.count))
    for uid in 4...7 { transcript = transcript.body(raw, uid: uid, sequence: uid) }
    let delivered = IMAPTestServer(
      transcript.metadata(Self.rows(2...3, size: raw.utf8.count))
    )
    let messages = try await Self.committedSweep(delivered, limit: 2, store: store)
    #expect(messages.map(\.identity.localID) == [4, 5, 6, 7])
    let commands = await delivered.commands
    #expect(commands.contains("FETCH 2:3 (UID RFC822.SIZE)"))
    #expect(commands.filter { $0.contains("BODY.PEEK") }.count == 4)
  }

  @Test
  func `resumes new mail deferred by the byte budget before revisiting older pages`()
    async throws
  {
    let store = try testStore()
    let prefix = "From: sender@example.com\r\n\r\n"
    let raw = prefix + String(repeating: "a", count: 1_000_000 - prefix.utf8.count)
    _ = try await Self.committedSweep(
      IMAPTestServer(Self.inbox(exists: 0, uidNext: 1)),
      limit: 20,
      store: store
    )
    var first = Self.inbox(exists: 5, uidNext: 6).metadata(Self.rows(1...5, size: 1_000_000))
    for uid in 1...4 { first = first.body(raw, uid: uid, sequence: uid) }
    let deferred = try await Self.committedSweep(IMAPTestServer(first), limit: 20, store: store)
    #expect(deferred.map(\.identity.localID) == [1, 2, 3, 4])
    var second = Self.inbox(exists: 5, uidNext: 6).metadata(Self.rows(1...5, size: 1_000_000))
      .body(raw, uid: 5, sequence: 5).metadata(Self.rows(1...4, size: 1_000_000))
    for uid in (1...4).reversed() { second = second.body(raw, uid: uid, sequence: uid) }
    let server = IMAPTestServer(second)
    let resumed = try await Self.committedSweep(server, limit: 20, store: store)
    #expect(resumed.map(\.identity.localID) == [5, 4, 3, 2, 1])
    #expect(await server.commands.contains("FETCH 1:4 (UID RFC822.SIZE)"))
  }

  @Test
  func `resumes from sweep progress saved under the host as written`() async throws {
    var mixedCase = IMAPConfiguration.test
    mixedCase.host = "IMAP.Example.com"
    let raw = "From: sender@example.com\r\n\r\nHello"
    let original = try testStore(), upgraded = try testStore()
    let first = await IMAPTestServer(Self.inbox(exists: 0, uidNext: 1)).adapter(mixedCase)
    try await first.commit(
      try await first.nextInboxSweep(limit: 20, cursorStore: original),
      cursorStore: original
    )
    let cursor = try await original.read(
      "imap-sweep-v1:" + mixedCase.endpointFingerprint,
      default: IMAPSweepCursor()
    )
    try await upgraded.update(
      "imap-sweep-v1:" + mixedCase.legacyEndpointFingerprint,
      default: IMAPSweepCursor()
    ) { $0 = cursor }
    let delivered = IMAPTestServer(
      Self.inbox(exists: 2, uidNext: 3).metadata(Self.rows(1...2, size: raw.utf8.count))
        .body(raw, uid: 1, sequence: 1).body(raw, uid: 2, sequence: 2)
    )
    let sweep = try await delivered.adapter(mixedCase)
      .nextInboxSweep(limit: 20, cursorStore: upgraded)
    #expect(sweep.messages.map(\.identity.localID) == [1, 2])
  }

  @Test
  func `reads the same new mail again after a paused batch stops before committing`()
    async throws
  {
    let store = try testStore()
    let raw = try #require(String(data: fixture("filler-spam"), encoding: .utf8))
    _ = try await Self.committedSweep(
      IMAPTestServer(Self.inbox(exists: 0, uidNext: 1)),
      limit: 20,
      store: store
    )
    try await StateRepository.update(store) { $0.settings.paused = true }
    let pipeline = Pipeline(
      store: store,
      classifier: MockClassifier(operation: { _ in
        Verdict(label: .junk, confidence: 99, reason: "lure")
      })
    )
    for _ in 1...2 {
      let server = IMAPTestServer(
        Self.inbox(exists: 2, uidNext: 3).metadata(Self.rows(1...2, size: raw.utf8.count))
          .body(raw, uid: 1, sequence: 1).body(raw, uid: 2, sequence: 2)
      )
      let adapter = await server.adapter()
      let sweep = try await adapter.nextInboxSweep(limit: 20, cursorStore: store)
      #expect(sweep.messages.map(\.identity.localID) == [1, 2])
      try await pipeline.processBatch(
        sweep.messages,
        adapter: adapter,
        dryRun: true,
        skipsSettled: true,
        onCompletion: { try await adapter.commit(sweep, cursorStore: store) }
      )
    }
  }
}

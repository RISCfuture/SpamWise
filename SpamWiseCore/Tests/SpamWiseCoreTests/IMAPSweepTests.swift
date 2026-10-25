import Foundation
import NIOCore
import Testing
@testable import MailIntegration
import SpamWiseCore

@Suite
struct `sweeps new IMAP Inbox mail` {
  /// A connection lifetime within the session's fetch margin, so each sweep fetches one message.
  private static let expiringLifetime = TimeAmount.seconds(5)
  private static let cursorKey = "imap-sweep-v1:" + IMAPConfiguration.test.endpointFingerprint

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
  func `starts at the newest existing UID and reads only the mail that arrives after it`()
    async throws
  {
    let store = try testStore()
    let raw = "From: sender@example.com\r\n\r\nHello", estimatedSize = raw.utf8.count + 3
    let boundary = IMAPTestServer(
      Self.inbox(exists: 3).metadata([.init(3, uid: 3, size: 10)])
    )
    #expect(try await Self.committedSweep(boundary, limit: 2, store: store).isEmpty)
    #expect(
      await boundary.commands.filter { $0.contains("FETCH") } == ["FETCH 3 (UID RFC822.SIZE)"]
    )
    var transcript = Self.inbox(exists: 7, uidNext: 8)
      .metadata(Self.rows(1...7, size: estimatedSize))
    for uid in 4...7 { transcript = transcript.body(raw, uid: uid, sequence: uid) }
    let delivered = IMAPTestServer(transcript)
    let messages = try await Self.committedSweep(delivered, limit: 2, store: store)
    #expect(messages.map(\.identity.localID) == [4, 5, 6, 7])
    #expect(
      await delivered.commands.filter { $0.contains("FETCH") }
        == ["FETCH 1:7 (UID RFC822.SIZE)"] + (4...7).map { "UID FETCH \($0) (UID BODY.PEEK[])" }
    )
  }

  @Test
  func `resumes new mail deferred by the byte budget without reading earlier mail again`()
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
    let server = IMAPTestServer(
      Self.inbox(exists: 5, uidNext: 6).metadata(Self.rows(1...5, size: 1_000_000))
        .body(raw, uid: 5, sequence: 5)
    )
    let resumed = try await Self.committedSweep(server, limit: 20, store: store)
    #expect(resumed.map(\.identity.localID) == [5])
    #expect(await server.commands.filter { $0.contains("FETCH") }.count == 2)
  }

  @Test
  func `leaves the older part of a burst too deep to scan to a backfill`() async throws {
    let store = try testStore()
    let raw = "From: sender@example.com\r\n\r\nHello"
    _ = try await Self.committedSweep(
      IMAPTestServer(Self.inbox(exists: 0, uidNext: 1)),
      limit: 1,
      store: store
    )
    var burst = Self.inbox(exists: 2100, uidNext: 2101)
    for last in stride(from: 2100, to: 100, by: -100) {
      burst = burst.metadata(Self.rows(last - 99...last, size: raw.utf8.count))
    }
    for uid in 101...105 { burst = burst.body(raw, uid: uid, sequence: uid) }
    let read = try await Self.committedSweep(IMAPTestServer(burst), limit: 1, store: store)
    #expect(read.map(\.identity.localID) == Array(101...105))
    let cursor = try await store.read(Self.cursorKey, default: IMAPSweepCursor())
    #expect(cursor.backfill == IMAPBackfill(lowWaterUID: 0, ceilingUID: 101))
    #expect(cursor.offset == 2000)
  }

  @Test
  func `reads a pending backfill once, skipping mail already read, and then stops`()
    async throws
  {
    let store = try testStore()
    let raw = "From: sender@example.com\r\n\r\nHello", size = raw.utf8.count
    try await store.update(Self.cursorKey, default: IMAPSweepCursor()) {
      $0 = IMAPSweepCursor(
        validity: 33,
        boundaryUID: 0,
        highWaterUID: 10,
        backfill: IMAPBackfill(lowWaterUID: 5, ceilingUID: 9)
      )
    }
    let sweeps = [
      Self.inbox(exists: 10, uidNext: 11).metadata(Self.rows(1...10, size: size))
        .metadata(Self.rows(8...10, size: size)).body(raw, uid: 8, sequence: 8),
      Self.inbox(exists: 12, uidNext: 13).metadata(Self.rows(1...12, size: size))
        .body(raw, uid: 11, sequence: 11).body(raw, uid: 12, sequence: 12)
        .metadata(Self.rows(7...9, size: size)).body(raw, uid: 7, sequence: 7),
      Self.inbox(exists: 12, uidNext: 13).metadata(Self.rows(1...12, size: size))
        .metadata(Self.rows(4...6, size: size)).body(raw, uid: 6, sequence: 6),
      Self.inbox(exists: 12, uidNext: 13).metadata(Self.rows(1...12, size: size))
    ]
    var read: [[Int?]] = []
    for transcript in sweeps {
      read.append(
        try await Self.committedSweep(IMAPTestServer(transcript), limit: 3, store: store)
          .map(\.identity.localID)
      )
    }
    #expect(read == [[8], [11, 12, 7], [6], []])
  }

  @Test
  func `keeps the new mail read before the connection cutoff and resumes after it`()
    async throws
  {
    let store = try testStore()
    let raw = "From: sender@example.com\r\n\r\nHello"
    _ = try await Self.committedSweep(
      IMAPTestServer(Self.inbox(exists: 0, uidNext: 1)),
      limit: 20,
      store: store
    )
    for uid in 1...2 {
      let server = IMAPTestServer(
        Self.inbox(exists: 2, uidNext: 3).metadata(Self.rows(1...2, size: raw.utf8.count))
          .body(raw, uid: uid, sequence: uid),
        lifetime: Self.expiringLifetime
      )
      let read = try await Self.committedSweep(server, limit: 20, store: store)
      #expect(read.map(\.identity.localID) == [uid])
    }
  }

  @Test
  func `passes new mail whose literal exceeds the size limit its server reported`()
    async throws
  {
    let store = try testStore()
    let raw = "From: sender@example.com\r\n\r\nHello"
    _ = try await Self.committedSweep(
      IMAPTestServer(Self.inbox(exists: 0, uidNext: 1)),
      limit: 20,
      store: store
    )
    let oversized = "* 1 FETCH (UID 1 BODY[] {\(MIMEParser.maximumMessageBytes + 1)}"
    let underReported = IMAPTestServer(
      Self.inbox(exists: 2, uidNext: 3).metadata(Self.rows(1...2, size: raw.utf8.count))
        .then("UID FETCH 1 ", oversized)
    )
    #expect(try await Self.committedSweep(underReported, limit: 20, store: store).isEmpty)
    let next = IMAPTestServer(
      Self.inbox(exists: 2, uidNext: 3).metadata(Self.rows(1...2, size: raw.utf8.count))
        .body(raw, uid: 2, sequence: 2)
        .metadata(Self.rows(1...1, size: raw.utf8.count)).then("UID FETCH 1 ", oversized)
    )
    let read = try await Self.committedSweep(next, limit: 20, store: store)
    #expect(read.map(\.identity.localID) == [2])
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

import Foundation
import Testing
@testable import MailIntegration
import SpamWiseCore

@Suite
// swiftlint:disable:next type_name
struct `sweeps new IMAP Inbox mail` {
  private static func fetched(_ raw: String, uid: Int, tag: Int) -> String {
    "* 1 FETCH (UID \(uid) RFC822.SIZE \(raw.utf8.count) BODY[] {\(raw.utf8.count)}\r\n\(raw))\r\nS\(tag) OK fetched\r\n"
  }
  private static func selected(count: Int) -> String {
    "* OK ready\r\n* CAPABILITY IMAP4rev1 MOVE SPECIAL-USE\r\nS1 OK capability\r\nS2 OK login\r\n"
      + "* CAPABILITY IMAP4rev1 MOVE SPECIAL-USE\r\nS3 OK capability\r\n"
      + "* OK [UIDVALIDITY 33] selected\r\n* \(count) EXISTS\r\n"
  }
  private static func inbox(count: Int, uidNext: Int) -> String {
    selected(count: count) + "* OK [UIDNEXT \(uidNext)] predicted\r\nS4 OK examine\r\n"
  }
  private static func sweepAdapter(_ transport: IMAPFixtureTransport) -> IMAPAdapter {
    IMAPAdapter(
      configuration: .init(id: "account", host: "imap.example.com", username: "user"),
      credentials: { .password("secret") },
      transport: { _ in transport }
    )
  }
  private static func committedSweep(
    _ transport: IMAPFixtureTransport,
    limit: Int,
    store: Store
  ) async throws -> [MailEnvelope] {
    let adapter = sweepAdapter(transport)
    let sweep = try await adapter.nextInboxSweep(limit: limit, cursorStore: store)
    try await adapter.commit(sweep, cursorStore: store)
    return sweep.messages
  }

  @Test
  func `starts at the newest existing UID and reads every new message before older pages`()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try Store(url: directory.appending(path: "cursor.store"))
    let raw = "From: sender@example.com\r\n\r\nHello"
    let withoutUIDNext = Self.selected(count: 3) + "S4 OK examine\r\n"
    let boundary = IMAPFixtureTransport(
      response: withoutUIDNext + "* 3 FETCH (UID 3 RFC822.SIZE 10)\r\nS5 OK metadata\r\n"
    )
    #expect(
      try await Self.committedSweep(boundary, limit: 2, store: store).isEmpty
    )
    #expect(
      await boundary.commands.filter { $0.contains("FETCH") } == [
        "S5 FETCH 3:3 (UID RFC822.SIZE)\r\n"
      ]
    )
    let metadata = { (uids: ClosedRange<Int>, tag: Int) in
      uids.reversed().map { "* \($0) FETCH (UID \($0) RFC822.SIZE \(raw.utf8.count))\r\n" }
        .joined()
        + "S\(tag) OK metadata\r\n"
    }
    let bodies = (4...7).enumerated().map { Self.fetched(raw, uid: $0.element, tag: $0.offset + 6) }
    let delivered = IMAPFixtureTransport(
      response: Self.inbox(count: 7, uidNext: 8) + metadata(1...7, 5) + bodies.joined()
        + metadata(2...3, 10)
    )
    let messages = try await Self.committedSweep(delivered, limit: 2, store: store)
    #expect(messages.map(\.identity.localID) == [4, 5, 6, 7])
    let commands = await delivered.commands
    #expect(commands.contains("S10 FETCH 2:3 (UID RFC822.SIZE)\r\n"))
    #expect(commands.filter { $0.contains("BODY.PEEK") }.count == 4)
  }

  @Test
  func `resumes new mail deferred by the byte budget before revisiting older pages`()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try Store(url: directory.appending(path: "cursor.store"))
    let prefix = "From: sender@example.com\r\n\r\n"
    let raw = prefix + String(repeating: "a", count: 1_000_000 - prefix.utf8.count)
    let metadata = { (uids: ClosedRange<Int>, tag: Int) in
      uids.reversed().map { "* \($0) FETCH (UID \($0) RFC822.SIZE 1000000)\r\n" }.joined()
        + "S\(tag) OK metadata\r\n"
    }
    let bodies = { (uids: [Int], tag: Int) in
      uids.enumerated().map { Self.fetched(raw, uid: $0.element, tag: $0.offset + tag) }.joined()
    }
    let empty = IMAPFixtureTransport(response: Self.inbox(count: 0, uidNext: 1))
    _ = try await Self.committedSweep(empty, limit: 20, store: store)
    let first = IMAPFixtureTransport(
      response: Self.inbox(count: 5, uidNext: 6) + metadata(1...5, 5) + bodies([1, 2, 3, 4], 6)
    )
    let deferred = try await Self.committedSweep(first, limit: 20, store: store)
    #expect(deferred.map(\.identity.localID) == [1, 2, 3, 4])
    let second = IMAPFixtureTransport(
      response: Self.inbox(count: 5, uidNext: 6) + metadata(1...5, 5) + bodies([5], 6)
        + metadata(1...4, 7) + bodies([4, 3, 2, 1], 8)
    )
    let resumed = try await Self.committedSweep(second, limit: 20, store: store)
    #expect(resumed.map(\.identity.localID) == [5, 4, 3, 2, 1])
    #expect(await second.commands.contains("S7 FETCH 1:4 (UID RFC822.SIZE)\r\n"))
  }

  @Test
  func `reads the same new mail again after a paused batch stops before committing`()
    async throws
  {
    let store = try testStore()
    let raw = String(decoding: try fixture("filler-spam"), as: UTF8.self)
    let metadata = (1...2).reversed()
      .map { "* \($0) FETCH (UID \($0) RFC822.SIZE \(raw.utf8.count))\r\n" }.joined()
    let bodies = [1, 2].enumerated().map { Self.fetched(raw, uid: $0.element, tag: $0.offset + 6) }
    _ = try await Self.committedSweep(
      IMAPFixtureTransport(response: Self.inbox(count: 0, uidNext: 1)),
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
      let adapter = Self.sweepAdapter(
        IMAPFixtureTransport(
          response: Self.inbox(count: 2, uidNext: 3) + metadata + "S5 OK metadata\r\n"
            + bodies.joined()
        )
      )
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

import Foundation
import Testing
@testable import MailIntegration
import SpamWiseCore

@Suite
struct `integrates bounded IMAP messages` {
  private static let validated =
    IMAPTranscript.authenticated().roles().examine(validity: 33, exists: 0)

  private static func identity(_ raw: String, uid: Int = 7, mailbox: String = "INBOX")
    -> MessageIdentity
  {
    MessageIdentity(
      accountID: "account",
      localID: uid,
      mailboxValidity: 33,
      mailbox: mailbox,
      contentHash: stableHash(Data(raw.utf8))
    )
  }

  private static func validatedStore() async throws -> Store {
    let store = try testStore()
    try await IMAPAccountValidation.record(.test, store: store)
    return store
  }

  private static func cause(of error: (any Error)?) -> (any Error)? {
    (error as? ActionNotAttempted)?.cause
  }

  @Test
  func `parses fragmented literal mailboxes and rejects oversized literals`() async throws {
    let server = IMAPTestServer(
      IMAPTranscript.authenticated(fragment: 2)
        .then("LIST", "* LIST (\\Junk) \"/\" {9}\r\nJunk Mail")
        .examine(validity: 33),
      IMAPTranscript.authenticated().examine(validity: 33)
        .then("UID FETCH 7 ", "* 1 FETCH (UID 7 RFC822.SIZE 2000001 BODY[] {2000001}")
    )
    #expect(try await server.adapter().validateReadOnly().junkMailbox == "Junk Mail")
    await #expect(throws: IMAPError.limitExceeded) {
      _ = try await server.adapter().lookup(Self.identity("unused"))
    }
  }

  @Test
  func `rejects malformed responses and treats literal content as opaque`() async throws {
    let raw = "From: sender@example.com\r\n\r\nS9 OK fake\r\n* BYE"
    let server = IMAPTestServer(
      IMAPTranscript.authenticated().then("LIST", "* LIST (\\Junk) \"/\" \"bad\u{1}name\""),
      IMAPTranscript.authenticated(fragment: 1).examine(validity: 33)
        .metadata([.init(1, uid: 7, size: raw.utf8.count)]).body(raw, uid: 7)
    )
    await #expect(throws: IMAPError.malformedResponse) {
      _ = try await server.adapter().validateReadOnly()
    }
    #expect(try await server.adapter().recentMessages(limit: 1).first?.raw == Data(raw.utf8))
  }

  @Test
  func `validates read only and refuses changed UID validity before an action`() async throws {
    let server = IMAPTestServer(
      Self.validated.roles().select(validity: 44)
    )
    let adapter = await server.adapter(validations: try await Self.validatedStore())
    #expect(try await adapter.validateReadOnly().supportsMove)
    let error = await #expect(throws: ActionNotAttempted.self) {
      _ = try await adapter.perform(.moveToJunk, for: Self.identity("old"))
    }
    #expect(Self.cause(of: error) as? IntegrationError == .staleMessage)
    let commands = await server.commands
    #expect(commands.contains { $0.hasPrefix("EXAMINE") })
    #expect(!commands.contains { $0.hasPrefix("UID MOVE") || $0.contains("EXPUNGE") })
    #expect(await server.connections == 1)
  }

  @Test
  func `rejects missing MOVE capability and ambiguous special use roles`() async throws {
    let withoutMove = IMAPTranscript.authenticated(capabilities: "IMAP4rev1 SPECIAL-USE")
    let server = IMAPTestServer(
      withoutMove.roles().examine(validity: 33, exists: 0),
      IMAPTranscript.authenticated()
        .then(
          "LIST",
          "* LIST (\\Junk) \"/\" \"Junk Mail\"",
          "* LIST (\\Junk) \"/\" \"Other Junk\""
        )
    )
    let adapter = await server.adapter(validations: try await Self.validatedStore())
    #expect(await adapter.supports(.moveToJunk))
    #expect(try await !adapter.validateReadOnly().supportsMove)
    #expect(await !adapter.supports(.moveToJunk))
    let error = await #expect(throws: ActionNotAttempted.self) {
      _ = try await adapter.perform(.moveToJunk, for: Self.identity("old"))
    }
    #expect(Self.cause(of: error) as? IMAPError == .unsupported)
    await #expect(throws: IntegrationError.ambiguous) {
      _ = try await server.adapter().validateReadOnly()
    }
    #expect(await !server.commands.contains { $0.hasPrefix("SELECT") || $0.hasPrefix("UID MOVE") })
  }

  @Test(arguments: [true, false])
  func `requires exact content and a UID mapping to confirm a move`(_ mapping: Bool) async throws {
    let raw = "From: sender@example.com\r\nSubject: bounded\r\n\r\nS9 OK content is opaque"
    var transcript = IMAPTranscript.authenticated(fragment: 1).roles()
      .select(validity: 33).body(raw, uid: 7)
      .move(uid: 7, to: "Junk Mail", copyUID: mapping ? (40, 90) : nil)
    if mapping { transcript = transcript.examine("Junk Mail", validity: 40).body(raw, uid: 90) }
    let server = IMAPTestServer(transcript)
    let adapter = await server.adapter(validations: try await Self.validatedStore())
    let receipt = try await adapter.perform(.moveToJunk, for: Self.identity(raw))
    #expect(receipt.confirmed == mapping)
    #expect(receipt.updatedIdentity?.localID == (mapping ? 90 : nil))
    #expect(receipt.updatedIdentity?.mailbox == (mapping ? "Junk Mail" : nil))
    #expect(receipt.updatedIdentity.map(\.key) == (mapping ? Self.identity(raw).key : nil))
    let commands = await server.commands
    #expect(commands.contains { $0.hasPrefix("UID FETCH 7 ") && $0.contains("BODY.PEEK[]") })
    #expect(!commands.contains { $0.contains("EXPUNGE") || $0.contains("STORE") })
  }

  @Test(arguments: [
    ("\\Flagged \\*", "$SpamWiseReview"), ("\\Seen \\Flagged", "\\Flagged"), ("\\Seen", nil)
  ])
  func `stores Review as the strongest flag each mailbox permits`(
    permanentFlags: String,
    expected: String?
  ) async throws {
    let raw = "From: sender@example.com\r\nSubject: maybe\r\n\r\nUncertain"
    var transcript = IMAPTranscript.authenticated()
      .select(validity: 33, permanentFlags: permanentFlags).body(raw, uid: 7)
    if expected == "\\Flagged" { transcript = transcript.flags(uid: 7, "\\Seen") }
    if let expected {
      transcript = transcript.then(
        "UID STORE 7 +FLAGS (\(expected))",
        "* 1 FETCH (UID 7 FLAGS (\\Seen \(expected)))"
      )
    }
    let server = IMAPTestServer(transcript)
    let adapter = await server.adapter(validations: try await Self.validatedStore())
    if expected == nil {
      let error = await #expect(throws: ActionNotAttempted.self) {
        _ = try await adapter.perform(.orangeFlag, for: Self.identity(raw))
      }
      #expect(Self.cause(of: error) as? IMAPError == .unsupported)
    } else {
      #expect(try await adapter.perform(.orangeFlag, for: Self.identity(raw)).confirmed)
    }
    #expect(await !server.commands.contains { $0.hasPrefix("UID MOVE") })
  }

  @Test(arguments: [
    ("\\Flagged \\*", "$SpamWiseReview"), ("\\Seen \\Flagged", nil), ("\\Seen", nil)
  ])
  func `clears only the Review flag each mailbox permits`(
    permanentFlags: String,
    expected: String?
  ) async throws {
    let raw = "From: sender@example.com\r\nSubject: maybe\r\n\r\nUncertain"
    var transcript = IMAPTranscript.authenticated()
      .select(validity: 33, permanentFlags: permanentFlags).body(raw, uid: 7)
    if let expected {
      transcript = transcript.then(
        "UID STORE 7 -FLAGS (\(expected))",
        "* 1 FETCH (UID 7 FLAGS (\\Seen))"
      )
    }
    let server = IMAPTestServer(transcript)
    let adapter = await server.adapter(validations: try await Self.validatedStore())
    #expect(try await adapter.perform(.clearOrangeFlag, for: Self.identity(raw)).confirmed)
    #expect(await server.commands.contains { $0.hasPrefix("UID STORE") } == (expected != nil))
  }

  @Test
  func `removes the Flagged fallback only where SpamWise set it`() async throws {
    let raw = "From: sender@example.com\r\nSubject: maybe\r\n\r\nUncertain"
    let fallback = IMAPTranscript.authenticated()
      .select(validity: 33, permanentFlags: "\\Seen \\Flagged").body(raw, uid: 7)
    let userFlagged = fallback.flags(uid: 7, "\\Seen \\Flagged")
      .select(validity: 33, permanentFlags: "\\Seen \\Flagged").body(raw, uid: 7)
    let store = try await Self.validatedStore()
    let kept = IMAPTestServer(userFlagged)
    let keeping = await kept.adapter(validations: store)
    #expect(try await keeping.perform(.orangeFlag, for: Self.identity(raw)).confirmed)
    #expect(try await keeping.perform(.clearOrangeFlag, for: Self.identity(raw)).confirmed)
    #expect(await !kept.commands.contains { $0.hasPrefix("UID STORE") })

    let owned = fallback.flags(uid: 7, "\\Seen")
      .then("UID STORE 7 +FLAGS (\\Flagged)", "* 1 FETCH (UID 7 FLAGS (\\Seen \\Flagged))")
      .select(validity: 33, permanentFlags: "\\Seen \\Flagged").body(raw, uid: 7)
      .then("UID STORE 7 -FLAGS (\\Flagged)", "* 1 FETCH (UID 7 FLAGS (\\Seen))")
    let cleared = IMAPTestServer(owned)
    let clearing = await cleared.adapter(validations: store)
    #expect(try await clearing.perform(.orangeFlag, for: Self.identity(raw)).confirmed)
    #expect(try await clearing.perform(.clearOrangeFlag, for: Self.identity(raw)).confirmed)
    #expect(await cleared.commands.filter { $0.hasPrefix("UID STORE") }.count == 2)
  }

  @Test
  func `bounds recent retrieval and preserves the UID namespace`() async throws {
    let raw = "From: sender@example.com\r\n\r\nHello"
    let server = IMAPTestServer(
      IMAPTranscript.authenticated(fragment: 3).examine(validity: 33)
        .metadata([.init(1, uid: 7, size: raw.utf8.count)]).body(raw, uid: 7)
    )
    let adapter = await server.adapter()
    let message = try #require(try await adapter.recentMessages(limit: 1000).first)
    #expect(message.raw == Data(raw.utf8))
    #expect(message.identity.localID == 7 && message.identity.mailboxValidity == 33)
    let error = await #expect(throws: ActionNotAttempted.self) {
      _ = try await adapter.perform(.moveToJunk, for: message.identity)
    }
    #expect(Self.cause(of: error) as? IntegrationError == .accountUnverified)
    #expect(await server.commands.contains("FETCH 1 (UID RFC822.SIZE)"))
  }

  @Test
  func `refuses credential injection and cancelled reads without sending more commands`()
    async throws
  {
    let server = IMAPTestServer(
      IMAPTranscript().then("CAPABILITY", "* CAPABILITY IMAP4rev1"),
      IMAPTranscript().stalls(at: "CAPABILITY")
    )
    await #expect(throws: IMAPError.invalidConfiguration) {
      _ = try await server.adapter(password: "password\r\nS3 DELETE INBOX").validateReadOnly()
    }
    let adapter = await server.adapter()
    let task = Task { try await adapter.validateReadOnly() }
    while await server.commands.count < 2 { await Task.yield() }
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(await server.commands == ["CAPABILITY", "CAPABILITY"])
  }

  @Test
  func `treats mail returned to Inbox after a Junk move as an implicit Good correction`()
    async throws
  {
    let returned = try await ReturnedFromJunk()
    #expect(await returned.correctRescued().map(\.decision.label) == [.inbox])
    let rules = try await StateRepository.load(returned.store).rules
    #expect(rules.contains { $0.value == "sender@example.com" && $0.disposition == .allow })
  }

  @Test
  func `never classifies, moves or corrects mail returned from Junk a second time`()
    async throws
  {
    let returned = try await ReturnedFromJunk()
    _ = await returned.correctRescued()
    let again = await returned.pipeline.process(returned.rescued, adapter: returned.adapter)
    #expect(again.decision.action == .moveToInbox && again.outcome == .applied)
    #expect(await returned.correctRescued().isEmpty)
    #expect(await returned.server.commands.filter { $0.hasPrefix("UID MOVE") }.count == 1)
  }

  @Test
  func `loads safe headless defaults and rejects embedded secrets`() throws {
    let json =
      #"{"account":{"id":"imap:test","host":"imap.example.com","username":"user"},"#
      + #""credential":{"environment":"IMAP_PASSWORD"}}"#
    let configuration = try IMAPDaemonConfiguration.decode(Data(json.utf8))
    #expect(configuration.account.port == 993 && !configuration.account.allowsActions)
    #expect(!configuration.credential.oauthBearer)
    let embedded = json.replacingOccurrences(
      of: #""environment":"IMAP_PASSWORD""#,
      with: #""password":"secret""#
    )
    #expect(throws: IMAPError.invalidConfiguration) {
      _ = try IMAPDaemonConfiguration.decode(Data(embedded.utf8))
    }
    #expect(throws: IMAPError.invalidConfiguration) {
      try IMAPCredentialReference(
        environment: "IMAP_PASSWORD",
        keychainService: "service",
        keychainAccount: "user"
      )
    }
    let providerBase = String(json.dropLast()) + #", "providerCredentials": "#
    for reference in [
      #"{"claude":{"apiKey":"secret"}}"#,
      #"{"unknown":{"environment":"PROVIDER_KEY"}}"#,
      #"{"onDevice":{"environment":"PROVIDER_KEY"}}"#,
      #"{"privateCloudCompute":{"environment":"PROVIDER_KEY"}}"#,
      #"{"claude":{"environment":"PROVIDER_KEY","oauthBearer":false}}"#,
      #"{"gemini":{"environment":"PROVIDER_KEY","keychainService":"service","keychainAccount":"user"}}"#
    ] {
      #expect(throws: IMAPError.invalidConfiguration) {
        _ = try IMAPDaemonConfiguration.decode(Data((providerBase + reference + "}").utf8))
      }
    }
    let configured = try IMAPDaemonConfiguration.decode(
      Data(
        (providerBase
          + #"{"openAI":{"environment":"SPAMWISE_TEST_INTENTIONALLY_MISSING_PROVIDER_KEY"}}}"#).utf8
      )
    )
    #expect(configured.providerCredentials?.keys.sorted { $0.rawValue < $1.rawValue } == [.openAI])
    for backend in [ModelBackend.openAI, .gemini] {
      #expect(throws: ClassificationError.missingCredential) {
        _ = try configured.providerKey(for: backend)
      }
    }
  }

  @Test
  func `binds validation to the endpoint, keeps it through Apple Mail checks and revokes it`()
    async throws
  {
    let store = try testStore()
    var configuration = IMAPConfiguration(
      id: "imap:test",
      host: "imap.example.com",
      username: "user"
    )
    var check = IMAPValidation(
      supportsMove: true,
      junkMailbox: "Junk",
      sentMailbox: nil,
      inboxValidity: 33
    )
    #expect(try await !IMAPAccountValidation.isValidated(configuration, store: store))
    #expect(try await IMAPAccountValidation.record(check, for: configuration, store: store))
    #expect(try await IMAPAccountValidation.isValidated(configuration, store: store))
    #expect(try await StateRepository.load(store).settings.dryRun)
    try await StateRepository.recordMailboxRoles(["mail:removed": true], in: store)
    try await StateRepository.recordAppleMailRoles(
      ["mail:current": false],
      in: store,
      reportedAccounts: ["mail:current"]
    )
    #expect(try await StateRepository.load(store).settings.validatedAccounts == ["imap:test"])
    #expect(try await IMAPAccountValidation.isValidated(configuration, store: store))
    configuration.host = "IMAP.Example.com"
    #expect(try await IMAPAccountValidation.isValidated(configuration, store: store))
    configuration.host = "other.example.com"
    #expect(try await !IMAPAccountValidation.isValidated(configuration, store: store))
    configuration.host = "imap.example.com"
    try await StateRepository.editSettings(store) { $0.dryRun = false }
    check.junkMailbox = nil
    #expect(try await !IMAPAccountValidation.record(check, for: configuration, store: store))
    #expect(try await !IMAPAccountValidation.isValidated(configuration, store: store))
    let settings = try await StateRepository.load(store).settings
    #expect(settings.validatedAccounts.isEmpty)
    #expect(settings.dryRun)
  }

  @Test
  func `restores a disposable probe using each new UID and refuses an ordinary subject`()
    async throws
  {
    let raw = "From: sender@example.com\r\nSubject: [SpamWise Probe] round trip\r\n\r\nDisposable"
    let server = IMAPTestServer(
      IMAPTranscript.authenticated(fragment: 8).roles().examine(validity: 33).body(raw, uid: 7)
        .select(validity: 33).body(raw, uid: 7)
        .move(uid: 7, to: "Junk Mail", copyUID: (40, 90))
        .examine("Junk Mail", validity: 40).body(raw, uid: 90)
        .select("Junk Mail", validity: 40).body(raw, uid: 90)
        .move(uid: 90, to: "INBOX", copyUID: (33, 95))
        .examine(validity: 33).body(raw, uid: 95)
    )
    let restored = try await server.adapter().testDisposableMessage(uid: 7)
    #expect(restored.localID == 95 && restored.mailboxValidity == 33 && restored.mailbox == "INBOX")
    #expect(await server.commands.contains("UID MOVE 90 \"INBOX\""))
    let ordinary = raw.replacingOccurrences(of: "[SpamWise Probe]", with: "Ordinary")
    let denied = IMAPTestServer(
      IMAPTranscript.authenticated().roles().examine(validity: 33).body(ordinary, uid: 7)
    )
    await #expect(throws: IntegrationError.notProbeMessage) {
      _ = try await denied.adapter().testDisposableMessage(uid: 7)
    }
    #expect(await !denied.commands.contains { $0.hasPrefix("UID MOVE") })
  }

  /// Moves a message to Junk over IMAP; the message is then found in Inbox again under UID 95.
  private struct ReturnedFromJunk {
    static let raw =
      "From: Sender <sender@example.com>\r\nMessage-ID: <wanted@example.com>\r\n"
      + "Subject: Newsletter\r\n\r\nWanted after all"

    let server: IMAPTestServer, store: Store, adapter: IMAPAdapter, pipeline: Pipeline
    let rescued = IMAPAdapter.envelope(
      Data(Self.raw.utf8),
      account: "account",
      uid: 95,
      mailbox: "INBOX",
      validity: 33
    )

    init() async throws {
      server = IMAPTestServer(
        IMAPTranscript.authenticated().roles().select(validity: 33).body(Self.raw, uid: 7)
          .move(uid: 7, to: "Junk Mail", copyUID: (40, 90))
          .examine("Junk Mail", validity: 40).body(Self.raw, uid: 90)
          .examine(validity: 33).body(Self.raw, uid: 95)
      )
      store = try await validatedStore()
      try await StateRepository.editSettings(store) { $0.dryRun = false }
      adapter = await server.adapter(validations: store)
      pipeline = Pipeline(
        store: store,
        classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "spam"))
      )
      let original = IMAPAdapter.envelope(
        Data(Self.raw.utf8),
        account: "account",
        uid: 7,
        mailbox: "INBOX",
        validity: 33
      )
      #expect(await pipeline.process(original, adapter: adapter).outcome == .applied)
    }

    func correctRescued() async -> [DecisionRecord] {
      await pipeline.correctMailReturnedFromJunk([rescued], adapter: adapter)
    }
  }
}

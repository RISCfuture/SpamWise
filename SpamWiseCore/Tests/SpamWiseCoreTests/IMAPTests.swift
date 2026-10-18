import Foundation
import Testing
@testable import MailIntegration
import SpamWiseCore

@Suite
// swiftlint:disable:next type_name
struct `integrates bounded IMAP messages` {
  private static let validation =
    "* OK ready\r\n* CAPABILITY IMAP4rev1 MOVE SPECIAL-USE\r\nS1 OK capability\r\nS2 OK login\r\n"
    + "* CAPABILITY IMAP4rev1 MOVE SPECIAL-USE\r\nS3 OK capability\r\n"
    + "* LIST (\\Junk) \"/\" \"Junk Mail\"\r\n* LIST (\\Sent) \"/\" \"Sent\"\r\nS4 OK list\r\n"
    + "* OK [UIDVALIDITY 33] selected\r\n* 0 EXISTS\r\nS5 OK examine\r\n"

  private static func fetched(_ raw: String, uid: Int, tag: Int) -> String {
    "* 1 FETCH (UID \(uid) RFC822.SIZE \(raw.utf8.count) BODY[] {\(raw.utf8.count)}\r\n\(raw))\r\nS\(tag) OK fetched\r\n"
  }
  private static func selection(validity: Int, tag: Int) -> String {
    "* OK [UIDVALIDITY \(validity)] selected\r\n* 1 EXISTS\r\nS\(tag) OK selected\r\n"
  }

  private static func selected(validity: Int) -> String {
    "* OK ready\r\n* CAPABILITY IMAP4rev1 MOVE SPECIAL-USE\r\nS1 OK capability\r\nS2 OK login\r\n* CAPABILITY IMAP4rev1 MOVE SPECIAL-USE\r\nS3 OK capability\r\n* OK [UIDVALIDITY \(validity)] selected\r\n* 1 EXISTS\r\nS4 OK select\r\n"
  }
  @Test
  func `parses fragmented literal mailboxes and rejects oversized literals`() async throws {
    let transport = IMAPFixtureTransport(
      response: "* LIST (\\Junk) \"/\" {9}\r\nJunk Mail\r\n",
      fragment: 2
    )
    let reader = IMAPResponseReader(transport: transport)
    let response = try await reader.read()
    #expect(response.last?.text == "Junk Mail")
    let oversized = IMAPResponseReader(
      transport: IMAPFixtureTransport(response: "* 1 FETCH (BODY[] {2000001}\r\n")
    )
    await #expect(throws: IMAPError.limitExceeded) { _ = try await oversized.read() }
  }

  @Test
  func `rejects unterminated quoting and treats literal content as opaque`() async throws {
    let invalid = IMAPResponseReader(
      transport: IMAPFixtureTransport(response: "* LIST () \"/\" \"unfinished\r\n")
    )
    await #expect(throws: IMAPError.malformedResponse) { _ = try await invalid.read() }
    let raw = "A1 OK fake\r\n* BYE"
    let reader = IMAPResponseReader(
      transport: IMAPFixtureTransport(
        response: "* 1 FETCH (UID 7 BODY[] {\(raw.utf8.count)}\r\n\(raw))\r\n",
        fragment: 1
      )
    )
    #expect(try await reader.read().contains(.literal(Data(raw.utf8))))
  }

  @Test
  func `validates read only and refuses changed UID validity before an action`() async throws {
    let transport = IMAPFixtureTransport(
      response: Self.validation + Self.selected(validity: 44),
      fragment: 1
    )
    let adapter = IMAPAdapter(
      configuration: .init(
        id: "account",
        host: "imap.example.com",
        username: "user",
        allowsActions: true
      ),
      credentials: { .password("secret") },
      transport: { _ in transport }
    )
    let validation = try await adapter.validateReadOnly()
    #expect(validation.supportsMove)
    let identity = MessageIdentity(
      accountID: "account",
      localID: 7,
      mailboxValidity: 33,
      mailbox: "INBOX",
      contentHash: "old"
    )
    await #expect(throws: IntegrationError.staleMessage) {
      _ = try await adapter.perform(.moveToJunk, for: identity)
    }
    let commands = await transport.commands
    #expect(commands.contains { $0.contains("EXAMINE") })
    #expect(
      !commands.contains {
        $0.contains("UID MOVE") || $0.contains("EXPUNGE") || $0.contains("DELETE")
      }
    )
  }

  @Test
  func `rejects missing MOVE capability and ambiguous special use roles`() async throws {
    let transcript = (Self.validation + Self.selected(validity: 33)).replacingOccurrences(
      of: " MOVE",
      with: ""
    )
    let transport = IMAPFixtureTransport(response: transcript, fragment: 1)
    let configuration = IMAPConfiguration(
      id: "account",
      host: "imap.example.com",
      username: "user",
      allowsActions: true
    )
    let adapter = IMAPAdapter(
      configuration: configuration,
      credentials: { .password("secret") },
      transport: { _ in transport }
    )
    #expect(try await !adapter.validateReadOnly().supportsMove)
    let identity = MessageIdentity(
      accountID: "account",
      localID: 7,
      mailboxValidity: 33,
      mailbox: "INBOX",
      contentHash: "old"
    )
    await #expect(throws: IMAPError.unsupported) {
      _ = try await adapter.perform(.moveToJunk, for: identity)
    }
    #expect(await !transport.commands.contains { $0.contains("SELECT") || $0.contains("UID MOVE") })
    let ambiguous = Self.validation.replacingOccurrences(
      of: "S4 OK list",
      with: "* LIST (\\Junk) \"/\" \"Other Junk\"\r\nS4 OK list"
    )
    let denied = IMAPFixtureTransport(response: ambiguous)
    let deniedAdapter = IMAPAdapter(
      configuration: configuration,
      credentials: { .password("secret") },
      transport: { _ in denied }
    )
    await #expect(throws: IntegrationError.ambiguous) {
      _ = try await deniedAdapter.validateReadOnly()
    }
    #expect(await !denied.commands.contains { $0.contains("SELECT") || $0.contains("UID MOVE") })
  }

  @Test(arguments: [true, false])
  func `requires exact content and a UID mapping to confirm a move`(_ mapping: Bool) async throws {
    let raw = "From: sender@example.com\r\nSubject: bounded\r\n\r\nA1 OK content is opaque"
    let fetched =
      "* 1 FETCH (UID 7 RFC822.SIZE \(raw.utf8.count) BODY[] {\(raw.utf8.count)}\r\n\(raw))\r\nS5 OK fetch\r\n"
    let roles = "* LIST (\\Junk) \"/\" \"Junk Mail\"\r\nS6 OK list\r\n"
    let moved =
      "S7 OK \(mapping ? "[COPYUID 40 7 90] " : "")moved\r\n"
      + (mapping ? Self.selection(validity: 40, tag: 8) + Self.fetched(raw, uid: 90, tag: 9) : "")
    let transport = IMAPFixtureTransport(
      response: Self.validation + Self.selected(validity: 33) + fetched + roles + moved,
      fragment: 1
    )
    let adapter = IMAPAdapter(
      configuration: .init(
        id: "account",
        host: "imap.example.com",
        username: "user",
        allowsActions: true
      ),
      credentials: { .password("secret") },
      transport: { _ in transport }
    )
    _ = try await adapter.validateReadOnly()
    let identity = MessageIdentity(
      accountID: "account",
      localID: 7,
      mailboxValidity: 33,
      mailbox: "INBOX",
      contentHash: stableHash(Data(raw.utf8))
    )
    let receipt = try await adapter.perform(.moveToJunk, for: identity)
    #expect(receipt.confirmed == mapping)
    #expect(receipt.updatedIdentity?.localID == (mapping ? 90 : nil))
    #expect(receipt.updatedIdentity?.mailbox == (mapping ? "Junk Mail" : nil))
    let commands = await transport.commands
    #expect(commands.contains("S7 UID MOVE 7 \"Junk Mail\"\r\n"))
    #expect(commands.contains { $0.contains("BODY.PEEK[]") })
    #expect(!commands.contains { $0.contains("EXPUNGE") || $0.contains("STORE") })
  }

  @Test
  func `bounds recent retrieval and preserves the UID namespace`() async throws {
    let raw = "From: sender@example.com\r\n\r\nHello"
    let metadata = "* 1 FETCH (UID 7 RFC822.SIZE \(raw.utf8.count))\r\nS5 OK metadata\r\n"
    let fetched =
      "* 1 FETCH (UID 7 RFC822.SIZE \(raw.utf8.count) BODY[] {\(raw.utf8.count)}\r\n\(raw))\r\nS6 OK fetched\r\n"
    let transport = IMAPFixtureTransport(
      response: Self.selected(validity: 33) + metadata + fetched,
      fragment: 3
    )
    let adapter = IMAPAdapter(
      configuration: .init(id: "account", host: "imap.example.com", username: "user"),
      credentials: { .password("secret") },
      transport: { _ in transport }
    )
    let messages = try await adapter.recentMessages(limit: 1000)
    let message = try #require(messages.first)
    #expect(message.raw == Data(raw.utf8))
    #expect(message.identity.localID == 7 && message.identity.mailboxValidity == 33)
    await #expect(throws: IntegrationError.accountUnverified) {
      _ = try await adapter.perform(.moveToJunk, for: message.identity)
    }
    let commands = await transport.commands
    #expect(commands.contains("S4 EXAMINE \"INBOX\"\r\n"))
  }

  @Test
  func `refuses credential injection and cancelled parsing without reading more bytes`()
    async throws
  {
    #expect(throws: IMAPError.invalidConfiguration) {
      _ = try IMAPSession.quote("password\r\nS3 DELETE INBOX")
    }
    let transport = IMAPFixtureTransport(response: "* OK ready\r\n")
    let reader = IMAPResponseReader(transport: transport)
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try await reader.read()
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
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
    let ambiguous = IMAPCredentialReference(
      environment: "IMAP_PASSWORD",
      keychainService: "service",
      keychainAccount: "user"
    )
    #expect(throws: IMAPError.invalidConfiguration) { try ambiguous.validate() }
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
    #expect(throws: IMAPError.authenticationFailed) {
      _ = try configured.providerCredentials?["openAI"]?.resolvedSecret()
    }
  }

  @Test
  func `binds validation to the endpoint, keeps it through Apple Mail checks and revokes it`()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try Store(url: directory.appending(path: "state.store"))
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
    let transcript =
      Self.validation.replacingOccurrences(of: "* 0 EXISTS", with: "* 1 EXISTS")
      + Self.fetched(raw, uid: 7, tag: 6) + Self.selection(validity: 33, tag: 7)
      + Self.fetched(raw, uid: 7, tag: 8) + "S9 OK [COPYUID 40 7 90] moved\r\n"
      + Self.selection(validity: 40, tag: 10) + Self.fetched(raw, uid: 90, tag: 11)
      + Self.selection(validity: 40, tag: 12) + Self.fetched(raw, uid: 90, tag: 13)
      + "S14 OK [COPYUID 33 90 95] restored\r\n"
      + Self.selection(validity: 33, tag: 15) + Self.fetched(raw, uid: 95, tag: 16)
    let transport = IMAPFixtureTransport(response: transcript, fragment: 8)
    let configuration = IMAPConfiguration(
      id: "imap:test",
      host: "imap.example.com",
      username: "user"
    )
    let adapter = IMAPAdapter(
      configuration: configuration,
      credentials: { .password("secret") },
      transport: { _ in transport }
    )
    let restored = try await adapter.testDisposableMessage(uid: 7)
    #expect(restored.localID == 95 && restored.mailboxValidity == 33 && restored.mailbox == "INBOX")
    let commands = await transport.commands
    #expect(commands.contains("S14 UID MOVE 90 \"INBOX\"\r\n"))
    let ordinary = raw.replacingOccurrences(of: "[SpamWise Probe]", with: "Ordinary")
    let deniedTransport = IMAPFixtureTransport(
      response: Self.validation + Self.fetched(ordinary, uid: 7, tag: 6)
    )
    let denied = IMAPAdapter(
      configuration: configuration,
      credentials: { .password("secret") },
      transport: { _ in deniedTransport }
    )
    await #expect(throws: IntegrationError.notProbeMessage) {
      _ = try await denied.testDisposableMessage(uid: 7)
    }
    #expect(await !deniedTransport.commands.contains { $0.contains("UID MOVE") })
  }

}

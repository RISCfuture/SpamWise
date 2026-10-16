import Foundation
import NIOIMAP
public import SpamWiseCore

/// Client-independent, bounded IMAP adapter using explicit TLS credentials and UID-scoped actions.
public actor IMAPAdapter: MailClientAdapter {
  typealias Connector = @Sendable (IMAPConfiguration) async throws -> IMAPConnection

  private static let probeSubjectPrefix = "[SpamWise Probe]"
  private static let maximumFlaggedFallbacks = 1000
  /// Explicit account identity used to scope retries and persisted actions.
  nonisolated public let accountID: String
  let configuration: IMAPConfiguration
  private let credentials: @Sendable () async throws -> IMAPCredential
  /// Holds validation evidence and the persisted sweep cursor.
  let validations: Store?
  private let validationScope: IMAPValidationScope
  private let connector: Connector
  private var idleSession: IMAPSession?
  private var observedCapabilities: Set<String>?
  private var sweepCursor = IMAPSweepCursor()
  private var sweepCursorKey: String { "imap-sweep-v1:" + configuration.endpointFingerprint }
  /// Identity keys of messages where SpamWise set `\Flagged` as the Review fallback.
  private var flaggedFallbackKey: String {
    "imap-review-flagged-v1:" + configuration.endpointFingerprint
  }

  /// Creates an adapter that connects with verified TLS through Network.framework.
  /// - Parameters:
  ///   - configuration: The account endpoint. Actions also require `allowsActions`.
  ///   - credentials: Supplies the secret for each new connection.
  ///   - validations: The store holding ``IMAPAccountValidation`` evidence and the sweep cursor;
  ///     without it every action is refused.
  ///   - validationScope: Whose validation evidence gates actions.
  public init(
    configuration: IMAPConfiguration,
    credentials: @escaping @Sendable () async throws -> IMAPCredential,
    validations: Store? = nil,
    validationScope: IMAPValidationScope = .app
  ) {
    self.init(
      configuration: configuration,
      credentials: credentials,
      validations: validations,
      validationScope: validationScope,
      connector: IMAPPipeline.connectTLS
    )
  }

  init(
    configuration: IMAPConfiguration,
    credentials: @escaping @Sendable () async throws -> IMAPCredential,
    validations: Store?,
    validationScope: IMAPValidationScope = .app,
    connector: @escaping Connector
  ) {
    self.configuration = configuration; self.credentials = credentials
    self.validations = validations; self.validationScope = validationScope
    self.connector = connector
    accountID = configuration.id
  }

  /// Authenticates, discovers special-use roles and examines Inbox without marking or moving any message.
  public func validateReadOnly() async throws -> IMAPValidation {
    try await withSession { session in
      let roles = try await Self.roles(session: session)
      let selected = try await Self.select("INBOX", writable: false, session: session)
      return IMAPValidation(
        supportsMove: Self.supportsMove(session.capabilities),
        junkMailbox: roles.junk,
        sentMailbox: roles.sent,
        inboxValidity: selected.validity
      )
    }
  }
  /// Fetches exactly the matching UID after checking UIDVALIDITY and content hash.
  public func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope? {
    try validateIdentity(identity)
    return try await withSession { session in
      try await Self.revalidate(identity, writable: false, session: session).envelope
    }
  }
  /// Fetches at most 100 recent Inbox messages, each capped at 2 MB, with a 4 MB aggregate content limit.
  public func recentMessages(limit: Int) async throws -> [MailEnvelope] {
    try await messages(mailbox: "INBOX", limit: limit)
  }
  /**
   Reads new Inbox mail, then one backfill page toward the account's start boundary.

   The first sweep for a UIDVALIDITY records the highest existing UID as the boundary and reads
   nothing; later sweeps only return messages whose UIDs exceed it. Each sweep first reads every
   message above the highest UID already read, oldest first and within a budget, and reads the
   backfill page only once it has caught up. Nothing advances until ``commit(_:cursorStore:)``,
   so mail from a sweep whose processing stopped early is read again as new mail.
   */
  public func nextInboxSweep(limit: Int, cursorStore: Store? = nil) async throws
    -> IMAPInboxSweep
  {
    let saved = try await savedCursor(in: cursorStore)
    guard limit > 0 else { return IMAPInboxSweep(messages: [], cursor: saved) }
    let account = configuration.id
    let (messages, next) = try await withSession { session in
      try await Self.sweepInbox(account: account, limit: limit, cursor: saved, session: session)
    }
    return IMAPInboxSweep(messages: messages, cursor: next)
  }
  /**
   Advances the boundary, high-water mark and backfill position past a processed sweep.

   An optional store preserves them across instances and processes.
   */
  public func commit(_ sweep: IMAPInboxSweep, cursorStore: Store? = nil) async throws {
    if let cursorStore {
      try await cursorStore.update(sweepCursorKey, default: IMAPSweepCursor()) { $0 = sweep.cursor }
    }
    sweepCursor = sweep.cursor
  }
  /// Reads a bounded mailbox page without setting the Seen flag; names use the server's wire encoding.
  public func messages(mailbox: String, limit: Int) async throws -> [MailEnvelope] {
    let account = configuration.id
    return try await withSession { session in
      try await Self.messages(mailbox: mailbox, account: account, limit: limit, session: session)
        .envelopes
    }
  }
  /// Moves are unsupported once a connection showed the server lacks UID MOVE; Review keywords are checked per mailbox.
  public func supports(_ action: MailAction) -> Bool {
    switch action {
      case .moveToInbox, .moveToJunk: observedCapabilities.map(Self.supportsMove) ?? true
      case .none, .orangeFlag, .orangeBackground, .clearOrangeFlag, .clearOrangeBackground: true
    }
  }
  /// Performs a UID MOVE or Review keyword change after persisted validation and an exact content recheck.
  /// Review is stored as the `$SpamWiseReview` keyword, or `\Flagged` where the mailbox admits no new keywords;
  /// clearing Review removes the same flag, but removes `\Flagged` only where SpamWise set it.
  /// Failures before the mail command is sent throw `ActionNotAttempted`.
  public func perform(_ action: MailAction, for identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    guard action != .none else { return .init(confirmed: true) }
    try await Self.notAttempted {
      try await requireActionValidation()
      try validateIdentity(identity)
    }
    return try await withSession(openingPrecedesAction: true) { session in
      switch action {
        case .moveToInbox, .moveToJunk:
          try await Self.move(identity, for: action, session: session)
        case .orangeFlag, .orangeBackground:
          try await markForReview(identity, session: session)
        case .clearOrangeFlag, .clearOrangeBackground:
          try await clearReview(identity, session: session)
        case .none: .init(confirmed: true)
      }
    }
  }
  /// Explicit disposable-message probe. Only an Inbox UID whose subject starts with `[SpamWise Probe]` is eligible.
  /// Both moves require COPYUID mappings and verified destination content; failures never trigger a guessed reverse move.
  public func testDisposableMessage(uid: UInt32) async throws -> MessageIdentity {
    guard uid > 0 else { throw IntegrationError.staleMessage }
    let account = configuration.id
    return try await withSession { session in
      try Self.requireMove(session)
      guard let junk = try await Self.roles(session: session).junk, junk.uppercased() != "INBOX"
      else { throw IMAPError.unsupported }
      let selected = try await Self.select("INBOX", writable: false, session: session)
      guard let raw = try await Self.fetch(uid: Int(uid), session: session),
        let parsed = try? MIMEParser().parse(raw)
      else { throw IntegrationError.staleMessage }
      guard parsed.subject.hasPrefix(Self.probeSubjectPrefix) else {
        throw IntegrationError.notProbeMessage
      }
      let original = Self.envelope(
        raw,
        account: account,
        uid: Int(uid),
        mailbox: "INBOX",
        validity: selected.validity
      ).identity
      guard let moved = try await Self.moveAndVerify(original, to: junk, session: session),
        let restored = try await Self.moveAndVerify(moved, to: "INBOX", session: session)
      else { throw IntegrationError.staleMessage }
      return restored
    }
  }

  isolated deinit { idleSession?.close() }
}

extension IMAPAdapter {
  private func requireActionValidation() async throws {
    guard configuration.allowsActions, let validations,
      try await IMAPAccountValidation.isValidated(
        configuration,
        scope: validationScope,
        store: validations
      )
    else { throw IntegrationError.accountUnverified }
  }

  /// Stores Review, remembering a `\Flagged` fallback SpamWise set so clearing Review can remove it.
  private func markForReview(_ identity: MessageIdentity, session: IMAPSession) async throws
    -> ActionReceipt
  {
    let marking = try await Self.markForReview(identity, session: session)
    if marking.setFlagged {
      try? await validations?.update(flaggedFallbackKey, default: [String]()) { keys in
        keys.removeAll { $0 == identity.key }
        keys.append(identity.key)
        keys.removeFirst(max(0, keys.count - Self.maximumFlaggedFallbacks))
      }
    }
    return marking.receipt
  }

  /// Clears Review; a `\Flagged` fallback is removed only when SpamWise recorded setting it.
  private func clearReview(_ identity: MessageIdentity, session: IMAPSession) async throws
    -> ActionReceipt
  {
    let recorded =
      (try? await validations?.read(flaggedFallbackKey, default: [String]()))?
      .contains(identity.key) ?? false
    let receipt = try await Self.clearReview(
      identity,
      removesFlagged: recorded,
      session: session
    )
    if recorded, receipt.confirmed {
      try? await validations?.update(flaggedFallbackKey, default: [String]()) {
        $0.removeAll { $0 == identity.key }
      }
    }
    return receipt
  }

  /// The saved sweep cursor, read under the legacy endpoint key when the current key has none.
  private func savedCursor(in store: Store?) async throws -> IMAPSweepCursor {
    guard let store else { return sweepCursor }
    let legacyKey = "imap-sweep-v1:" + configuration.legacyEndpointFingerprint
    let saved = try await store.read([sweepCursorKey, legacyKey], as: IMAPSweepCursor.self)
    return saved[sweepCursorKey] ?? saved[legacyKey] ?? sweepCursor
  }

  private func validateIdentity(_ identity: MessageIdentity) throws {
    guard identity.accountID == configuration.id, let uid = identity.localID,
      uid > 0, uid <= UInt32.max, let validity = identity.mailboxValidity,
      validity > 0, validity <= UInt32.max, identity.mailbox != nil
    else {
      throw IntegrationError.staleMessage
    }
  }

  /// Runs `operation` on an idle session when one is still young, otherwise on a fresh authenticated session.
  /// A session returns to the pool only after an operation succeeds; any failure closes it.
  func withSession<Value: Sendable>(
    openingPrecedesAction: Bool = false,
    _ operation: (IMAPSession) async throws -> Value
  ) async throws -> Value {
    let session: IMAPSession
    do {
      session = try await checkOutSession()
    } catch {
      guard openingPrecedesAction, !(error is CancellationError) else { throw error }
      throw ActionNotAttempted(cause: error)
    }
    do {
      let result = try await operation(session)
      checkIn(session)
      return result
    } catch {
      session.close()
      try Task.checkCancellation()
      throw error
    }
  }

  private func checkOutSession() async throws -> IMAPSession {
    if let idle = idleSession {
      idleSession = nil
      if idle.isReusable { return idle }
      idle.close()
    }
    try configuration.validate()
    try Task.checkCancellation()
    let session = IMAPSession(connection: try await connector(configuration))
    do {
      try await session.open(configuration: configuration, credential: credentials())
    } catch {
      session.close()
      try Task.checkCancellation()
      throw error
    }
    observedCapabilities = session.capabilities
    return session
  }

  private func checkIn(_ session: IMAPSession) {
    guard idleSession == nil, session.isReusable else {
      session.close()
      return
    }
    idleSession = session
  }
}

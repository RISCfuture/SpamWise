public import Foundation
public import SpamWiseCore
import OSLog
import Dispatch
import CoreServices

/// Sendable subset of Apple Event results used by the Mail adapter.
public indirect enum ScriptValue: Sendable, Equatable {
  case string(String), integer(Int), list([ScriptValue]), boolean(Bool)
  var string: String? { if case .string(let value) = self { value } else { nil } }
  var integer: Int? { if case .integer(let value) = self { value } else { nil } }
  var list: [ScriptValue]? { if case .list(let value) = self { value } else { nil } }
  static func decode(_ descriptor: NSAppleEventDescriptor) -> ScriptValue {
    if descriptor.descriptorType == typeAEList {
      return .list(
        (1...max(1, descriptor.numberOfItems)).compactMap { descriptor.atIndex($0) }.map(decode)
      )
    }
    if [typeBoolean, typeTrue, typeFalse].contains(descriptor.descriptorType) {
      return .boolean(descriptor.booleanValue)
    }
    if [typeSInt16, typeSInt32, typeSInt64].contains(descriptor.descriptorType) {
      return .integer(Int(descriptor.int32Value))
    }
    return .string(descriptor.stringValue ?? "")
  }
}
/// Injectable execution boundary for Mail Apple Events.
public protocol AppleEventRunner: Sendable {
  /// Executes a script and returns only transferable result values.
  func run(_ source: String) async throws -> ScriptValue
}
/// Serializes AppleScript execution off the UI thread and sanitizes integration failures.
public struct SystemAppleEventRunner: AppleEventRunner {
  @MainActor private static let initialized: Void = {
    _ = unsafe NSAppleScript(source: "return true")?.executeAndReturnError(nil)
  }()
  /// Initializes AppleScript on the main actor before dispatching work to its serial executor.
  @MainActor public init() { _ = Self.initialized }
  /// Requests Mail Automation consent independently of a script's execution timeout.
  public static func requestMailPermission() async throws {
    try await AppleScriptExecutor.shared.checkPermission(askUser: true)
  }
  /// Executes the supplied Mail script and returns a sendable result.
  public func run(_ source: String) async throws -> ScriptValue {
    try await AppleScriptExecutor.shared.run(source)
  }
}

private actor AppleScriptExecutor {
  static let shared = AppleScriptExecutor()
  private let queue = DispatchSerialQueue(label: "codes.tim.SpamWise.apple-events")
  // The actor owns this queue for its entire lifetime, including every AppleScript call.
  nonisolated var unownedExecutor: UnownedSerialExecutor { unsafe queue.asUnownedSerialExecutor() }
  private let logger = Logger(subsystem: "codes.tim.SpamWise", category: "AppleEvents")

  func checkPermission(askUser: Bool) throws {
    try Task.checkCancellation()
    let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.mail")
    let status = unsafe AEDeterminePermissionToAutomateTarget(
      target.aeDesc,
      typeWildCard,
      typeWildCard,
      askUser
    )
    logger.info("Mail Automation permission status: \(status)")
    guard status == noErr else {
      if status == procNotFound { throw IntegrationError.unavailable }
      throw IntegrationError.permissionDenied
    }
    try Task.checkCancellation()
  }

  func run(_ source: String) throws -> ScriptValue {
    try checkPermission(askUser: false)
    guard let script = NSAppleScript(source: source) else { throw IntegrationError.scriptFailed }
    var error: NSDictionary?
    let result = unsafe script.executeAndReturnError(&error)
    if let error {
      let code = error[NSAppleScript.errorNumber] as? Int
      logger.error("AppleScript execution failed: code \(code ?? 0)")
      if code == -1743 || code == -10004 { throw IntegrationError.permissionDenied }
      if code == -1701 { throw IntegrationError.ambiguous }
      if code == -1702 { throw IntegrationError.staleMessage }
      throw IntegrationError.scriptFailed
    }
    logger.info(
      "AppleScript returned descriptor type \(result.descriptorType), items \(result.numberOfItems)"
    )
    try Task.checkCancellation()
    return ScriptValue.decode(result)
  }

}
/// A Mail account's stable scripting identifier and display name.
public struct MailAccount: Identifiable, Sendable {
  /// Mail’s stable scripting account identifier.
  public var id: String
  /// Account name supplied by Mail for display.
  public var name: String
}
/// Account-scoped Apple Events integration with exact-source action checks.
public actor AppleMailAdapter: MailClientAdapter {
  private static let maximumPageSize = 1000
  private static let historyPageSize = 100
  private static let maximumMessageBytes = 2_000_000
  private let runner: any AppleEventRunner
  private let moveSettlingTime: Duration
  private var pageOffsets: [String: Int] = [:]
  /// Creates an AppleMailAdapter with the supplied configuration.
  public init(runner: any AppleEventRunner, moveSettlingTime: Duration = .seconds(30)) {
    self.runner = runner
    self.moveSettlingTime = max(.zero, moveSettlingTime)
  }
  private static func envelope(_ value: ScriptValue) throws -> MailEnvelope {
    guard let fields = value.list, fields.count == 5, let account = fields[0].string,
      !account.isEmpty,
      let box = fields[1].string, let id = fields[2].integer, let messageID = fields[3].string,
      let source = fields[4].string, source.utf8.count <= maximumMessageBytes
    else { throw IntegrationError.scriptFailed }
    let raw = Data(source.utf8)
    return .init(
      identity: .init(
        accountID: account,
        messageID: messageID.isEmpty ? nil : messageID,
        localID: id,
        mailbox: box,
        contentHash: stableHash(raw)
      ),
      raw: raw
    )
  }
  /// Reads Mail account identifiers and display names.
  public func accounts() async throws -> [MailAccount] {
    guard let rows = try await runner.run(MailScripts.accounts).list else {
      throw IntegrationError.scriptFailed
    }
    return try rows.map { row in
      guard let fields = row.list, fields.count == 2, let id = fields[0].string,
        let name = fields[1].string
      else { throw IntegrationError.scriptFailed }
      return MailAccount(id: id, name: name)
    }
  }
  /// Resolves exactly one account-scoped message and rejects stale content.
  public func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope? {
    let envelope = try Self.envelope(await runner.run(MailScripts.lookup(identity)))
    guard envelope.identity.accountID == identity.accountID,
      envelope.identity.contentHash == identity.contentHash
    else { throw IntegrationError.staleMessage }
    return envelope
  }
  /// Reads a bounded window of Inbox messages without changing mail.
  public func recentMessages(limit: Int) async throws -> [MailEnvelope] {
    try await messages(limit: limit, role: "inbox")
  }
  /// Advances a bounded Inbox sweep, restarting at the beginning after its last page.
  public func nextInboxMessages(limit: Int) async throws -> [MailEnvelope] {
    try await nextPage(limit: limit, role: "inbox", cursor: "filter")
  }
  private func nextPage(limit: Int, role: String, cursor: String) async throws -> [MailEnvelope] {
    let count = max(1, min(Self.maximumPageSize, limit))
    let offset = pageOffsets[cursor, default: 0]
    guard
      let rows = try await runner.run(
        MailScripts.recent(limit: count, mailbox: role, offset: offset)
      ).list
    else { throw IntegrationError.scriptFailed }
    let envelopes = try rows.map(Self.envelope)
    pageOffsets[cursor] = rows.count < count ? 0 : offset + rows.count
    return envelopes
  }
  /// Reads a bounded window from the specified special mailbox role.
  public func messages(limit: Int, role: String) async throws -> [MailEnvelope] {
    guard ["inbox", "junk mailbox", "sent mailbox"].contains(role),
      let rows = try await runner.run(MailScripts.recent(limit: limit, mailbox: role)).list
    else { throw IntegrationError.scriptFailed }
    return try rows.map(Self.envelope)
  }
  /// Reads exactly one message selected in Mail.
  public func selectedMessage() async throws -> MailEnvelope {
    try Self.envelope(await runner.run(MailScripts.selected))
  }
  /// Requests an action and observes its result after allowing each move to settle.
  public func perform(_ action: MailAction, for identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    guard action != .none else { return .init(confirmed: true) }
    guard let message = try await lookup(identity),
      let source = String(data: message.raw, encoding: .utf8)
    else { throw IntegrationError.staleMessage }
    try Task.checkCancellation()
    let result = try await runner.run(
      MailScripts.lookup(identity, action: action, expectedSource: source)
    )
    guard result == .boolean(true) else { throw IntegrationError.scriptFailed }
    if action == .moveToJunk || action == .moveToInbox {
      try await Task.sleep(for: moveSettlingTime)
    }
    try await verify(action, for: identity, source: source)
    return .init(confirmed: true)
  }
  private func verify(_ action: MailAction, for identity: MessageIdentity, source: String)
    async throws
  {
    try Task.checkCancellation()
    let observed = try await runner.run(
      MailScripts.verification(identity, action: action, expectedSource: source)
    )
    guard observed == .boolean(true) else { throw IntegrationError.staleMessage }
  }
  /// Imports bounded Inbox and Sent history with explicit partial availability.
  public func importHistory() async throws -> [String: HistoryIndex] {
    try await importHistory(previous: [:])
  }
  /// Adds only unseen messages to an account-scoped history snapshot.
  public func importHistory(
    previous: [String: HistoryIndex],
    eligibleInbox: Set<String>? = nil,
    incremental: Bool = false
  ) async throws -> [String: HistoryIndex] {
    // Automatic imports accept only previously classified Inbox mail, never a new message's own claims.
    let sent =
      try await
      (incremental
      ? nextPage(limit: Self.historyPageSize, role: "sent mailbox", cursor: "history-sent")
      : messages(limit: Self.maximumPageSize, role: "sent mailbox"))
    let inboxPage =
      try await
      (incremental
      ? nextPage(limit: Self.historyPageSize, role: "inbox", cursor: "history-inbox")
      : messages(limit: Self.maximumPageSize, role: "inbox"))
    let inbox = inboxPage.filter { eligibleInbox?.contains($0.identity.key) ?? true }
    var indexes = previous
    let sentKeys = Set(sent.map { $0.identity.key })
    for envelope in inbox + sent {
      guard let account = envelope.identity.accountID,
        let message = try? MIMEParser().parse(envelope.raw)
      else { continue }
      var index = indexes[account] ?? HistoryIndex()
      index.availability = .partial; index.updatedAt = .now
      let isSent = sentKeys.contains(envelope.identity.key)
      let id = (isSent ? "sent:" : "inbox:") + envelope.identity.key
      guard index.importedIDs.insert(id).inserted else { continue }
      if isSent {
        if message.header("in-reply-to") != nil {
          for value in (message.headers["to"] ?? []) + (message.headers["cc"] ?? []) {
            for address in value.components(separatedBy: ",").compactMap(MIMEParser.address) {
              index.replied[address, default: 0] += 1
            }
          }
        }
      } else if let domain = DomainResolver().domain(ofAddress: message.fromAddress) {
        index.received[domain, default: 0] += 1
        // Conservative receipt heuristic; current incoming claims never establish their own gate.
        let subject = message.subject.lowercased(), body = message.text.lowercased()
        if subject.contains("order confirmation") || subject.contains("your receipt"),
          body.contains("order"),
          body.range(of: #"(?:\$|USD|EUR)\s*\d"#, options: [.regularExpression, .caseInsensitive])
            != nil
        {
          index.receipts[domain, default: 0] += 1
        }
      }
      indexes[account] = index
    }
    return indexes
  }
  /// Explicit UI probe: only a message deliberately named [SpamWise Probe] is eligible.
  public func testDisposableMessage() async throws -> String {
    let selected = try await selectedMessage()
    let message = try MIMEParser().parse(selected.raw)
    guard message.subject.hasPrefix("[SpamWise Probe]"), let account = selected.identity.accountID
    else { throw IntegrationError.unavailable }
    guard let source = String(data: selected.raw, encoding: .utf8) else {
      throw IntegrationError.staleMessage
    }
    try await verify(.moveToInbox, for: selected.identity, source: source)
    _ = try await perform(.moveToJunk, for: selected.identity)
    _ = try await perform(.moveToInbox, for: selected.identity)
    _ = try await perform(.orangeFlag, for: selected.identity)
    try await verify(.moveToInbox, for: selected.identity, source: source)
    return account
  }
  /// Writes raw messages to a directory without overwriting existing files.
  public func export(role: String, to directory: URL, limit: Int = 500) async throws -> Int {
    let messages = try await messages(limit: limit, role: role)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for message in messages {
      try message.raw.write(
        to: directory.appending(path: message.identity.key + ".eml"),
        options: [.atomic, .withoutOverwriting]
      )
    }
    return messages.count
  }
}

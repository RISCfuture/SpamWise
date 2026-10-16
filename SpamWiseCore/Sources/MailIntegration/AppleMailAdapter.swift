public import Foundation
public import SpamWiseCore

/**
 Account-scoped Apple Events integration with exact-source action checks.

 Every handler call runs under a wall-clock limit. Mutating calls that pass that limit, or are
 cancelled after they start, report an unconfirmed receipt because Mail may still apply them.
 Corrections, lookups, selections, account and destination reads and the disposable probe run
 on the interactive lane; sweeps, pages and automatic actions run on the background lane.
 */
public actor AppleMailAdapter: MailClientAdapter {
  /// Default wall-clock limit for one handler call.
  public static let defaultCallTimeLimit = Duration.seconds(30)
  /// Default longest wait for Mail to show a moved message in its destination.
  public static let defaultMoveSettlingTime = Duration.seconds(30)
  /// Default delay between observations of a moved message.
  public static let defaultObservationInterval = Duration.seconds(2)
  let runner: any AppleEventRunner
  let callTimeLimit: Duration
  let moveSettlingTime: Duration
  let observationInterval: Duration

  /**
   Creates an adapter over a Mail handler runner, raising negative durations to zero.

   Each move waits up to `moveSettlingTime`, 30 seconds by default, for Mail to show the message
   in its destination before reporting the result.

   - Parameters:
     - runner: Executes Mail handler requests.
     - callTimeLimit: Wall-clock limit for each handler call.
     - moveSettlingTime: Longest time to wait for Mail to show a moved message.
     - observationInterval: Delay between observations of a moved message.
   */
  public init(
    runner: any AppleEventRunner,
    callTimeLimit: Duration = defaultCallTimeLimit,
    moveSettlingTime: Duration = defaultMoveSettlingTime,
    observationInterval: Duration = defaultObservationInterval
  ) {
    self.runner = runner
    self.callTimeLimit = max(.zero, callTimeLimit)
    self.moveSettlingTime = max(.zero, moveSettlingTime)
    self.observationInterval = max(.zero, observationInterval)
  }

  /// Runs one handler request on the current task's lane under the adapter's wall-clock limit.
  func invoke(_ request: MailRequest) async throws -> ScriptValue {
    let runner = self.runner, lane = ScriptLane.current
    do {
      return try await withResourceDeadline(seconds: callTimeLimit.timeInterval) {
        try await runner.run(request, lane: lane)
      }
    } catch ResourceDeadlineError.timeout {
      throw IntegrationError.timedOut
    }
  }
  /// Runs `operation` with its handler calls on the interactive lane.
  func interactively<Value>(_ operation: () async throws -> Value) async throws -> Value {
    try await ScriptLane.$current.withValue(.interactive, operation: operation)
  }
  /// Reads Mail account identifiers and display names.
  public func accounts() async throws -> [MailAccount] {
    guard let rows = try await interactively({ try await invoke(.accounts) }).list else {
      throw IntegrationError.scriptFailed
    }
    return try rows.map { row in
      guard let fields = row.list, (2...3).contains(fields.count), let id = fields[0].string,
        let name = fields[1].string
      else { throw IntegrationError.scriptFailed }
      let addresses = fields.count == 3 ? fields[2].list?.compactMap(\.string) ?? [] : []
      return MailAccount(id: id, name: name, addresses: addresses.compactMap(MIMEParser.address))
    }
  }
}

extension AppleMailAdapter {
  /// Reads a bounded window of Inbox messages without changing mail.
  public func recentMessages(limit: Int) async throws -> [MailEnvelope] {
    try await messages(limit: limit, role: .inbox)
  }
  /// Reads an Inbox page within one account, optionally limited to mail received on or after `since` or before `before`, without advancing the caller's durable cursor.
  public func inboxPage(
    accountID: String,
    offset: Int,
    limit: Int,
    since: Date? = nil,
    before: Date? = nil
  ) async throws -> MailPage {
    try await accountPage(
      accountID: accountID,
      offset: offset,
      limit: limit,
      received: (since, before)
    )
  }
  /// Reads a special mailbox through Mail.app without inferring a label from its membership.
  public func accountPage(
    accountID: String,
    offset: Int,
    limit: Int,
    role: MailboxRole = .inbox,
    received: (since: Date?, before: Date?) = (nil, nil)
  ) async throws -> MailPage {
    try Self.decodePage(
      await invoke(
        .accountPage(
          role: role,
          accountID: accountID,
          offset: offset,
          limit: limit,
          since: received.since,
          before: received.before
        )
      ),
      accountID: accountID,
      offset: offset,
      limit: limit
    )
  }
  /// Reads readable messages from the first page of Mail's combined special mailbox.
  public func messages(limit: Int, role: MailboxRole) async throws -> [MailEnvelope] {
    try await unifiedPage(role, offset: 0, limit: limit).messages
  }
  /// Reads exactly one readable message selected in Mail.
  public func selectedMessage() async throws -> MailEnvelope {
    let selection = try await selection(maximumCount: 1)
    guard let message = selection.messages.first else { throw IntegrationError.messageTooLarge }
    return message
  }
  /// Captures up to fifty selected messages before any correction or move begins, counting unreadable ones separately.
  public func selectedMessages() async throws -> MailPage {
    try await selection(maximumCount: MailScripts.maximumSelectionCount)
  }
  /// Writes up to `limit` raw messages from `role`'s mailboxes to `directory` without overwriting files, returning the count.
  public func export(role: MailboxRole, to directory: URL, limit: Int = 500) async throws -> Int {
    let messages = try await messages(limit: limit, role: role)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for message in messages {
      try message.raw.write(
        to: directory.appending(path: message.identity.key + ".eml"),
        options: .withoutOverwriting
      )
    }
    return messages.count
  }

  private func unifiedPage(_ role: MailboxRole, offset: Int, limit: Int) async throws -> MailPage {
    try Self.decodePage(
      await invoke(.unifiedPage(role: role, offset: offset, limit: limit)),
      offset: offset,
      limit: limit
    )
  }
  private func selection(maximumCount: Int) async throws -> MailPage {
    guard
      let result = try await interactively({
        try await invoke(.selection(maximumCount: maximumCount))
      }).list,
      result.count == 2, let count = result[0].integer, let values = result[1].list
    else { throw IntegrationError.scriptFailed }
    guard (1...maximumCount).contains(count) else {
      throw IntegrationError.selectionCount(minimum: 1, maximum: maximumCount)
    }
    guard values.count == count else { throw IntegrationError.scriptFailed }
    let rows = try values.map(MailRow.init)
    return MailPage(messages: rows.compactMap(\.envelope), total: count, visitedCount: count)
  }
}

extension Duration {
  var timeInterval: TimeInterval {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}

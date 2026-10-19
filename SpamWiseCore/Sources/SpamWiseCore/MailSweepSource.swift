public import Foundation

/// A mail account's stable identifier and display name.
public struct MailAccount: Identifiable, Sendable {
  /// The client's stable account identifier.
  public var id: String
  /// Account name supplied by the client for display.
  public var name: String
  /// Own addresses reported by the client, without reading credentials.
  public var addresses: [String]
  /// Creates a displayable account with optional own-address discovery.
  public init(id: String, name: String, addresses: [String] = []) {
    self.id = id; self.name = name; self.addresses = addresses
  }
}

/// One bounded mailbox page, including entries whose source could not be read.
public struct MailPage: Sendable {
  /// Readable envelopes; unavailable entries never reach classification or mail actions.
  public let messages: [MailEnvelope]
  /// Current observed mailbox size; not a server acknowledgement.
  public let total: Int
  /// Mailbox positions visited, including unavailable entries.
  public let visitedCount: Int
  /// Entries requiring another attempt on a later sweep.
  public var unavailableCount: Int { visitedCount - messages.count }
  /// Creates a page from its readable envelopes and the positions it visited.
  public init(messages: [MailEnvelope], total: Int, visitedCount: Int) {
    self.messages = messages; self.total = total; self.visitedCount = visitedCount
  }
}

/// A mailbox whose messages contribute relationship history.
public enum HistoryMailbox: String, Sendable, CaseIterable, Codable {
  /// Sent mail, whose reply headers count correspondents.
  case sent
  /// Inbox mail, which counts only once SpamWise or the user kept it in the Inbox.
  case inbox
}

/// Where one automatic Inbox pass starts and how much it reads per page.
public struct InboxPassRequest: Sendable {
  /// Earliest received date the pass considers.
  public var start: Date
  /// Saved backfill position from the previous pass; zero starts at the newest message.
  public var resumeOffset: Int
  /// Maximum messages per page.
  public var pageLimit: Int
  /// Creates a request.
  public init(start: Date, resumeOffset: Int, pageLimit: Int) {
    self.start = start; self.resumeOffset = resumeOffset; self.pageLimit = pageLimit
  }
}

/// Positions one automatic Inbox pass covered and where the next pass resumes.
public struct InboxTraversal: Sendable, Equatable {
  /// Backfill position for the next pass; zero completes the traversal.
  public var end: Int
  /// Mailbox size observed by the pass.
  public var total: Int
  /// Positions the pass visited, including unreadable ones.
  public var visited = 0
  /// Unreadable positions the pass visited.
  public var unavailable = 0
  /// Whether processing stopped early because filtering paused; the cursor then stays in place.
  public var interrupted = false
  /// Position of a page whose read timed out and ended the pass.
  public var stalledOffset: Int?
  /// Creates a traversal summary.
  public init(
    end: Int,
    total: Int,
    visited: Int = 0,
    unavailable: Int = 0,
    interrupted: Bool = false,
    stalledOffset: Int? = nil
  ) {
    self.end = end; self.total = total; self.visited = visited; self.unavailable = unavailable
    self.interrupted = interrupted; self.stalledOffset = stalledOffset
  }
}

/// The result of processing one discovered page.
public struct ProcessedPage: Sendable {
  /// Records of the messages processed for the first time.
  public var records: [DecisionRecord]
  /// Whether every envelope was handled; false when filtering paused part way through.
  public var completed: Bool
  /// Creates a page result.
  public init(records: [DecisionRecord], completed: Bool) {
    self.records = records; self.completed = completed
  }
}

/// Processes one discovered Inbox page and reports whether it completed.
public typealias InboxPageProcessor = @Sendable (MailPage) async throws -> ProcessedPage

/**
 A mail client that ``MailSweeper`` can traverse.

 Sources only read pages; the sweeper decides which messages are new, records progress and
 health, schedules retries, observes training folders and maintains history.
 */
public protocol MailSweepSource: MailClientAdapter {
  /// The accounts this client can sweep.
  func sweepAccounts() async throws -> [MailAccount]
  /**
   Runs one automatic pass over an account's Inbox, handing each page to `processing` in order.

   - Throws: Read failures other than a page timeout, which ends the pass with
     ``InboxTraversal/stalledOffset`` set instead.
   */
  func sweepInbox(
    of account: MailAccount,
    _ request: InboxPassRequest,
    processing: @escaping InboxPageProcessor
  ) async throws -> InboxTraversal
  /// The newest Inbox messages of an account, for an explicit preview.
  func recentInboxPage(accountID: String, limit: Int) async throws -> MailPage
  /// Reads one page of a configured folder; unresolved or renamed paths throw.
  func folderPage(_ folder: MailFolder, offset: Int, limit: Int, since: Date?) async throws
    -> MailPage
  /**
   Reads one page of a history mailbox, newest first.

   Sent pages may hold only headers. An account without a uniquely resolvable mailbox returns
   an empty page.
   */
  func historyPage(accountID: String, mailbox: HistoryMailbox, offset: Int, limit: Int)
    async throws -> MailPage
}

extension MailSweepSource {
  /// Clients without configurable folders cannot resolve any folder plan.
  public func folderPage(_: MailFolder, offset _: Int, limit _: Int, since _: Date?)
    throws -> MailPage
  {
    throw IntegrationError.folderUnresolved
  }
}

/// A sweep source whose Inbox pages are addressed by position from the newest message.
public protocol PositionalInboxSource: MailSweepSource {
  /// Reads an Inbox page within one account, limited to mail received on or after `since`.
  func inboxSweepPage(accountID: String, offset: Int, limit: Int, since: Date?) async throws
    -> MailPage
}

extension PositionalInboxSource {
  /// Traverses new mail from the newest position, then a bounded backfill; see ``PositionalInboxPass``.
  public func sweepInbox(
    of account: MailAccount,
    _ request: InboxPassRequest,
    processing: @escaping InboxPageProcessor
  ) async throws -> InboxTraversal {
    try await PositionalInboxPass(request: request, processing: processing) { offset, limit in
      try await inboxSweepPage(
        accountID: account.id,
        offset: offset,
        limit: limit,
        since: request.start
      )
    }.run()
  }
  /// The first page of the account's Inbox.
  public func recentInboxPage(accountID: String, limit: Int) async throws -> MailPage {
    try await inboxSweepPage(accountID: accountID, offset: 0, limit: limit, since: nil)
  }
}

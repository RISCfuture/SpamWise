public import Foundation
public import SpamWiseCore

/// A special mailbox role that Mail.app resolves per account.
public enum MailboxRole: String, Sendable, CaseIterable {
  /// The account's Inbox.
  case inbox
  /// The account's Junk mailbox.
  case junk
  /// The account's Sent mailbox.
  case sent
}

/// A change or presentation step applied to one exactly resolved message.
public enum MailCommand: String, Sendable, CaseIterable {
  /// Moves the message to its account's Junk mailbox.
  case moveToJunk = "junk"
  /// Moves the message to its account's Inbox.
  case moveToInbox = "inbox"
  /// Applies the orange flag unless the user already set another flag.
  case orangeFlag = "flag"
  /// Applies the orange background unless the user already set another color.
  case orangeBackground = "background"
  /// Marks the message read while it remains in its account's Junk mailbox.
  case markRead = "read"
  /// Opens the message in Mail's viewer.
  case open

  init?(_ action: MailAction) {
    switch action {
      case .moveToJunk: self = .moveToJunk
      case .moveToInbox: self = .moveToInbox
      case .orangeFlag: self = .orangeFlag
      case .orangeBackground: self = .orangeBackground
      case .none: return nil
    }
  }
}

/// The exact Mail location and fingerprint fields an action handler rechecks before acting.
public struct MailMessageLocation: Sendable, Equatable {
  /// Mail's stable account identifier.
  public let accountID: String
  /// Name of the mailbox that currently holds the message.
  public let mailbox: String
  /// Mail's local scripting identifier within that mailbox.
  public let localID: Int
  /// RFC Message-ID claim, when the message has one.
  public let messageID: String?
  /// Mail's reported message size, compared again before acting.
  public let byteCount: Int
}

/// One invocation of the compiled Mail handler library, with typed parameters.
public enum MailRequest: Sendable, Equatable {
  /// Lists account identifiers, names and addresses.
  case accounts
  /// Reads the current selection when it holds at most `maximumCount` messages.
  case selection(maximumCount: Int)
  /// Reads a page of Mail's combined special mailbox across all accounts.
  case unifiedPage(role: MailboxRole, offset: Int, limit: Int)
  /// Reads a page of one account's special mailbox, or only its messages' headers.
  ///
  /// A page limited to mail received on or after `since` or before `before` is read newest first.
  case accountPage(
    role: MailboxRole,
    accountID: String,
    offset: Int,
    limit: Int,
    headersOnly: Bool = false,
    since: Date? = nil,
    before: Date? = nil
  )
  /// Lists bounded account-scoped mailbox paths.
  case folders
  /// Reads a page of one exact mailbox path, optionally limited by received date.
  case folderPage(MailFolder, offset: Int, limit: Int, since: Date?)
  /// Reads one account's Inbox and Junk mailbox names.
  case destinations(accountID: String)
  /// Finds candidates by Message-ID or local ID, within the named mailbox or across the account.
  case find(accountID: String, messageID: String?, localID: Int?, mailbox: String?)
  /// Applies one command after rechecking the message's exact location and fingerprint.
  case apply(MailCommand, target: MailMessageLocation)
  /// Finds messages with a Message-ID in one account's special mailbox.
  case observe(accountID: String, role: MailboxRole, messageID: String)
}

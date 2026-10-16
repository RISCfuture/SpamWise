public import Foundation

/// An exact account-scoped mailbox path resolved through Mail.app.
public struct MailFolder: Codable, Sendable, Hashable, Identifiable {
  /// Stable Mail account identifier.
  public var accountID: String
  /// Hierarchical mailbox names; names are never interpreted as script syntax.
  public var path: [String]
  /// Stable identity for this configured account and path.
  public var id: String { stableHash(Data(([accountID] + path).joined(separator: "\u{0}").utf8)) }
  /// Human-readable hierarchy for configuration and diagnostics.
  public var displayName: String { path.joined(separator: " / ") }
  /// Creates an explicit mailbox reference without assuming it exists.
  public init(accountID: String, path: [String]) { self.accountID = accountID; self.path = path }
}

/// The operation explicitly selected for a dedicated mailbox.
public enum MailFolderPurpose: String, Codable, Sendable, CaseIterable {
  case filter, trainGood, trainJunk
}

/// Opt-in processing scope; removing or renaming a mailbox fails closed.
public struct MailFolderPlan: Codable, Sendable, Identifiable, Equatable {
  /// Exact configured mailbox path.
  public var folder: MailFolder
  /// Explicit filtering or dedicated-training role.
  public var purpose: MailFolderPurpose
  /// Automatic processing remains off until explicitly enabled.
  public var enabled = false
  /// Earliest received date for filtering; training uses observed placement instead.
  public var startDate = Date()
  /// Empty training-folder observation required before enabling deliberate placement training.
  public var trainingBaselineValidated = false
  /// Stable plan identity shared with its scope.
  public var id: String { folder.id }
  /// Creates a disabled plan for staged configuration.
  public init(folder: MailFolder, purpose: MailFolderPurpose = .filter) {
    self.folder = folder; self.purpose = purpose
  }
}

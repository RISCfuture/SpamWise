public import Foundation

/**
 A durable configuration or learning mutation, independent of decision records.

 Events store what changed as typed values, so presentation can describe them in the reader's
 language at display time.
 */
public struct AuditEvent: Codable, Sendable, Equatable, Identifiable {
  /// Stable event identity.
  public var id = UUID()
  /// Local event time.
  public var date = Date()
  /// Configuration revision after the mutation.
  public var revision: Int
  /// What changed, without credentials or message bodies.
  public var change: Change
  /// Fixed event category for filtering.
  public var kind: Kind { change.kind }
  /// Creates an event for `change` at `revision`.
  public init(revision: Int, change: Change) {
    self.revision = revision; self.change = change
  }
  /// Decodes an event; one stored with only a free-text `detail` becomes ``Change/recorded(_:)``.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    revision = values.lenient(.revision, default: 0)
    change =
      values.lenient(.change, default: nil)
      ?? .recorded(values.lenient(.detail, default: ""))
    id = values.lenient(.id, default: id)
    date = values.lenient(.date, default: date)
  }
  /// Encodes the event and its typed change.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(date, forKey: .date)
    try values.encode(revision, forKey: .revision)
    try values.encode(change, forKey: .change)
  }
  private enum CodingKeys: String, CodingKey { case id, date, revision, change, detail }

  /// Supported configuration and learning event categories.
  public enum Kind: String, Codable, Sendable {
    case settings
    case senderRule = "senderRule"
    case contentRule = "contentRule"
    case correction
    case backupRestore = "backupRestore"
    case corpusImport = "corpusImport"
    case corpusForget = "corpusForget"
    case undo
  }

  /// One configuration or learning mutation and the values it affected.
  public enum Change: Codable, Sendable, Equatable {
    /// Settings changed in the named encoded fields.
    case settingsChanged(fields: [String])
    /// An explicit sender rule was saved.
    case senderRuleSaved(scope: RuleScope, value: String, disposition: RuleDisposition)
    /// An explicit sender rule was removed.
    case senderRuleRemoved(scope: RuleScope, value: String)
    /// A rule archive was imported.
    case senderRulesImported(count: Int)
    /// A content rule was saved.
    case contentRuleSaved(field: ContentRuleField, pattern: String, disposition: RuleDisposition)
    /// A content rule was removed.
    case contentRuleRemoved(field: ContentRuleField, pattern: String)
    /// A content rule archive was imported.
    case contentRulesImported(count: Int)
    /// A message from `sender` was corrected, saving a rule at `scope`.
    case corrected(scope: RuleScope, sender: String, label: MailLabel)
    /// A portable learning backup was restored and actions were paused.
    case backupRestored
    /// Explicitly reviewed messages were imported as labels.
    case corpusImported(count: Int, label: MailLabel)
    /// A reviewed label was changed.
    case corpusRelabeled(label: MailLabel)
    /// A reviewed label and its derived learning were forgotten.
    case corpusForgotten
    /// Derived learning was rebuilt from the current reviewed labels.
    case learningRebuilt
    /// The latest correction's rules and learning were restored; its mail action was not.
    case correctionUndone
    /// A free-text description stored without a typed change.
    case recorded(String)

    /// The category of this change.
    public var kind: Kind {
      switch self {
        case .settingsChanged, .recorded: .settings
        case .senderRuleSaved, .senderRuleRemoved, .senderRulesImported: .senderRule
        case .contentRuleSaved, .contentRuleRemoved, .contentRulesImported: .contentRule
        case .corrected: .correction
        case .backupRestored: .backupRestore
        case .corpusImported, .corpusRelabeled, .learningRebuilt: .corpusImport
        case .corpusForgotten: .corpusForget
        case .correctionUndone: .undo
      }
    }
  }
}

extension AppState {
  /// Records a bounded event in the same transaction as its mutation.
  public mutating func audit(_ change: AuditEvent.Change) {
    auditEvents.append(AuditEvent(revision: revision, change: change))
    auditEvents = Array(auditEvents.suffix(RetentionLimits.auditEvents))
  }
}

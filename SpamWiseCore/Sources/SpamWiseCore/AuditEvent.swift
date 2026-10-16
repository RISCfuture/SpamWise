public import Foundation

/// A durable configuration or learning mutation, independent of decision records.
public struct AuditEvent: Codable, Sendable, Identifiable {
  /// Stable event identity.
  public var id = UUID()
  /// Local event time.
  public var date = Date()
  /// Configuration revision after the mutation.
  public var revision: Int
  /// Fixed event category for filtering and localization.
  public var kind: Kind
  /// Bounded description without credentials or message bodies.
  public var detail: String
  /// Supported configuration and learning events.
  public enum Kind: String, Codable, Sendable {
    case settings, senderRule, contentRule, correction, backupRestore, corpusImport, corpusForget,
      undo
  }
}

extension AppState {
  private static let maximumAuditEvents = 1000
  private static let maximumAuditDetailCharacters = 500
  /// Records a bounded event in the same transaction as its mutation.
  public mutating func audit(_ kind: AuditEvent.Kind, detail: String) {
    var events = auditEvents ?? []
    events.append(
      AuditEvent(
        revision: revision,
        kind: kind,
        detail: String(detail.prefix(Self.maximumAuditDetailCharacters))
      )
    )
    auditEvents = Array(events.suffix(Self.maximumAuditEvents))
  }
}

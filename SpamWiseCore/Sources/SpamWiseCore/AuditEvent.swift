public import Foundation

/// A durable configuration or learning mutation, independent of decision records.
public struct AuditEvent: Codable, Sendable, Equatable, Identifiable {
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
  public enum Kind: String, Codable, Sendable, FallbackDecodable {
    case settings, senderRule, contentRule, correction, backupRestore, corpusImport, corpusForget,
      undo
    /// An unrecognized category is shown as a settings change.
    public static var fallback: Self { .settings }
  }
}

extension AppState {
  /// Records a bounded event in the same transaction as its mutation.
  public mutating func audit(_ kind: AuditEvent.Kind, detail: String) {
    auditEvents.append(
      AuditEvent(
        revision: revision,
        kind: kind,
        detail: String(detail.prefix(RetentionLimits.auditDetailCharacters))
      )
    )
    auditEvents = Array(auditEvents.suffix(RetentionLimits.auditEvents))
  }
}

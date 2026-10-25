package import Foundation
package import SwiftData

/// The original schema: one keyed document per value, including the whole application snapshot.
package enum StoreSchemaV1: VersionedSchema {
  /// Schema version of the single-document store.
  package static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
  /// Entities in the single-document store.
  package static var models: [any PersistentModel.Type] { [StoredValue.self] }

  /// A small keyed document with a JSON payload.
  @Model
  package final class StoredValue {
    /// Unique document name.
    @Attribute(.unique)
    package var key: String
    /// JSON-encoded document value.
    package var payload: Data
    /// Creates a document row.
    package init(key: String, payload: Data) { self.key = key; self.payload = payload }
  }
}

/// Entity-per-element schema whose hot paths fetch only the rows they use.
package enum StoreSchemaV2: VersionedSchema {
  /// Schema version of the entity store.
  package static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
  /// Entities in the entity store.
  package static var models: [any PersistentModel.Type] {
    [
      StoredValue.self, ChangeRow.self, RecordRow.self, ClaimRow.self, RetryRow.self,
      HistoryRow.self, LabelRow.self, CorrectionRow.self, SenderRuleRow.self, ContentRuleRow.self,
      ContentRuleHitRow.self, AuditRow.self, MailHealthRow.self
    ]
  }
}

/// Adds the entity tables to an existing single-document store without changing its rows.
package enum StoreMigrationPlan: SchemaMigrationPlan {
  /// Schemas in migration order.
  package static var schemas: [any VersionedSchema.Type] {
    [StoreSchemaV1.self, StoreSchemaV2.self]
  }
  /// Lightweight addition of the entity tables.
  package static var stages: [MigrationStage] {
    [.lightweight(fromVersion: StoreSchemaV1.self, toVersion: StoreSchemaV2.self)]
  }
}

/// A small keyed document with a JSON payload.
package typealias StoredValue = StoreSchemaV1.StoredValue

/// A JSON element addressed by a unique string key.
package protocol PayloadRow: PersistentModel {
  /// Unique element identity.
  var key: String { get set }
  /// JSON-encoded element.
  var payload: Data { get set }
  /// Matches rows whose key is in `keys`.
  static func keyed(_ keys: [String]) -> Predicate<Self>
}

/// A JSON element whose collection order is persisted explicitly.
package protocol OrderedPayloadRow: PayloadRow {
  /// Ascending position within the collection.
  var order: Int { get set }
  /// Creates a row for a newly inserted element.
  init(key: String, order: Int, payload: Data)
  /// The `limit` rows with the lowest order.
  static func oldest(_ limit: Int) -> FetchDescriptor<Self>
}

/// The latest change-counter value at which a named slice was written.
@Model
package final class ChangeRow {
  /// Slice name.
  @Attribute(.unique)
  package var key: String
  /// Counter value of the latest write.
  package var value: Int
  /// Creates a counter row.
  package init(key: String, value: Int) { self.key = key; self.value = value }
}

/// One Activity decision, with indexed columns for paged and predicate fetches.
@Model
package final class RecordRow: PayloadRow {
  #Index<RecordRow>([\.date], [\.identityKey], [\.changeStamp])
  /// Record identifier.
  @Attribute(.unique)
  package var key: String
  /// Account-scoped message identity key.
  package var identityKey: String
  /// Mail account identifier, when known.
  package var accountID: String?
  /// Decision creation time.
  package var date: Date
  /// Raw action outcome.
  package var outcome: String
  /// Raw intended label, when classified.
  package var label: String?
  /// Raw label of the user's explicit correction, when corrected.
  package var correctedLabel: String?
  /// Decision source.
  package var path: String
  /// Sender address for text search.
  package var sender: String
  /// Subject for text search.
  package var subject: String
  /// Decision explanation for text search.
  package var reason: String
  /// Change counter at the latest write.
  package var changeStamp: Int
  /// JSON-encoded record.
  package var payload: Data
  /// Creates an empty row whose columns are assigned by the caller.
  package init(key: String) {
    self.key = key; identityKey = ""; date = .distantPast; outcome = ""; path = ""
    sender = ""; subject = ""; reason = ""; changeStamp = 0; payload = Data()
  }
}

/// A durable at-most-once action claim for one message identity.
@Model
package final class ClaimRow {
  #Index<ClaimRow>([\.date])
  /// Message identity key.
  @Attribute(.unique)
  package var key: String
  /// Record that requested the action.
  package var recordID: String
  /// Time the claim was first written.
  package var date: Date
  /// Creates a claim row.
  package init(key: String, recordID: String, date: Date) {
    self.key = key; self.recordID = recordID; self.date = date
  }
}

/// One bounded classification retry.
@Model
package final class RetryRow: PayloadRow {
  /// Message identity key.
  @Attribute(.unique)
  package var key: String
  /// Mail account identifier, when known.
  package var accountID: String?
  /// JSON-encoded retry job.
  package var payload: Data
  /// Creates a retry row.
  package init(key: String, accountID: String?, payload: Data) {
    self.key = key; self.accountID = accountID; self.payload = payload
  }
}

/// One account's correspondence counts, with its import identities stored separately.
@Model
package final class HistoryRow: PayloadRow {
  /// Mail account identifier.
  @Attribute(.unique)
  package var key: String
  /// JSON-encoded counts, without import identities.
  package var payload: Data
  /// JSON-encoded bounded import identities used only while importing history.
  package var imports: Data
  /// Creates a history row.
  package init(key: String, payload: Data, imports: Data) {
    self.key = key; self.payload = payload; self.imports = imports
  }
}

/// One explicit reviewed label.
@Model
package final class LabelRow: OrderedPayloadRow {
  /// Content identity.
  @Attribute(.unique)
  package var key: String
  /// Ascending position, oldest first.
  package var order: Int
  /// JSON-encoded label.
  package var payload: Data
  /// Creates a label row.
  package init(key: String, order: Int, payload: Data) {
    self.key = key; self.order = order; self.payload = payload
  }
}

/// One quoted correction example.
@Model
package final class CorrectionRow: OrderedPayloadRow {
  /// Example identifier.
  @Attribute(.unique)
  package var key: String
  /// Ascending position, oldest first.
  package var order: Int
  /// JSON-encoded example.
  package var payload: Data
  /// Creates an example row.
  package init(key: String, order: Int, payload: Data) {
    self.key = key; self.order = order; self.payload = payload
  }
}

/// One explicit sender rule.
@Model
package final class SenderRuleRow: OrderedPayloadRow {
  /// Scoped rule identity.
  @Attribute(.unique)
  package var key: String
  /// Ascending position, oldest first.
  package var order: Int
  /// JSON-encoded rule.
  package var payload: Data
  /// Creates a rule row.
  package init(key: String, order: Int, payload: Data) {
    self.key = key; self.order = order; self.payload = payload
  }
}

/// One user-authored content rule.
@Model
package final class ContentRuleRow: OrderedPayloadRow {
  /// Rule identifier.
  @Attribute(.unique)
  package var key: String
  /// Ascending position, oldest first.
  package var order: Int
  /// JSON-encoded rule.
  package var payload: Data
  /// Creates a rule row.
  package init(key: String, order: Int, payload: Data) {
    self.key = key; self.order = order; self.payload = payload
  }
}

/// The winning-match count of one content rule.
@Model
package final class ContentRuleHitRow: PayloadRow {
  /// Rule identifier.
  @Attribute(.unique)
  package var key: String
  /// JSON-encoded count.
  package var payload: Data
  /// Creates a count row.
  package init(key: String, payload: Data) { self.key = key; self.payload = payload }
}

/// One configuration or learning audit event.
@Model
package final class AuditRow: OrderedPayloadRow {
  /// Event identifier.
  @Attribute(.unique)
  package var key: String
  /// Ascending position, oldest first.
  package var order: Int
  /// JSON-encoded event.
  package var payload: Data
  /// Creates an event row.
  package init(key: String, order: Int, payload: Data) {
    self.key = key; self.order = order; self.payload = payload
  }
}

/// Durable sweep progress for one account or configured folder.
@Model
package final class MailHealthRow: PayloadRow {
  /// Account identifier or folder cursor key.
  @Attribute(.unique)
  package var key: String
  /// JSON-encoded progress.
  package var payload: Data
  /// Creates a progress row.
  package init(key: String, payload: Data) { self.key = key; self.payload = payload }
}

extension RecordRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<RecordRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension RetryRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<RetryRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension HistoryRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<HistoryRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension LabelRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<LabelRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension CorrectionRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<CorrectionRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension SenderRuleRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<SenderRuleRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension ContentRuleRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<ContentRuleRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension ContentRuleHitRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<ContentRuleHitRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension AuditRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<AuditRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension MailHealthRow {
  /// Matches rows whose key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<MailHealthRow> {
    #Predicate { keys.contains($0.key) }
  }
}

extension LabelRow {
  /// The `limit` rows with the lowest order.
  package static func oldest(_ limit: Int) -> FetchDescriptor<LabelRow> {
    var descriptor = FetchDescriptor<LabelRow>(sortBy: [SortDescriptor(\.order)])
    descriptor.fetchLimit = limit
    return descriptor
  }
}

extension CorrectionRow {
  /// The `limit` rows with the lowest order.
  package static func oldest(_ limit: Int) -> FetchDescriptor<CorrectionRow> {
    var descriptor = FetchDescriptor<CorrectionRow>(sortBy: [SortDescriptor(\.order)])
    descriptor.fetchLimit = limit
    return descriptor
  }
}

extension SenderRuleRow {
  /// The `limit` rows with the lowest order.
  package static func oldest(_ limit: Int) -> FetchDescriptor<SenderRuleRow> {
    var descriptor = FetchDescriptor<SenderRuleRow>(sortBy: [SortDescriptor(\.order)])
    descriptor.fetchLimit = limit
    return descriptor
  }
}

extension ContentRuleRow {
  /// The `limit` rows with the lowest order.
  package static func oldest(_ limit: Int) -> FetchDescriptor<ContentRuleRow> {
    var descriptor = FetchDescriptor<ContentRuleRow>(sortBy: [SortDescriptor(\.order)])
    descriptor.fetchLimit = limit
    return descriptor
  }
}

extension AuditRow {
  /// The `limit` rows with the lowest order.
  package static func oldest(_ limit: Int) -> FetchDescriptor<AuditRow> {
    var descriptor = FetchDescriptor<AuditRow>(sortBy: [SortDescriptor(\.order)])
    descriptor.fetchLimit = limit
    return descriptor
  }
}

extension RecordRow {
  /// The `limit` oldest records by decision date.
  package static func oldest(_ limit: Int) -> FetchDescriptor<RecordRow> {
    var descriptor = FetchDescriptor<RecordRow>(sortBy: [SortDescriptor(\.date)])
    descriptor.fetchLimit = limit
    return descriptor
  }
}

extension ClaimRow {
  /// Matches claims whose identity key is in `keys`.
  package static func keyed(_ keys: [String]) -> Predicate<ClaimRow> {
    #Predicate { keys.contains($0.key) }
  }
  /// Matches claims written before `date`.
  package static func older(than date: Date) -> Predicate<ClaimRow> {
    #Predicate { $0.date < date }
  }
}

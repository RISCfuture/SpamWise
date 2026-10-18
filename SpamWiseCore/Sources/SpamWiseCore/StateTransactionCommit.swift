import Foundation
import SwiftData

extension StateTransaction {
  func commitDocuments(_ changed: inout Set<StateSlice>) throws {
    if state.revision != baseline.revision || state.settings != baseline.settings {
      try write(PolicyDocument(revision: state.revision, settings: state.settings), Self.policyKey)
      changed.insert(.policy)
    }
    if state.costByMonth != baseline.costByMonth || state.lastDigestWeek != baseline.lastDigestWeek
    {
      try write(
        MetaDocument(costByMonth: state.costByMonth, lastDigestWeek: state.lastDigestWeek),
        Self.metaKey
      )
      changed.insert(.meta)
    }
    if ContactsDocument(state) != ContactsDocument(baseline) {
      try requireLoaded(.contacts, .contacts)
      try write(ContactsDocument(state), Self.contactsKey)
      changed.insert(.contacts)
    }
    if TrainingDocument(state) != TrainingDocument(baseline) {
      try requireLoaded(.training, .training)
      try write(TrainingDocument(state), Self.trainingKey)
      changed.insert(.training)
    }
    if state.contentRuleSkips != baseline.contentRuleSkips {
      try requireLoaded(.contentRules, .contentRuleSkips)
      try write(state.contentRuleSkips, Self.contentRuleSkipsKey)
      changed.insert(.contentRuleSkips)
    }
    if state.learning != baseline.learning {
      try requireLoaded(.learning, .learning)
      try write(state.learning, Self.learningKey)
      changed.insert(.learning)
    }
    if state.authServerObservations != baseline.authServerObservations {
      try requireLoaded(.authentication, .authentication)
      try write(state.authServerObservations, Self.authenticationKey)
      changed.insert(.authentication)
    }
    try commitUndo(&changed)
  }
  /// Writes a replaced undo, or discards it when pending work was invalidated or what it restores changed.
  private func commitUndo(_ changed: inout Set<StateSlice>) throws {
    let replaced = state.correctionUndo != baseline.correctionUndo
    let superseded = !changed.isDisjoint(with: [.rules, .corrections, .learning, .reviewedLabels])
    guard replaced || state.invalidatedPendingWork || superseded else { return }
    if replaced && !state.invalidatedPendingWork { try requireLoaded(.undo, .undo) }
    if replaced, let undo = state.correctionUndo {
      try write(undo, Self.undoKey)
    } else {
      try context.removeDocument(Self.undoKey)
    }
    changed.insert(.undo)
  }
  private func requireLoaded(_ part: StateSlices.Parts, _ slice: StateSlice) throws {
    guard parts.contains(part) else { throw StoreError.unloadedChange(slice.rawValue) }
  }
  private func write(_ value: some Encodable, _ key: String) throws {
    try context.setDocument(key, encoder.encode(value))
  }
}

extension StateTransaction {
  private static func hits(_ state: AppState) -> [HitCount] {
    state.contentRuleHits.map { HitCount(id: $0.key.uuidString, count: $0.value) }
  }
  func commitCollections(stamp: Int, _ changed: inout Set<StateSlice>) throws {
    let ordered = [
      try commitOrdered(.rules, state.rules, baseline.rules, key: \.id) {
        SenderRuleRow(key: $0, order: $1, payload: $2)
      },
      try commitOrdered(.contentRules, state.contentRules, baseline.contentRules) {
        $0.id.uuidString
      } make: {
        ContentRuleRow(key: $0, order: $1, payload: $2)
      },
      try commitOrdered(.corrections, state.corrections, baseline.corrections) {
        $0.id.uuidString
      } make: {
        CorrectionRow(key: $0, order: $1, payload: $2)
      },
      try commitOrdered(.audit, state.auditEvents, baseline.auditEvents) {
        $0.id.uuidString
      } make: {
        AuditRow(key: $0, order: $1, payload: $2)
      },
      try commitOrdered(.reviewedLabels, state.reviewedLabels, baseline.reviewedLabels) {
        $0.id
      } make: {
        LabelRow(key: $0, order: $1, payload: $2)
      }
    ]
    changed.formUnion(ordered.compactMap(\.self))
    let hits = RowCodec<HitCount, ContentRuleHitRow>(key: \.id) {
      ContentRuleHitRow(key: $0, payload: $1)
    }
    if try commitRows(.contentRuleHits, Self.hits(state), Self.hits(baseline), hits) {
      changed.insert(.contentRuleHits)
    }
    if try commitRecords(stamp: stamp) { changed.insert(.records) }
    if try commitRetries() { changed.insert(.retries) }
    if try commitClaims() { changed.insert(.claims) }
    if try commitHistories() { changed.insert(.histories) }
    try prune(changed)
  }
  private func commitRecords(stamp: Int) throws -> Bool {
    let codec = RowCodec<DecisionRecord, RecordRow>(
      key: { $0.id.uuidString },
      make: { key, _ in RecordRow(key: key) },
      configure: { record, row in
        row.identityKey = record.identity.key; row.accountID = record.identity.accountID
        row.date = record.date; row.outcome = record.outcome.rawValue
        row.path = record.path.rawValue
        row.label = record.decision.label?.rawValue
        row.correctedLabel = record.correctedLabel?.rawValue
        row.sender = record.sender ?? ""; row.subject = record.subject ?? ""
        row.reason = record.decision.reason.localizedDescription
        row.changeStamp = stamp
      }
    )
    return try commitRows(.records, state.records, baseline.records, codec)
  }
  private func commitRetries() throws -> Bool {
    if state.invalidatedPendingWork { try context.delete(model: RetryRow.self) }
    let codec = RowCodec<RetryJob, RetryRow>(
      key: \.id,
      make: { key, payload in RetryRow(key: key, accountID: nil, payload: payload) },
      configure: { job, row in row.accountID = job.identity.accountID }
    )
    let previous = state.invalidatedPendingWork ? [] : baseline.retries
    return try commitRows(.retries, state.retries, previous, codec)
      || state.invalidatedPendingWork
  }
  private func commitClaims() throws -> Bool {
    let removed = Set(baseline.claimedActions.keys).subtracting(state.claimedActions.keys)
    let written = state.claimedActions.filter { baseline.claimedActions[$0.key] != $0.value }
    guard !removed.isEmpty || !written.isEmpty else { return false }
    let rows = try context.fetch(
      FetchDescriptor(predicate: ClaimRow.keyed(Array(removed.union(written.keys))))
    )
    let byKey = Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    for key in removed { byKey[key].map(context.delete) }
    for (key, recordID) in written {
      if let row = byKey[key] {
        row.recordID = recordID.uuidString; row.date = .now
      } else {
        context.insert(ClaimRow(key: key, recordID: recordID.uuidString, date: .now))
      }
    }
    try context.delete(
      model: ClaimRow.self,
      where: ClaimRow.older(than: Date(timeIntervalSinceNow: -RetentionLimits.actionClaimAge))
    )
    return true
  }
  /// Writes counts and, only when they were read, import identities.
  private func commitHistories() throws -> Bool {
    let removed = Set(baseline.histories.keys).subtracting(state.histories.keys)
    let written = state.histories.filter { baseline.histories[$0.key] != $0.value }
    guard !removed.isEmpty || !written.isEmpty else { return false }
    let rows = try context.fetch(
      FetchDescriptor(predicate: HistoryRow.keyed(Array(removed.union(written.keys))))
    )
    let byKey = Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    for key in removed { byKey[key].map(context.delete) }
    for (key, index) in written {
      var counts = index
      counts.importedIDs = RollingIdentitySet(capacity: RetentionLimits.historyImportIdentities)
      let payload = try encoder.encode(counts), imports = try encoder.encode(index.importedIDs)
      if let row = byKey[key] {
        row.payload = payload
        if parts.contains(.historyImports) {
          row.imports = imports
        } else if index.importedIDs.count > 0 {
          throw StoreError.unloadedChange(StateSlice.histories.rawValue)
        }
      } else {
        context.insert(HistoryRow(key: key, payload: payload, imports: imports))
      }
    }
    return true
  }
}

extension StateTransaction {
  /**
   Writes an ordered collection, keeping persisted positions that are still ascending.

   - Returns: The slice, if anything was written.
   */
  private func commitOrdered<Element: Encodable & Equatable, Row: OrderedPayloadRow>(
    _ slice: StateSlice,
    _ current: [Element],
    _ previous: [Element],
    key: @escaping (Element) -> String,
    make: @escaping (String, Int, Data) -> Row
  ) throws -> StateSlice? {
    var lastOrder = Int.min
    var assigned: [String: Int] = [:]
    for element in current {
      let id = key(element)
      if let existing = orders[slice]?[id], existing > lastOrder {
        lastOrder = existing
      } else {
        nextOrder += 1; lastOrder = nextOrder; assigned[id] = nextOrder
      }
    }
    let positions = assigned
    let codec = RowCodec<Element, Row>(
      key: key,
      make: { id, payload in make(id, positions[id] ?? 0, payload) },
      configure: { element, row in
        if let order = positions[key(element)] { row.order = order }
      }
    )
    let written = try commitRows(slice, current, previous, codec, forceWrite: Set(assigned.keys))
    return written ? slice : nil
  }
  /**
   Deletes read elements that are gone and upserts elements that are new or changed.

   - Returns: Whether any row was written or deleted.
   */
  private func commitRows<Element: Encodable & Equatable, Row: PayloadRow>(
    _ slice: StateSlice,
    _ current: [Element],
    _ previous: [Element],
    _ codec: RowCodec<Element, Row>,
    forceWrite: Set<String> = []
  ) throws -> Bool {
    let key = codec.key
    let before = Dictionary(previous.map { (key($0), $0) }, uniquingKeysWith: { _, last in last })
    let removed = Set(before.keys).subtracting(current.map(key))
    let written = current.filter { before[key($0)] != $0 || forceWrite.contains(key($0)) }
    guard !removed.isEmpty || !written.isEmpty else { return false }
    let keys = removed.union(written.map(key))
    let rows = try context.fetch(FetchDescriptor(predicate: Row.keyed(Array(keys))))
    var byKey = Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    for id in removed { byKey[id].map(context.delete) }
    for element in written {
      let id = key(element), payload = try encoder.encode(element)
      let row: Row
      if let existing = byKey[id] {
        existing.payload = payload; row = existing
      } else {
        row = codec.make(id, payload); row.payload = payload
        context.insert(row); byKey[id] = row
      }
      codec.configure(element, row)
    }
    return true
  }
  private func prune(_ changed: Set<StateSlice>) throws {
    if changed.contains(.records) {
      try prune(limit: RetentionLimits.activityRecords, oldest: RecordRow.oldest)
    }
    if changed.contains(.audit) {
      try prune(limit: RetentionLimits.auditEvents, oldest: AuditRow.oldest)
    }
    if changed.contains(.corrections) {
      try prune(limit: RetentionLimits.corrections, oldest: CorrectionRow.oldest)
    }
    if changed.contains(.reviewedLabels) {
      try prune(limit: RetentionLimits.reviewedLabels, oldest: LabelRow.oldest)
    }
  }
  private func prune<Row: PersistentModel>(limit: Int, oldest: (Int) -> FetchDescriptor<Row>)
    throws
  {
    let excess = try context.fetchCount(FetchDescriptor<Row>()) - limit
    guard excess > 0 else { return }
    for row in try context.fetch(oldest(excess)) { context.delete(row) }
  }
}

/// How one collection's elements map to entity rows.
struct RowCodec<Element, Row: PayloadRow> {
  /// Unique element identity.
  let key: (Element) -> String
  /// Creates a row for a new element from its key and payload.
  let make: (String, Data) -> Row
  /// Updates columns derived from the element.
  var configure: (Element, Row) -> Void = { _, _ in }
}

struct PolicyDocument: Codable {
  var revision = 0
  var settings = Settings()
}

struct MetaDocument: Codable {
  var costByMonth: [String: Double] = [:]
  var lastDigestWeek: String?
}

struct ContactsDocument: Codable, Equatable {
  var contactAddresses: Set<String>?
  var contactsUpdatedAt: Date?
  var ownAddresses: Set<String> = []
  init() {}
  init(_ state: AppState) {
    contactAddresses = state.contactAddresses; contactsUpdatedAt = state.contactsUpdatedAt
    ownAddresses = state.ownAddresses
  }
}

struct TrainingDocument: Codable, Equatable {
  var claims: [String: UUID] = [:]
  var observations: [String: Set<String>] = [:]
  init() {}
  init(_ state: AppState) {
    claims = state.trainingClaims; observations = state.trainingObservations
  }
}

/// One content rule's winning-match count, stored as a bare integer.
struct HitCount: Encodable, Equatable {
  let id: String
  let count: Int
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(count)
  }
}

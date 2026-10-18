import Foundation
import SwiftData

/**
 Reads selected slices of ``AppState`` from entity rows and writes back only what changed.

 Loading records what was read; committing compares the state with that baseline, so a
 transaction deletes only elements it read and never overwrites a slice it did not read.
 */
final class StateTransaction {
  static let ordersPerCommit = 20
  static let policyKey = "state.policy"
  static let metaKey = "state.meta"
  static let contactsKey = "state.contacts"
  static let trainingKey = "state.training"
  static let learningKey = "state.learning"
  static let undoKey = "state.undo"
  static let contentRuleSkipsKey = "state.contentRuleSkips"
  static let authenticationKey = "state.authentication"
  let context: ModelContext
  var state = AppState()
  /// The state as read, compared with ``state`` to find what to write.
  var baseline = AppState()
  /// Whole parts read so far.
  var parts: StateSlices.Parts = []
  /// Persisted positions of the ordered elements read so far.
  var orders: [StateSlice: [String: Int]] = [:]
  /// The latest position assigned during this commit.
  var nextOrder = 0
  let encoder = JSONEncoder()
  private var loadedKeys: [StateSlice: Set<String>] = [:]
  private var loadedAll: Set<StateSlice> = []
  private let decoder = JSONDecoder()

  /// Opens a transaction with settings, the revision and usage totals read.
  init(context: ModelContext) throws {
    self.context = context
    let policy = try document(Self.policyKey, slice: .policy, default: PolicyDocument())
    let meta = try document(Self.metaKey, slice: .meta, default: MetaDocument())
    state.revision = policy.revision; state.settings = policy.settings
    state.costByMonth = meta.costByMonth; state.lastDigestWeek = meta.lastDigestWeek
    baseline = state
  }
  /// Opens a transaction that writes `imported` into empty entity tables.
  init(importing imported: AppState, context: ModelContext) {
    self.context = context
    state = imported
    parts = .all
    loadedAll = Set(StateSlice.allCases)
  }
}

extension StateTransaction {
  /// Reads every selected slice not already read; call before mutating ``state``.
  func load(_ slices: StateSlices) throws {
    let newParts = slices.parts.subtracting(parts)
    try loadDocuments(newParts)
    parts.formUnion(slices.parts)
    if newParts.contains(.rules) {
      state.rules = try loadOrdered(.rules, SenderRuleRow.self, .all, key: \.id)
    }
    if newParts.contains(.contentRules) {
      state.contentRules = try loadOrdered(.contentRules, ContentRuleRow.self, .all) {
        $0.id.uuidString
      }
      state.contentRuleHits = try loadHits()
      state.contentRuleSkips = try document(
        Self.contentRuleSkipsKey,
        slice: .contentRuleSkips,
        default: [UUID: Int]()
      )
    }
    if newParts.contains(.corrections) {
      state.corrections = try loadOrdered(.corrections, CorrectionRow.self, .all) {
        $0.id.uuidString
      }
    }
    if newParts.contains(.audit) {
      state.auditEvents = try loadOrdered(.audit, AuditRow.self, .all) { $0.id.uuidString }
    }
    state.reviewedLabels = try loadOrdered(
      .reviewedLabels,
      LabelRow.self,
      slices.reviewedLabels,
      merging: state.reviewedLabels,
      key: \.id
    )
    state.records = try loadRecords(slices.records)
    state.retries = try loadUnordered(
      .retries,
      RetryRow.self,
      slices.retries,
      merging: state.retries,
      key: \.id
    )
    state.claimedActions.merge(try loadClaims(slices.claims)) { _, loaded in loaded }
    state.histories.merge(try loadHistories(slices.histories)) { _, loaded in loaded }
    baseline = state
  }
  /// Reads `identity`'s action claim and the record that holds it.
  func loadClaim(for identity: MessageIdentity) throws {
    try load(StateSlices(claims: .only([identity.key])))
    guard let recordID = state.claimedActions[identity.key] else { return }
    try load(StateSlices(records: .only([recordID])))
  }
  /// Identifiers of every retained record for one message identity, without decoding them.
  func recordIDs(identityKey: String) throws -> Set<UUID> {
    let rows = try context.fetch(
      FetchDescriptor<RecordRow>(predicate: #Predicate { $0.identityKey == identityKey })
    )
    return Set(rows.compactMap { UUID(uuidString: $0.key) })
  }
  /// Writes every changed slice, stamps its change token, and saves.
  func commit() throws {
    try stage()
    try context.save()
  }
  /// Writes every changed slice and stamps its change token without saving.
  func stage() throws {
    let stamp = try context.nextChangeStamp()
    nextOrder = stamp << Self.ordersPerCommit
    var changed = Set<StateSlice>()
    try commitCollections(stamp: stamp, &changed)
    try commitDocuments(&changed)
    if !changed.isEmpty { try context.markChanged(changed.map(\.rawValue), stamp: stamp) }
  }
}

extension StateTransaction {
  private func loadDocuments(_ newParts: StateSlices.Parts) throws {
    if newParts.contains(.contacts) {
      let contacts = try document(Self.contactsKey, slice: .contacts, default: ContactsDocument())
      state.contactAddresses = contacts.contactAddresses
      state.contactsUpdatedAt = contacts.contactsUpdatedAt
      state.ownAddresses = contacts.ownAddresses
    }
    if newParts.contains(.training) {
      let training = try document(Self.trainingKey, slice: .training, default: TrainingDocument())
      state.trainingClaims = training.claims; state.trainingObservations = training.observations
    }
    if newParts.contains(.learning) {
      state.learning = try document(Self.learningKey, slice: .learning, default: LearningState())
    }
    if newParts.contains(.undo) {
      state.correctionUndo = try document(
        Self.undoKey,
        slice: .undo,
        default: CorrectionUndo?.none
      )
    }
    if newParts.contains(.authentication) {
      state.authServerObservations = try document(
        Self.authenticationKey,
        slice: .authentication,
        default: [String: AuthServerObservations]()
      )
    }
  }
  /// Decodes a document, setting aside an unreadable one for recovery and using `fallback`.
  private func document<T: Codable>(_ key: String, slice: StateSlice, default fallback: T) throws
    -> T
  {
    guard let data = try context.document(key) else { return fallback }
    do { return try decoder.decode(T.self, from: data) } catch {
      try StateRecovery.quarantine(data, source: slice.rawValue, in: context)
      try context.removeDocument(key)
      return fallback
    }
  }
  private func decoded<T: Decodable>(_ rows: [some PayloadRow], as type: T.Type) -> [T] {
    rows.compactMap { try? decoder.decode(T.self, from: $0.payload) }
  }
  private func fetch<Row: PayloadRow>(_ slice: StateSlice, _ selection: StateSelection<String>)
    throws -> [Row]
  {
    guard !loadedAll.contains(slice) else { return [] }
    switch selection {
      case .none: return []
      case .all:
        loadedAll.insert(slice)
        return try context.fetch(FetchDescriptor<Row>())
      case .only(let keys):
        let missing = keys.subtracting(loadedKeys[slice, default: []])
        loadedKeys[slice, default: []].formUnion(missing)
        guard !missing.isEmpty else { return [] }
        return try context.fetch(FetchDescriptor(predicate: Row.keyed(Array(missing))))
    }
  }
  private func loadOrdered<Element: Decodable, Row: OrderedPayloadRow>(
    _ slice: StateSlice,
    _ row: Row.Type,
    _ selection: StateSelection<String>,
    merging existing: [Element] = [],
    key: (Element) -> String
  ) throws -> [Element] {
    let rows: [Row] = try fetch(slice, selection).sorted { $0.order < $1.order }
    for row in rows { orders[slice, default: [:]][row.key] = row.order }
    let elements = decoded(rows, as: Element.self)
    let loaded = Set(elements.map(key))
    return existing.filter { !loaded.contains(key($0)) } + elements
  }
  private func loadUnordered<Element: Decodable, Row: PayloadRow>(
    _ slice: StateSlice,
    _ row: Row.Type,
    _ selection: StateSelection<String>,
    merging existing: [Element],
    key: (Element) -> String
  ) throws -> [Element] {
    let elements = decoded(try fetch(slice, selection) as [Row], as: Element.self)
    let loaded = Set(elements.map(key))
    return existing.filter { !loaded.contains(key($0)) } + elements
  }
  private func loadRecords(_ selection: StateSelection<UUID>) throws -> [DecisionRecord] {
    let keys: StateSelection<String> =
      switch selection {
        case .none: .none
        case .all: .all
        case .only(let ids): .only(Set(ids.map(\.uuidString)))
      }
    return try loadUnordered(.records, RecordRow.self, keys, merging: state.records) {
      (record: DecisionRecord) in record.id.uuidString
    }.sorted { $0.date < $1.date }
  }
  private func loadHits() throws -> [UUID: Int] {
    let rows: [ContentRuleHitRow] = try fetch(.contentRuleHits, .all)
    return rows.reduce(into: [:]) { hits, row in
      if let id = UUID(uuidString: row.key) {
        hits[id] = try? decoder.decode(Int.self, from: row.payload)
      }
    }
  }
  private func loadClaims(_ selection: StateSelection<String>) throws -> [String: UUID] {
    guard !loadedAll.contains(.claims) else { return [:] }
    let rows: [ClaimRow]
    switch selection {
      case .none: return [:]
      case .all:
        loadedAll.insert(.claims)
        rows = try context.fetch(FetchDescriptor<ClaimRow>())
      case .only(let keys):
        loadedKeys[.claims, default: []].formUnion(keys)
        rows = try context.fetch(FetchDescriptor(predicate: ClaimRow.keyed(Array(keys))))
    }
    return rows.reduce(into: [:]) { claims, row in
      claims[row.key] = UUID(uuidString: row.recordID)
    }
  }
  private func loadHistories(_ selection: StateSelection<String>) throws -> [String: HistoryIndex] {
    let rows: [HistoryRow] = try fetch(.histories, selection)
    let withImports = parts.contains(.historyImports)
    return rows.reduce(into: [:]) { histories, row in
      guard var index = try? decoder.decode(HistoryIndex.self, from: row.payload) else { return }
      if withImports, let imports = try? decoder.decode([String].self, from: row.imports) {
        index.importedIDs = RollingIdentitySet(
          capacity: RetentionLimits.historyImportIdentities,
          imports
        )
      }
      histories[row.key] = index
    }
  }
}

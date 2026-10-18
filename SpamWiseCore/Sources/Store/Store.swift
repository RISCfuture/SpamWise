public import Foundation
package import SwiftData
import Darwin
import Synchronization

/// Failures while accessing durable shared storage.
public protocol StorageFailure: Error {}

/// Shared storage or transaction-lock failures.
public enum StoreError: StorageFailure, Sendable, LocalizedError {
  /// Another process held the transaction lock for longer than the bounded wait.
  case lockUnavailable
  /// The signed App Group container could not be resolved.
  case missingAppGroup
  /// The store path identifies a directory instead of a file.
  case invalidPath
  /// A transaction changed state that it did not load, so its result cannot be merged safely.
  case unloadedChange(String)
  /// Whether repeating the operation later can succeed without any configuration change.
  public var retryable: Bool { self == .lockUnavailable }
  /// General description of the failed storage operation.
  public var errorDescription: String? {
    String(localized: "Shared storage is unavailable.", bundle: .module)
  }
  /// The storage prerequisite that could not be satisfied.
  public var failureReason: String? {
    switch self {
      case .lockUnavailable:
        String(localized: "The shared storage lock could not be acquired.", bundle: .module)
      case .missingAppGroup:
        String(localized: "The shared app container is unavailable.", bundle: .module)
      case .invalidPath:
        String(localized: "The storage path refers to a directory.", bundle: .module)
      case .unloadedChange(let slice):
        String(
          localized: "A storage update changed “\(slice)” without reading it first.",
          bundle: .module
        )
    }
  }
}

extension StoreError: Equatable {}

/**
 Serializes read-modify-write transactions across processes with an advisory file lock.

 Each process shares one `ModelContainer` per store location, and every transaction uses a
 fresh `ModelContext` so it observes rows committed by other processes. No actor suspension
 occurs between acquiring the lock and saving a transaction.
 */
public actor Store {
  /// App Group shared by the app and extension.
  public static let appGroupIdentifier = "group.codes.tim.SpamWise"
  private static let maximumLockWait: Duration = .seconds(5)
  private static let initialLockBackoff: Duration = .milliseconds(2)
  private static let maximumLockBackoff: Duration = .milliseconds(100)
  private static let lockBackoffFactor = 2
  private static let containers = Mutex<[URL: ModelContainer]>([:])
  /// Location of the durable shared store.
  public nonisolated let url: URL
  /// Creates the parent directory of `url` with owner-only permissions; the database opens on first use.
  public init(url: URL) throws {
    self.url = url
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
  }
  /// Resolves storage inside the signed application's App Group container.
  public static func sharedURL() throws -> URL {
    guard
      let url = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      )
    else { throw StoreError.missingAppGroup }
    return url.appending(path: "SpamWise.store")
  }
  private static func cachedContainer(for url: URL) -> ModelContainer? {
    containers.withLock { $0[url] }
  }
  /// Decodes the document stored under `key`, or returns `fallback` when none is stored.
  public func read<T: Codable & Sendable>(_ key: String, default fallback: T) async throws -> T {
    try await transaction { context in
      try context.document(key).map { try JSONDecoder().decode(T.self, from: $0) } ?? fallback
    }
  }
  /// Reads the stored documents among several keys in one transaction, omitting absent keys.
  public func read<T: Codable & Sendable>(_ keys: Set<String>, as type: T.Type) async throws
    -> [String: T]
  {
    try await transaction { context in try context.documents(keys, as: T.self) }
  }
  /**
   Atomically reads, modifies, and commits several small keyed documents in one transaction.

   The body receives the stored documents among `keys`, omitting absent keys. Documents it adds
   or changes for those keys are committed; other keys and removed entries are left unchanged.
   */
  @discardableResult public func update<T: Codable & Sendable, R: Sendable>(
    _ keys: Set<String>,
    as type: T.Type,
    _ body: @Sendable (inout [String: T]) throws -> R
  ) async throws -> R {
    try await transaction { context in
      var values = try context.documents(keys, as: T.self)
      let result = try body(&values)
      let written = values.filter { keys.contains($0.key) }
      for (key, value) in written { try context.setDocument(key, JSONEncoder().encode(value)) }
      try context.markChanged(written.keys, stamp: context.nextChangeStamp())
      try context.save()
      return result
    }
  }
  /// Atomically reads, modifies, and commits a small keyed document.
  @discardableResult public func update<T: Codable & Sendable, R: Sendable>(
    _ key: String,
    default fallback: T,
    _ body: @Sendable (inout T) throws -> R
  ) async throws -> R {
    try await transaction { context in
      var value =
        try context.document(key).map { try JSONDecoder().decode(T.self, from: $0) } ?? fallback
      let result = try body(&value)
      try context.setDocument(key, JSONEncoder().encode(value))
      try context.markChanged([key], stamp: context.nextChangeStamp())
      try context.save()
      return result
    }
  }
  /// Change counters keyed by slice name, read without waiting for the transaction lock.
  public func changeTokens() async throws -> [String: Int] {
    try await snapshot { context in
      Dictionary(
        try context.fetch(FetchDescriptor<ChangeRow>()).map { ($0.key, $0.value) },
        uniquingKeysWith: max
      )
    }
  }
  /**
   Runs `body` under the cross-process lock with a fresh context.

   The body must save the context itself; unsaved changes are discarded.
   */
  package func transaction<R: Sendable>(_ body: @Sendable (ModelContext) throws -> R)
    async throws -> R
  {
    let descriptor = try await acquireLock()
    defer { release(descriptor) }
    let context = ModelContext(try container())
    context.autosaveEnabled = false
    return try body(context)
  }
  /// Runs a read-only body against committed rows without taking the transaction lock.
  package func snapshot<R: Sendable>(_ body: @Sendable (ModelContext) throws -> R) async throws
    -> R
  {
    if Self.cachedContainer(for: url) == nil { try await transaction { _ in } }
    let context = ModelContext(try container())
    context.autosaveEnabled = false
    return try body(context)
  }
  private func container() throws -> ModelContainer {
    if let cached = Self.cachedContainer(for: url) { return cached }
    let created = try ModelContainer(
      for: Schema(versionedSchema: StoreSchemaV2.self),
      migrationPlan: StoreMigrationPlan.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    return Self.containers.withLock { containers in
      if let existing = containers[url] { return existing }
      containers[url] = created
      return created
    }
  }
  private func acquireLock() async throws -> Int32 {
    var isDirectory: ObjCBool = false
    if unsafe FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      throw StoreError.invalidPath
    }
    let descriptor = unsafe open(url.path + ".lock", O_CREAT | O_RDWR, 0o600)
    guard descriptor >= 0 else { throw StoreError.lockUnavailable }
    do {
      try await waitForLock(descriptor)
      return descriptor
    } catch {
      close(descriptor)
      throw error
    }
  }
  private func waitForLock(_ descriptor: Int32) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + Self.maximumLockWait
    var backoff = Self.initialLockBackoff
    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      guard errno == EWOULDBLOCK, clock.now + backoff < deadline else {
        throw StoreError.lockUnavailable
      }
      try await Task.sleep(for: backoff)
      backoff = min(Self.maximumLockBackoff, backoff * Self.lockBackoffFactor)
    }
  }
  private func release(_ descriptor: Int32) {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}

extension ModelContext {
  private static let globalChangeKey = "*"
  /// Raw bytes of a keyed document, if present.
  package func document(_ key: String) throws -> Data? {
    try fetch(FetchDescriptor<StoredValue>(predicate: #Predicate { $0.key == key })).first?
      .payload
  }
  /// Decoded documents among `keys`, omitting absent keys.
  package func documents<T: Decodable>(_ keys: Set<String>, as type: T.Type) throws -> [String: T] {
    let wanted = Array(keys)
    return try fetch(
      FetchDescriptor<StoredValue>(predicate: #Predicate { wanted.contains($0.key) })
    )
    .reduce(into: [:]) { values, row in
      values[row.key] = try JSONDecoder().decode(T.self, from: row.payload)
    }
  }
  /// Inserts or replaces a keyed document.
  package func setDocument(_ key: String, _ payload: Data) throws {
    if let row = try fetch(FetchDescriptor<StoredValue>(predicate: #Predicate { $0.key == key }))
      .first
    {
      row.payload = payload
    } else {
      insert(StoredValue(key: key, payload: payload))
    }
  }
  /// Deletes a keyed document if it exists.
  package func removeDocument(_ key: String) throws {
    try delete(model: StoredValue.self, where: #Predicate { $0.key == key })
  }
  /// The counter value the next committed write will carry.
  package func nextChangeStamp() throws -> Int {
    var latest = FetchDescriptor<ChangeRow>(sortBy: [SortDescriptor(\.value, order: .reverse)])
    latest.fetchLimit = 1
    return (try fetch(latest).first?.value ?? 0) + 1
  }
  /// Stamps each named slice, and the shared counter, with `stamp` from ``nextChangeStamp()``.
  package func markChanged(_ slices: some Sequence<String>, stamp: Int) throws {
    let keys = Set(slices).union([Self.globalChangeKey])
    let rows = try fetch(
      FetchDescriptor<ChangeRow>(predicate: #Predicate { keys.contains($0.key) })
    )
    for key in keys {
      if let row = rows.first(where: { $0.key == key }) {
        row.value = stamp
      } else {
        insert(ChangeRow(key: key, value: stamp))
      }
    }
  }
}

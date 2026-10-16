public import Foundation
import SwiftData
import Darwin

@Model final class StoredValue {
  @Attribute(.unique) var key: String
  var payload: Data
  init(key: String, payload: Data) { self.key = key; self.payload = payload }
}
/// Failures while accessing durable shared storage.
public protocol StorageFailure: Error {}

/// Shared storage or transaction-lock failures.
public enum StoreError: StorageFailure, Sendable, LocalizedError {
  /// The nonblocking transaction lock could not be acquired.
  case lockUnavailable
  /// The signed App Group container could not be resolved.
  case missingAppGroup
  /// The store path identifies a directory instead of a file.
  case invalidPath
  /// General description of the failed storage operation.
  public var errorDescription: String? { String(localized: "Shared storage is unavailable.") }
  /// The storage prerequisite that could not be satisfied.
  public var failureReason: String? {
    switch self {
      case .lockUnavailable: String(localized: "The shared storage lock could not be acquired.")
      case .missingAppGroup: String(localized: "The shared app container is unavailable.")
      case .invalidPath: String(localized: "The storage path refers to a directory.")
    }
  }
}
/**
 Each operation uses a fresh container/context under a cross-process lock.
 No actor suspension occurs between reading and saving a transaction.
 */
public actor Store {
  /// Location of the durable shared store.
  public let url: URL
  /// Creates a Store with the supplied configuration.
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
        forSecurityApplicationGroupIdentifier: "group.codes.tim.SpamWise"
      )
    else { throw StoreError.missingAppGroup }
    return url.appending(path: "SpamWise.store")
  }
  /// Reads durable state or credentials, throwing when access is unavailable.
  public func read<T: Codable & Sendable>(_ key: String, default fallback: T) throws -> T {
    try access { context in
      let rows = try context.fetch(
        FetchDescriptor<StoredValue>(predicate: #Predicate { $0.key == key })
      )
      guard let row = rows.first else { return fallback }
      return try JSONDecoder().decode(T.self, from: row.payload)
    }
  }
  /// Atomically reads, modifies, and commits a shared value.
  @discardableResult public func update<T: Codable & Sendable, R: Sendable>(
    _ key: String,
    default fallback: T,
    _ body: @Sendable (inout T) throws -> R
  ) throws -> R {
    try access { context in
      let rows = try context.fetch(
        FetchDescriptor<StoredValue>(predicate: #Predicate { $0.key == key })
      )
      var value =
        try rows.first.map { try JSONDecoder().decode(T.self, from: $0.payload) } ?? fallback
      let result = try body(&value)
      let payload = try JSONEncoder().encode(value)
      if let row = rows.first {
        row.payload = payload
      } else {
        context.insert(StoredValue(key: key, payload: payload))
      }
      try context.save()
      return result
    }
  }
  private func access<R>(_ body: (ModelContext) throws -> R) throws -> R {
    var isDirectory: ObjCBool = false
    if unsafe FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      throw StoreError.invalidPath
    }
    let fd = unsafe open(url.path + ".lock", O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw StoreError.lockUnavailable }
    defer { close(fd) }
    // Fail open instead of blocking a Mail callback on an unavailable lock.
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw StoreError.lockUnavailable }
    defer { flock(fd, LOCK_UN) }
    let container = try ModelContainer(
      for: StoredValue.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container); context.autosaveEnabled = false
    return try body(context)
  }
}

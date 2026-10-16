import Foundation
import SwiftData
import Darwin

@Model final class StoredValue {
    @Attribute(.unique) var key: String
    var payload: Data
    init(key: String, payload: Data) { self.key = key; self.payload = payload }
}
public enum StoreError: Error, Sendable { case lockUnavailable, missingAppGroup }
/// Each operation uses a fresh container/context under a cross-process lock.
/// No actor suspension occurs between reading and saving a transaction.
public actor Store {
    public let url: URL
    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public static func sharedURL() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.codes.tim.SpamWise") else { throw StoreError.missingAppGroup }
        return url.appending(path: "SpamWise.store")
    }
    public func read<T: Codable & Sendable>(_ key: String, default fallback: T) throws -> T {
        try access { context in
            let rows = try context.fetch(FetchDescriptor<StoredValue>(predicate: #Predicate { $0.key == key }))
            guard let row = rows.first else { return fallback }
            return try JSONDecoder().decode(T.self, from: row.payload)
        }
    }
    @discardableResult public func update<T: Codable & Sendable, R: Sendable>(_ key: String, default fallback: T, _ body: @Sendable (inout T) throws -> R) throws -> R {
        try access { context in
            let rows = try context.fetch(FetchDescriptor<StoredValue>(predicate: #Predicate { $0.key == key }))
            var value = try rows.first.map { try JSONDecoder().decode(T.self, from: $0.payload) } ?? fallback
            let result = try body(&value)
            let payload = try JSONEncoder().encode(value)
            if let row = rows.first { row.payload = payload } else { context.insert(StoredValue(key: key, payload: payload)) }
            try context.save()
            return result
        }
    }
    private func access<R>(_ body: (ModelContext) throws -> R) throws -> R {
        let fd = open(url.path + ".lock", O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw StoreError.lockUnavailable }
        defer { close(fd) }
        // Fail open instead of blocking a Mail callback on an unavailable lock.
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw StoreError.lockUnavailable }
        defer { flock(fd, LOCK_UN) }
        let container = try ModelContainer(for: StoredValue.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container); context.autosaveEnabled = false
        return try body(context)
    }
}

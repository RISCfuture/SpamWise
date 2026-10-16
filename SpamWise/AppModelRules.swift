import Foundation
import SpamWiseCore

extension AppModel {
  private static let maximumRuleImportBytes = 2_000_000
  func saveRule(
    scope: RuleScope,
    value: String,
    disposition: RuleDisposition,
    completion: @escaping @MainActor (Result<Void, any Error>) -> Void = { _ in }
  ) {
    run { [self] in
      do {
        guard let store else { throw IntegrationError.unavailable }
        try await RuleManagement.save(
          scope: scope,
          value: value,
          disposition: disposition,
          store: store
        )
        status = String(localized: "Rule saved. Pending classifications were invalidated.")
        completion(.success(()))
      } catch {
        completion(.failure(error))
        throw error
      }
    }
  }
  func removeRule(_ id: String) {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      try await RuleManagement.remove(id: id, store: store)
      status = String(localized: "Rule removed.")
    }
  }
  func importRules(_ url: URL) {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let file = try FileHandle(forReadingFrom: url)
      defer { try? file.close() }
      let data = try file.read(upToCount: Self.maximumRuleImportBytes + 1) ?? Data()
      try await RuleManagement.importRules(data, store: store)
      status = String(localized: "Rules imported. Pending classifications were invalidated.")
    }
  }
}

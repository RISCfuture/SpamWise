public import Foundation
import SwiftData

/// The result of an explicit dry-run preview.
public struct MailPreview: Sendable {
  /// Decisions for the previewed messages, reused where content and policy are unchanged.
  public var records: [DecisionRecord]
  /// Entries that could not be read.
  public var unavailableCount: Int
  /// Creates a preview result.
  public init(records: [DecisionRecord], unavailableCount: Int) {
    self.records = records; self.unavailableCount = unavailableCount
  }
}

extension MailSweeper {
  /// Takes elements from each list in turn, so every list contributes before any repeats.
  static func interleaved<Element>(_ lists: [[Element]]) -> [Element] {
    let longest = lists.map(\.count).max() ?? 0
    return (0..<longest).flatMap { index in lists.compactMap { index < $0.count ? $0[index] : nil }
    }
  }

  /**
   Previews at most `total` of the newest Inbox messages across the accounts in scope, taking
   the newest of each account in turn. No mail action is requested.
   */
  public func previewRecent(total: Int, onEvent: @escaping EventHandler = { _ in }) async throws
    -> MailPreview
  {
    var pages: [[MailEnvelope]] = [], unavailable = 0
    for account in try await accountsInScope(currentSettings()) {
      try Task.checkCancellation()
      let page = try await source.recentInboxPage(accountID: account.id, limit: total)
      pages.append(page.messages)
      unavailable += page.unavailableCount
    }
    let batch = Array(Self.interleaved(pages).prefix(max(0, total)))
    return MailPreview(
      records: try await preview(batch, onEvent: onEvent),
      unavailableCount: unavailable
    )
  }

  /// Previews one page of a folder received on or after `since`. No mail action is requested.
  public func previewFolder(
    _ folder: MailFolder,
    since: Date,
    offset: Int,
    limit: Int,
    onEvent: @escaping EventHandler = { _ in }
  ) async throws -> MailPreview {
    let page = try await source.folderPage(folder, offset: offset, limit: limit, since: since)
    return MailPreview(
      records: try await preview(page.messages, onEvent: onEvent),
      unavailableCount: page.unavailableCount
    )
  }

  /**
   Classifies messages as a dry run, in order.

   A message already previewed with identical content under the current policy revision keeps
   that decision, so repeating a preview makes no new provider requests and adds no Activity rows.
   */
  public func preview(_ envelopes: [MailEnvelope], onEvent: @escaping EventHandler = { _ in })
    async throws
    -> [DecisionRecord]
  {
    let reusable = try await StateRepository.reusablePreviews(for: envelopes, in: store)
    let fresh = envelopes.filter { reusable[$0.identity.key] == nil }, total = fresh.count
    let classified = try await pipeline.processBatch(
      fresh,
      adapter: source,
      dryRun: true,
      skipsSettled: false,
      progress: { count in await onEvent(.processed(count: count, total: total)) }
    )
    let byKey = Dictionary(classified.map { ($0.identity.key, $0) }) { first, _ in first }
      .merging(reusable) { new, _ in new }
    var seen: Set<String> = []
    return envelopes.compactMap { envelope in
      let key = envelope.identity.key
      return seen.insert(key).inserted ? byKey[key] : nil
    }
  }
}

extension StateRepository {
  /**
   The latest uncorrected classification of each message that requested no action, by identity
   key, made under the current revision.
   */
  static func reusablePreviews(for envelopes: [MailEnvelope], in store: Store) async throws
    -> [String: DecisionRecord]
  {
    let keys = envelopes.map(\.identity.key)
    guard !keys.isEmpty else { return [:] }
    let revision = try await load(store, StateSlices()).revision
    let dryRun = ActionOutcome.dryRun.rawValue, noAction = ActionOutcome.noAction.rawValue
    let records = try await store.snapshot { context in
      let decoder = JSONDecoder()
      return try context.fetch(
        FetchDescriptor<RecordRow>(
          predicate: #Predicate {
            keys.contains($0.identityKey) && ($0.outcome == dryRun || $0.outcome == noAction)
              && $0.label != nil && $0.correctedLabel == nil
          },
          sortBy: [SortDescriptor(\.date)]
        )
      ).compactMap { try? decoder.decode(DecisionRecord.self, from: $0.payload) }
    }
    return records.filter { $0.revision == revision }.reduce(into: [:]) {
      $0[$1.identity.key] = $1
    }
  }
}

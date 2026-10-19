import Foundation
import Observation
import SpamWiseCore

/// The reviewed corpus: messages the user labeled, imported or corrected.
@MainActor
@Observable
final class CorpusModel {
  /// Importing, relabeling, forgetting and rebuilding reviewed examples.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel

  /// Reviewed labels, newest first.
  var labels: [ReviewedLabel] { shared.state.reviewedLabels.sorted { $0.date > $1.date } }
  /// How many reviewed labels are kept, and how many more imports fit.
  var capacity: ReviewedLabelCapacity { shared.state.reviewedLabelCapacity }

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  /// Reads and parses each file away from the main actor, naming the files that can’t be read.
  @concurrent
  private static func read(_ urls: [URL]) async -> CorpusFiles {
    var files = CorpusFiles()
    for url in urls {
      do {
        let data = try url.readSecurityScoped(maximumBytes: MIMEParser.maximumMessageBytes)
        files.messages.append(try MIMEParser().parse(data))
      } catch {
        files.unreadable.append(url.lastPathComponent)
      }
    }
    return files
  }

  private static func importedStatus(_ count: Int, label: MailLabel, unreadable: [String])
    -> String
  {
    let imported =
      switch label {
        case .inbox: String(localized: "Imported \(count) messages as Good.")
        case .junk: String(localized: "Imported \(count) messages as Junk.")
        case .review: String(localized: "Imported \(count) messages as Review.")
      }
    guard !unreadable.isEmpty else { return imported }
    let names = unreadable.formatted(.list(type: .and))
    return imported + " " + String(localized: "Couldn’t read \(names).")
  }

  /// Correction examples an import of `count` messages would replace to stay within the limit.
  func correctionsDisplaced(importing count: Int) -> Int {
    let capacity = capacity
    let excess = capacity.imported + capacity.corrections + count - capacity.limit
    return min(capacity.corrections, max(0, excess))
  }

  /**
   Imports reviewed `.eml` files as examples labeled `label`, skipping files that can’t be read.

   Nothing is imported when every file is unreadable; no sender rule or mail action is created.
   */
  func importMessages(_ urls: [URL], label: MailLabel) {
    operation.run { [self] in
      let store = try services.requireStore()
      guard urls.count <= CorpusManagement.maximumBatch else {
        throw CorpusError.batchTooLarge(limit: CorpusManagement.maximumBatch)
      }
      let files = await Self.read(urls)
      guard !files.messages.isEmpty else {
        throw CorpusImportError.noReadableFiles(files.unreadable)
      }
      try await CorpusManagement.importMessages(files.messages, label: label, store: store)
      await shared.refresh()
      return Self.importedStatus(files.messages.count, label: label, unreadable: files.unreadable)
    }
  }

  /// Gives the reviewed examples `ids` the label `label`; sender rules and mail are unchanged.
  func relabel(_ ids: Set<String>, as label: MailLabel) {
    operation.run { [self] in
      let store = try services.requireStore()
      for id in ids { try await CorpusManagement.relabel(id: id, label: label, store: store) }
      await shared.refresh()
      return nil
    }
  }

  /// Forgets the reviewed examples `ids` and what was learned from them; sender rules remain.
  func forget(_ ids: Set<String>) {
    operation.run { [self] in
      let store = try services.requireStore()
      for id in ids { try await CorpusManagement.forget(id: id, store: store) }
      await shared.refresh()
      return nil
    }
  }

  /// Rebuilds learning from the current reviewed examples.
  func rebuildLearning() {
    operation.run { [self] in
      try await CorpusManagement.rebuildLearning(store: services.requireStore())
      return String(localized: "Learning rebuilt from your reviewed examples.")
    }
  }

  /// The reviewed labels as exported JSON.
  func exported() throws -> Data {
    try JSONEncoder.pretty.encode(labels)
  }
}

/// The messages read from chosen files, and the names of files that couldn’t be read.
private struct CorpusFiles: Sendable {
  var messages: [ParsedMessage] = []
  var unreadable: [String] = []
}

/// Why chosen files couldn’t be imported as reviewed examples.
enum CorpusImportError: LocalizedError, Equatable {
  /// None of the chosen files is a readable message.
  case noReadableFiles([String])

  var errorDescription: String? { String(localized: "The messages couldn’t be imported.") }
  var failureReason: String? {
    switch self {
      case .noReadableFiles(let names):
        String(
          localized:
            "SpamWise couldn’t read \(names.formatted(.list(type: .and))) as email messages."
        )
    }
  }
  var recoverySuggestion: String? {
    let limit = Int64(MIMEParser.maximumMessageBytes).formatted(.byteCount(style: .file))
    return String(localized: "Choose .eml files saved from Mail, each no larger than \(limit).")
  }
}

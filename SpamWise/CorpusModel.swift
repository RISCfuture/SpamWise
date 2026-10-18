import Foundation
import Observation
import SpamWiseCore

/// The reviewed corpus: messages the user labeled, imported or corrected.
@MainActor @Observable final class CorpusModel {
  private static let maximumImportFiles = 20
  private static let maximumMessageBytes = 2_000_000
  /// Importing, relabeling and forgetting reviewed examples.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel

  /// Reviewed labels, newest first.
  var labels: [ReviewedLabel] { shared.state.reviewedLabels.sorted { $0.date > $1.date } }

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  /// Imports reviewed `.eml` files as examples labeled `label`.
  func importMessages(_ urls: [URL], label: MailLabel) {
    operation.run { [self] in
      let store = try services.requireStore()
      guard urls.count <= Self.maximumImportFiles else {
        throw CorpusError.batchTooLarge(limit: Self.maximumImportFiles)
      }
      var messages: [ParsedMessage] = []
      for url in urls {
        try Task.checkCancellation()
        let data = try SecurityScopedFile.read(url, limit: Self.maximumMessageBytes)
        messages.append(try MIMEParser().parse(data))
      }
      try await CorpusManagement.importMessages(messages, label: label, store: store)
      return String(
        localized: "Reviewed examples imported. No sender rules or mail actions were created."
      )
    }
  }

  func relabel(_ id: String, as label: MailLabel) {
    operation.run { [self] in
      try await CorpusManagement.relabel(id: id, label: label, store: services.requireStore())
      return nil
    }
  }

  func forget(_ id: String) {
    operation.run { [self] in
      try await CorpusManagement.forget(id: id, store: services.requireStore())
      return nil
    }
  }

  /// The reviewed labels as exported JSON.
  func exported() throws -> Data {
    try JSONEncoder.pretty.encode(labels)
  }
}

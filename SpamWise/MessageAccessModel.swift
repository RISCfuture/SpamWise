import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// Opens, previews and exports the message behind a recorded decision.
@MainActor
@Observable
final class MessageAccessModel {
  /// Reading the message from Mail.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices

  init(services: AppServices) { self.services = services }

  /// Shows `record`'s message in Mail.
  func open(_ record: DecisionRecord) {
    operation.run(retryable: true) { [self] in
      try await services.appleMail.open(record.identity)
      return nil
    }
  }

  /// Reads `record`'s message text and hands it to `present`.
  func preview(_ record: DecisionRecord, present: @escaping @MainActor (MessagePreview) -> Void) {
    operation.run(retryable: true) { [self] in
      present(MessagePreview(text: try await ReviewMessage.text(of: envelope(of: record))))
      return nil
    }
  }

  /// Reads `record`'s raw source and hands it to `export`.
  func exportSource(_ record: DecisionRecord, export: @escaping @MainActor (Data) -> Void) {
    operation.run(retryable: true) { [self] in
      export(try await envelope(of: record).raw)
      return nil
    }
  }

  private func envelope(of record: DecisionRecord) async throws -> MailEnvelope {
    guard let envelope = try await services.appleMail.lookup(record.identity) else {
      throw IntegrationError.messageNotFound
    }
    return envelope
  }
}

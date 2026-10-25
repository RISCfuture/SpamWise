import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/**
 Opens, previews and exports the message behind a recorded decision.

 Each request replaces the one before it, so a read the user has moved on from never finishes by
 opening Mail or presenting its result.
 */
@MainActor
@Observable
final class MessageAccessModel {
  /// Reading the message from its mail integration.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices

  init(services: AppServices) { self.services = services }

  /// Whether Mail can show `record`'s message, which it can only for Apple Mail identities.
  func canOpenInMail(_ record: DecisionRecord) -> Bool { record.identity.mailboxValidity == nil }

  /// Shows `record`'s message in Mail; does nothing for a message Mail can't address.
  func open(_ record: DecisionRecord) {
    guard canOpenInMail(record) else { return }
    access { [self] in try await services.appleMail.open(record.identity) }
  }

  /// Reads `record`'s message text and hands it to `present`.
  func preview(_ record: DecisionRecord, present: @escaping @MainActor (MessagePreview) -> Void) {
    access { [self] in
      let text = try await ReviewMessage.text(of: envelope(of: record))
      try Task.checkCancellation()
      present(MessagePreview(text: text))
    }
  }

  /// Reads `record`'s raw source and hands it to `export`.
  func exportSource(_ record: DecisionRecord, export: @escaping @MainActor (Data) -> Void) {
    access { [self] in
      let source = try await envelope(of: record).raw
      try Task.checkCancellation()
      export(source)
    }
  }

  /// Stops the current request, reporting that it was cancelled.
  func cancel() { operation.cancel() }

  /// Abandons the current request without reporting it, as when its message is no longer shown.
  func abandon() { operation.discard() }

  private func access(_ work: @escaping @MainActor () async throws -> Void) {
    operation.discard()
    operation.run(retryable: true) {
      try await work()
      return nil
    }
  }

  private func envelope(of record: DecisionRecord) async throws -> MailEnvelope {
    guard let envelope = try await services.adapter(for: record).lookup(record.identity) else {
      throw IntegrationError.messageNotFound
    }
    return envelope
  }
}

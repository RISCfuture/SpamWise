import Foundation
import SpamWiseCore
import MailIntegration

extension AppModel {
  func correctSelection(_ label: MailLabel) {
    guard let pipeline else { return }
    run { [self] in
      let messages = try await adapter.selectedMessages()
      correctionResults = []
      showCorrections = true
      for message in messages {
        try Task.checkCancellation()
        let subject =
          (try? MIMEParser().parse(message.raw).subject)
          ?? String(localized: "Unclassified message")
        do {
          let record = try await pipeline.correct(envelope: message, label: label, adapter: adapter)
          correctionResults.append(
            .init(id: message.identity.key, subject: subject, record: record)
          )
        } catch {
          correctionResults.append(
            .init(
              id: message.identity.key,
              subject: subject,
              record: nil,
              error: Self.describe(error)
            )
          )
        }
      }
      status = String(localized: "Selected-message corrections finished. Review each mail outcome.")
    }
  }
  func loadJunk(accountID: String, offset: Int) {
    run { [self] in
      let page = try await adapter.accountPage(
        accountID: accountID,
        offset: offset,
        limit: 20,
        role: "junk mailbox"
      )
      junkMessages = page.messages
      junkTotal = page.total
    }
  }
  func restoreReviewedMessage(_ envelope: MailEnvelope) {
    guard let pipeline else { return }
    run { [self] in
      let record = try await pipeline.correct(envelope: envelope, label: .inbox, adapter: adapter)
      status = String(localized: "Correction saved. Mail action: \(record.outcome.localizedTitle).")
      if record.outcome == .applied {
        junkMessages.removeAll { $0.identity.key == envelope.identity.key }
      }
    }
  }
  func openInMail(_ record: DecisionRecord) {
    run { [self] in try await adapter.open(record.identity) }
  }
  func previewMessage(_ record: DecisionRecord) {
    run { [self] in
      guard let envelope = try await adapter.lookup(record.identity) else {
        throw IntegrationError.unavailable
      }
      previewText = try MIMEParser().parse(envelope.raw).text
      showPreview = true
    }
  }
}

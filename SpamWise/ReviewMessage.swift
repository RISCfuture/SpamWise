import Foundation
import SpamWiseCore

/// A message parsed once for display; nil fields mean the message couldn’t be read.
struct ReviewMessage: Identifiable, Sendable {
  let envelope: MailEnvelope
  let subject: String?
  let sender: String?
  let text: String?

  var id: String { envelope.identity.key }
  /// Whether the message could be parsed.
  var isReadable: Bool { text != nil }
  var displaySubject: String {
    guard isReadable else { return String(localized: "Couldn’t read message") }
    guard let subject, !subject.isEmpty else { return String(localized: "No subject") }
    return subject
  }

  /// Parses each envelope away from the main actor.
  @concurrent static func load(_ envelopes: [MailEnvelope]) async -> [Self] {
    envelopes.map { envelope in
      let message = try? MIMEParser().parse(envelope.raw)
      return Self(
        envelope: envelope,
        subject: message?.subject,
        sender: message?.fromAddress,
        text: message?.text
      )
    }
  }

  /// Parses one message’s body text away from the main actor.
  @concurrent static func text(of envelope: MailEnvelope) async throws -> String {
    try MIMEParser().parse(envelope.raw).text
  }
}

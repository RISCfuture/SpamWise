import Foundation
import SpamWiseCore
@testable import MailIntegration

/// Answers Mail handler requests by handler, repeating each handler's last scripted response.
actor StubAppleEvents: AppleEventRunner {
  private var responses: [MailHandler: [ScriptValue]]
  private let delays: [MailHandler: Duration]
  private(set) var requests: [MailRequest] = []
  var moves: [MailMessageLocation] {
    requests.compactMap { request in
      guard case let .apply(command, location) = request, command.destination != nil else {
        return nil
      }
      return location
    }
  }
  var searchedMailboxes: [String?] {
    requests.compactMap { request in
      guard case .find(_, _, _, let mailbox) = request else { return nil }
      return .some(mailbox)
    }
  }
  var appliedCount: Int {
    requests.count { if case .apply = $0 { true } else { false } }
  }

  init(_ responses: [MailHandler: [ScriptValue]], delays: [MailHandler: Duration] = [:]) {
    self.responses = responses; self.delays = delays
  }
  func run(_ request: MailRequest) async throws -> ScriptValue {
    requests.append(request)
    if let delay = delays[request.handler] { try await Task.sleep(for: delay) }
    guard var queue = responses[request.handler], let next = queue.first else {
      throw IntegrationError.scriptFailed
    }
    if queue.count > 1 {
      queue.removeFirst()
      responses[request.handler] = queue
    }
    return next
  }
}

/// Named Mail handler results, shaped exactly as the compiled library returns them.
enum MailReply {
  static let probeSource =
    "From: probe@example.org\r\nSubject: [SpamWise Probe] Test\r\n\r\nDisposable probe."
  static let applied = ScriptValue.boolean(true)

  /// One envelope row; a nil source marks a message the handler could not read.
  static func message(
    account: String = "account",
    mailbox: String = "Inbox",
    localID: Int = 1,
    messageID: String = "id",
    source: String? = probeSource,
    byteCount: Int? = nil
  ) -> ScriptValue {
    .list([
      .string(account), .string(mailbox), .integer(localID), .string(messageID),
      .integer(byteCount ?? source?.utf8.count ?? MailScripts.maximumMessageBytes + 1),
      source.map(ScriptValue.string) ?? .boolean(false)
    ])
  }
  /// Candidates returned by a find or observe request.
  static func found(_ rows: ScriptValue...) -> ScriptValue { .list(rows) }
  /// A page with the mailbox's total and the visited rows.
  static func page(total: Int, _ rows: [ScriptValue]) -> ScriptValue {
    .list([.integer(total), .list(rows)])
  }
  /// The current selection, read in full.
  static func selection(_ rows: ScriptValue...) -> ScriptValue {
    .list([.integer(rows.count), .list(rows)])
  }
  /// The identity a recorded message row produces.
  static func identity(
    mailbox: String = "Inbox",
    localID: Int? = 1,
    messageID: String? = "id",
    source: String = probeSource
  ) -> MessageIdentity {
    .init(
      accountID: "account",
      messageID: messageID,
      localID: localID,
      mailbox: mailbox,
      contentHash: stableHash(Data(source.utf8))
    )
  }
}

import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// Sender and content rules: editing, transfer and testing against the message selected in Mail.
@MainActor @Observable final class RulesModel {
  private static let maximumSenderRuleImportBytes = 2_000_000
  private static let maximumContentRuleImportBytes = 1_000_000
  /// Removing, importing and exporting sender rules.
  let senderRules = TrackedOperation()
  /// Removing, importing and exporting content rules.
  let contentRules = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  private static func outcome(
    of rule: ContentRule,
    evaluation: ContentRuleEvaluation,
    overridden: Bool
  ) -> String {
    if overridden {
      String(localized: "An address or domain rule takes precedence.")
    } else if evaluation.skipped[rule.id] != nil {
      String(
        localized: "This rule could not be evaluated for the selected message and does not match."
      )
    } else if evaluation.decisive?.id == rule.id {
      String(localized: "This rule wins for the selected message.")
    } else {
      String(localized: "This rule does not win for the selected message.")
    }
  }

  /// Saves a sender rule, replacing any rule of the same scope and value.
  func saveSenderRule(scope: RuleScope, value: String, disposition: RuleDisposition) async throws {
    try await RuleManagement.save(
      scope: scope,
      value: value,
      disposition: disposition,
      store: services.requireStore()
    )
  }

  /// Saves a suggested domain rule.
  func saveSuggestedRule(domain: String, disposition: RuleDisposition) {
    senderRules.run { [self] in
      try await saveSenderRule(scope: .domain, value: domain, disposition: disposition)
      return String(localized: "Rule saved. Pending classifications were invalidated.")
    }
  }

  func removeSenderRule(_ id: String) {
    senderRules.run { [self] in
      try await RuleManagement.remove(id: id, store: services.requireStore())
      return nil
    }
  }

  func importSenderRules(from url: URL) {
    senderRules.run { [self] in
      let data = try SecurityScopedFile.read(url, limit: Self.maximumSenderRuleImportBytes)
      try await RuleManagement.importRules(data, store: services.requireStore())
      return String(localized: "Rules imported. Pending classifications were invalidated.")
    }
  }

  /// The saved sender rules in the transfer format.
  func exportedSenderRules() throws -> Data {
    try RuleManagement.exportRules(shared.state.rules)
  }

  func saveContentRule(_ rule: ContentRule) async throws {
    try await ContentRuleManagement.save(rule, store: services.requireStore())
  }

  func removeContentRule(_ id: UUID) {
    contentRules.run { [self] in
      try await ContentRuleManagement.remove(id, store: services.requireStore())
      return nil
    }
  }

  func importContentRules(from url: URL) {
    contentRules.run { [self] in
      let data = try SecurityScopedFile.read(url, limit: Self.maximumContentRuleImportBytes)
      try await ContentRuleManagement.importRules(data, store: services.requireStore())
      return nil
    }
  }

  /// The saved content rules in the transfer format.
  func exportedContentRules() throws -> Data {
    try ContentRuleManagement.exportRules(shared.state.contentRules)
  }

  /// Describes how `draft` would decide the message selected in Mail, alongside the saved rules.
  func test(_ draft: ContentRule) async throws -> String {
    let envelope = try await services.appleMail.selectedMessage()
    let message = try MIMEParser().parse(envelope.raw)
    var candidate = draft
    candidate.updatedAt = .now
    let state = shared.state
    let evaluation = ContentRules.evaluate(
      state.contentRules.filter { $0.id != candidate.id } + [candidate],
      message: message
    )
    let evidence = EvidenceBundle(
      message: message,
      trustedAuthServers: state.settings.mailOptions.trustedAuthServers(
        for: envelope.identity.accountID
      )
    )
    let senderRule = Gates.evaluate(
      address: message.fromAddress,
      domain: evidence.fromDomain,
      rules: state.rules,
      contact: nil,
      history: .init(),
      authentication: evidence.senderAuthentication
    )
    var result = Self.outcome(of: candidate, evaluation: evaluation, overridden: senderRule != nil)
    if evaluation.matching.count > 1 {
      result +=
        " "
        + String(
          localized: "Matching content rules: \(evaluation.matching.count). Newest wins."
        )
    }
    return result
  }

}

/// Reads user-chosen files through their security scope.
enum SecurityScopedFile {
  /// Reads at most `limit` + 1 bytes of `url`, so callers can reject larger files.
  static func read(_ url: URL, limit: Int) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    return try file.read(upToCount: limit + 1) ?? Data()
  }
}

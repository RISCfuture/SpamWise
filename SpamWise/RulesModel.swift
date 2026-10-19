import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// Sender and content rules: editing, transfer and testing against the message selected in Mail.
@MainActor
@Observable
final class RulesModel {
  /// Removing, importing and exporting sender rules.
  let senderRules = TrackedOperation()
  /// Removing, importing, exporting and turning content rules on or off.
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
      String(localized: "A sender rule decides this message first, so this rule isn’t used.")
    } else if evaluation.skipped[rule.id] != nil {
      String(localized: "This rule took too long to check, so it doesn’t match this message.")
    } else if evaluation.decisive?.id == rule.id {
      String(localized: "This rule decides the selected message.")
    } else {
      String(localized: "This rule doesn’t decide the selected message.")
    }
  }

  /// Parses `envelope` away from the main actor.
  @concurrent
  private static func parse(_ envelope: MailEnvelope) async throws -> ParsedMessage {
    try MIMEParser().parse(envelope.raw)
  }

  /// Saves a sender rule, replacing any rule of the same scope and value.
  func saveSenderRule(scope: RuleScope, value: String, disposition: RuleDisposition) async throws {
    try await RuleManagement.save(
      scope: scope,
      value: value,
      disposition: disposition,
      store: services.requireStore()
    )
    await shared.refresh()
  }

  /// Saves a suggested domain rule.
  func saveSuggestedRule(domain: String, disposition: RuleDisposition) {
    senderRules.run { [self] in
      try await saveSenderRule(scope: .domain, value: domain, disposition: disposition)
      return String(localized: "Rule saved. Pending classifications were invalidated.")
    }
  }

  /// Removes the sender rules `ids`; mail already filtered stays where it is.
  func removeSenderRules(_ ids: Set<String>) {
    senderRules.run { [self] in
      let store = try services.requireStore()
      for id in ids { try await RuleManagement.remove(id: id, store: store) }
      await shared.refresh()
      return nil
    }
  }

  func importSenderRules(from url: URL) {
    senderRules.run { [self] in
      let data = try url.readSecurityScoped(maximumBytes: RuleManagement.maximumArchiveBytes)
      try await RuleManagement.importRules(data, store: services.requireStore())
      await shared.refresh()
      return String(localized: "Rules imported. Pending classifications were invalidated.")
    }
  }

  /// The saved sender rules in the transfer format.
  func exportedSenderRules() throws -> Data {
    try RuleManagement.exportRules(shared.state.rules)
  }

  func saveContentRule(_ rule: ContentRule) async throws {
    try await ContentRuleManagement.save(rule, store: services.requireStore())
    await shared.refresh()
  }

  /// Turns content rule `id` on or off, showing the change before it is saved.
  func setContentRule(_ id: UUID, enabled: Bool) {
    showContentRule(id, enabled: enabled)
    contentRules.run { [self] in
      do {
        try await ContentRuleManagement.setEnabled(id, enabled, store: services.requireStore())
      } catch {
        showContentRule(id, enabled: !enabled)
        throw error
      }
      await shared.refresh()
      return nil
    }
  }

  private func showContentRule(_ id: UUID, enabled: Bool) {
    guard let index = shared.state.contentRules.firstIndex(where: { $0.id == id }) else { return }
    shared.state.contentRules[index].enabled = enabled
  }

  /// Removes the content rules `ids`; mail already filtered stays where it is.
  func removeContentRules(_ ids: Set<UUID>) {
    contentRules.run { [self] in
      let store = try services.requireStore()
      for id in ids { try await ContentRuleManagement.remove(id, store: store) }
      await shared.refresh()
      return nil
    }
  }

  func importContentRules(from url: URL) {
    contentRules.run { [self] in
      let data = try url.readSecurityScoped(
        maximumBytes: ContentRuleManagement.maximumArchiveBytes
      )
      try await ContentRuleManagement.importRules(data, store: services.requireStore())
      await shared.refresh()
      return String(localized: "Content rules imported. Pending classifications were invalidated.")
    }
  }

  /// The saved content rules in the transfer format.
  func exportedContentRules() throws -> Data {
    try ContentRuleManagement.exportRules(shared.state.contentRules)
  }

  /// Describes how `draft` would decide the message selected in Mail, alongside the saved rules.
  func test(_ draft: ContentRule) async throws -> String {
    let envelope = try await services.appleMail.selectedMessage()
    let message = try await Self.parse(envelope)
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
          localized: "\(evaluation.matching.count) content rules match; the newest one decides."
        )
    }
    return result
  }
}

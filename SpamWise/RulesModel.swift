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
  /// A validated sender-rule archive, waiting for the user to confirm what it changes.
  private(set) var pendingImport: RuleImportPreview?
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  nonisolated private static func outcome(
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

  /// Reads and validates the sender-rule archive at `url` against the saved rules.
  @concurrent
  private static func previewImport(from url: URL, store: Store) async throws
    -> RuleImportPreview
  {
    let data = try url.readSecurityScoped(maximumBytes: RuleManagement.maximumArchiveBytes)
    let saved = try await StateRepository.load(store, StateSlices([.rules])).rules
    return try RuleManagement.previewImport(data, against: saved)
  }

  /// Reads the content-rule archive at `url` and merges it.
  @concurrent
  private static func importContentRules(from url: URL, store: Store) async throws {
    let data = try url.readSecurityScoped(maximumBytes: ContentRuleManagement.maximumArchiveBytes)
    try await ContentRuleManagement.importRules(data, store: store)
  }

  /**
   Describes how `candidate` would decide the message in `envelope`, alongside the saved rules.

   - Parameters:
     - contentRules: The saved content rules; any with the candidate's identity is replaced.
     - senderRules: The saved sender rules, which decide before any content rule.
     - trustedAuthServers: The receiving servers trusted for the message's account.
   */
  @concurrent
  private static func describe(
    _ candidate: ContentRule,
    in envelope: MailEnvelope,
    contentRules: [ContentRule],
    senderRules: [SenderRule],
    trustedAuthServers: Set<String>
  ) async throws -> String {
    let message = try MIMEParser().parse(envelope.raw)
    let evaluation = ContentRules.evaluate(
      contentRules.filter { $0.id != candidate.id } + [candidate],
      message: message
    )
    let evidence = EvidenceBundle(message: message, trustedAuthServers: trustedAuthServers)
    let senderRule = Gates.evaluate(
      address: message.fromAddress,
      domain: evidence.fromDomain,
      rules: senderRules,
      contact: nil,
      history: .init(),
      authentication: evidence.senderAuthentication
    )
    var result = outcome(of: candidate, evaluation: evaluation, overridden: senderRule != nil)
    if evaluation.matching.count > 1 {
      result +=
        " "
        + String(
          localized: "\(evaluation.matching.count) content rules match; the newest one decides."
        )
    }
    return result
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

  /// Validates the sender-rule archive at `url` and holds what it changes for confirmation.
  func previewSenderRuleImport(from url: URL) {
    senderRules.run { [self] in
      pendingImport = try await Self.previewImport(from: url, store: services.requireStore())
      return nil
    }
  }

  /// Imports the previewed archive the user confirmed.
  func importSenderRules(_ preview: RuleImportPreview) {
    pendingImport = nil
    senderRules.run { [self] in
      try await RuleManagement.commitImport(preview, store: services.requireStore())
      await shared.refresh()
      return String(localized: "Rules imported. Pending classifications were invalidated.")
    }
  }

  /// Discards the archive waiting for confirmation.
  func cancelSenderRuleImport() { pendingImport = nil }

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
      try await Self.importContentRules(from: url, store: services.requireStore())
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
    var candidate = draft
    candidate.updatedAt = .now
    let state = shared.state
    return try await Self.describe(
      candidate,
      in: envelope,
      contentRules: state.contentRules,
      senderRules: state.rules,
      trustedAuthServers: state.settings.mailOptions.trustedAuthServers(
        for: envelope.identity.accountID
      )
    )
  }
}

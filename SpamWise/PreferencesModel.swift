import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/**
 What the user doesn't want in their Inbox: a choice for each kind of graymail, and examples
 learned from the mail already in their Junk folders.

 Scanning Junk only reads mail; importing saves reviewed examples without sender rules, and
 neither moves a message.
 */
@MainActor
@Observable
final class PreferencesModel {
  private static let pageSize = 50
  /// The most Junk messages read from each account.
  static let maximumScannedPerAccount = 400
  /// Reading the Junk folders of the accounts in scope.
  let scan = TrackedOperation()
  /// Importing the chosen senders' examples.
  let importing = TrackedOperation()
  /// Senders found in Junk, most frequent first; empty until a scan finishes.
  private(set) var junkSenders: [JunkFolderSender] = []
  /// How many Junk messages the latest scan read.
  private(set) var scannedCount = 0
  /// Whether the latest scan's examples were imported.
  private(set) var hasImported = false
  /// Senders the user left out of the import.
  var excludedSenders: Set<String> = []
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private let settings: SettingsModel
  @ObservationIgnored private let mail: MailConnectionModel

  /// Whether Junk folders can be scanned with the selected transport.
  var canScanJunk: Bool { shared.settings.advancedOptions.transport != .imap }
  /// The senders whose examples an import saves.
  var includedSenders: [JunkFolderSender] {
    junkSenders.filter { !excludedSenders.contains($0.id) }
  }

  /// Category preferences the user's corrections consistently ask to change.
  var categorySuggestions: [CategorySuggestion] {
    PolicyDistiller.categorySuggestions(
      from: shared.state.corrections,
      preferences: shared.settings.categoryPreferences
    )
  }

  init(
    services: AppServices,
    shared: SharedStateModel,
    settings: SettingsModel,
    mail: MailConnectionModel
  ) {
    self.services = services; self.shared = shared; self.settings = settings; self.mail = mail
  }

  /// Parses a page of Junk mail off the main actor, skipping messages that can't be parsed.
  @concurrent
  private static func parse(_ envelopes: [MailEnvelope]) async -> [ParsedMessage] {
    envelopes.compactMap { try? MIMEParser().parse($0.raw) }
  }

  /// The user's preference for a graymail `category`.
  func preference(for category: MailCategory) -> GraymailPreference {
    shared.settings.categoryPreferences[category] ?? .keep
  }

  /// Saves `preference` for `category`; pending classifications use it from then on.
  func setPreference(_ preference: GraymailPreference, for category: MailCategory) {
    settings.editSettings { $0.categoryPreferences[category] = preference }
  }

  /// Reads the newest Junk mail of each account in scope and groups it by sender.
  func scanJunk() {
    scan.run(retryable: true) { [self] in
      hasImported = false
      let messages = try await junkMessages()
      let state = try await StateRepository.load(
        services.requireStore(),
        StateSlices([.contacts], histories: .all)
      )
      junkSenders = JunkFolderBootstrap.senders(in: messages, state: state)
      scannedCount = messages.count
      excludedSenders = Set(junkSenders.filter(\.possiblyWanted).map(\.id))
      guard messages.isEmpty else { return nil }
      return String(
        localized:
          "No Junk mail was found to learn from. Check the Mail connection, then scan again."
      )
    }
  }

  /// Saves one example from each included sender as reviewed Junk; no rules are created.
  func importJunkExamples() {
    let senders = includedSenders
    importing.run { [self] in
      try await JunkFolderBootstrap.importExamples(from: senders, store: services.requireStore())
      hasImported = true
      return String(localized: "Saved \(senders.count) examples of mail you don’t want.")
    }
  }

  private func junkMessages() async throws -> [ParsedMessage] {
    let scope = shared.settings.mailOptions.accountIDs
    var messages: [ParsedMessage] = []
    for account in mail.accounts where scope?.contains(account.id) ?? true {
      var offset = 0
      while offset < Self.maximumScannedPerAccount {
        try Task.checkCancellation()
        let page = try await services.appleMail.accountPage(
          accountID: account.id,
          offset: offset,
          limit: Self.pageSize,
          role: .junk
        )
        messages += await Self.parse(page.messages)
        offset += page.visitedCount
        guard page.visitedCount > 0, offset < page.total else { break }
      }
    }
    return messages
  }
}

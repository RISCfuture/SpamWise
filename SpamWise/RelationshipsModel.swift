import Foundation
import Observation
import SpamWiseCore

/// Relationship evidence: Contacts, imported correspondence history and trust exclusions.
@MainActor
@Observable
final class RelationshipsModel {
  private static let contactsRefreshInterval: Duration = .seconds(3600)
  /// Connecting or refreshing Contacts.
  let contacts = TrackedOperation()
  /// Importing bounded Inbox and Sent history.
  let historyImport = TrackedOperation()
  /// Saving trust exclusions.
  let exclusions = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private var lastContactsRefresh: ContinuousClock.Instant?

  /// Exclusions typed but not yet saved, kept until they save so switching away never drops them.
  private(set) var exclusionsEdit: String?

  var contactsNeedRefresh: Bool {
    lastContactsRefresh.map { .now - $0 >= Self.contactsRefreshInterval } ?? true
  }
  /// The addresses excluded from automatic trust, one per line: the unsaved edit, or else the
  /// saved list. Setting it records an edit, which ``commitTrustExclusions()`` saves.
  var exclusionsText: String {
    get { exclusionsEdit ?? savedExclusionsText }
    set { exclusionsEdit = newValue == savedExclusionsText ? nil : newValue }
  }
  private var savedExclusionsText: String {
    shared.settings.mailOptions.trustExclusions.sorted().joined(separator: "\n")
  }

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  /// Asks for Contacts access, then caches its addresses as relationship evidence.
  func connectContacts() {
    contacts.run { [self] in try await refreshContacts(requestAccess: true) }
  }

  /// Refreshes cached Contacts when the hourly refresh is due and no other refresh is in progress.
  func refreshContactsIfDue() async {
    guard !services.uiTesting, contactsNeedRefresh, !contacts.isBusy else { return }
    await contacts.run { [self] in try await refreshContacts() }.value
  }

  /// Imports the newest bounded Inbox and Sent history of the selected transport.
  func importHistory() {
    historyImport.run { [self] in
      let source = try await services.sweepSource(for: shared.settings.advancedOptions.transport)
      try await HistoryMaintenance(source: source, store: services.requireStore()).importRecent()
      return String(localized: "Imported recent Inbox and Sent mail.")
    }
  }

  /// Saves the edited exclusions; an edit that can't be saved stays, with the reason.
  @discardableResult
  func commitTrustExclusions() -> Task<Void, Never> {
    guard let edit = exclusionsEdit else { return Task {} }
    return exclusions.run { [self] in
      try await TrustExclusions.save(edit, store: services.requireStore())
      await shared.refresh()
      if exclusionsEdit == edit { exclusionsEdit = nil }
      return nil
    }
  }

  private func refreshContacts(requestAccess: Bool = false) async throws -> String {
    lastContactsRefresh = .now
    do {
      let addresses = try await ContactsLookup().addresses(requestAccess: requestAccess)
      if let store = services.store {
        try await StateRepository.update(store, loading: StateSlices([.contacts])) {
          $0.contactAddresses = addresses; $0.contactsUpdatedAt = .now
        }
      }
      return addresses == nil
        ? String(
          localized:
            "SpamWise can’t read Contacts. Allow access in System Settings › Privacy & Security › Contacts."
        )
        : String(localized: "Contacts connected.")
    } catch {
      throw ContactsRefreshError.failed
    }
  }
}

/// Contacts could not be read.
enum ContactsRefreshError: LocalizedError {
  case failed

  var errorDescription: String? { String(localized: "Couldn’t refresh Contacts.") }
  var failureReason: String? {
    String(
      localized:
        "SpamWise couldn’t read your contacts, so contacts it read earlier soon stop counting."
    )
  }
  var recoverySuggestion: String? {
    String(
      localized:
        "Check that SpamWise is allowed in System Settings → Privacy & Security → Contacts, then try again."
    )
  }
}

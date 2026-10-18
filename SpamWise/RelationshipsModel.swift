import Foundation
import Observation
import SpamWiseCore

/// Relationship evidence: Contacts, imported correspondence history and trust exclusions.
@MainActor @Observable final class RelationshipsModel {
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

  var contactsNeedRefresh: Bool {
    lastContactsRefresh.map { .now - $0 >= Self.contactsRefreshInterval } ?? true
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
      return String(
        localized: "Imported bounded Inbox and Sent history; remaining history is unknown."
      )
    }
  }

  /// Saves `addresses`, one per line, as excluded from automatic trust.
  func saveTrustExclusions(_ addresses: String) {
    exclusions.run { [self] in
      try await TrustExclusions.save(addresses, store: services.requireStore())
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
        ? String(localized: "Contacts unavailable — relationship remains unknown")
        : String(localized: "Contacts refreshed")
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

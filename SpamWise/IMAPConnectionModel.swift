import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// The draft and actions behind the app's separate IMAP connection.
@MainActor
@Observable
final class IMAPConnectionModel {
  /// The implicit-TLS IMAP port a new draft starts with.
  static let defaultPort = String(IMAPConfiguration.defaultPort)
  var host = ""
  var username = ""
  var port = IMAPConnectionModel.defaultPort
  var credential = ""
  var accountID = IMAPConnectionModel.newAccountID()
  /// Whether a connection is saved, as of the latest load, save or removal.
  private(set) var hasSavedConnection = false
  /// Whether the saved connection, if any, has been read into the draft.
  private(set) var hasLoaded = false
  /// Loading, saving and checking the connection.
  let operation = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  /// The server and username the saved credential belongs to.
  private var savedEndpoint: Endpoint?

  /// The connection's account as people recognize it, such as “name@example.com on imap.example.com”.
  var accountName: String { String(localized: "\(username) on \(host)") }
  /// Whether saving can leave the password blank: the draft still signs in to the saved server, as
  /// the saved username.
  var canKeepSavedCredential: Bool { savedEndpoint.map { $0 == draftEndpoint } ?? false }
  /// Whether the saved connection has been read and nothing else is running.
  var canSave: Bool { hasLoaded && !operation.isBusy }
  /// Whether a username is entered that isn't an email address.
  var usernameIsNotAddress: Bool {
    !trimmedUsername.isEmpty && MIMEParser.address(trimmedUsername) == nil
  }

  private var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var draftEndpoint: Endpoint {
    Endpoint(host: trimmedHost, username: trimmedUsername)
  }

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  private static func newAccountID() -> String {
    MailTransport.imapAccountPrefix + UUID().uuidString
  }

  @concurrent
  private static func deleteCredential(service: String) async throws {
    try APIKeychain(service: service).delete()
  }

  /// Saves `secret` for `connection`, or, when it is blank, confirms a credential is saved.
  @concurrent
  private static func saveCredential(_ secret: String, for connection: IMAPAppConnection)
    async throws
  {
    let keychain = APIKeychain(service: connection.credentialService)
    if secret.isEmpty {
      guard try keychain.exists() else { throw KeychainError.missing }
    } else {
      try keychain.save(secret, preserveWhitespace: true)
    }
  }

  /// Records `username` as the user's own address, when it is an email address.
  private static func recordOwnAddress(of username: String, in store: Store) async throws {
    guard let address = MIMEParser.address(username) else { return }
    try await StateRepository.update(store, loading: StateSlices([.contacts])) {
      $0.ownAddresses = [address]
    }
  }

  /**
   Fills the draft from the saved connection once, keeping later edits to the draft.

   Until the saved connection has been read, the draft can't be saved, so a failed read can't
   replace the saved connection with a new account.
   */
  func loadIfNeeded() {
    guard !hasLoaded else { return }
    operation.run(retryable: true) { [self] in
      guard !hasLoaded else { return nil }
      let saved = try await IMAPAppConnection.saved(in: services.requireStore())
      hasLoaded = true
      guard let saved else { return nil }
      host = saved.account.host; username = saved.account.username
      port = String(saved.account.port); accountID = saved.account.id
      hasSavedConnection = true
      savedEndpoint = Endpoint(saved)
      return nil
    }
  }

  /// Saves the draft and its credential, selecting IMAP with dry run on.
  func save() {
    guard let port = UInt16(port), port > 0 else {
      operation.run { throw IMAPSetupError.invalidPort }
      return
    }
    guard !credential.isEmpty || canKeepSavedCredential else {
      operation.run { throw IMAPSetupError.credentialRequired }
      return
    }
    let secret = credential
    credential = ""
    operation.run { [self] in
      let connection = connection(port: port)
      try await save(connection, secret: secret, store: services.requireStore())
      hasSavedConnection = true
      savedEndpoint = Endpoint(connection)
      await shared.refresh()
      return String(
        localized:
          """
          Connection saved with dry run on. Check the connection so SpamWise can find its Junk \
          mailbox.
          """
      )
    }
  }

  /**
   Checks the saved connection read-only and records whether its mailboxes are validated.

   A username that is an email address becomes the user's own address.
   */
  func check() {
    operation.run(retryable: true) { [self] in
      let store = try services.requireStore()
      guard let connection = try await IMAPAppConnection.saved(in: store) else {
        throw IMAPSetupError.noSavedConnection
      }
      let result = try await services.imapAdapter().validateReadOnly()
      try await Self.recordOwnAddress(of: connection.account.username, in: store)
      let validated = try await IMAPAccountValidation.record(
        result,
        for: connection.account,
        store: store
      )
      await shared.refresh()
      return validated
        ? String(localized: "Connected. SpamWise found the Inbox and Junk mailboxes.")
        : String(
          localized:
            """
            Connected, but SpamWise can’t move mail on this server. It needs IMAP MOVE support and \
            exactly one Junk mailbox.
            """
        )
    }
  }

  /**
   Forgets the saved connection: removes its password from Keychain and its mailbox check, then
   returns to Apple Mail with dry run on. Mail on the server is unchanged.
   */
  func forget() {
    operation.run { [self] in
      let store = try services.requireStore()
      if let saved = try await IMAPAppConnection.saved(in: store) {
        try await Self.deleteCredential(service: saved.credentialService)
        try await IMAPAccountValidation.revoke(saved.account, scope: .app, store: store)
      }
      try await store.update(
        IMAPAppConnection.storeKey,
        default: Optional<IMAPAppConnection>.none
      ) { $0 = nil }
      try await StateRepository.editSettings(store) { settings in
        var advanced = settings.advancedOptions
        advanced.transport = .appleMail
        settings.advancedOptions = advanced
        settings.dryRun = true
      }
      clearDraft()
      await shared.refresh()
      return String(
        localized:
          "IMAP connection forgotten and its password removed. SpamWise now uses Apple Mail."
      )
    }
  }

  private func clearDraft() {
    host = ""; username = ""; port = Self.defaultPort; credential = ""
    accountID = Self.newAccountID(); hasSavedConnection = false; savedEndpoint = nil
  }

  private func connection(port: UInt16) -> IMAPAppConnection {
    IMAPAppConnection(
      account: .init(id: accountID, host: trimmedHost, port: port, username: trimmedUsername)
    )
  }

  private func save(_ connection: IMAPAppConnection, secret: String, store: Store) async throws {
    try connection.account.validate()
    try await Self.saveCredential(secret, for: connection)
    let replaced = try await store.update(
      IMAPAppConnection.storeKey,
      default: Optional<IMAPAppConnection>.none
    ) { saved in
      defer { saved = connection }
      return saved
    }
    if let replaced, replaced.credentialService != connection.credentialService {
      try? await Self.deleteCredential(service: replaced.credentialService)
    }
    try await StateRepository.editSettings(store) { settings in
      var advanced = settings.advancedOptions
      advanced.transport = .imap
      settings.advancedOptions = advanced
      settings.dryRun = true
    }
  }
}

/// Where a saved IMAP credential signs in; a credential is reused only for the same endpoint.
private struct Endpoint: Equatable {
  /// The server, compared without regard to case.
  let host: String
  let username: String

  init(host: String, username: String) {
    self.host = host.lowercased()
    self.username = username
  }

  init(_ connection: IMAPAppConnection) {
    self.init(host: connection.account.host, username: connection.account.username)
  }
}

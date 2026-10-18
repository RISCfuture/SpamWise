public import Foundation

/// Receiving-server authserv-ids observed at the top of one account's received mail.
public struct AuthServerObservations: Codable, Sendable, Equatable {
  private static let minimumMessages = 10
  private static let consistentShare = 0.9
  /// Account-scoped identity keys of the sampled messages, so each message counts once.
  public private(set) var messageKeys: [String] = []
  /// Number of sampled messages whose leading Authentication-Results headers named each server.
  public private(set) var serverCounts: [String: Int] = [:]
  /// Whether the bounded sample is full, so no further message is recorded.
  public var isComplete: Bool {
    messageKeys.count >= RetentionLimits.authServerObservationMessages
  }
  /**
   What the sample shows.

   A server is detected when the leading headers of at least 90% of at least ten sampled messages
   name it. A server that a sender names below the provider's own headers appears only in that
   sender's messages, so it does not reach that share.
   */
  public var detection: AuthServerDetection {
    let count = messageKeys.count
    guard count >= Self.minimumMessages else {
      return .collecting(observed: count, required: Self.minimumMessages)
    }
    let consistent = serverCounts.filter {
      Double($0.value) >= Self.consistentShare * Double(count)
    }.keys
    return consistent.isEmpty ? .inconsistent : .detected(Set(consistent))
  }
  /// Creates an empty sample.
  public init() {}
  /// Records one message's leading servers, once per message, until the sample is full.
  mutating func observe(_ servers: [String], identityKey: String) {
    guard !servers.isEmpty, !isComplete, !messageKeys.contains(identityKey) else { return }
    messageKeys.append(identityKey)
    for server in Set(servers)
    where serverCounts[server] != nil
      || serverCounts.count < RetentionLimits.authServerObservationServers
    {
      serverCounts[server, default: 0] += 1
    }
  }
}

/// Progress toward detecting an account's receiving-server authserv-ids.
public enum AuthServerDetection: Sendable, Equatable {
  /// Too few messages with Authentication-Results headers have been sampled.
  case collecting(observed: Int, required: Int)
  /// These authserv-ids led the headers of nearly every sampled message; trust needs confirmation.
  case detected(Set<String>)
  /// No authserv-id led the headers consistently, so the account needs one set explicitly.
  case inconsistent
}

/// One account's trusted receiving servers and detection progress.
public struct AccountAuthentication: Sendable, Equatable {
  /// Confirmed or user-set authserv-ids; empty means no authentication result is trusted.
  public let trustedServers: Set<String>
  /// Detection from the account's sampled mail, independent of the trusted set.
  public let detection: AuthServerDetection
}

/// An error category for trusted receiving-server configuration.
public protocol AuthenticationTrustFailure: Error {}

/// Why trusted receiving servers could not be saved.
public enum AuthenticationTrustError: AuthenticationTrustFailure, Sendable, LocalizedError {
  /// A value is not a single authserv-id.
  case invalidServer
  /// The list exceeds the number of servers one account can trust.
  case tooManyServers
  /// The account's mail has not shown a consistent receiving server to confirm.
  case notDetected
  /// A user-visible explanation of the rejected change.
  public var errorDescription: String? {
    String(localized: "The trusted mail servers could not be updated.", bundle: .module)
  }
  /// The validation constraint that rejected the change.
  public var failureReason: String? {
    switch self {
      case .invalidServer:
        String(
          localized: "Enter each server as a single name, such as mx.google.com.",
          bundle: .module
        )
      case .tooManyServers:
        String(localized: "An account can trust at most eight servers.", bundle: .module)
      case .notDetected:
        String(
          localized: "SpamWise hasn’t seen enough of this account’s mail to detect its servers.",
          bundle: .module
        )
    }
  }
}

/**
 Per-account trust in the receiving servers that add Authentication-Results headers.

 Until an account trusts a server, no authentication result in its mail is trusted, so Allow
 rules, Contacts and correspondence history reach the classifier as evidence instead of deciding
 messages. SpamWise samples the leading headers of each such account's mail to propose servers,
 which take effect only once confirmed or set explicitly.
 */
public enum AuthenticationTrust {
  private static let maximumServers = 8
  /// Trusted servers and detection progress by account identifier, for every account with either.
  public static func accounts(_ store: Store) async throws -> [String: AccountAuthentication] {
    let state = try await StateRepository.load(store, StateSlices([.authentication]))
    let trusted = state.settings.mailOptions.trustedAuthServers
    let observed = state.authServerObservations
    return Set(trusted.keys).union(observed.keys).reduce(into: [:]) { accounts, accountID in
      accounts[accountID] = AccountAuthentication(
        trustedServers: trusted[accountID] ?? [],
        detection: (observed[accountID] ?? .init()).detection
      )
    }
  }
  /// The receiving servers each account trusts, by account identifier.
  public static func trustedServers(_ store: Store) async throws -> [String: Set<String>] {
    try await StateRepository.load(store, StateSlices([.authentication]))
      .settings.mailOptions.trustedAuthServers
  }
  /// Trusts the servers detected in the account's mail, superseding pending classifications.
  public static func confirmDetected(accountID: String, store: Store) async throws {
    let observations = try await StateRepository.load(store, StateSlices([.authentication]))
      .authServerObservations[accountID]
    guard case .detected(let servers) = observations?.detection else {
      throw AuthenticationTrustError.notDetected
    }
    try await save(Array(servers), accountID: accountID, store: store)
  }
  /// Replaces the account's trusted servers with normalized `servers`; an empty list trusts none.
  public static func save(_ servers: [String], accountID: String, store: Store) async throws {
    let normalized = try Set(
      servers.map {
        guard let server = AuthenticationHeaders.normalizedServer($0) else {
          throw AuthenticationTrustError.invalidServer
        }
        return server
      }
    )
    guard normalized.count <= maximumServers else { throw AuthenticationTrustError.tooManyServers }
    try await StateRepository.editSettings(store) {
      $0.mailOptions.trustedAuthServers[accountID] = normalized.isEmpty ? nil : normalized
    }
  }
}

extension MailPreferences {
  /// The trusted receiving servers of `accountID`; empty for an unknown or unconfigured account.
  public func trustedAuthServers(for accountID: String?) -> Set<String> {
    accountID.flatMap { trustedAuthServers[$0] } ?? []
  }
}

extension Pipeline {
  /// Samples a message's leading receiving servers while its account trusts none; best effort.
  func observeReceivingServers(
    _ message: ParsedMessage,
    identity: MessageIdentity,
    settings: Settings
  ) async {
    guard let accountID = identity.accountID,
      settings.mailOptions.trustedAuthServers(for: accountID).isEmpty
    else { return }
    let servers = AuthenticationHeaders.leadingServers(
      message.headers["authentication-results"] ?? []
    )
    guard !servers.isEmpty else { return }
    try? await StateRepository.update(store, loading: StateSlices([.authentication])) { state in
      state.authServerObservations[accountID, default: .init()]
        .observe(servers, identityKey: identity.key)
    }
  }
}

/// A reason to ask the user before saving a correction.
public enum CorrectionWarning: Sendable, Equatable {
  /**
   A Junk correction would block a sender that trusted authentication did not confirm.

   The From address may be forged, so the Block rule can also send the genuine sender's mail to
   Junk.
   */
  case unauthenticatedSender

  /// The warning for correcting a message with `evidence` to `label`; nil when none applies.
  public static func check(label: MailLabel, evidence: EvidenceBundle?) -> CorrectionWarning? {
    label == .junk && evidence?.senderAuthentication != .alignedPass
      ? .unauthenticatedSender : nil
  }
}

extension DecisionRecord {
  /// The warning to show before correcting this record to `label`; nil when none applies.
  public func correctionWarning(for label: MailLabel) -> CorrectionWarning? {
    .check(label: label, evidence: evidence)
  }
}

extension Pipeline {
  /// The warning to show before correcting a selected message to `label`; nil when none applies.
  public func correctionWarning(envelope: MailEnvelope, label: MailLabel) async throws
    -> CorrectionWarning?
  {
    let settings = try await StateRepository.load(store, StateSlices()).settings
    return .check(
      label: label,
      evidence: EvidenceBundle(
        message: try MIMEParser().parse(envelope.raw),
        trustedAuthServers: settings.mailOptions.trustedAuthServers(
          for: envelope.identity.accountID
        )
      )
    )
  }
}

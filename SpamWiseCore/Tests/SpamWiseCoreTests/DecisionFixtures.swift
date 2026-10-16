import Foundation
import Synchronization
import SpamWiseCore

actor RecordingAdapter: MailClientAdapter {
  var actions: [MailAction] = []
  var failure: (any Error)?
  var unsupported: Set<MailAction> = []
  var updatedIdentity: MessageIdentity?
  var lookups = 0
  var message: MailEnvelope?
  var readRequests = 0
  /// Read-status requests made as a step of a user's correction, also counted in `readRequests`.
  var correctionReadRequests = 0
  var failRead = true
  /// Whether each performed action found its decision and claim already persisted in the observed store.
  var persistedBeforeAction: [Bool] = []
  private var observedStore: Store?
  private var afterAction: (@Sendable () throws -> Void)?
  private var supportCheck: (@Sendable () -> Void)?

  private static func isClaimed(_ identity: MessageIdentity, in store: Store) async throws -> Bool {
    let state = try await StateRepository.load(
      store,
      StateSlices(records: .all, claims: .only([identity.key]))
    )
    guard let id = state.claimedActions[identity.key] else { return false }
    return state.records.contains { $0.id == id && $0.outcome == .requested }
  }
  func markReadInJunk(_: MessageIdentity) throws -> ActionReceipt {
    readRequests += 1
    if failRead { throw IntegrationError.staleMessage }
    return .init(confirmed: true)
  }
  func markCorrectionReadInJunk(_ identity: MessageIdentity) throws -> ActionReceipt {
    correctionReadRequests += 1
    return try markReadInJunk(identity)
  }
  func allowMarkRead() { failRead = false }
  func lookup(_: MessageIdentity) throws -> MailEnvelope? {
    lookups += 1
    return message
  }
  func retain(_ envelope: MailEnvelope) { message = envelope }
  func recentMessages(limit _: Int) throws -> [MailEnvelope] { [] }
  func perform(_ action: MailAction, for identity: MessageIdentity) async throws -> ActionReceipt {
    if let failure { throw failure }
    if let observedStore {
      persistedBeforeAction.append(try await Self.isClaimed(identity, in: observedStore))
    }
    actions.append(action)
    try afterAction?()
    return .init(confirmed: true, updatedIdentity: updatedIdentity)
  }
  /// Records, at each action, whether `store` already holds its claimed, requested decision.
  func observe(_ store: Store) { observedStore = store }
  /// Runs `body` after each performed action, as when storage fails once Mail has acted.
  func afterEachAction(_ body: @escaping @Sendable () throws -> Void) { afterAction = body }
  func allow() { failure = nil }
  func deny(with error: any Error = IntegrationError.permissionDenied) { failure = error }
  func refuse(_ action: MailAction) { unsupported.insert(action) }
  func supports(_ action: MailAction) -> Bool {
    supportCheck?()
    return !unsupported.contains(action)
  }
  /// Runs `body` whenever dispatch asks whether an action is supported, before it claims the action.
  func beforeEachSupportCheck(_ body: @escaping @Sendable () -> Void) { supportCheck = body }
  func moveIdentity(to identity: MessageIdentity) { updatedIdentity = identity }
}
func testStore() throws -> Store {
  try Store(
    url: FileManager.default.temporaryDirectory.appending(
      path: "SpamWise-tests/\(UUID())/state.store"
    )
  )
}
func envelope(_ name: String = "filler-spam") throws -> MailEnvelope {
  let raw = try fixture(name)
  return MailEnvelope(
    identity: .init(accountID: "account-A", contentHash: stableHash(raw)),
    raw: raw
  )
}
/// Makes every transaction on `store` fail, as when its lock file cannot be opened.
func blockStorage(_ store: Store) throws {
  let lock = store.url.path + ".lock"
  try? FileManager.default.removeItem(atPath: lock)
  try FileManager.default.createDirectory(atPath: lock, withIntermediateDirectories: false)
}
/// Holds a store's transaction lock from outside the store, as another process would.
final class StoreLockHolder: Sendable {
  private let handle: FileHandle

  init(_ store: Store) throws {
    let path = store.url.path + ".lock"
    if !FileManager.default.fileExists(atPath: path) {
      FileManager.default.createFile(atPath: path, contents: nil)
    }
    handle = try FileHandle(forUpdating: URL(filePath: path))
  }

  func hold() { flock(handle.fileDescriptor, LOCK_EX) }
  func release() { flock(handle.fileDescriptor, LOCK_UN) }
}
/// Makes `store` available again after ``blockStorage(_:)``.
func restoreStorage(_ store: Store) throws {
  try FileManager.default.removeItem(atPath: store.url.path + ".lock")
}
/// Classifies every message as Junk with a confidence that meets every filtering threshold.
let junkClassifier = MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "lure"))

func enableActions(_ store: Store) async throws {
  try await StateRepository.update(store) { state in
    state.settings.dryRun = false
    state.settings.validatedAccounts = ["account-A"]
  }
}

func enqueueFailedRetries(store: Store, accountIDs: [String]) async throws {
  let failed = Pipeline(
    store: store,
    classifier: MockClassifier(operation: { _ in throw ClassificationError.rateLimited })
  )
  for account in accountIDs {
    var message = try envelope(); message.identity.accountID = account
    _ = await failed.process(message)
  }
}

struct FixtureThreatDetector: ThreatDetector {
  var identity: ThreatDetectorIdentity
  var operation: @Sendable (ThreatInput) async throws -> [ThreatFinding]

  init(
    usesNetwork: Bool = false,
    policy: String = "fixture-policy-v1",
    operation: @escaping @Sendable (ThreatInput) async throws -> [ThreatFinding]
  ) {
    identity = .init(
      implementation: "fixture-v1",
      model: "synthetic-v1",
      preprocessing: "bounded-text-v1",
      policy: policy,
      usesNetwork: usesNetwork
    )
    self.operation = operation
  }

  func assess(_ input: ThreatInput) async throws -> [ThreatFinding] { try await operation(input) }
}

/// Counts calls from concurrent closures, such as classifier and detector fixtures.
final class Counter: Sendable {
  private let storage = Mutex(0)
  var value: Int { storage.withLock { $0 } }

  func increment() { storage.withLock { $0 += 1 } }
}

func enableSpamhausEvidence(in settings: inout Settings) {
  var evidence = ExternalEvidenceSettings()
  evidence.domainBlocklist = true
  evidence.termsAcknowledged = true
  evidence.spamhausTransport = .https
  settings.advancedOptions.externalEvidence = evidence
}

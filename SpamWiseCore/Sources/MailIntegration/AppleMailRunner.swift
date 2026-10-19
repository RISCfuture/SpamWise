public import Foundation
public import SpamWiseCore
import OSLog
import Dispatch
import CoreServices
import Carbon.OpenScripting

/// Sendable subset of Apple Event results used by the Mail adapter.
public indirect enum ScriptValue: Sendable, Equatable {
  case string(String), integer(Int), list([Self]), boolean(Bool)

  var string: String? { if case .string(let value) = self { value } else { nil } }
  var integer: Int? { if case .integer(let value) = self { value } else { nil } }
  var list: [Self]? { if case .list(let value) = self { value } else { nil } }

  static func decode(_ descriptor: NSAppleEventDescriptor) -> Self {
    if descriptor.descriptorType == typeAEList {
      return .list(
        (1...max(1, descriptor.numberOfItems)).compactMap { descriptor.atIndex($0) }.map(decode)
      )
    }
    if [typeBoolean, typeTrue, typeFalse].contains(descriptor.descriptorType) {
      return .boolean(descriptor.booleanValue)
    }
    if [typeSInt16, typeSInt32, typeSInt64].contains(descriptor.descriptorType) {
      return .integer(Int(descriptor.int32Value))
    }
    return .string(descriptor.stringValue ?? "")
  }
}

/// Positional handler parameter encoded as an Apple Event descriptor.
enum ScriptArgument: Sendable {
  case string(String), integer(Int), boolean(Bool), date(Date), list([Self])

  var descriptor: NSAppleEventDescriptor {
    switch self {
      case .string(let value): NSAppleEventDescriptor(string: value)
      case .integer(let value): NSAppleEventDescriptor(int32: Int32(clamping: value))
      case .boolean(let value): NSAppleEventDescriptor(boolean: value)
      case .date(let value): NSAppleEventDescriptor(date: value)
      case .list(let values):
        values.enumerated().reduce(into: NSAppleEventDescriptor.list()) { list, element in
          list.insert(element.element.descriptor, at: element.offset + 1)
        }
    }
  }
}

/// Injectable execution boundary for Mail Apple Events.
public protocol AppleEventRunner: Sendable {
  /// Invokes one handler of the compiled Mail library and returns transferable result values.
  func run(_ request: MailRequest) async throws -> ScriptValue
}

/// Serializes Mail handler calls off the UI thread and sanitizes integration failures.
public struct SystemAppleEventRunner: AppleEventRunner {
  @MainActor private static let initialized: Void = {
    _ = unsafe NSAppleScript(source: "return true")?.executeAndReturnError(nil)
  }()
  /// Initializes AppleScript on the main actor before dispatching work to its serial executor.
  @MainActor
  public init() { _ = Self.initialized }
  /// Requests Mail Automation consent without blocking queued Mail handler calls.
  public static func requestMailPermission() async throws {
    try await MailAutomationPermission.request()
  }
  /// Reads Mail Automation consent without prompting, launching Mail or waiting for a script.
  @concurrent
  public static func mailAutomationStatus() async -> MailAutomationStatus {
    let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.mail")
    let status = unsafe AEDeterminePermissionToAutomateTarget(
      target.aeDesc,
      typeWildCard,
      typeWildCard,
      false
    )
    if status == noErr { return .granted }
    return status == procNotFound ? .mailNotRunning : .notAuthorized
  }
  /// Invokes the requested Mail handler and returns a sendable result.
  public func run(_ request: MailRequest) async throws -> ScriptValue {
    try await AppleScriptExecutor.shared.run(request)
  }
}

private enum MailAutomationPermission {
  private static let queue = DispatchQueue(label: "codes.tim.SpamWise.apple-events.permission")
  private static let logger = Logger(subsystem: "codes.tim.SpamWise", category: "AppleEvents")

  static func request() async throws {
    try Task.checkCancellation()
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      queue.async { continuation.resume(with: Result { try check(askUser: true) }) }
    }
  }
  static func check(askUser: Bool) throws {
    let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.mail")
    let status = unsafe AEDeterminePermissionToAutomateTarget(
      target.aeDesc,
      typeWildCard,
      typeWildCard,
      askUser
    )
    logger.info("Mail Automation permission status: \(status)")
    guard status == noErr else {
      if status == procNotFound { throw IntegrationError.unavailable }
      throw IntegrationError.permissionDenied
    }
  }
}

private actor AppleScriptExecutor {
  static let shared = AppleScriptExecutor()
  private let queue = DispatchSerialQueue(label: "codes.tim.SpamWise.apple-events")
  // The actor owns this queue for its entire lifetime, including every AppleScript call.
  nonisolated var unownedExecutor: UnownedSerialExecutor { unsafe queue.asUnownedSerialExecutor() }
  private let logger = Logger(subsystem: "codes.tim.SpamWise", category: "AppleEvents")
  private var library: AppleScriptLibrary?

  func run(_ request: MailRequest) throws -> ScriptValue {
    try Task.checkCancellation()
    try MailAutomationPermission.check(askUser: false)
    do {
      let result = try compiledLibrary().call(request.handler.rawValue, request.arguments)
      logger.info("Mail handler \(request.handler.rawValue) returned")
      return result
    } catch let failure as AppleScriptFailure {
      logger.error(
        "Mail handler \(request.handler.rawValue) failed: code \(failure.number ?? 0)"
      )
      throw failure.integrationError
    }
  }
  private func compiledLibrary() throws -> AppleScriptLibrary {
    if let library { return library }
    let compiled = try AppleScriptLibrary(source: MailScripts.library)
    library = compiled
    return compiled
  }
}

/// A failed compilation or handler call, carrying AppleScript's error number when reported.
struct AppleScriptFailure: Error {
  let number: Int?
  var integrationError: IntegrationError {
    switch number {
      case -1743, -10004: .permissionDenied
      case -1712: .timedOut
      case -600, -609: .unavailable
      case let number?: MailScriptError(rawValue: number)?.integrationError ?? .scriptFailed
      case nil: .scriptFailed
    }
  }
}

extension MailScriptError {
  var integrationError: IntegrationError {
    switch self {
      case .accountUnresolved: .accountUnresolved
      case .mailboxUnresolved: .mailboxUnresolved
      case .folderUnresolved: .folderUnresolved
      case .folderLimit:
        .folderLimit(count: MailScripts.maximumFolders, depth: MailScripts.maximumFolderDepth)
      case .existingAnnotation: .existingAnnotation
      case .messageChanged: .staleMessage
      case .messageMissing: .messageMoved
    }
  }
}

/// A compiled AppleScript whose handlers are invoked by Apple Event.
final class AppleScriptLibrary {
  private let script: NSAppleScript

  init(source: String) throws(AppleScriptFailure) {
    guard let script = NSAppleScript(source: source) else { throw AppleScriptFailure(number: nil) }
    // NSAppleScript reports errors through an NSDictionary out-parameter.
    // swiftlint:disable:next legacy_objc_type
    var error: NSDictionary?
    guard unsafe script.compileAndReturnError(&error) else {
      throw AppleScriptFailure(number: error?[NSAppleScript.errorNumber] as? Int)
    }
    self.script = script
  }

  private static func event(_ handler: String, _ arguments: [ScriptArgument])
    -> NSAppleEventDescriptor
  {
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kASAppleScriptSuite),
      eventID: AEEventID(kASSubroutineEvent),
      targetDescriptor: .currentProcess(),
      returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(
      NSAppleEventDescriptor(string: handler),
      forKeyword: AEKeyword(keyASSubroutineName)
    )
    event.setParam(ScriptArgument.list(arguments).descriptor, forKeyword: keyDirectObject)
    return event
  }

  /// Invokes a handler by its lowercase name with positional arguments.
  func call(_ handler: String, _ arguments: [ScriptArgument]) throws(AppleScriptFailure)
    -> ScriptValue
  {
    // NSAppleScript reports errors through an NSDictionary out-parameter.
    // swiftlint:disable:next legacy_objc_type
    var error: NSDictionary?
    let result: NSAppleEventDescriptor? = unsafe script.executeAppleEvent(
      Self.event(handler, arguments),
      error: &error
    )
    if let error { throw AppleScriptFailure(number: error[NSAppleScript.errorNumber] as? Int) }
    guard let result else { throw AppleScriptFailure(number: nil) }
    return ScriptValue.decode(result)
  }
}

extension MailRequest {
  var handler: MailHandler {
    switch self {
      case .accounts: .accountList
      case .selection: .selectedRows
      case .unifiedPage: .unifiedPage
      case .accountPage: .accountPage
      case .folders: .folderList
      case .folderPage: .folderPage
      case .destinations: .destinationNames
      case .find: .findMessages
      case .apply: .applyAction
      case .observe: .observeMessages
    }
  }
  var arguments: [ScriptArgument] {
    switch self {
      case .accounts, .folders: []
      case .selection(let maximumCount): [.integer(maximumCount)]
      case let .unifiedPage(role, offset, limit):
        [.string(role.rawValue)] + Self.window(offset: offset, limit: limit)
      case let .accountPage(role, accountID, offset, limit, headersOnly, since, before):
        [.string(role.rawValue), .string(accountID)] + Self.window(offset: offset, limit: limit)
          + [.boolean(headersOnly)] + Self.optional(since) + Self.optional(before)
      case let .folderPage(folder, offset, limit, since):
        [.string(folder.accountID), .list(folder.path.map(ScriptArgument.string))]
          + Self.window(offset: offset, limit: limit)
          + Self.optional(since)
      case .destinations(let accountID): [.string(accountID)]
      case let .find(accountID, messageID, localID, mailbox):
        [
          .string(accountID), .string(messageID ?? ""), .integer(localID ?? -1),
          .string(mailbox ?? "")
        ]
      case let .apply(command, location):
        [
          .string(command.rawValue), .string(location.accountID), .string(location.mailbox),
          .integer(location.localID), .string(location.messageID ?? ""),
          .integer(location.byteCount)
        ]
      case let .observe(accountID, role, messageID):
        [.string(accountID), .string(role.rawValue), .string(messageID)]
    }
  }
  /// A presence flag followed by the date, or the epoch when absent.
  private static func optional(_ date: Date?) -> [ScriptArgument] {
    [.boolean(date != nil), .date(date ?? Date(timeIntervalSince1970: 0))]
  }
  private static func window(offset: Int, limit: Int) -> [ScriptArgument] {
    [.integer(max(0, offset) + 1), .integer(max(1, min(MailScripts.maximumPageSize, limit)))]
  }
}

public import AppIntents
import Foundation
import UniformTypeIdentifiers
import SpamWiseCore
import MailIntegration

nonisolated enum AutomationLabel: String, AppEnum {
  case good = "inbox", junk = "spam", review = "needs-review"

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mail label"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .good: "Good", .junk: "Junk", .review: "Review"
  ]
  var label: MailLabel {
    switch self { case .good: .inbox;  case .junk: .junk;  case .review: .review
    }
  }
}

struct PreviewSelectedMailIntent: AppIntent, CancellableIntent {
  static let title: LocalizedStringResource = "Preview Selected Mail"
  static let description = IntentDescription(
    "Classify one selected Mail message using your configured provider and budget, without moving it."
  )
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
  static var parameterSummary: some ParameterSummary { Summary("Preview selected Mail") }
  @Parameter(
    title: "Request UUID",
    description:
      "Advanced. Leave empty for a new request. To retry a run safely, enter the Request UUID its result or error shows."
  )
  var requestID: String?
  @Dependency var model: AppModel

  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let id = try AutomationRequestID.resolve(requestID)
    let model = model
    let task = Task { try await AutomationContext.execute(.preview, id: id, model: model) }
    let result = try await withIntentCancellationHandler {
      try await task.value
    } onCancel: { _ in
      task.cancel()
    }
    return .result(value: result)
  }
}

struct CorrectSelectedMailIntent: AppIntent, CancellableIntent {
  static let title: LocalizedStringResource = "Correct Selected Mail"
  static let description = IntentDescription(
    "Save a sender correction for one selected message, then attempt its action under existing safety settings."
  )
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
  static var parameterSummary: some ParameterSummary {
    Summary("Correct selected Mail as \(\.$label)")
  }
  @Parameter(title: "Label")
  var label: AutomationLabel
  @Parameter(
    title: "Request UUID",
    description:
      "Advanced. Leave empty for a new request. To retry a run safely, enter the Request UUID its result or error shows."
  )
  var requestID: String?
  @Dependency var model: AppModel

  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let id = try AutomationRequestID.resolve(requestID)
    let operation = AutomationOperation.correct(label.label)
    let model = model
    let task = Task {
      try await AutomationContext.execute(operation, id: id, model: model) { sender in
        try await confirmBlocking(sender)
      }
    }
    let result = try await withIntentCancellationHandler {
      try await task.value
    } onCancel: { _ in
      task.cancel()
    }
    return .result(value: result)
  }

  /// Asks, as the app's Junk corrections do, before blocking a sender SpamWise couldn’t verify.
  private func confirmBlocking(_ sender: String) async throws {
    try await requestConfirmation(
      actionName: .custom(
        acceptLabel: "Block Sender Anyway",
        acceptAlternatives: [],
        denyLabel: "Cancel",
        denyAlternatives: [],
        destructive: true
      ),
      dialog: "\(UnverifiedSenderPrompt.message(sender: sender))"
    )
  }
}

/**
 The identifier that protects one preview or correction against repetition.

 Each run gets a new identifier unless the shortcut supplies one, and its reply or failure names
 the identifier used. Running again with the same identifier returns the saved result instead of
 repeating the work.
 */
nonisolated enum AutomationRequestID {
  /// The identifier in `text`, or a new one when `text` is empty or absent.
  static func resolve(_ text: String?) throws -> UUID {
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return UUID() }
    guard let id = UUID(uuidString: trimmed) else {
      throw AutomationIntentError.invalidRequestID(trimmed)
    }
    return id
  }
}

/// A preview or correction reply, with the Request UUID that a retry enters to replay it.
nonisolated struct IdentifiedAutomationReply: Encodable {
  let requestID: UUID
  let reply: AutomationReply

  /// Encodes the reply's fields and `requestID` side by side in one object.
  func encode(to encoder: any Encoder) throws {
    try reply.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(requestID, forKey: .requestID)
  }

  private enum CodingKeys: String, CodingKey {
    case requestID
  }
}

/// Says whether SpamWise is filtering, and returns its redacted status as JSON text for shortcuts.
public struct SpamWiseStatusIntent: AppIntent {
  public static let title: LocalizedStringResource = "Get SpamWise Status"
  public static var supportedModes: IntentModes { .background }
  @Dependency var model: AppModel

  /// Creates the intent; App Intents supplies the model when it runs.
  public init() {}

  /// Says the filtering state, as the menu bar shows it, and returns the same redacted diagnostics as the exported file.
  public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let model = model
    let data = try await AutomationContext.diagnostics(model: model)
    guard let text = String(data: data, encoding: .utf8) else {
      throw AutomationIntentError.failed(reason: nil)
    }
    let state = await MainActor.run { model.scanning.filteringState.localizedTitle }
    return .result(value: text, dialog: IntentDialog(stringLiteral: state))
  }
}

struct ExportSpamWiseDiagnosticsIntent: AppIntent {
  static let title: LocalizedStringResource = "Export SpamWise Diagnostics"
  static var supportedModes: IntentModes { .background }

  @Dependency var model: AppModel

  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
    let data = try await AutomationContext.diagnostics(model: model)
    return .result(
      value: IntentFile(data: data, filename: "SpamWise-diagnostics.json", type: .json)
    )
  }
}

nonisolated private enum AutomationContext {
  /// Asks the user to let a correction block `sender`, which SpamWise couldn’t verify, and throws
  /// when they decline.
  typealias SenderConfirmation = @Sendable (_ sender: String) async throws -> Void

  static func diagnostics(model: AppModel) async throws -> Data {
    do { return try await model.activity.diagnostics() } catch {
      throw AutomationIntentError(error)
    }
  }

  /**
   Runs `operation` on Mail's selected message as request `id`.

   A Junk correction of a sender SpamWise couldn’t verify first waits for `confirmSender`. An
   error it throws passes through unchanged, and nothing is saved.
   */
  static func execute(
    _ operation: AutomationOperation,
    id: UUID,
    model: AppModel,
    confirmSender: SenderConfirmation? = nil
  ) async throws -> String {
    let (pipeline, adapter, selected) = try await identifyingFailures(of: id) {
      try Task.checkCancellation()
      let (store, pipeline, adapter) = try await MainActor.run {
        let services = model.services
        return (try services.requireStore(), try services.requirePipeline(), services.appleMail)
      }
      return (pipeline, adapter, try await selectedMessage(from: adapter, store: store))
    }
    if case .correct(let label) = operation, let confirmSender,
      await pipeline.correctionWarning(envelope: selected, label: label) == .unauthenticatedSender
    {
      try await confirmSender(sender(of: selected))
    }
    return try await identifyingFailures(of: id) {
      let reply = try await pipeline.execute(
        operation,
        requestID: id,
        envelope: selected,
        adapter: adapter
      )
      return try JSONEncoder.pretty.encodeText(
        IdentifiedAutomationReply(requestID: id, reply: reply)
      )
    }
  }

  /// Runs `work`, naming request `id` in every failure but cancellation.
  private static func identifyingFailures<Value>(
    of id: UUID,
    _ work: () async throws -> Value
  ) async throws -> Value {
    do { return try await work() } catch is CancellationError { throw CancellationError() } catch {
      throw AutomationRequestFailure(requestID: id, failure: AutomationIntentError(error))
    }
  }

  /// The address `envelope` says it’s from, or “Unknown sender”.
  private static func sender(of envelope: MailEnvelope) -> String {
    (try? MIMEParser().parse(envelope.raw).fromAddress) ?? String(localized: "Unknown sender")
  }

  /// Mail's one selected message, once setup is finished with Apple Mail as the transport.
  private static func selectedMessage(from adapter: AppleMailAdapter, store: Store) async throws
    -> MailEnvelope
  {
    let settings = try await StateRepository.load(store, StateSlices()).settings
    guard settings.onboardingComplete else { throw AutomationIntentError.setupIncomplete }
    guard settings.advancedOptions.transport == .appleMail else {
      throw AutomationIntentError.unsupportedTransport
    }
    return try await adapter.selectedMessage()
  }
}

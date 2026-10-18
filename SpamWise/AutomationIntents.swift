public import AppIntents
import Foundation
import UniformTypeIdentifiers
import SpamWiseCore
import MailIntegration

nonisolated enum AutomationLabel: String, AppEnum {
  case good = "inbox", junk = "spam", review = "needs-review"
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mail label"
  static let caseDisplayRepresentations: [AutomationLabel: DisplayRepresentation] = [
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
  static var parameterSummary: some ParameterSummary {
    Summary("Preview selected Mail with request \(\.$requestID)")
  }
  @Parameter(title: "Request UUID") var requestID: String
  @Dependency var model: AppModel

  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    guard let id = UUID(uuidString: requestID) else { throw AutomationIntentError.invalidRequest }
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
    Summary("Correct selected Mail as \(\.$label) with request \(\.$requestID)")
  }
  @Parameter(title: "Label") var label: AutomationLabel
  @Parameter(title: "Request UUID") var requestID: String
  @Dependency var model: AppModel

  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    guard let id = UUID(uuidString: requestID) else { throw AutomationIntentError.invalidRequest }
    let operation = AutomationOperation.correct(label.label)
    let model = model
    let task = Task { try await AutomationContext.execute(operation, id: id, model: model) }
    let result = try await withIntentCancellationHandler {
      try await task.value
    } onCancel: { _ in
      task.cancel()
    }
    return .result(value: result)
  }
}

/// Reports SpamWise’s redacted filtering status as JSON text.
public struct SpamWiseStatusIntent: AppIntent {
  public static let title: LocalizedStringResource = "Get SpamWise Status"
  public static var supportedModes: IntentModes { .background }
  @Dependency var model: AppModel

  /// Creates the intent; App Intents supplies the model when it runs.
  public init() {}

  /// Returns the same redacted diagnostics as the exported file.
  public func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let data = try await AutomationContext.diagnostics(model: model)
    return .result(value: String(decoding: data, as: UTF8.self))
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
  static func diagnostics(model: AppModel) async throws -> Data {
    do {
      guard let store = await MainActor.run(body: { model.services.store }) else {
        throw IntegrationError.unavailable
      }
      let state = try await StateRepository.load(store, StateSlices(records: .all, retries: .all))
      return try JSONEncoder().encode(DiagnosticSummary(state: state))
    } catch { throw AutomationIntentError.unavailable }
  }
  static func execute(_ operation: AutomationOperation, id: UUID, model: AppModel) async throws
    -> String
  {
    do {
      try Task.checkCancellation()
      let (store, pipeline, adapter) = await MainActor.run {
        (model.services.store, model.services.pipeline, model.services.appleMail)
      }
      guard let store, let pipeline else { throw IntegrationError.unavailable }
      let settings = try await StateRepository.load(store, StateSlices()).settings
      guard settings.onboardingComplete, settings.advancedOptions.transport == .appleMail else {
        throw IntegrationError.unavailable
      }
      let selected = try await adapter.selectedMessage()
      let reply = try await pipeline.execute(
        operation,
        requestID: id,
        envelope: selected,
        adapter: adapter
      )
      let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      return String(decoding: try encoder.encode(reply), as: UTF8.self)
    } catch is CancellationError { throw CancellationError() } catch {
      throw AutomationIntentError.unavailable
    }
  }
}

nonisolated private enum AutomationIntentError: MailIntegrationFailure, LocalizedError,
  CustomLocalizedStringResourceConvertible
{
  case invalidRequest, unavailable
  var localizedStringResource: LocalizedStringResource {
    switch self {
      case .invalidRequest:
        "Use a generated UUID for each new operation; reuse it only to retry that same request."
      case .unavailable:
        "Check setup and Activity in SpamWise. Select one Mail message. Uncertain requests are never replayed."
    }
  }
  var errorDescription: String? { String(localized: localizedStringResource) }
}

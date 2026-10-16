import AppIntents
import AppIntentsTesting
import XCTest

@MainActor
struct RegisteredAutomation {
  private let definitions = IntentDefinitions(bundleIdentifier: "codes.tim.SpamWise")

  func preview() -> AnyAppIntent {
    definitions.intents["PreviewSelectedMailIntent"].makeIntent(requestID: UUID().uuidString)
  }

  func correctAsGood() -> AnyAppIntent {
    definitions.intents["CorrectSelectedMailIntent"].makeIntent(
      label: definitions.enums["AutomationLabel"].makeCase("inbox"),
      requestID: UUID().uuidString
    )
  }

  func reply(to intent: AnyAppIntent) async throws -> [String: String] {
    let result = try await intent.run()
    let text: String = try result.value
    return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String])
  }

  func status() async throws -> [String: Any] {
    let result = try await definitions.intents["SpamWiseStatusIntent"].makeIntent().run()
    let text: String = try result.value
    return try diagnostics(Data(text.utf8))
  }

  func exportDiagnostics() async throws -> [String: Any] {
    let result = try await definitions.intents["ExportSpamWiseDiagnosticsIntent"].makeIntent().run()
    let file: IntentFile = try result.value
    XCTAssertEqual(file.filename, "SpamWise-diagnostics.json")
    return try diagnostics(file.data)
  }

  private func diagnostics(_ data: Data) throws -> [String: Any] {
    let text = try XCTUnwrap(String(data: data, encoding: .utf8))
    for privateValue in ["newsletter@example.org", "Your weekly digest", "ui-test"] {
      XCTAssertFalse(text.contains(privateValue))
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}

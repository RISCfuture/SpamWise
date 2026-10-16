import XCTest

/// App Intents run through the registered signed app, against its automation fixture.
final class RegisteredAutomationTests: UITestCase {
  @MainActor private var automation: RegisteredAutomation { RegisteredAutomation() }

  override func setUpWithError() throws {
    try super.setUpWithError()
    let environment = ProcessInfo.processInfo.environment
    try XCTSkipUnless(
      environment["SPAMWISE_INTENTS_TEST"] == "1",
      "Requires the current signed app to be indexed by macOS App Intents."
    )
    _ = try XCTUnwrap(
      environment[UITestApplication.registeredAppPathVariable],
      "Pass the registered signed fixture app path so UI and intents use the same process."
    )
  }

  @MainActor
  func testStatusReportsTheValidatedLiveFixture() async throws {
    _ = ActivityScreen.launchCorrectionFixture(automation: true)
    let diagnostics = try await automation.status()
    XCTAssertEqual(diagnostics["dryRun"] as? Bool, false)
    XCTAssertEqual(diagnostics["validatedAccountCount"] as? Int, 1)
  }

  @MainActor
  func testReplayedRequestsReturnTheirFirstReplyAndRecordOnce() async throws {
    _ = ActivityScreen.launchCorrectionFixture(automation: true)
    let preview = automation.preview()
    let firstPreview = try await automation.reply(to: preview)
    XCTAssertEqual(firstPreview["label"], "junk")
    XCTAssertEqual(firstPreview["action"], "moveToJunk")
    XCTAssertEqual(firstPreview["outcome"], "dryRun")
    let repeatedPreview = try await automation.reply(to: preview)
    XCTAssertEqual(repeatedPreview, firstPreview)

    let correction = automation.correctAsGood()
    let firstCorrection = try await automation.reply(to: correction)
    XCTAssertEqual(firstCorrection["label"], "inbox")
    XCTAssertEqual(firstCorrection["action"], "moveToInbox")
    XCTAssertEqual(firstCorrection["outcome"], "failed")
    let repeatedCorrection = try await automation.reply(to: correction)
    XCTAssertEqual(repeatedCorrection, firstCorrection)

    let status = try await automation.status()
    XCTAssertEqual(status["outcomes"] as? [String: Int], ["dryRun": 2, "failed": 1, "noAction": 1])
  }

  @MainActor
  func testCorrectionIntentSavesAnAddressAllowRule() async throws {
    let activity = ActivityScreen.launchCorrectionFixture(automation: true)
    _ = try await automation.reply(to: automation.correctAsGood())
    let rules = activity.openRulesSettings()
    XCTAssertTrue(rules.waitForAddressRule(.allow))
    XCTAssertTrue(rules.waitForNoDomainRule())
  }

  @MainActor
  func testExportedDiagnosticsMatchStatus() async throws {
    _ = ActivityScreen.launchCorrectionFixture(automation: true)
    let status = try await automation.status()
    let exported = try await automation.exportDiagnostics()
    XCTAssertEqual(
      try JSONSerialization.data(withJSONObject: exported, options: .sortedKeys),
      try JSONSerialization.data(withJSONObject: status, options: .sortedKeys)
    )
  }
}

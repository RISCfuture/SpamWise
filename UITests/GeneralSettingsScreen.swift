import XCTest

@MainActor struct GeneralSettingsScreen {
  let app: XCUIApplication

  var dryRunToggle: XCUIElement { app.switches["settings.dryRun"] }
  var isDryRun: Bool { (dryRunToggle.value as? NSNumber)?.boolValue == true }
  var canChangeDryRun: Bool { dryRunToggle.isEnabled }
  var hasMailPermissionDeniedStatus: Bool {
    app.staticTexts["settings.mailPermissionDenied"].waitForExistence(
      timeout: UITestTiming.transition
    )
  }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(
      app.switches["settings.dryRun"].waitForExistence(timeout: UITestTiming.transition)
    )
    return Self(app: app)
  }

  func turnOnDryRun() {
    dryRunToggle.click()
    waitForDryRun(true)
  }

  func checkMailConnection() {
    app.buttons["settings.checkMail"].click()
  }

  func requestLiveFiltering() -> LiveFilteringConfirmation {
    dryRunToggle.click()
    return LiveFilteringConfirmation.waitForLanding(in: app)
  }

  func waitForDryRun(_ expected: Bool) {
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", NSNumber(value: expected)),
            object: dryRunToggle
          )
        ],
        timeout: UITestTiming.transition
      ),
      .completed
    )
  }

  func close() -> ActivityScreen {
    app.typeKey("w", modifierFlags: .command)
    return ActivityScreen.waitForLanding(in: app)
  }
}

@MainActor struct LiveFilteringConfirmation {
  let app: XCUIApplication

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(
      app.buttons["settings.dryRun.confirm"].waitForExistence(timeout: UITestTiming.transition)
    )
    return Self(app: app)
  }

  func cancel() -> GeneralSettingsScreen {
    app.buttons["settings.dryRun.cancel"].click()
    return GeneralSettingsScreen(app: app)
  }

  func confirm() -> GeneralSettingsScreen {
    app.buttons["settings.dryRun.confirm"].click()
    return GeneralSettingsScreen(app: app)
  }
}

extension UITests {
  @MainActor func testLeavingDryRunRequiresConfirmation() throws {
    continueAfterFailure = false
    let activity = ActivityScreen.launchCorrectionFixture()
    XCTAssertEqual(activity.mode, "filtering")
    let settings = activity.openGeneralSettings()
    XCTAssertFalse(settings.isDryRun)
    settings.turnOnDryRun()
    let cancelled = settings.requestLiveFiltering().cancel()
    cancelled.waitForDryRun(true)
    let confirmed = cancelled.requestLiveFiltering().confirm()
    confirmed.waitForDryRun(false)
    XCTAssertEqual(confirmed.close().mode, "filtering")
  }
}

import XCTest

/// The General settings tab.
@MainActor
struct GeneralSettingsScreen {
  let app: XCUIApplication

  private var dryRunToggle: XCUIElement { app.switches["settings.dryRun"] }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(
      app.switches["settings.dryRun"].waitForExistence(timeout: UITestTiming.transition)
    )
    return Self(app: app)
  }

  /// Waits until dry run is on or off.
  func waitForDryRun(_ isOn: Bool) -> Bool { dryRunToggle.waitForSwitch(isOn) }

  /// Waits until the dry-run switch can or can't be changed.
  func waitForDryRunChangeable(_ isChangeable: Bool) -> Bool {
    dryRunToggle.waitForEnabled(isChangeable)
  }

  /// Waits for the status that reports Mail permission as denied.
  func waitForMailPermissionDenied() -> Bool {
    app.staticTexts["settings.mailPermissionDenied"].waitForExistence(
      timeout: UITestTiming.transition
    )
  }

  /// Turns dry run on, which needs no confirmation.
  func turnOnDryRun() {
    dryRunToggle.click()
    XCTAssertTrue(waitForDryRun(true))
  }

  func checkMailConnection() { app.buttons["settings.checkMail"].click() }

  /// Turns off the menu bar item.
  func hideMenuBarItem() {
    let toggle = app.switches["settings.menuBar"]
    toggle.click()
    XCTAssertTrue(toggle.waitForSwitch(false))
  }

  /// Asks to turn dry run off, which the app confirms first.
  func requestLiveFiltering() -> LiveFilteringConfirmation {
    dryRunToggle.click()
    return LiveFilteringConfirmation.waitForLanding(in: app)
  }

  func close() -> ActivityScreen {
    app.typeKey("w", modifierFlags: .command)
    return ActivityScreen.waitForLanding(in: app)
  }
}

/// The confirmation shown before dry run turns off.
@MainActor
struct LiveFilteringConfirmation {
  let app: XCUIApplication

  private var confirmButton: XCUIElement { app.buttons["settings.dryRun.confirm"] }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(
      app.buttons["settings.dryRun.confirm"].waitForExistence(timeout: UITestTiming.transition)
    )
    return Self(app: app)
  }

  func cancel() -> GeneralSettingsScreen {
    app.buttons["settings.dryRun.cancel"].click()
    return dismissed()
  }

  func confirm() -> GeneralSettingsScreen {
    confirmButton.click()
    return dismissed()
  }

  /// Confirms a request made from the Activity window.
  func confirmFromActivity() -> ActivityScreen {
    confirmButton.click()
    XCTAssertTrue(confirmButton.waitForNonExistence(timeout: UITestTiming.transition))
    return ActivityScreen.waitForLanding(in: app)
  }

  private func dismissed() -> GeneralSettingsScreen {
    XCTAssertTrue(confirmButton.waitForNonExistence(timeout: UITestTiming.transition))
    return GeneralSettingsScreen.waitForLanding(in: app)
  }
}

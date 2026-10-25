import XCTest

/// The filtering states the Activity footer identifies as `activity.mode.<state>`.
enum FilteringMode: String {
  case filtering, paused, mailNotAuthorized
}

@MainActor
struct ActivityScreen {
  private static let fixtureSubject = "activity.subject.00000000-0000-0000-0000-000000000001"
  let app: XCUIApplication

  /**
   Launches Activity with one recorded Junk decision, isolated storage and a denied Mail
   connection.

   - Parameter automation: Whether Mail instead returns one synthetic selected message, for
     App Intents.
   */
  static func launchCorrectionFixture(automation: Bool = false) -> Self {
    let app = UITestApplication.launch(
      arguments: ["--ui-testing", "--ui-corrections"] + (automation ? ["--ui-automation"] : [])
    )
    XCTAssertTrue(modes(in: app).firstMatch.waitForExistence(timeout: UITestTiming.launch))
    return Self(app: app)
  }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(modes(in: app).firstMatch.waitForExistence(timeout: UITestTiming.transition))
    return Self(app: app)
  }

  private static func modes(in app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any).identified(byPrefix: "activity.mode.")
  }

  /// Waits until the footer shows `mode`.
  func waitForMode(_ mode: FilteringMode) -> Bool {
    app.descendants(matching: .any)["activity.mode.\(mode.rawValue)"]
      .waitForExistence(timeout: UITestTiming.transition)
  }

  func openFixture() -> DecisionScreen {
    let subject = app.staticTexts[Self.fixtureSubject]
    XCTAssertTrue(subject.waitForExistence(timeout: UITestTiming.transition))
    subject.click()
    return DecisionScreen.waitForLanding(in: app)
  }

  func openRulesSettings() -> RulesScreen {
    openSettingsPane("Rules")
    return RulesScreen.waitForLanding(in: app)
  }

  func openGeneralSettings() -> GeneralSettingsScreen {
    openSettingsPane("General")
    return GeneralSettingsScreen.waitForLanding(in: app)
  }

  func openPreferencesSettings() -> CategoryPreferencesScreen {
    openSettingsPane("Mail Choices")
    return CategoryPreferencesScreen.waitForLanding(in: app)
  }

  func openEvidenceSettings() -> EvidenceScreen {
    openSettingsPane("Advanced")
    return EvidenceScreen.waitForLanding(in: app)
  }

  func openStatistics() -> StatisticsScreen {
    app.buttons["activity.statistics"].click()
    return StatisticsScreen.waitForLanding(in: app)
  }

  func openCorpus() -> CorpusScreen {
    app.menuBars.menuBarItems[AppText.localized("Tools")].click()
    app.menuItems["activity.corpus"].click()
    return CorpusScreen.waitForLanding(in: app)
  }

  func pause() { app.buttons["activity.pause"].click() }

  /// Closes the Activity window, which leaves SpamWise running.
  func close() {
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(
      Self.modes(in: app).firstMatch.waitForNonExistence(timeout: UITestTiming.transition)
    )
  }

  /// Opens `spamwise://activity` and waits until the Activity window shows.
  func reopenFromURL() -> Bool {
    app.open(URL(string: "spamwise://activity")!)
    return Self.modes(in: app).firstMatch.waitForExistence(timeout: UITestTiming.transition)
  }

  /// Whether the Filtering menu offers to mark the selected decision as Junk.
  func canMarkSelectionAsJunk() -> Bool {
    app.menuBars.menuBarItems[AppText.localized("Filtering")].click()
    let item = app.menuItems["activity.correct.junk"]
    XCTAssertTrue(item.waitForExistence(timeout: UITestTiming.transition))
    defer { app.typeKey(.escape, modifierFlags: []) }
    return item.isEnabled
  }

  /// Asks, from the footer, to leave dry run, which the app confirms first.
  func startFiltering() -> LiveFilteringConfirmation {
    let button = app.buttons["activity.startFiltering"]
    XCTAssertTrue(button.waitForExistence(timeout: UITestTiming.transition))
    button.click()
    return LiveFilteringConfirmation.waitForLanding(in: app)
  }

  /// Opens Settings on the tab titled by `titleKey`.
  private func openSettingsPane(_ titleKey: String) {
    app.typeKey(",", modifierFlags: .command)
    // Native Settings tabs expose only their titles, not SwiftUI accessibility identifiers.
    let tab = app.toolbars.buttons[AppText.localized(titleKey)]
    XCTAssertTrue(tab.waitForExistence(timeout: UITestTiming.transition))
    tab.click()
  }
}

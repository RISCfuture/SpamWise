import XCTest

@MainActor struct ActivityScreen {
  let app: XCUIApplication

  /// The footer's filtering state, read from its `activity.mode.<state>` identifier.
  var mode: String? {
    Self.modeElement(in: app).identifier.split(separator: ".").last.map(String.init)
  }

  private static func modeElement(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.mode.")).firstMatch
  }

  static func launchCorrectionFixture(automation: Bool = false, appURL: URL? = nil) -> Self {
    let app = UITestApplication.make(url: appURL)
    app.launchArguments = [
      "--ui-testing", "--ui-corrections", "-AppleLanguages", "(en)"
    ]
    if automation { app.launchArguments.append("--ui-automation") }
    app.launch()
    return waitForLanding(in: app)
  }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(modeElement(in: app).waitForExistence(timeout: UITestTiming.launch))
    return Self(app: app)
  }

  func openFixture() -> DecisionScreen {
    let subject = app.staticTexts["activity.subject.00000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(subject.waitForExistence(timeout: UITestTiming.transition))
    subject.click()
    XCTAssertTrue(app.buttons["correction.good"].waitForExistence(timeout: UITestTiming.transition))
    return DecisionScreen(app: app)
  }

  func openRulesSettings() -> RulesScreen {
    app.typeKey(",", modifierFlags: .command)
    // Native Settings toolbar tabs expose their titles instead of SwiftUI identifiers.
    let rules = app.toolbars.buttons["Rules"]
    XCTAssertTrue(rules.waitForExistence(timeout: UITestTiming.transition))
    rules.click()
    XCTAssertTrue(
      app.descendants(matching: .any)["settings.rules.content"]
        .waitForExistence(timeout: UITestTiming.transition)
    )
    return RulesScreen(app: app)
  }

  func openGeneralSettings() -> GeneralSettingsScreen {
    app.typeKey(",", modifierFlags: .command)
    let general = app.toolbars.buttons["General"]
    XCTAssertTrue(general.waitForExistence(timeout: UITestTiming.transition))
    general.click()
    return GeneralSettingsScreen.waitForLanding(in: app)
  }

  func openEvidenceSettings() -> EvidenceScreen {
    app.typeKey(",", modifierFlags: .command)
    let advanced = app.toolbars.buttons["Advanced"]
    XCTAssertTrue(advanced.waitForExistence(timeout: UITestTiming.transition))
    advanced.click()
    return EvidenceScreen.waitForLanding(in: app)
  }

  func openStatistics() -> StatisticsScreen {
    app.buttons["activity.statistics"].click()
    XCTAssertTrue(
      app.staticTexts["statistics.decisions"].waitForExistence(timeout: UITestTiming.transition)
    )
    return StatisticsScreen(app: app)
  }

  func openCorpus() -> CorpusScreen {
    app.typeKey("c", modifierFlags: [.command, .option])
    XCTAssertTrue(
      app.staticTexts["corpus.title"].waitForExistence(timeout: UITestTiming.transition)
    )
    return CorpusScreen(app: app)
  }

  func pause() {
    app.buttons["activity.pause"].click()
    XCTAssertTrue(
      app.descendants(matching: .any)["activity.mode.paused"]
        .waitForExistence(timeout: UITestTiming.transition)
    )
  }
}

@MainActor enum UITestApplication {
  static func make(url: URL? = nil) -> XCUIApplication {
    let appURL =
      url
      ?? ProcessInfo.processInfo.environment["SPAMWISE_INTENTS_APP_PATH"].map {
        URL(filePath: $0)
      }
    return appURL.map { XCUIApplication(url: $0) } ?? XCUIApplication()
  }
}

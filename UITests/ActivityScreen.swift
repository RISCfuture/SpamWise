import XCTest

@MainActor struct ActivityScreen {
  let app: XCUIApplication

  var isDryRun: Bool { app.staticTexts["activity.mode"].value as? String == "dryRun" }
  var isPaused: Bool { app.staticTexts["activity.mode"].value as? String == "paused" }

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
    XCTAssertTrue(app.staticTexts["activity.mode"].waitForExistence(timeout: UITestTiming.launch))
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
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "paused"),
            object: app.staticTexts["activity.mode"]
          )
        ],
        timeout: UITestTiming.transition
      ),
      .completed
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

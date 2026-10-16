import XCTest

/// The Activity statistics sheet.
@MainActor
struct StatisticsScreen {
  let app: XCUIApplication

  private var decisions: XCUIElement { app.staticTexts["statistics.decisions"] }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(
      app.staticTexts["statistics.decisions"].waitForExistence(timeout: UITestTiming.transition)
    )
    return Self(app: app)
  }

  /// Waits until the decision total shows `count`, formatted as the app formats it.
  func waitForDecisionCount(_ count: Int) -> Bool {
    decisions.wait(until: NSPredicate(format: "value == %@", count.formatted()))
  }

  func close() -> ActivityScreen {
    app.buttons["statistics.done"].click()
    XCTAssertTrue(decisions.waitForNonExistence(timeout: UITestTiming.transition))
    return ActivityScreen.waitForLanding(in: app)
  }
}

/// The reviewed-messages sheet.
@MainActor
struct CorpusScreen {
  let app: XCUIApplication

  private var labels: XCUIElementQuery { app.staticTexts.identified(byPrefix: "corpus.label.") }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(
      app.staticTexts["corpus.title"].waitForExistence(timeout: UITestTiming.transition)
    )
    return Self(app: app)
  }

  /// Waits until the sheet lists `count` reviewed messages.
  func waitForLabelCount(_ count: Int) -> Bool { labels.waitForCount(count) }

  func forgetFirstExample() {
    labels.firstMatch.click()
    app.buttons["corpus.forget"].click()
    let confirm = app.buttons["corpus.forget.confirm"]
    XCTAssertTrue(confirm.waitForExistence(timeout: UITestTiming.transition))
    confirm.click()
  }

  func close() -> ActivityScreen {
    app.buttons["corpus.done"].click()
    XCTAssertTrue(
      app.staticTexts["corpus.title"].waitForNonExistence(timeout: UITestTiming.transition)
    )
    return ActivityScreen.waitForLanding(in: app)
  }
}

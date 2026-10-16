import XCTest

@MainActor struct StatisticsScreen {
  let app: XCUIApplication
  var decisionCount: String { app.staticTexts["statistics.decisions"].value as? String ?? "" }
  func close() {
    app.buttons["statistics.done"].click()
    XCTAssertTrue(
      app.buttons["activity.statistics"].waitForExistence(timeout: UITestTiming.transition)
    )
  }
}

@MainActor struct CorpusScreen {
  let app: XCUIApplication
  private var labels: XCUIElementQuery {
    app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "corpus.label."))
  }
  var labelCount: Int { labels.count }
  func forgetFirstExample() {
    labels.firstMatch.click()
    app.buttons["corpus.forget"].click()
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"),
            object: labels
          )
        ],
        timeout: UITestTiming.transition
      ),
      .completed
    )
  }
  func close() { app.buttons["corpus.done"].click() }
}

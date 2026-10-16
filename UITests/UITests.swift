import AppIntents
import XCTest

final class UITests: XCTestCase {
  @MainActor func testOnboardingAndOfflineActivity() throws {
    let setup = SetupScreen.launchOffline()
    XCTAssertTrue(setup.introVisible)
    setup.continueSetup()
    XCTAssertTrue(setup.keyVisible)
    setup.continueSetup()
    setup.checkDeniedMailPermission()
    XCTAssertTrue(setup.hasPermissionDeniedStatus)
    setup.continueSetup()
    let activity = setup.finish()
    XCTAssertTrue(activity.isDryRun)
    activity.pause()
    XCTAssertTrue(activity.isPaused)
  }
}
@MainActor private struct SetupScreen {
  let app: XCUIApplication
  static func launchOffline() -> Self {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    _ = app.staticTexts["setup.intro"].waitForExistence(timeout: 10)
    return Self(app: app)
  }
  var introVisible: Bool { app.staticTexts["setup.intro"].exists }
  var keyVisible: Bool { app.secureTextFields["setup.key"].waitForExistence(timeout: 5) }
  private var permissionDeniedStatus: XCUIElement {
    app.staticTexts["mail.status"].descendants(matching: .staticText).matching(
      NSPredicate(format: "value CONTAINS %@", "Automation permission denied")
    ).firstMatch
  }
  var hasPermissionDeniedStatus: Bool { permissionDeniedStatus.exists }
  func continueSetup() { app.buttons["setup.continue"].click() }
  func checkDeniedMailPermission() {
    app.buttons["mail.check"].click()
    _ = permissionDeniedStatus.waitForExistence(timeout: 5)
  }
  func finish() -> ActivityScreen {
    app.buttons["setup.finish"].click()
    _ = app.staticTexts["activity.title"].waitForExistence(timeout: 5)
    return ActivityScreen(app: app)
  }
}
@MainActor private struct ActivityScreen {
  let app: XCUIApplication
  var isDryRun: Bool {
    (app.staticTexts["activity.mode"].value as? String)?.contains("Dry run") == true
  }
  var isPaused: Bool { app.buttons["activity.pause"].label.contains("Resume") }
  func pause() {
    app.buttons["activity.pause"].click()
    let predicate = NSPredicate(format: "label CONTAINS %@", "Resume")
    _ = XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: predicate, object: app.buttons["activity.pause"])],
      timeout: 5
    )
  }
}

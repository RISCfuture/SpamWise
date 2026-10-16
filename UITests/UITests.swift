import AppIntents
import XCTest

final class UITests: XCTestCase {
  @MainActor func testCorrectionsKeepRulesWhenMailActionFails() throws {
    continueAfterFailure = false
    let activity = ActivityScreen.launchCorrectionFixture()
    let detail = activity.openFixture()
    detail.markGood()
    XCTAssertTrue(detail.correctionSavedWithActionFailure)
    let settings = activity.openAdvancedSettings()
    XCTAssertEqual(settings.addressRule, "Allow")
    XCTAssertFalse(settings.hasDomainRule)
    settings.close()
    detail.markJunk()
    XCTAssertTrue(detail.correctionSavedWithActionFailure)
    detail.allowDomain()
    XCTAssertTrue(detail.correctionSavedWithActionFailure)
    let updatedSettings = activity.openAdvancedSettings()
    XCTAssertEqual(updatedSettings.addressRule, "Block")
    XCTAssertEqual(updatedSettings.domainRule, "Allow")
    updatedSettings.close()
  }
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
  static func launchCorrectionFixture() -> Self {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-corrections", "-AppleLanguages", "(en)"]
    app.launch()
    return Self(app: app)
  }
  func openFixture() -> DecisionScreen {
    let subject = app.staticTexts["activity.subject.00000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(subject.waitForExistence(timeout: 10))
    subject.click()
    XCTAssertTrue(app.buttons["correction.good"].waitForExistence(timeout: 5))
    return DecisionScreen(app: app)
  }
  func openAdvancedSettings() -> SettingsScreen {
    app.buttons["activity.settings"].click()
    // Native Settings toolbar tabs do not expose SwiftUI accessibility identifiers.
    let advanced = app.toolbars.buttons["Advanced"]
    XCTAssertTrue(advanced.waitForExistence(timeout: 5))
    advanced.click()
    return SettingsScreen(app: app)
  }
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
@MainActor private struct DecisionScreen {
  let app: XCUIApplication
  private var savedFailure: XCUIElement {
    app.staticTexts["activity.status"].descendants(matching: .staticText).matching(
      NSPredicate(format: "value CONTAINS %@", "Correction saved. Mail action: failed.")
    ).firstMatch
  }
  var correctionSavedWithActionFailure: Bool { savedFailure.waitForExistence(timeout: 5) }
  private func waitForCorrection(_ label: String) {
    let predicate = NSPredicate(format: "value CONTAINS %@", label)
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: predicate,
            object: app.staticTexts["correction.label"]
          )
        ],
        timeout: 5
      ),
      .completed
    )
  }
  func markGood() {
    app.buttons["correction.good"].click()
    waitForCorrection("inbox")
  }
  func markJunk() {
    app.buttons["correction.junk"].click()
    waitForCorrection("junk")
  }
  func allowDomain() {
    app.menuButtons["correction.domain"].click()
    app.menuItems["correction.domain.allow"].click()
    waitForCorrection("inbox")
  }
}
@MainActor private struct SettingsScreen {
  let app: XCUIApplication
  var addressRule: String {
    ruleValue("settings.rule.address.newsletter@example.org")
  }
  private func ruleValue(_ identifier: String) -> String {
    let rule = app.staticTexts[identifier]
    _ = rule.waitForExistence(timeout: 5)
    let text = rule.staticTexts.firstMatch
    return (text.exists ? text.value : rule.value) as? String ?? ""
  }
  var hasDomainRule: Bool { app.staticTexts["settings.rule.domain.example.org"].exists }
  var domainRule: String {
    ruleValue("settings.rule.domain.example.org")
  }
  func close() { app.typeKey("w", modifierFlags: .command) }
}

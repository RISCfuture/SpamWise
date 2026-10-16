import AppIntents
import XCTest

final class UITests: XCTestCase {
  @MainActor func testCorrectionsKeepRulesWhenMailActionFails() throws {
    continueAfterFailure = false
    let activity = ActivityScreen.launchCorrectionFixture()
    let statistics = activity.openStatistics()
    XCTAssertEqual(statistics.decisionCount, "1")
    statistics.close()
    let detail = activity.openFixture()
    detail.markGood()
    XCTAssertTrue(detail.correctionSavedWithActionFailure)
    let settings = activity.openRulesSettings()
    XCTAssertEqual(settings.addressRule, "Allow")
    XCTAssertFalse(settings.hasDomainRule)
    settings.close()
    detail.markJunk()
    XCTAssertTrue(detail.correctionSavedWithActionFailure)
    detail.allowDomain()
    XCTAssertTrue(detail.correctionSavedWithActionFailure)
    let updatedSettings = activity.openRulesSettings()
    XCTAssertEqual(updatedSettings.addressRule, "Block")
    XCTAssertEqual(updatedSettings.domainRule, "Allow")
    updatedSettings.close()
    detail.markReview()
    XCTAssertTrue(detail.correctionSavedWithActionFailure)
    let reviewedSettings = activity.openRulesSettings()
    XCTAssertFalse(reviewedSettings.hasAddressRule)
    XCTAssertEqual(reviewedSettings.domainRule, "Allow")
    let newRule = reviewedSettings.addAddressRule()
    XCTAssertFalse(newRule.canSave)
    newRule.enterAddress("newsletter@example.org")
    let addedSettings = newRule.save()
    XCTAssertEqual(addedSettings.addressRule, "Allow")
    let editedRule = addedSettings.editAddressRule()
    editedRule.blockSender()
    let editedSettings = editedRule.save()
    XCTAssertEqual(editedSettings.addressRule, "Block")
    XCTAssertEqual(editedSettings.domainRule, "Allow")
    editedSettings.close()
  }

  @MainActor func testOnboardingAndOfflineActivity() throws {
    continueAfterFailure = false
    let introduction = IntroductionScreen.launchOffline()
    XCTAssertTrue(introduction.isVisible)
    let credential = introduction.continueSetup()
    XCTAssertTrue(credential.isVisible)
    let mail = credential.continueSetup()
    mail.checkDeniedPermission()
    XCTAssertTrue(mail.hasPermissionDeniedStatus)
    let finish = mail.continueSetup()
    let activity = finish.finish()
    XCTAssertTrue(activity.isDryRun)
    activity.pause()
    XCTAssertTrue(activity.isPaused)
  }
}

private enum UITestTiming {
  static let launch: TimeInterval = 10
  static let transition: TimeInterval = 5
}

@MainActor private struct IntroductionScreen {
  let app: XCUIApplication

  var isVisible: Bool { app.staticTexts["setup.intro"].exists }

  static func launchOffline() -> Self {
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-testing", "-AppleLanguages", "(en)"
    ]
    app.launch()
    XCTAssertTrue(app.staticTexts["setup.intro"].waitForExistence(timeout: UITestTiming.launch))
    return Self(app: app)
  }

  func continueSetup() -> CredentialScreen {
    app.buttons["setup.continue"].click()
    XCTAssertTrue(
      app.secureTextFields["setup.key"].waitForExistence(timeout: UITestTiming.transition)
    )
    return CredentialScreen(app: app)
  }
}

@MainActor private struct CredentialScreen {
  let app: XCUIApplication

  var isVisible: Bool { app.secureTextFields["setup.key"].exists }

  func continueSetup() -> MailSetupScreen {
    app.buttons["setup.continue"].click()
    XCTAssertTrue(app.buttons["mail.check"].waitForExistence(timeout: UITestTiming.transition))
    return MailSetupScreen(app: app)
  }
}

@MainActor private struct MailSetupScreen {
  let app: XCUIApplication

  var hasPermissionDeniedStatus: Bool { app.staticTexts["mail.permissionDenied"].exists }

  func checkDeniedPermission() {
    app.buttons["mail.check"].click()
    XCTAssertTrue(
      app.staticTexts["mail.permissionDenied"].waitForExistence(timeout: UITestTiming.transition)
    )
  }

  func continueSetup() -> FinishSetupScreen {
    app.buttons["setup.continue"].click()
    XCTAssertTrue(app.buttons["setup.finish"].waitForExistence(timeout: UITestTiming.transition))
    return FinishSetupScreen(app: app)
  }
}

@MainActor private struct FinishSetupScreen {
  let app: XCUIApplication

  func finish() -> ActivityScreen {
    app.buttons["setup.finish"].click()
    return ActivityScreen.waitForLanding(in: app)
  }
}

@MainActor private struct ActivityScreen {
  let app: XCUIApplication

  var isDryRun: Bool { app.staticTexts["activity.mode"].value as? String == "dryRun" }
  var isPaused: Bool { app.staticTexts["activity.mode"].value as? String == "paused" }

  static func launchCorrectionFixture() -> Self {
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-testing", "--ui-corrections", "-AppleLanguages", "(en)"
    ]
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

  func openStatistics() -> StatisticsScreen {
    app.buttons["activity.statistics"].click()
    XCTAssertTrue(
      app.staticTexts["statistics.decisions"].waitForExistence(timeout: UITestTiming.transition)
    )
    return StatisticsScreen(app: app)
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

@MainActor private struct StatisticsScreen {
  let app: XCUIApplication
  var decisionCount: String { app.staticTexts["statistics.decisions"].value as? String ?? "" }
  func close() {
    app.buttons["statistics.done"].click()
    XCTAssertTrue(
      app.buttons["activity.statistics"].waitForExistence(timeout: UITestTiming.transition)
    )
  }
}

@MainActor private struct DecisionScreen {
  let app: XCUIApplication

  var correctionSavedWithActionFailure: Bool {
    let status = app.staticTexts["activity.status"]
    guard status.waitForExistence(timeout: UITestTiming.transition) else { return false }
    let text = status.staticTexts.firstMatch
    return XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(
            format: "value CONTAINS[c] %@",
            "Correction saved. Mail action: failed."
          ),
          object: text.exists ? text : status
        )
      ],
      timeout: UITestTiming.transition
    ) == .completed
  }

  func markGood() {
    app.buttons["correction.good"].click()
    waitForCorrection("inbox")
  }

  func markJunk() {
    app.buttons["correction.junk"].click()
    waitForCorrection("junk")
  }

  func markReview() {
    app.buttons["correction.review"].click()
    waitForCorrection("review")
  }

  func allowDomain() {
    app.menuButtons["correction.domain"].click()
    app.menuItems["correction.domain.allow"].click()
    waitForCorrection("inbox")
  }

  private func waitForCorrection(_ label: String) {
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", label),
            object: app.staticTexts["correction.label"]
          )
        ],
        timeout: UITestTiming.transition
      ),
      .completed
    )
  }
}

@MainActor private struct RulesScreen {
  let app: XCUIApplication

  var addressRule: String { ruleValue("settings.rule.address.newsletter@example.org") }
  var domainRule: String { ruleValue("settings.rule.domain.example.org") }
  var hasDomainRule: Bool { app.staticTexts["settings.rule.domain.example.org"].exists }
  var hasAddressRule: Bool {
    app.staticTexts["settings.rule.address.newsletter@example.org"].exists
  }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(app.buttons["rules.add"].waitForExistence(timeout: UITestTiming.transition))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: app.buttons["rules.add"]
          )
        ],
        timeout: UITestTiming.transition
      ),
      .completed
    )
    return Self(app: app)
  }

  func addAddressRule() -> RuleFormScreen {
    app.buttons["rules.add"].click()
    return RuleFormScreen.waitForLanding(in: app)
  }

  func editAddressRule() -> RuleFormScreen {
    app.staticTexts["settings.rule.address.newsletter@example.org"].click()
    app.buttons["rules.edit"].click()
    return RuleFormScreen.waitForLanding(in: app)
  }

  @discardableResult
  func close() -> ActivityScreen {
    app.typeKey("w", modifierFlags: .command)
    return ActivityScreen.waitForLanding(in: app)
  }

  private func ruleValue(_ identifier: String) -> String {
    let rule = app.staticTexts[identifier]
    XCTAssertTrue(rule.waitForExistence(timeout: UITestTiming.transition))
    let text = rule.staticTexts.firstMatch
    return (text.exists ? text.value : rule.value) as? String ?? ""
  }
}

@MainActor private struct RuleFormScreen {
  let app: XCUIApplication

  var canSave: Bool { app.buttons["rules.save"].isEnabled }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(app.textFields["rules.value"].waitForExistence(timeout: UITestTiming.transition))
    return Self(app: app)
  }

  func enterAddress(_ address: String) {
    app.textFields["rules.value"].click()
    app.textFields["rules.value"].typeText(address)
  }

  func blockSender() {
    app.popUpButtons["rules.action"].click()
    let block = app.menuItems["rules.action.block"]
    XCTAssertTrue(block.waitForExistence(timeout: UITestTiming.transition))
    block.click()
  }

  func save() -> RulesScreen {
    app.buttons["rules.save"].click()
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.buttons["rules.save"]
          )
        ],
        timeout: UITestTiming.transition
      ),
      .completed
    )
    return RulesScreen.waitForLanding(in: app)
  }
}

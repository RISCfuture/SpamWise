import XCTest

/// Mail action outcomes, as the correction status identifies them in `correction.status.<outcome>`.
enum MailActionOutcome: String {
  case applied, failed
}

/// The inspector for one recorded decision.
@MainActor
struct DecisionScreen {
  let app: XCUIApplication

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(app.buttons["correction.good"].waitForExistence(timeout: UITestTiming.transition))
    return Self(app: app)
  }

  /// Waits until the inspector shows no threat assessment, as when no detector ran.
  func waitForNoThreatAssessment() -> Bool {
    app.descendants(matching: .any).identified(byPrefix: "threats.").waitForCount(0)
  }

  /// Waits until the latest correction is saved and its Mail action ends with `outcome`.
  func waitForMailAction(_ outcome: MailActionOutcome) -> Bool {
    app.descendants(matching: .any)["correction.status.\(outcome.rawValue)"]
      .waitForExistence(timeout: UITestTiming.transition)
  }

  func markGood() {
    app.buttons["correction.good"].click()
    waitForCorrection("inbox")
  }

  /// Marks the message Junk, confirming the warning about its unverified sender.
  func markJunk() {
    app.buttons["correction.junk"].click()
    let blockAnyway = app.buttons["correction.warning.confirm"]
    XCTAssertTrue(blockAnyway.waitForExistence(timeout: UITestTiming.transition))
    blockAnyway.click()
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

  func undoLatestCorrection() {
    let undo = app.buttons["correction.undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: UITestTiming.transition))
    undo.click()
    let confirm = app.buttons["correction.undo.confirm"]
    XCTAssertTrue(confirm.waitForExistence(timeout: UITestTiming.transition))
    confirm.click()
    XCTAssertTrue(undo.waitForNonExistence(timeout: UITestTiming.transition))
  }

  private func waitForCorrection(_ label: String) {
    XCTAssertTrue(
      app.staticTexts["correction.label.\(label)"].waitForExistence(
        timeout: UITestTiming.transition
      )
    )
  }
}

/// Rule actions, as each rule row identifies them in `settings.rule.<scope>.<sender>.<action>`.
enum SenderRuleAction: String {
  case allow, block
}

/// The sender rules in the Rules settings tab.
@MainActor
struct RulesScreen {
  private static let address = "newsletter@example.org"
  private static let domain = "example.org"
  let app: XCUIApplication

  static func waitForLanding(in app: XCUIApplication) -> Self {
    let add = app.buttons["rules.add"]
    XCTAssertTrue(add.waitForExistence(timeout: UITestTiming.transition))
    XCTAssertTrue(add.waitForEnabled(true))
    return Self(app: app)
  }

  /// Waits until the fixture sender's address rule has `action`.
  func waitForAddressRule(_ action: SenderRuleAction) -> Bool {
    rule("address", Self.address, action).waitForExistence(timeout: UITestTiming.transition)
  }

  /// Waits until the fixture sender's domain rule has `action`.
  func waitForDomainRule(_ action: SenderRuleAction) -> Bool {
    rule("domain", Self.domain, action).waitForExistence(timeout: UITestTiming.transition)
  }

  func waitForNoAddressRule() -> Bool { rules("address", Self.address).waitForCount(0) }

  func waitForNoDomainRule() -> Bool { rules("domain", Self.domain).waitForCount(0) }

  func addAddressRule() -> RuleFormScreen {
    app.buttons["rules.add"].click()
    return RuleFormScreen.waitForLanding(in: app)
  }

  func editAddressRule() -> RuleFormScreen {
    let rule = rules("address", Self.address).firstMatch
    XCTAssertTrue(rule.waitForExistence(timeout: UITestTiming.transition))
    rule.click()
    app.buttons["rules.edit"].click()
    return RuleFormScreen.waitForLanding(in: app)
  }

  func close() -> ActivityScreen {
    app.typeKey("w", modifierFlags: .command)
    return ActivityScreen.waitForLanding(in: app)
  }

  private func rule(_ scope: String, _ sender: String, _ action: SenderRuleAction) -> XCUIElement {
    app.staticTexts["settings.rule.\(scope).\(sender).\(action.rawValue)"]
  }

  private func rules(_ scope: String, _ sender: String) -> XCUIElementQuery {
    app.staticTexts.identified(byPrefix: "settings.rule.\(scope).\(sender).")
  }
}

/// The sheet that adds or edits one sender rule.
@MainActor
struct RuleFormScreen {
  let app: XCUIApplication

  private var saveButton: XCUIElement { app.buttons["rules.save"] }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(app.textFields["rules.value"].waitForExistence(timeout: UITestTiming.transition))
    return Self(app: app)
  }

  /// Waits until Save is enabled or disabled.
  func waitForSaveEnabled(_ isEnabled: Bool) -> Bool { saveButton.waitForEnabled(isEnabled) }

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
    saveButton.click()
    XCTAssertTrue(saveButton.waitForNonExistence(timeout: UITestTiming.transition))
    return RulesScreen.waitForLanding(in: app)
  }
}

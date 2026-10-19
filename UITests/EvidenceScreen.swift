import XCTest

/// The Spamhaus controls in the Advanced settings tab.
@MainActor
struct EvidenceScreen {
  let app: XCUIApplication

  private var termsNotice: XCUIElement {
    app.descendants(matching: .any)["spamhaus.consentRequired"]
  }
  private var queryKeyField: XCUIElement { app.secureTextFields["spamhaus.key"] }
  private var consent: XCUIElement { app.switches["spamhaus.consent"] }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(
      app.switches["spamhaus.enabled"].waitForExistence(timeout: UITestTiming.transition)
    )
    return Self(app: app)
  }

  /// Waits until the notice asking to accept Spamhaus's terms is shown or hidden.
  func waitForTermsNotice(_ isShown: Bool) -> Bool {
    isShown
      ? termsNotice.waitForExistence(timeout: UITestTiming.transition)
      : termsNotice.waitForNonExistence(timeout: UITestTiming.transition)
  }

  /// Waits until the terms switch is on or off.
  func waitForTermsAccepted(_ isAccepted: Bool) -> Bool { consent.waitForSwitch(isAccepted) }

  /// Waits until the secure query-key field is shown or hidden.
  func waitForQueryKeyField(_ isShown: Bool) -> Bool {
    isShown
      ? queryKeyField.waitForExistence(timeout: UITestTiming.transition)
      : queryKeyField.waitForNonExistence(timeout: UITestTiming.transition)
  }

  /// Waits until the query key's Save button is enabled or disabled.
  func waitForQueryKeySaveEnabled(_ isEnabled: Bool) -> Bool {
    app.buttons["spamhaus.saveKey"].waitForEnabled(isEnabled)
  }

  func enableSpamhaus() {
    app.switches["spamhaus.enabled"].click()
    XCTAssertTrue(
      app.popUpButtons["spamhaus.transport"].waitForExistence(timeout: UITestTiming.transition)
    )
  }

  func acceptTerms() {
    consent.scrollIntoViewAndClick(
      within: app.scrollViews.containing(.switch, identifier: "spamhaus.consent").firstMatch
    )
    XCTAssertTrue(waitForTermsAccepted(true))
  }

  func selectHTTPS() { selectService("spamhaus.transport.https") }

  func selectPublicDNS() { selectService("spamhaus.transport.publicDNS") }

  func close() -> ActivityScreen {
    app.typeKey("w", modifierFlags: .command)
    return ActivityScreen.waitForLanding(in: app)
  }

  private func selectService(_ identifier: String) {
    app.popUpButtons["spamhaus.transport"].click()
    let service = app.menuItems[identifier]
    XCTAssertTrue(service.waitForExistence(timeout: UITestTiming.transition))
    service.click()
  }
}

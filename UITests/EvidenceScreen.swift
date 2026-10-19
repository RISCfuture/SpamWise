import XCTest

@MainActor
struct EvidenceScreen {
  let app: XCUIApplication

  var termsNotice: XCUIElement { app.descendants(matching: .any)["spamhaus.consentRequired"] }
  var canSaveQueryKey: Bool { app.buttons["spamhaus.saveKey"].isEnabled }
  var hasSecureQueryKeyField: Bool { app.secureTextFields["spamhaus.key"].exists }
  var hasAcceptedTerms: Bool {
    (app.switches["spamhaus.consent"].value as? NSNumber)?.boolValue == true
  }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(
      app.switches["spamhaus.enabled"].waitForExistence(timeout: UITestTiming.transition)
    )
    return Self(app: app)
  }

  func enableSpamhaus() {
    app.switches["spamhaus.enabled"].click()
    XCTAssertTrue(
      app.popUpButtons["spamhaus.transport"].waitForExistence(timeout: UITestTiming.transition)
    )
  }

  func acceptTerms() {
    app.switches["spamhaus.consent"].click()
    XCTAssertTrue(termsNotice.waitForNonExistence(timeout: UITestTiming.transition))
  }

  func selectHTTPS() {
    selectService("spamhaus.transport.https")
    XCTAssertTrue(
      app.secureTextFields["spamhaus.key"].waitForExistence(timeout: UITestTiming.transition)
    )
  }

  func selectPublicDNS() {
    selectService("spamhaus.transport.publicDNS")
  }

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

extension UITests {
  @MainActor
  func testSpamhausConsentTracksSelectedService() throws {
    continueAfterFailure = false
    let activity = ActivityScreen.launchCorrectionFixture()
    let evidence = activity.openEvidenceSettings()
    evidence.enableSpamhaus()
    XCTAssertTrue(evidence.termsNotice.exists)
    evidence.acceptTerms()
    evidence.selectHTTPS()
    XCTAssertTrue(evidence.hasSecureQueryKeyField)
    XCTAssertFalse(evidence.canSaveQueryKey)
    XCTAssertFalse(evidence.hasAcceptedTerms)
    XCTAssertTrue(evidence.termsNotice.exists)
    evidence.acceptTerms()
    let reopened = evidence.close().openEvidenceSettings()
    XCTAssertTrue(reopened.hasSecureQueryKeyField)
    XCTAssertTrue(reopened.hasAcceptedTerms)
    reopened.selectPublicDNS()
    XCTAssertFalse(reopened.hasSecureQueryKeyField)
    XCTAssertFalse(reopened.hasAcceptedTerms)
    XCTAssertTrue(reopened.termsNotice.exists)
  }
}

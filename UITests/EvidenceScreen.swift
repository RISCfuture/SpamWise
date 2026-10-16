import XCTest

@MainActor struct EvidenceScreen {
  let app: XCUIApplication

  var canSave: Bool { app.buttons["evidence.save"].isEnabled }
  var canSaveQueryKey: Bool { app.buttons["spamhaus.saveKey"].isEnabled }
  var hasSecureQueryKeyField: Bool { app.secureTextFields["spamhaus.key"].exists }
  var hasAcceptedTerms: Bool {
    (app.switches["spamhaus.consent"].value as? NSNumber)?.boolValue == true
  }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    let disclosure = app.disclosureTriangles["evidence.disclosure"]
    XCTAssertTrue(disclosure.waitForExistence(timeout: UITestTiming.transition))
    if !app.switches["spamhaus.enabled"].exists {
      disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).click()
    }
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

  func save() {
    app.buttons["evidence.save"].click()
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
  @MainActor func testSpamhausConsentTracksSelectedService() throws {
    continueAfterFailure = false
    let activity = ActivityScreen.launchCorrectionFixture()
    let evidence = activity.openEvidenceSettings()
    evidence.enableSpamhaus()
    XCTAssertFalse(evidence.canSave)
    evidence.acceptTerms()
    XCTAssertTrue(evidence.canSave)
    evidence.selectHTTPS()
    XCTAssertTrue(evidence.hasSecureQueryKeyField)
    XCTAssertFalse(evidence.canSaveQueryKey)
    XCTAssertFalse(evidence.hasAcceptedTerms)
    XCTAssertFalse(evidence.canSave)
    evidence.acceptTerms()
    evidence.save()
    let reopened = evidence.close().openEvidenceSettings()
    XCTAssertTrue(reopened.hasSecureQueryKeyField)
    XCTAssertTrue(reopened.hasAcceptedTerms)
    reopened.selectPublicDNS()
    XCTAssertFalse(reopened.hasSecureQueryKeyField)
    XCTAssertFalse(reopened.hasAcceptedTerms)
    XCTAssertFalse(reopened.canSave)
  }

}

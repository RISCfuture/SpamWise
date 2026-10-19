import XCTest

@MainActor
struct IntroductionScreen {
  let app: XCUIApplication

  /// Launches first-run setup with isolated storage and a Mail connection that is always denied.
  static func launchOffline() -> Self {
    let app = UITestApplication.launch(arguments: ["--ui-testing"])
    XCTAssertTrue(app.staticTexts["setup.intro"].waitForExistence(timeout: UITestTiming.launch))
    return Self(app: app)
  }

  func continueSetup() -> CredentialScreen {
    app.buttons["setup.continue"].click()
    return CredentialScreen.waitForLanding(in: app)
  }

  /// Goes through every setup step without a provider or Mail permission.
  func completeOfflineSetup() -> ActivityScreen {
    let mail = continueSetup().continueSetup()
    mail.checkMailPermission()
    XCTAssertTrue(mail.waitForPermissionDenied())
    return mail.continueSetup().finish()
  }
}

@MainActor
struct CredentialScreen {
  let app: XCUIApplication

  private var consent: XCUIElement { app.switches["provider.consent"] }

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(
      app.secureTextFields["setup.key"].waitForExistence(timeout: UITestTiming.transition)
    )
    return Self(app: app)
  }

  /// Waits until the provider mail-sharing switch is on or off.
  func waitForMailSharing(_ isOn: Bool) -> Bool { consent.waitForSwitch(isOn) }

  func toggleMailSharing() { consent.click() }

  func continueSetup() -> MailSetupScreen {
    app.buttons["setup.continue"].click()
    return MailSetupScreen.waitForLanding(in: app)
  }
}

@MainActor
struct MailSetupScreen {
  let app: XCUIApplication

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(app.buttons["mail.check"].waitForExistence(timeout: UITestTiming.transition))
    return Self(app: app)
  }

  func checkMailPermission() { app.buttons["mail.check"].click() }

  /// Waits for the status that reports Mail permission as denied.
  func waitForPermissionDenied() -> Bool {
    app.staticTexts["mail.permissionDenied"].waitForExistence(timeout: UITestTiming.transition)
  }

  func continueSetup() -> FinishSetupScreen {
    app.buttons["setup.continue"].click()
    return FinishSetupScreen.waitForLanding(in: app)
  }
}

@MainActor
struct FinishSetupScreen {
  let app: XCUIApplication

  static func waitForLanding(in app: XCUIApplication) -> Self {
    XCTAssertTrue(app.buttons["setup.finish"].waitForExistence(timeout: UITestTiming.transition))
    return Self(app: app)
  }

  func finish() -> ActivityScreen {
    app.buttons["setup.finish"].click()
    return ActivityScreen.waitForLanding(in: app)
  }
}

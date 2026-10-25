import XCTest

/// First-run setup without a provider or Mail permission.
final class OnboardingTests: UITestCase {
  @MainActor
  func testProviderMailSharingStartsOffAndFollowsItsSwitch() {
    let credential = IntroductionScreen.launchOffline().continueSetup()
    XCTAssertTrue(credential.waitForMailSharing(false))
    credential.toggleMailSharing()
    XCTAssertTrue(credential.waitForMailSharing(true))
    credential.toggleMailSharing()
    XCTAssertTrue(credential.waitForMailSharing(false))
  }

  @MainActor
  func testMailStepReportsDeniedPermission() {
    let mail = IntroductionScreen.launchOffline().continueSetup().continueSetup()
    mail.checkMailPermission()
    XCTAssertTrue(mail.waitForPermissionDenied())
  }

  @MainActor
  func testSetupPreferenceAppliesInSettings() {
    let mail = IntroductionScreen.launchOffline().continueSetup().continueSetup()
    let preferences = mail.continueSetup()
    XCTAssertTrue(preferences.waitForChoice(.flag, for: "promotion"))
    preferences.choose(.junk, for: "promotion")
    let settings = preferences.continueSetup().finish().openPreferencesSettings()
    XCTAssertTrue(settings.waitForChoice(.junk, for: "promotion"))
  }

  @MainActor
  func testFinishingWithoutMailPermissionShowsMailNotAuthorized() {
    let activity = IntroductionScreen.launchOffline().completeOfflineSetup()
    XCTAssertTrue(activity.waitForMode(.mailNotAuthorized))
  }

  @MainActor
  func testDryRunStaysOnAndLockedWithoutMailPermission() {
    let settings = IntroductionScreen.launchOffline().completeOfflineSetup().openGeneralSettings()
    XCTAssertTrue(settings.waitForDryRun(true))
    XCTAssertTrue(settings.waitForDryRunChangeable(false))
  }

  @MainActor
  func testSettingsMailCheckReportsDeniedPermission() {
    let settings = IntroductionScreen.launchOffline().completeOfflineSetup().openGeneralSettings()
    settings.checkMailConnection()
    XCTAssertTrue(settings.waitForMailPermissionDenied())
  }

  @MainActor
  func testPausingShowsPausedMode() {
    let activity = IntroductionScreen.launchOffline().completeOfflineSetup()
    activity.pause()
    XCTAssertTrue(activity.waitForMode(.paused))
  }
}

import XCTest

/// Leaving dry run, which the app confirms first.
final class DryRunTests: UITestCase {
  @MainActor
  func testCancellingLiveFilteringKeepsDryRunOn() {
    let settings = ActivityScreen.launchCorrectionFixture().openGeneralSettings()
    settings.turnOnDryRun()
    let cancelled = settings.requestLiveFiltering().cancel()
    XCTAssertTrue(cancelled.waitForDryRun(true))
  }

  @MainActor
  func testConfirmingLiveFilteringFromSettingsOrActivityResumesFiltering() {
    let settings = ActivityScreen.launchCorrectionFixture().openGeneralSettings()
    settings.turnOnDryRun()
    let confirmed = settings.requestLiveFiltering().confirm()
    XCTAssertTrue(confirmed.waitForDryRun(false))
    confirmed.turnOnDryRun()
    let activity = confirmed.close().startFiltering().confirmFromActivity()
    XCTAssertTrue(activity.waitForMode(.filtering))
  }
}

/// Hiding the menu bar item, after which Activity stays reachable.
final class MenuBarItemTests: UITestCase {
  @MainActor
  func testActivityReopensFromItsURLWithTheMenuBarItemHidden() {
    let settings = ActivityScreen.launchCorrectionFixture().openGeneralSettings()
    settings.hideMenuBarItem()
    let activity = settings.close()
    activity.close()
    XCTAssertTrue(activity.reopenFromURL())
  }
}

/// Spamhaus domain lookups, whose terms must be accepted again for each service.
final class SpamhausSettingsTests: UITestCase {
  @MainActor
  func testEnablingSpamhausAsksToAcceptItsTerms() {
    let evidence = ActivityScreen.launchCorrectionFixture().openEvidenceSettings()
    evidence.enableSpamhaus()
    XCTAssertTrue(evidence.waitForTermsNotice(true))
    evidence.acceptTerms()
    XCTAssertTrue(evidence.waitForTermsNotice(false))
  }

  @MainActor
  func testSwitchingToHTTPSResetsConsentAndAsksForAQueryKey() {
    let evidence = ActivityScreen.launchCorrectionFixture().openEvidenceSettings()
    evidence.enableSpamhaus()
    evidence.acceptTerms()
    evidence.selectHTTPS()
    XCTAssertTrue(evidence.waitForQueryKeyField(true))
    XCTAssertTrue(evidence.waitForQueryKeySaveEnabled(false))
    XCTAssertTrue(evidence.waitForTermsAccepted(false))
    XCTAssertTrue(evidence.waitForTermsNotice(true))
  }

  @MainActor
  func testHTTPSServiceAndConsentPersistAfterReopening() {
    let evidence = ActivityScreen.launchCorrectionFixture().openEvidenceSettings()
    evidence.enableSpamhaus()
    evidence.selectHTTPS()
    evidence.acceptTerms()
    let reopened = evidence.close().openEvidenceSettings()
    XCTAssertTrue(reopened.waitForQueryKeyField(true))
    XCTAssertTrue(reopened.waitForTermsAccepted(true))
  }

  @MainActor
  func testSwitchingBackToPublicDNSResetsConsentAndHidesTheQueryKey() {
    let evidence = ActivityScreen.launchCorrectionFixture().openEvidenceSettings()
    evidence.enableSpamhaus()
    evidence.selectHTTPS()
    evidence.acceptTerms()
    evidence.selectPublicDNS()
    XCTAssertTrue(evidence.waitForQueryKeyField(false))
    XCTAssertTrue(evidence.waitForTermsAccepted(false))
    XCTAssertTrue(evidence.waitForTermsNotice(true))
  }
}

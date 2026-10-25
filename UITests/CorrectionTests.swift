import XCTest

/// Corrections of the fixture's recorded Junk decision while every Mail action fails.
final class CorrectionTests: UITestCase {
  @MainActor
  func testStatisticsCountTheRecordedDecisionAndHideTheSelectionFromCorrections() {
    let activity = ActivityScreen.launchCorrectionFixture()
    _ = activity.openFixture()
    XCTAssertTrue(activity.canMarkSelectionAsJunk())
    let statistics = activity.openStatistics()
    XCTAssertTrue(statistics.waitForDecisionCount(1))
    XCTAssertFalse(activity.canMarkSelectionAsJunk())
  }

  @MainActor
  func testInspectorOmitsThreatAssessmentWhenNoDetectorRan() {
    let detail = ActivityScreen.launchCorrectionFixture().openFixture()
    XCTAssertTrue(detail.waitForNoThreatAssessment())
  }

  @MainActor
  func testGoodCorrectionSavesAllowRuleDespiteFailedMailAction() {
    let activity = ActivityScreen.launchCorrectionFixture()
    let detail = activity.openFixture()
    detail.markGood()
    XCTAssertTrue(detail.waitForMailAction(.failed))
    let rules = activity.openRulesSettings()
    XCTAssertTrue(rules.waitForAddressRule(.allow))
    XCTAssertTrue(rules.waitForNoDomainRule())
  }

  @MainActor
  func testJunkCorrectionReplacesAllowRuleWithBlock() {
    let activity = ActivityScreen.launchCorrectionFixture()
    let detail = activity.openFixture()
    detail.markGood()
    detail.markJunk()
    XCTAssertTrue(detail.waitForMailAction(.failed))
    let rules = activity.openRulesSettings()
    XCTAssertTrue(rules.waitForAddressRule(.block))
    XCTAssertTrue(rules.waitForNoDomainRule())
  }

  @MainActor
  func testDomainCorrectionReplacesTheContradictingAddressRule() {
    let activity = ActivityScreen.launchCorrectionFixture()
    let detail = activity.openFixture()
    detail.markJunk()
    detail.allowDomain()
    XCTAssertTrue(detail.waitForMailAction(.failed))
    let rules = activity.openRulesSettings()
    XCTAssertTrue(rules.waitForNoAddressRule())
    XCTAssertTrue(rules.waitForDomainRule(.allow))
  }

  @MainActor
  func testDomainCorrectionKeepsAnAgreeingAddressRule() {
    let activity = ActivityScreen.launchCorrectionFixture()
    let detail = activity.openFixture()
    detail.markGood()
    detail.allowDomain()
    XCTAssertTrue(detail.waitForMailAction(.failed))
    let rules = activity.openRulesSettings()
    XCTAssertTrue(rules.waitForAddressRule(.allow))
    XCTAssertTrue(rules.waitForDomainRule(.allow))
  }

  @MainActor
  func testReviewCorrectionRemovesOnlyTheAddressRule() {
    let activity = ActivityScreen.launchCorrectionFixture()
    let detail = activity.openFixture()
    detail.markGood()
    detail.allowDomain()
    detail.markReview()
    XCTAssertTrue(detail.waitForMailAction(.failed))
    let rules = activity.openRulesSettings()
    XCTAssertTrue(rules.waitForNoAddressRule())
    XCTAssertTrue(rules.waitForDomainRule(.allow))
  }

  @MainActor
  func testUndoRestoresRulesFromBeforeTheLatestCorrection() {
    let activity = ActivityScreen.launchCorrectionFixture()
    let detail = activity.openFixture()
    detail.markJunk()
    detail.markGood()
    detail.undoLatestCorrection()
    XCTAssertTrue(activity.openRulesSettings().waitForAddressRule(.block))
  }

  @MainActor
  func testForgettingReviewedMessageKeepsItsSenderRule() {
    let activity = ActivityScreen.launchCorrectionFixture()
    activity.openFixture().markJunk()
    let corpus = activity.openCorpus()
    XCTAssertTrue(corpus.waitForLabelCount(1))
    corpus.forgetFirstExample()
    XCTAssertTrue(corpus.waitForLabelCount(0))
    XCTAssertTrue(corpus.close().openRulesSettings().waitForAddressRule(.block))
  }
}

/// Sender rules added and edited by hand in the Rules settings tab.
final class SenderRuleEditingTests: UITestCase {
  @MainActor
  func testNewRuleNeedsAnAddressAndAllowsBySender() {
    let rules = ActivityScreen.launchCorrectionFixture().openRulesSettings()
    let form = rules.addAddressRule()
    XCTAssertTrue(form.waitForSaveEnabled(false))
    form.enterAddress("newsletter@example.org")
    XCTAssertTrue(form.save().waitForAddressRule(.allow))
  }

  @MainActor
  func testEditingRuleCanBlockTheSender() {
    let rules = ActivityScreen.launchCorrectionFixture().openRulesSettings()
    let form = rules.addAddressRule()
    form.enterAddress("newsletter@example.org")
    let edited = form.save().editAddressRule()
    edited.blockSender()
    XCTAssertTrue(edited.save().waitForAddressRule(.block))
  }
}

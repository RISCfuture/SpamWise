import XCTest

/// How long the UI tests wait for the app to respond.
enum UITestTiming {
  /// The wait for a freshly launched app to show its first screen.
  static let launch: TimeInterval = 10
  /// The wait for a click or keystroke to take visible effect.
  static let transition: TimeInterval = 5
}

/**
 The app under test, launched from a registered fixture path when one is supplied.

 The app runs in the user's preferred language unless `SPAMWISE_UI_TEST_LANGUAGE` names another
 of its localizations, such as `es`; pass it to `xcodebuild` as
 `TEST_RUNNER_SPAMWISE_UI_TEST_LANGUAGE`.
 */
@MainActor
enum UITestApplication {
  /// The environment variable that names a registered signed fixture app.
  nonisolated static let registeredAppPathVariable = "SPAMWISE_INTENTS_APP_PATH"
  private static let languageVariable = "SPAMWISE_UI_TEST_LANGUAGE"
  private static let appName = "SpamWise.app"
  private static let sharedFrameworkPath = "Contents/Frameworks/SpamWiseCommon.framework"

  /// The app bundle the tests launch: the registered fixture, or the built product.
  static var bundleURL: URL {
    registeredAppURL ?? productsDirectory.appending(path: appName)
  }

  /// The bundle holding the app's String Catalog, narrowed to the requested language if any.
  static var stringsBundle: Bundle? {
    let bundle = Bundle(url: bundleURL.appending(path: sharedFrameworkPath))
    guard let language, let localization = bundle?.path(forResource: language, ofType: "lproj")
    else { return bundle }
    return Bundle(path: localization)
  }

  private static var registeredAppURL: URL? {
    ProcessInfo.processInfo.environment[registeredAppPathVariable].map { URL(filePath: $0) }
  }

  private static var language: String? { ProcessInfo.processInfo.environment[languageVariable] }

  /// The build products directory, which holds both this runner and the app.
  private static var productsDirectory: URL {
    // The test bundle is <products>/UITests-Runner.app/Contents/PlugIns/UITests.xctest.
    Bundle(for: UITestCase.self).bundleURL
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
  }

  /// An app launched with `arguments`, in the requested language if any.
  static func launch(arguments: [String]) -> XCUIApplication {
    let app = registeredAppURL.map { XCUIApplication(url: $0) } ?? XCUIApplication()
    app.launchArguments = arguments + (language.map { ["-AppleLanguages", "(\($0))"] } ?? [])
    app.launch()
    return app
  }
}

/**
 Text the app shows, looked up in its String Catalog.

 The catalog is read in the app's language: the requested one, or else the user's preferred
 language, which the app and this runner share. Tests look up text only where the framework
 exposes nothing else, such as the titles of native Settings tabs.
 */
@MainActor
enum AppText {
  /// The app's translation of `key`, or `key` itself when the catalog has none.
  static func localized(_ key: String) -> String {
    UITestApplication.stringsBundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
  }
}

/// A UI test that stops at its first failure, since later steps depend on earlier screens.
class UITestCase: XCTestCase {  // swiftlint:disable:this final_test_case
  override func setUpWithError() throws {
    try super.setUpWithError()
    continueAfterFailure = false
  }
}

@MainActor
extension XCUIElement {
  private static let maximumScrolls = 10
  private static let scrollStep: CGFloat = 120

  /// Clicks the element after scrolling `scrollView` until it is on screen, which macOS UI tests
  /// don't do before a click.
  func scrollIntoViewAndClick(within scrollView: XCUIElement) {
    for direction: CGFloat in [-1, 1] {
      for _ in 0..<Self.maximumScrolls where !isHittable {
        scrollView.scroll(byDeltaX: 0, deltaY: direction * Self.scrollStep)
      }
    }
    click()
  }

  /// Waits until `predicate` holds for this element.
  func wait(until predicate: NSPredicate, timeout: TimeInterval = UITestTiming.transition) -> Bool {
    XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: predicate, object: self)],
      timeout: timeout
    ) == .completed
  }

  /// Waits until a switch is on or off.
  func waitForSwitch(_ isOn: Bool, timeout: TimeInterval = UITestTiming.transition) -> Bool {
    wait(until: NSPredicate(format: "value == %@", NSNumber(value: isOn)), timeout: timeout)
  }

  /// Waits until the element is enabled or disabled.
  func waitForEnabled(_ isEnabled: Bool, timeout: TimeInterval = UITestTiming.transition) -> Bool {
    wait(for: \.isEnabled, toEqual: isEnabled, timeout: timeout)
  }

  /// Waits until the element, such as a segment, is selected.
  func waitForSelection(timeout: TimeInterval = UITestTiming.transition) -> Bool {
    wait(until: NSPredicate(format: "selected == YES OR value == 1"), timeout: timeout)
  }
}

@MainActor
extension XCUIElementQuery {
  /// Waits until the query matches exactly `count` elements.
  func waitForCount(_ count: Int, timeout: TimeInterval = UITestTiming.transition) -> Bool {
    XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "count == %@", NSNumber(value: count)),
          object: self
        )
      ],
      timeout: timeout
    ) == .completed
  }

  /// The elements whose identifier starts with `prefix`, for identifiers that end in a state.
  func identified(byPrefix prefix: String) -> XCUIElementQuery {
    matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
  }
}

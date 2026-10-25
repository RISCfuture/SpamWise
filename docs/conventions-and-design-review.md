# Conventions and design decisions

The authoritative code conventions are the owner's `swift-conventions` and
`swiftui-conventions` skills. This page records how SpamWise applies them and the
interface design they produced, so a change can stay consistent without re-deriving
either. It is not a per-file review record. Vendor packages, generated build output,
fixture messages and the bundled Public Suffix List are data or dependencies, not
application code.

Apple's [Settings](https://developer.apple.com/design/human-interface-guidelines/settings),
[toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars),
[layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)
and [onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
guidance informs the design.

## Interface

- Activity is a single window with a customizable toolbar of labeled actions, a
  paged table (date, sender, subject, verdict, confidence, reason) and an inspector
  shown with View → Show Inspector. Corrections stay visible in the inspector;
  evidence, usage and action diagnostics sit behind a disclosure, and the threat
  section appears only when a detector ran. The Filtering menu acts on the selected
  row, and the Activity footer reports one aggregate filtering state in its own layout
  space.
- Every Activity sheet shares the same navigation chrome, with Done, Cancel and
  confirmation buttons in the toolbar, and is presented through one router. The
  weekly Review digest is announced rather than opened unprompted.
- Settings has General, Classifier, Accounts, Rules, Policy and Advanced tabs, built
  as grouped forms with section footers. Every control applies on change; there are
  no Save buttons for settings. Conditional controls appear only when relevant, one
  Diagnostics disclosure holds Mail access, pending retries and, in Debug builds only,
  the move test, and the app remembers the selected tab.
- First launch presents four setup steps in the main window: an introduction, the
  provider choice with its key and mail-sharing consent, the Mail connection, and a
  dry run whose results are listed. General can reopen them in a sheet with Cancel.
- Each operation shows its own progress, result or failure with a recovery action,
  next to the control that started it. Destructive actions confirm first.
- A menu-bar extra keeps monitoring, Pause and selected-message corrections reachable
  with every window closed, and its symbol and spoken title follow the filtering state.
  Its items carry no key equivalents, because those fire only while the menu is open;
  Shortcuts supplies global keys. General can hide it; closing every window never
  quits, and clicking the Dock icon with no window open shows Activity.
- Help buttons use the native AppKit control and open anchored Help pages.
- Every view has injected previews. Interface text is localized in English, Spanish
  and French.

## Code

- The app framework is a set of narrow feature models composed by `AppModel`. Views
  take the narrowest model they need, and only models touch the store or Keychain.
- SwiftLint inherits the house parent config, including declaration ordering and
  documentation rules, and must report zero strict violations. Production bounds are
  named constants that views read rather than repeat, public APIs carry DocC comments,
  and errors expose localized descriptions, failure reasons and recovery suggestions.
- Swift Testing cases use prose identifiers. XCTest UI flows use typed screen objects,
  stable accessibility identifiers and predicate waits.
- Strict memory safety is on for every package and Xcode target; narrow C and
  Objective-C interop is marked `unsafe` at the expression.

## Compatibility decisions

- Public and persisted signed integer fields keep their established types and
  negative-input validation; collection indices stay `Int`.
- Camel-case `Codable` enums carry explicit raw values equal to their case names, so
  renaming a case never changes persisted or wire values.
- Protocol bytes, schemas, HTTP codes, pricing tables and mathematical identities
  stay literal domain data.
- Model prompts, cache identities, stored keys and machine-readable reports keep
  stable source-English vocabulary; localized presentation happens at the app
  boundary. The command-line tools have catalogs, but print English until their
  executables declare their localizations.
- UI tests launch the app in English, so locators that match visible text stay
  stable; app controls also carry stable identifiers.
- The package is an app and tool package with no external library compatibility
  promise, and stays in Swift 6 language mode.

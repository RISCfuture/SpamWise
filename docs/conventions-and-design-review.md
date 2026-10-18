# Conventions and design decisions

The authoritative code conventions are the owner's `swift-conventions` and
`swiftui-conventions` skills. This page records how SpamWise applies them and the
interface design they produced, so a change can stay consistent without re-deriving
either. Vendor packages, generated build output, fixture messages and the bundled
Public Suffix List are data or dependencies, not application code.

Apple's [Settings](https://developer.apple.com/design/human-interface-guidelines/settings),
[toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars),
[layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)
and [onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
guidance informs the design.

## Interface

- Activity is a single window with a native toolbar, a compact table and an
  inspector. Corrections stay visible; evidence, usage and action diagnostics sit
  behind a disclosure. Status footers occupy their own layout space instead of
  overlapping scrollable forms. Tools commands bring the one Activity window forward.
- Settings separates General, Accounts, Rules, Preferences and Advanced. Connection
  and provider controls appear only when relevant. Native Help buttons replace
  repeated explanatory links, and the app remembers the selected pane.
- First launch presents four offline-capable steps in the main window; General can
  reopen them in a sheet. Both use the same Back/Continue navigation and concise
  privacy information. Error and permission feedback stays visible when it applies.
- A menu-bar extra keeps monitoring reachable with every window closed.
- Every view has injected previews; UI state and asynchronous connection work are
  separate types. Interface text is localized in English, Spanish and French.

## Code

- Declaration ordering is enforced by SwiftLint. Production bounds are named
  constants, public APIs carry DocC comments, and errors expose localized
  descriptions and failure reasons.
- Swift Testing cases use prose identifiers. XCTest UI flows use typed screen
  objects, stable accessibility identifiers and predicate waits.
- Strict memory safety is on for every package and Xcode target; narrow C and
  Objective-C interop is marked `unsafe` at the expression.

## Compatibility decisions

- Public and persisted signed integer fields keep their established types and
  negative-input validation; collection indices stay `Int`.
- Protocol bytes, schemas, HTTP codes, pricing tables and mathematical identities
  stay literal domain data.
- Model prompts, cache identities, stored keys and machine-readable reports keep
  stable source-English vocabulary; localized presentation happens at the app
  boundary. CLI output in the Evaluation and `spamwise-eval` modules stays English.
- Native Settings toolbar tabs expose no SwiftUI identifiers, so the XCTest Settings
  screen pins English for that one system locator; app controls use stable
  identifiers.
- The package is an app and tool package with no external library compatibility
  promise, and stays in Swift 6 language mode.

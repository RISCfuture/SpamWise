# SpamWise development

SpamWise is a sandboxed macOS 27 Apple Mail filter. `docs/phase-one-brief.md` is the
original contract, preserved verbatim; where it differs from this file or `TODO.md`,
those record later owner decisions. `TODO.md` is the single status source. Branch from
`main` and open a pull request.

## Product invariants

- Never expose delete or Trash. Actions are limited to the account's own Inbox and Junk
  moves, Review annotations (orange flag or background), optional read status after a
  confirmed Junk move, and clearing Mail's own junk mark (IMAP's `$Junk` and `Junk`
  keywords) after a Good correction's confirmed move to Inbox. SpamWise never sets a junk
  mark.
- Persist the decision and an at-most-once action claim before dispatching; never retry
  a dispatched action automatically.
- Fail open: errors leave mail untouched and record unknown or failed outcomes. Messages
  over 2 MB stay unclassified by design.
- Dry run is on by default. Leaving it needs explicit confirmation after a read-only
  check that each account's Inbox and Junk roles resolve uniquely; live moves are
  verified afterward.
- Precedence: address rule > domain rule > content rules > Contacts/history. Block rules
  always apply; Allow rules and relationship gates apply only with trusted, aligned
  authentication from the account's configured receiving servers, and are otherwise
  model evidence. A correction replaces the same-scope rule; domain scope is explicit.
- No silent provider fallback. Cloud classification needs per-provider mail-sharing
  consent; local mode blocks every outbound provider and evidence lookup.
- Never read Mail's databases or request Full Disk Access. Default logs contain no keys
  or message content.

## Architecture

`SpamWiseCore/Package.swift` (Swift 6.4, language mode 6, strict memory safety and the
upcoming features on every target) defines this DAG. Keep new code in the lowest module
that can own it; core modules have no SwiftUI or MailKit dependency.

| Module | Depends on |
| --- | --- |
| MessageModel (bounded MIME, identity, public suffix list) | — |
| Signals (gates, evidence, Spamhaus, RDAP, Rspamd) | MessageModel, CResolver |
| Classifier (prompt, providers, ModelCatalog) | MessageModel, Signals |
| Decision (pure action policy) | Classifier, Signals |
| Learning | Classifier, Signals, MessageModel |
| Store (SwiftData, Keychain) | MessageModel, Signals, Classifier, Decision |
| SpamWiseCore (pipeline, sweeper, state) | MessageModel, Signals, Classifier, Decision, Store, Learning |
| MailIntegration (Apple Events, swift-nio-imap) | SpamWiseCore |
| Evaluation | SpamWiseCore |
| `spamwise-eval`, `spamwise-daemon` (argument-parser CLIs) | SpamWiseCore, MailIntegration (+ Evaluation) |

The Xcode project builds the `SpamWise Common` framework from `SpamWise/` (every view
and model) and two editions that differ only in their entry point: `SpamWise-MAS`
(scheme `SpamWise (MAS)`, App Store) and `SpamWise-download` (scheme `SpamWise
(download)`, Developer ID with GitHubUpdateChecker). Both embed `MailExtension`, which
deliberately leaves every message to Mail. `UnitTests` runs hostless under the `SpamWise
Common` scheme; `UITests` runs under `SpamWise (MAS)`. Every Xcode target enables strict
memory safety and treats warnings as errors. A new app-bundle resource must be added to
the three synchronized-group exception sets in `project.pbxproj`.

`AppModel` only composes narrow feature models (`SharedStateModel`, `SettingsModel`,
`ScanCoordinator`, `CorrectionsModel` and the rest), each built from `AppServices` and
its dependencies; views take the narrowest model and never write to the store or
Keychain. User operations run through `TrackedOperation` and show their own
`OperationStatusView`. `ScanCoordinator` sweeps in its own coalescing task, a minute
after the previous sweep ends. Activity sheets are `ActivitySheet` cases routed through
`ActivityRouter`, and the Activity table pages 200 rows at a time from the store.
Settings apply on change; text fields and steppers save through a debounced
`SettingDraft`, and quitting commits any edit still waiting. URLs reach the app
delegate, and window requests are answered at the scene, because the menu bar item can
be hidden. App Intents generate a request UUID unless the caller supplies one.

Identifiers are fixed: bundle ID `codes.tim.SpamWise` for both editions (install only
one), `codes.tim.SpamWise.MailExtension`, team `2NFSK2WB24`, App Group
`group.codes.tim.SpamWise`, Keychain group `2NFSK2WB24.codes.tim.SpamWise.shared`.
Credentials live only in that Keychain group, never in settings or backups.

Shared state is one SwiftData store (`SpamWise.store`) in the App Group, with an entity
per collection (`StoreSchemaV2`, without a migration plan, so schema changes must suit
SwiftData's automatic lightweight migration). A `state.schema` mark refuses a store a
newer version wrote. Pre-1.0 data is not imported; a single-document snapshot from a
build before the entity schema is set aside for recovery. Every read-modify-write
transaction takes a process-shared `flock` on `SpamWise.store.lock` with a bounded
five-second wait, then uses a fresh `ModelContext` on the process's one
`ModelContainer`, so it sees rows other processes committed. Callers load only the
`StateSlices` they need and detect other processes' writes by polling `changeTokens()`;
never rely on Core Data change notifications. Lock contention fails open.

## Commands

```sh
Scripts/check.sh [build-token]     # package-reference, localization, Help and
                                   # compiled-resource checks, tool and package tests,
                                   # Release builds of both editions, extension and
                                   # hostless unit tests, then the diagnostics grep
Scripts/ui-check.sh [build-token]  # development-signed XCTest UI flows (needs the team)
swift test --package-path SpamWiseCore --scratch-path .build/swiftpm -Xswiftc -warnings-as-errors
swift format format -i -r SpamWise SpamWise-MAS SpamWise-download SpamWiseCore/Sources \
  SpamWiseCore/Tests MailExtension UITests UnitTests
swiftlint lint --fix && swiftlint lint --strict
python3 Scripts/check-core-localizations.py   # package strings: bundle, es/fr, unused keys
python3 Scripts/check-help-book.py            # Help anchors the app opens, links, structure
Scripts/help-index.sh                         # rebuild the Help search indexes
python3 Scripts/check-compiled-resources.py   # Mail rule script, Help indexes vs sources
bash Scripts/store-check.sh <build-token>     # two-process store transaction probe
bundle exec fastlane mac download_release version:X build:N   # Developer ID DMG
bundle exec fastlane mac release version:X build:N            # App Store upload
```

Builds land in `.build/<build-token>/`; give each concurrent session its own token.
Do not pass `SWIFT_TREAT_WARNINGS_AS_ERRORS` or `SWIFT_SUPPRESS_WARNINGS` on the
command line for the download scheme: they break the third-party MarkdownUI package.
`.swiftlint.yml` inherits the house parent config (a gist URL) and must stay at zero
strict violations; `swiftlint analyze` is not part of the gate. The site under `docs/`
is generated by `Tools/Site` (see its README); rebuild it after editing its Markdown
sources.

Every user-visible string needs `es` and `fr` values. Package modules declare
`defaultLocalization: "en"` and call `String(localized:bundle: .module)` against their
own `Localizable.xcstrings`; the app catalog holds only strings app targets extract.
Every Help anchor the app opens must exist in all three Help languages.

On pushes and pull requests to `main`, `ci.yml` runs the localization, Help-anchor
and package-reference checks and Python tool tests, package tests, hostless unit tests,
unsigned Release builds of both editions (with the icon check) and the extension, UI
tests on an ad-hoc-signed App Store edition in test mode, and DocC (failing on
SpamWiseCore warnings); the package, unit and build jobs fail on any build diagnostic
in their logs (`Scripts/check-diagnostics.sh`). CI doesn't run the compiled-resource
check. `lint.yml` runs a pinned SwiftLint. `site.yml` validates the site;
`release.yml` ships a pushed version tag, refusing one that names another commit
(`Scripts/check-release-tag.sh`) before anything is uploaded.

## Signing and sandbox caveats

- Inside the tool sandbox (not the app's App Sandbox), compiler caches and macro
  subprocesses need approval, and `security`/`codesign` misreport identities and
  entitlements; inspect signatures unrestricted.
- Keep `PROVISIONING_PROFILE_REQUIRED = YES` on UITests: a development-signed runner
  needs a profile. Only CI's ad-hoc UI job overrides it.
- Automation consent is requested separately via `AEDeterminePermissionToAutomateTarget`;
  ordinary scripts preflight without prompting and keep their 8-second limit.
- Mail builds the extension's principal object off the main actor; keep it `nonisolated`.
- Stale Launch Services registrations route App Intents to another installed copy; run
  intent tests with exactly one SpamWise process.
- `--ui-testing` (isolated store, preferences and in-memory credentials) is honored only
  in Debug builds.

## Live tests, spending and probe mail

- Live and paid checks are opt-in only and need the user's go-ahead in the session:
  `SPAMWISE_LIVE_API=1` (package), `TEST_RUNNER_SPAMWISE_INTENTS_TEST=1` (native intent
  UI test), `spamwise-eval` with a paid model (requires `--budget-store`).
- The additional evaluation spend is capped at $150. It is a ceiling, not a target.
- Never act on ordinary mail. Action probes use only generated messages whose subject
  starts with `[SpamWise Probe]`, sent cross-account so no same-account Sent copy shares
  the Message-ID. The app's Apple Mail move test exists only in Debug builds.
- When a check finishes, move each generated probe, including its Sent copies and
  leftover drafts, to its own account's Trash, resolving it by account and exact
  identity, and verify where it landed. For Gmail, verify the system `TRASH` label,
  not Mail's custom "Deleted Messages" folder. Never empty Trash and never touch
  ordinary mail or the Junk folders, which hold the user's accumulating samples. This
  is operator cleanup; the product itself still exposes no Trash operation.

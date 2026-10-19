# SpamWise

[![CI](https://github.com/RISCfuture/SpamWise/actions/workflows/ci.yml/badge.svg)](https://github.com/RISCfuture/SpamWise/actions/workflows/ci.yml)
[![Linters](https://github.com/RISCfuture/SpamWise/actions/workflows/lint.yml/badge.svg)](https://github.com/RISCfuture/SpamWise/actions/workflows/lint.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2027-lightgrey.svg)](https://developer.apple.com/)

SpamWise is a sandboxed junk-mail filter for Apple Mail on macOS 27. Your sender and
domain rules decide first; Contacts and your own mail history help when the sender's
authentication can be trusted; a language model you choose classifies the rest:
Anthropic Claude, OpenAI, Google Gemini or Apple's on-device model.

It never deletes mail. Inbox means no action, Review leaves the message in the Inbox
with an orange flag or background, and Junk moves it to that account's own Junk
mailbox. It starts in dry run, recording what it would do without touching mail, until
you turn actions on.

SpamWise has not been released. The repository is
[RISCfuture/SpamWise](https://github.com/RISCfuture/SpamWise); the prerelease site
under `docs/` is not deployed. See [TODO.md](TODO.md) for what is done and what is still
waiting on acceptance.

## Editions

Two app targets build from one project. Both produce `SpamWise.app` with the bundle
identifier `codes.tim.SpamWise`, embed the same Mail extension and share one App Group
store and Keychain group, so install only one at a time.

| | **SpamWise (download)** | **SpamWise (MAS)** |
| --- | --- | --- |
| Target | `SpamWise-download` | `SpamWise-MAS` |
| Distribution | Developer ID, notarized disk image on GitHub Releases | Mac App Store |
| Updates | Checks GitHub Releases with [GitHubUpdateChecker](https://github.com/RISCfuture/GitHubUpdateChecker) | The store |
| Status | Primary channel | Depends on App Review granting the Mail Apple Events exception |

Nothing is conditionally compiled. Each target holds only its entry point, Info.plist,
entitlements and App Shortcuts; the download edition injects the update checker, and
the shared views show update controls only when one is present. See
[distribution differences](docs/distribution-differences.md).

## Architecture

### Layout

| Path | Contents |
| --- | --- |
| `SpamWiseCore/` | Swift package with all filtering logic; no SwiftUI or MailKit |
| `SpamWise/` | The `SpamWise Common` framework: app model, every view and Settings, the Help book, string catalogs |
| `SpamWise-MAS/`, `SpamWise-download/` | Edition entry points, Info.plists and entitlements |
| `MailExtension/` | The Mail extension, which deliberately leaves every message to Mail |
| `UnitTests/`, `UITests/` | Hostless framework tests and XCTest UI flows |
| `eval/` | Five synthetic fixtures, their seed state and mock verdicts |
| `Scripts/` | Check, packaging and runtime-probe scripts |
| `Tools/` | Research harnesses: corpus preparation, document worker, preference probe, site generator |
| `fastlane/`, `.github/workflows/` | Release lanes, CI, lint, release and site workflows |
| `docs/` | Reference documentation and the generated prerelease site |

### Package modules

| Module | Role | Depends on |
| --- | --- | --- |
| MessageModel | Bounded MIME parsing, message identity, public suffix list | — |
| Signals | Rule gates, authentication evidence, Spamhaus DBL, RDAP, Rspamd | MessageModel, CResolver |
| Classifier | Prompt construction, provider classifiers, model catalog | MessageModel, Signals |
| Decision | Pure action policy from verdict and settings | Classifier, Signals |
| Learning | Optional Bayes, evidence weights and campaign fingerprints | Classifier, Signals, MessageModel |
| Store | SwiftData store shared across processes, Keychain | MessageModel, Signals, Classifier, Decision |
| SpamWiseCore | Pipeline, mail sweeper, corrections, state | all of the above |
| MailIntegration | Apple Events adapter for Mail, IMAP on swift-nio-imap | SpamWiseCore |
| Evaluation | Metrics, calibration and comparison reports | SpamWiseCore |
| `spamwise-eval` | Evaluation CLI | SpamWiseCore, MailIntegration, Evaluation |
| `spamwise-daemon` | Headless IMAP filter | SpamWiseCore, MailIntegration |

Every message passes through the same pipeline: parse, gather evidence, apply rules,
classify if no rule decided, choose an action, persist the decision and an
at-most-once action claim, then ask the mail adapter to act. Any failure leaves the
message where it is.

Each package module resolves its strings from its own `Localizable.xcstrings` through
`bundle: .module`, in English, Spanish and French. Processes share one SwiftData store
in the App Group; transactions take a cross-process file lock, load only the state
slices they need, and notice other processes' writes by polling change tokens.

### App

The `SpamWise Common` framework holds the app. `AppModel` composes feature models, each
built from the shared `AppServices` and only the models it depends on:
`SharedStateModel` and `SettingsModel` for stored state, `ScanCoordinator` for sweeps,
and one model per feature, such as `CorrectionsModel`, `RulesModel`, `CorpusModel`,
`CredentialsModel` and `AuthenticationTrustModel`. Views receive the narrowest model
they need and never write to the store or Keychain directly.

- Automatic sweeps run in their own coalescing task, one minute after the previous
  sweep finishes and independently of user work; a check requested during a sweep runs
  right after it.
- Each user operation runs through a `TrackedOperation` and reports its own progress,
  result or failure, with a recovery action, next to the control that started it.
- Activity is one window. Its table pages 200 rows at a time from the store, with
  store-backed sorting, and every sheet is an `ActivitySheet` case presented through
  `ActivityRouter`. The menu bar and the Activity footer show one aggregate filtering
  state, such as dry run, offline or failing.
- Settings has General, Classifier, Accounts, Rules, Policy and Advanced tabs. Every
  control applies on change; text fields and steppers save after a short pause or
  when focus leaves them.

### Schemes

| Scheme | Builds | Tests |
| --- | --- | --- |
| `SpamWise (download)` | Download edition and extension | — |
| `SpamWise (MAS)` | App Store edition and extension | `UnitTests`, `UITests` (`SpamWise.xctestplan`) |
| `SpamWise Common` | Shared framework | `UnitTests`, hostless |
| `MailExtension` | The extension | — |
| `SpamWiseCore`, `MailIntegration`, `spamwise-eval`, `spamwise-daemon` | Package products | — |

## Requirements

- macOS 27 and Xcode 27 with Swift 6.4, on Apple silicon (Intel is untested).
- `swiftlint`, `xcbeautify` and `python3` for `Scripts/check.sh`.
- For releases: Ruby 4.0.7 with the `spamwise` gemset (`.ruby-version`,
  `.ruby-gemset`) and the gems in `Gemfile`, plus access to the team's match
  certificates repository.
- For the corpus and site tools under `Tools/`: pyenv with a Python 3 virtualenv, as
  each tool's README describes.

Swift packages resolve from their remote repositories at the versions pinned in the
committed `Package.resolved` files.

## Building

```sh
xcodebuild build -project SpamWise.xcodeproj -scheme "SpamWise (download)" \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

An unsigned build compiles, but Mail Automation, the App Group and the Keychain group
need signing with team `2NFSK2WB24`. Open `SpamWise.xcodeproj` and run either edition
scheme with automatic signing to try the app.

## Testing

```sh
Scripts/check.sh            # CI's unsigned checks, with warnings as errors
Scripts/ui-check.sh         # XCTest UI flows; development-signed
```

`check.sh` checks package localizations and the Help book, runs the package tests,
builds both editions and the extension, checks the app icon and runs the hostless unit
tests, failing on any warning. Products land in `.build/check/`; pass another name
(`Scripts/check.sh feature-x`) to keep concurrent builds apart. The pieces can run
alone:

| Layer | Command |
| --- | --- |
| Package tests | `swift test --package-path SpamWiseCore -Xswiftc -warnings-as-errors` |
| Hostless unit tests | `xcodebuild test -project SpamWise.xcodeproj -scheme "SpamWise Common" CODE_SIGNING_ALLOWED=NO` |
| UI tests | `Scripts/ui-check.sh`, which signs for team `2NFSK2WB24` and runs `UITests` from `SpamWise.xctestplan` against the App Store edition |
| Package localizations | `python3 Scripts/check-core-localizations.py`: every package string uses its module's catalog and has matching es/fr values |
| Help book | `python3 Scripts/check-help-book.py`: every anchor the app opens exists in all three languages, and links resolve |
| Documentation | `xcodebuild docbuild -scheme SpamWiseCore-Package -destination 'platform=macOS,arch=arm64'`, run in `SpamWiseCore/` |
| Store concurrency | `bash Scripts/store-check.sh <build-token>`: two processes make 50 transactions each, a third reads 100 |
| Format | `swift format format -i -r SpamWise SpamWise-MAS SpamWise-download SpamWiseCore/Sources SpamWiseCore/Tests MailExtension UITests UnitTests` |
| Lint | `swiftlint lint --strict`, with the house parent config that `.swiftlint.yml` names |

The UI flows use isolated temporary storage and a simulated denied Mail permission, so
they never touch mail. Two checks are opt-in because they spend money or need an
installed, indexed app:

- `SPAMWISE_LIVE_API=1 swift test --package-path SpamWiseCore` classifies one fixture
  with Claude Haiku using the Keychain key.
- `TEST_RUNNER_SPAMWISE_INTENTS_TEST=1
  TEST_RUNNER_SPAMWISE_INTENTS_APP_PATH=/path/to/SpamWise.app Scripts/ui-check.sh`
  runs the App Intents through the registered app. See [automation](docs/automation.md).

The [evaluation guide](docs/evaluation.md) covers the offline fixture check and
labeled-corpus runs with `spamwise-eval`.

### Continuous integration

Pushes and pull requests to `main` run two workflows on Xcode 27 runners:

| Workflow | Job | Checks |
| --- | --- | --- |
| `ci.yml` | Package Tests | `swift test` with warnings as errors |
| | Unit Tests | The hostless `SpamWise Common` tests |
| | Build Editions | Unsigned builds of both editions and the Mail extension |
| | UI Tests | `UITests` against an ad-hoc-signed App Store edition in test mode |
| | Documentation | The package's DocC; any warning in SpamWiseCore sources fails |
| `lint.yml` | Run SwiftLint | `swiftlint lint --strict` |

No CI job drives Mail: real actions need a signed app, a configured account and
Automation approval. `site.yml` validates the prerelease site on pull requests that
touch it and deploys only from a manual run on `main`; `release.yml` runs the release
lanes for a pushed version tag. CI does not run the localization or Help checks, so
run `Scripts/check.sh` before pushing.

## Running

Complete the four setup steps. Allow SpamWise to control Mail when macOS asks;
Contacts is optional. Do not grant Full Disk Access: SpamWise never reads Mail's
databases. Choose a model; a cloud provider needs your own API key, stored in Keychain,
and separate permission to share mail with it.

Check the Mail connection in Settings → Accounts to validate each account's Inbox and
Junk mailboxes, review the dry-run results in Activity, then turn dry run off in
General. SpamWise filters only while it runs: closing its windows leaves the menu-bar
app monitoring, and launch at login is optional. Automatic scans consider mail received
after setup; older mail is filtered only through an explicit preview under the
account's Older mail in Settings → Accounts.

`spamwise-daemon` filters one IMAP account headlessly; see [IMAP](docs/imap.md).

## Releasing

```sh
bundle install
bundle exec fastlane mac download_release version:1.0 build:42
bundle exec fastlane mac release version:1.0 build:42
```

`download_release` archives, notarizes and staples the download edition and builds a
notarized disk image; `release` uploads the App Store edition without submitting it.
Pushing a version tag runs both through `.github/workflows/release.yml`, using the
matching `CHANGELOG.md` section as release notes. See [packaging](docs/packaging.md).

## Privacy

SpamWise has no analytics or tracking. With your permission it sends bounded message
context to the model provider you choose, and optional evidence lookups send domains to
Spamhaus or registration-data services. Everything else stays on the Mac. The
[privacy policy](docs/privacy.md) and [data inventory](docs/privacy-audit.md) give the
details.

## Documentation

The [documentation index](docs/README.md) lists the reference docs. [TODO.md](TODO.md)
tracks status, and [CHANGELOG.md](CHANGELOG.md) holds release notes. The original
[Phase 1 brief](docs/phase-one-brief.md) is preserved verbatim.

## License

No license has been selected yet; all rights are reserved. Third-party components are
listed in [CREDITS.md](CREDITS.md).

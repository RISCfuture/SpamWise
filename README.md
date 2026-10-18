# SpamWise

A macOS 27 Apple Mail filter with local sender rules, optional relationship evidence, and guided Claude classification. It never deletes mail. Inbox means no action, Review stays in Inbox with an annotation, and eligible Junk moves only to that account's resolved Junk mailbox.

The app starts in dry run, and dry-run checks begin once Mail Automation is allowed. Leaving dry run requires an explicit confirmation after a read-only check that each account's Inbox and Junk mailboxes resolve uniquely; every live move is verified afterward and fails open. Signed live Mail behavior and production thresholds still require the acceptance checks in [the runtime checklist](docs/probes/runtime-checklist.md).

The repository is [RISCfuture/SpamWise](https://github.com/RISCfuture/SpamWise),
currently private while publication is reviewed. The prepared marketing, privacy
and support pages have no public deployment or release download yet. See the
[repository approval checklist](docs/repository-approval.md).

## Prerequisites

- Xcode 27 with Swift 6.4, on macOS 27.
- `swiftlint`, `xcbeautify`, `shellcheck` and `markdownlint-cli2`, which the check scripts call.
- `rg` (ripgrep) and `agent-lock`, for the runtime probe scripts (`store-check.sh`, `evidence-runtime-check.sh`, `rspamd-runtime-check.sh`), which take an `agent-lock` worker token to isolate their build caches.
- pyenv with a Python 3 virtualenv, for the corpus and packaging tools under `Tools/` and `Scripts/`.

Swift package dependencies, including GitHubUpdateChecker for the direct-download edition, resolve from their remote repositories at the versions pinned in `Package.resolved`; no sibling checkouts are needed.

## Build and verify

The project has two app targets, `SpamWise-MAS` and `SpamWise-download`, that share the `SpamWise Common` framework; their shared schemes are `SpamWise (MAS)` and `SpamWise (download)`. The provider dependency is pinned in the local package. Preserve bundle identifiers, signing team, App Group, and shared Keychain group.

```sh
Scripts/check.sh
Scripts/ui-check.sh
swiftlint lint --strict --no-cache
shellcheck Scripts/*.sh
```

The check script runs all package tests with warnings as errors, builds both editions and the Mail extension without signing, and runs the hostless unit tests in the `SpamWise Common` scheme. It writes to `.build/check/`; pass another name, such as `Scripts/check.sh feature-x`, to keep builds apart. The UI script runs the UITests target against the App Store edition with automatic development signing. That target requires an embedded provisioning profile to authorize the runner's application-identifier entitlement; Xcode downloads or creates it using the configured team account. The test-mode app uses isolated temporary storage and simulated denied Mail permission. The UI flows cover all four onboarding steps, denied-permission messaging, dry-run status, Pause, address-rule replacement, explicit domain correction, and retained corrections when a Mail action fails. The `SpamWise (MAS)` scheme's test plan, `SpamWise.xctestplan`, runs the unit and UI tests together.

Use `swift format format -i -r SpamWise SpamWise-MAS SpamWise-download SpamWiseCore/Sources SpamWiseCore/Tests MailExtension UITests UnitTests`, then `swiftlint lint --fix` and `swiftlint lint --strict`. SwiftLint layout rules that disagree with Swift's formatter are disabled in the repository configuration. CI runs the same package tests, builds and unit tests, plus SwiftLint, on every pull request.

## Run

Open `SpamWise.xcodeproj` and run the SpamWise scheme with signing configured for team `2NFSK2WB24`. Complete the four setup steps. API verification sends a synthetic message; recent-mail dry run sends eligible message context to Anthropic. The key is stored in Keychain only after successful verification. Contacts is optional. Do not grant Full Disk Access.

For mail actions, check the Mail connection in Settings → Accounts to validate each account's mailboxes, optionally install the bundled Mail rule script as described in Help, and review dry-run results before turning off dry run. An optional `[SpamWise Probe]` move test is in Settings → Advanced. Keep SpamWise running. Automatic scans consider only mail received after setup (or after a later account is added or included), read each account's new Inbox mail first on every check, and then continue a bounded backfill; mailbox changes can delay discovery of backfilled mail. Older mail is filtered only through an explicit preview in Settings. Authorized Contacts refresh hourly, and bounded Sent/Inbox history updates run with automatic scans. The Inbox scanner does not automatically process server-routed Junk.

## Evaluation and packaging

[Evaluation instructions](docs/evaluation.md) cover labeled corpora, mailbox export, mock/live selection, cache identity, confidence buckets, usage, and statistical limits. The included fixture verdicts are explicit mocks and do not establish model quality. Live tests are opt-in via `SPAMWISE_LIVE_API=1`.

[Packaging instructions](docs/packaging.md) cover Help indexing, hardened-runtime archives, Developer ID export, notarization, and acceptance. [CLAUDE.md](CLAUDE.md) records implementation decisions and actual probe results; [TODO.md](TODO.md) tracks deferred product work. The original [Phase 1 brief](docs/phase-one-brief.md) is preserved verbatim.

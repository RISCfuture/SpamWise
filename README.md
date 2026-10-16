# SpamWise

A macOS 27 Apple Mail filter with local sender rules, optional relationship evidence, and guided Claude classification. It never deletes mail. Inbox means no action, Review stays in Inbox with an annotation, and eligible Junk moves only to that account's resolved Junk mailbox.

The app starts in dry run. MailKit records incoming dry runs; automatic Apple Events actions require a successful disposable-message probe for each account. Signed live Mail behavior and production thresholds still require the acceptance checks in [the runtime checklist](docs/probes/runtime-checklist.md).

## Build and verify

Requires Xcode 27, Swift 6.4, macOS 27, `swiftlint`, `xcbeautify`, `shellcheck`, and `markdownlint-cli2`. The provider dependency is pinned in the local package. Preserve bundle identifiers, signing team, App Group, and shared Keychain group.

```sh
agent-lock worker
# Use the printed token consistently for this session.
bash Scripts/check.sh <worker-token>
swiftlint lint --strict --no-cache
shellcheck Scripts/*.sh
markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc --fix README.md CLAUDE.md TODO.md docs/evaluation.md docs/packaging.md
bash Scripts/ui-check.sh <worker-token>
```

The check script runs all package tests with warnings as errors, then builds the app and extension without signing. The UI script takes the shared UI lock and uses automatic development signing. macOS must allow the test runner to launch; a Gatekeeper “Move to Trash” rejection is an environment failure, not a passing UI test. Cancel that prompt and resolve provisioning in Xcode. The test-mode app uses isolated temporary storage and simulated denied Mail permission.

Use `swift format format -i -r SpamWise SpamWiseCore/Sources SpamWiseCore/Tests MailExtension UITests UnitTests`, then `swiftlint lint --fix` and `swiftlint lint --strict`. SwiftLint layout rules that disagree with Swift's formatter are disabled in the repository configuration.

## Run

Open `SpamWise.xcodeproj` and run the SpamWise scheme with signing configured for team `2NFSK2WB24`. Complete the four setup steps. API verification sends a synthetic message; recent-mail dry run sends eligible message context to Anthropic. The key is stored in Keychain only after successful verification. Contacts is optional. Do not grant Full Disk Access.

For mail actions, select an explicitly disposable message beginning `[SpamWise Probe]`, run the account probe in Settings, install the bundled Mail rule script as described in Help, and review dry-run results before disabling dry run. Keep SpamWise running. The Inbox scanner does not automatically process server-routed Junk.

## Evaluation and packaging

[Evaluation instructions](docs/evaluation.md) cover labeled corpora, mailbox export, mock/live selection, cache identity, confidence buckets, usage, and statistical limits. The included fixture verdicts are explicit mocks and do not establish model quality. Live tests are opt-in via `SPAMWISE_LIVE_API=1`.

[Packaging instructions](docs/packaging.md) cover Help indexing, hardened-runtime archives, Developer ID export, notarization, and acceptance. [CLAUDE.md](CLAUDE.md) records implementation decisions and actual probe results; [TODO.md](TODO.md) tracks deferred product work. The original [Phase 1 brief](docs/phase-one-brief.md) is preserved verbatim.

# Mail.app automation

SpamWise defines four App Intents for Shortcuts: **Preview Selected Mail**,
**Correct Selected Mail**, **Get SpamWise Status**, and **Export SpamWise Diagnostics**.
The first two require one selected Mail message, completed setup, Mail Automation
permission, and an unlocked Mac. Preview uses the configured provider and spending
limit; it never requests mail actions. Correction saves an address rule and example
before attempting its action under Pause, dry run and account validation.

Status returns redacted JSON; export returns the same data as a JSON file. Neither
includes credentials, subjects, senders, account identities or message bodies.
The Filtering Status App Shortcut exposes status without building a custom shortcut.

## Requests and retries

Preview and correction require a **Request UUID**. Generate a UUID for each new
operation and retain it for retries. A completed duplicate returns its original
JSON result without a new classification or action. Reusing a UUID for a different
operation or selected message fails. An interrupted/uncertain request also fails on
retry instead of risking another move or charge. Inspect Activity before creating
another request. Claims survive Activity retention and have a hard 10,000-request
limit; saturation fails without evicting old protection.

Replies contain `recordID`, optional `label`, `action`, `outcome` and a bounded
`reason`. A label is not an action acknowledgement. Cancellation stops pending work;
Mail operations already dispatched cannot be recalled.

## Command-line and AppleScript bridge

After macOS indexes the installed app, create a shortcut in Shortcuts containing the
appropriate SpamWise action. For preview/correction, supply the caller's saved UUID
as the action's Request UUID, rather than generating another UUID during a retry.
Then invoke the saved shortcut using Apple's CLI, for example:

```sh
shortcuts run 'SpamWise Status' --output-path status.json
```

An AppleScript can invoke that saved shortcut with `do shell script`. SpamWise does
not add an AppleScript dictionary or accept arbitrary source text in a URL. The
existing `spamwise://check-inbox` trigger remains subject to app safety settings.

## Verification status

Core tests verify preview replay, mismatched UUID rejection and one correction/action
per completed request. Metadata extraction includes all four intents. Native
`AppIntentsTesting` execution currently fails with
`AppIntentsServicesMetadataErrorDomain Code=400`, “codes.tim.SpamWise is not present,”
in this development setup, even after Launch Services registration and shortcut
parameter registration. Shortcuts/CLI/AppleScript execution is **not yet accepted**.

The separate UI acceptance test is opt-in. With the current signed build installed
and indexed, run:

```sh
TEST_RUNNER_SPAMWISE_INTENTS_TEST=1 bash Scripts/ui-check.sh "$(agent-lock worker)"
```

The ordinary UI suite reports this test as skipped; it still exercises onboarding,
corrections, undo, corpus management and statistics. Never infer native automation
acceptance from the package tests alone.

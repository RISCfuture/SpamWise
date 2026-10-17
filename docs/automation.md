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
per completed request. Metadata extraction includes all four intents. On
2026-10-16 at 21:14 PDT, the signed native `AppIntentsTesting` status test passed
in 2.207 seconds. It executed the intent out of process against isolated fixture
state, verified the expected dry-run/account-count values, and checked that the
fixture sender was absent from the returned JSON. It made no provider calls or
Mail actions. Preview/correction runtime execution and the saved
Shortcuts/CLI/AppleScript bridge remain **not yet accepted**.

The separate UI acceptance test is opt-in. With the current signed build installed
and indexed, run:

```sh
TEST_RUNNER_SPAMWISE_INTENTS_TEST=1 bash Scripts/ui-check.sh "$(agent-lock worker)"
```

The ordinary UI suite reports this test as skipped; it still exercises onboarding,
corrections, undo, corpus management and statistics. Never infer native automation
acceptance from the package tests alone.

### Registration diagnosis and reproduction

The native test initially returned `AppIntentsServicesMetadataErrorDomain Code=400`,
“codes.tim.SpamWise is not present.” Launch Services resolved the bundle identifier
to `~/Applications/SpamWise.app`, an older build without
`Contents/Resources/Metadata.appintents`. The current signed build contained all
four intents, but building and launching it under `.build` did not resolve the
registration failure. No intent implementation change was needed.

To inspect the selected installation and its metadata:

```sh
osascript -e 'POSIX path of (path to application id "codes.tim.SpamWise")'
ls ~/Applications/SpamWise.app/Contents/Resources/Metadata.appintents
```

The successful probe copied the strictly verified current development-signed app
to `~/Applications/SpamWise-Automation-14903120.app`. It unregistered only the
older production app and registered that temporary copy using Launch Services:

```sh
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u ~/Applications/SpamWise.app
"$lsregister" -f ~/Applications/SpamWise-Automation-14903120.app
open -n ~/Applications/SpamWise-Automation-14903120.app --args --ui-testing --ui-corrections
```

`linkd` then logged indexing the temporary app's `extract.actionsdata`. Rerunning
the scoped `UITests/UITests/testRegisteredAutomationStatus` test with
`TEST_RUNNER_SPAMWISE_INTENTS_TEST=1` passed. Evidence is preserved at
`.build/14903120-a82f-4ad9-8b2a-fd2ffef477ae/intents-registered.xcresult` and the
adjacent `intents-registered.log`; `intents-native.xcresult` records the preceding
failure. The temporary process was stopped, its registration removed, and the
copy moved back into the worker's build artifacts. The production app was
registered again, and its original Launch Services resolution was verified.
No global registration reset or production-app replacement was performed.

The Shortcuts CLI itself runs successfully, but `shortcuts run 'Filtering Status'`
does not locate the App Shortcut as a saved shortcut. Create a named shortcut
containing **Get SpamWise Status** before running the documented CLI example.
The current Shortcuts UI is blocked at its **What's New in Shortcuts** panel:
its accessibility tree is empty and Continue remains disabled. Saved-shortcut
creation and CLI execution await dismissal of that panel; the native test pass
does not establish those separate paths.

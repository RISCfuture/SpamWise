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
appropriate SpamWise action, followed by **Stop and Output**, with the SpamWise
action's result as its input. Explicit output is required for the verified CLI
path; returning the last action's implicit output hung on the tested macOS build.
For preview/correction, supply the caller's saved UUID as the action's Request UUID,
rather than generating another UUID during a retry. Then invoke the saved shortcut
using Apple's CLI, for example:

```sh
shortcuts run 'SpamWise Status' --output-path "$PWD/status.json" </dev/null
```

An AppleScript can invoke that saved shortcut with `do shell script`. SpamWise does
not add an AppleScript dictionary or accept arbitrary source text in a URL. The
existing `spamwise://check-inbox` trigger remains subject to app safety settings.

## Verification status

Core tests verify preview replay, mismatched UUID rejection and one correction/action
per completed request. Metadata extraction includes all four intents. The signed
native `AppIntentsTesting` flow passed in 7.710 seconds on 2026-10-16, exercising
all four intents out of process against one isolated fixture app. Preview returned
the mock Junk verdict with a dry-run outcome, and a repeated request returned
the identical response. Correction saved an address Allow rule, retained it after
the denied Mail action, and returned the identical response on replay without
creating a domain rule. Diagnostics export matched status, including the expected
outcome counts, and omitted the fixture sender, subject and account identity.
The fixture used a mock classifier and denied every Mail action: zero provider
calls and zero actual Mail operations occurred. Evidence is
`.build/7ae09be2-7487-4cc9-900a-1c1b9fb169c9/automation-native.xcresult`.
The saved status shortcut also passed direct Shortcuts editor execution, CLI
execution and the AppleScript `do shell script` bridge. CLI and AppleScript output
matched the exact redacted fixture schema and values. Those paths used an explicit
**Stop and Output** action; live Mail/provider behavior is outside this fixture test.

The separate UI acceptance test is opt-in. With the current signed debug build
installed and indexed, pass its absolute path so XCTest launches the same app
that App Intents resolves:

```sh
TEST_RUNNER_SPAMWISE_INTENTS_TEST=1 \
TEST_RUNNER_SPAMWISE_INTENTS_APP_PATH="$HOME/Applications/SpamWise.app" \
  bash Scripts/ui-check.sh "$(agent-lock worker)"
```

The ordinary UI suite reports this test as skipped; it still exercises onboarding,
corrections, undo, corpus management and statistics. Never infer native automation
acceptance from the package tests alone.

Keep only the test's SpamWise process running during native acceptance. Each
fixture launch creates a separate temporary store; two apps with the same bundle
identifier can route intent execution to one process while XCTest inspects the
other. Explicit app-path selection applies to onboarding, corrections and native
intent tests throughout the suite. A single running process keeps the intent
results and UI assertions attached to the same fixture.

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
After the user dismissed **What's New in Shortcuts**, the action library exposed
**Get SpamWise Status**. A saved shortcut named
`SpamWise Status Acceptance 14903120` was created with exactly that action
(UUID `DEABDD18-AB09-4205-BF0E-89A949A3BC6B`).

At 22:10 PDT, CLI execution failed because `linkd` attempted to communicate with
the still-running older production app, despite Launch Services resolving the
temporary fixture app. Its log reported an untrusted application record and
`LNConnectionErrorDomain Code=1200`, “AppleEvents communication failed.” The
verified older production process was gracefully quit without changing settings.
The next run connected to the fixture process, but returned no output during
approximately 45 seconds of observation; the owned CLI process was interrupted.
No permission dialog or definitive execution error was observed during that run.
Logs are preserved as `shortcut-first-failure.log`,
`shortcut-live-registration.log` and `shortcut-bounded-hang.log` under the same
worker artifact directory.

A fresh test build reproduced the CLI hang even with stdin closed, an absolute
output path, and only one fixture process running. App Intents logs confirmed
`SpamWiseStatusIntent.perform` returned within milliseconds. Running the saved
shortcut directly in the Shortcuts editor immediately displayed the expected JSON.
Adding **Stop and Output**, connected to the status action's result, resolved the
CLI return path. Both the CLI and AppleScript bridge then exited successfully
and wrote the same decoded JSON values; object key order differed. The output
artifacts are `shortcut-explicit-status.json`
and `shortcut-applescript-status.json` under
`.build/14903120-a82f-4ad9-8b2a-fd2ffef477ae/`. No app implementation change was
required for this output configuration. The owned acceptance shortcut was deleted
after verification; the four pre-existing shortcuts retained their original UUIDs.

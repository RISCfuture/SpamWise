# Mail.app automation

SpamWise defines four App Intents for Shortcuts: **Preview Selected Mail**,
**Correct Selected Mail**, **Get SpamWise Status**, and **Export SpamWise Diagnostics**.
The first two require one selected Mail message, completed setup, SpamWise connected
through Apple Mail rather than IMAP, Mail Automation permission, and an unlocked Mac. Preview uses the configured provider and spending
limit; it never requests mail actions. Correction saves an address rule and example
before attempting its action under Pause, dry run and account validation.

Status speaks the current filtering state, as the menu bar shows it, and returns
redacted JSON as its value; export returns the same data as a JSON file. Neither
includes credentials, subjects, senders, account identities or message bodies.
The Filtering Status App Shortcut exposes status without building a custom shortcut.

## Requests and retries

Each preview or correction runs as a new request unless its optional, advanced
**Request UUID** parameter is set. The JSON reply and every failure message name
the UUID the run used, so a run that finished or failed can be retried with it.
A run that is cancelled or times out reports nothing, so to make those retries
safe too, generate a UUID for the operation and pass the same value on every
retry. A completed duplicate returns
its original JSON result without a new classification or action. Reusing a UUID
for a different operation or selected message fails. An interrupted/uncertain
request also fails on retry instead of risking another move or charge. Inspect
Activity before creating another request. Claims survive Activity retention and
hold up to 10,000 requests. A completed request can be replayed for 30 days, after
which its claim is dropped, and the oldest completed claims make room when the store
is full. A claim whose result was never saved is kept, since replaying it is unsafe.

Replies contain `requestID`, `recordID`, optional `label`, `action`, `outcome` and
a bounded `reason`. A label is not an action acknowledgement. Cancellation stops pending work;
Mail operations already dispatched cannot be recalled.

## Command-line and AppleScript bridge

After macOS indexes the installed app, create a shortcut in Shortcuts containing the
appropriate SpamWise action, followed by **Stop and Output**, with the SpamWise
action's result as its input. The explicit output is required: with only the last
action's implicit output, `shortcuts run` waits indefinitely even though the intent
has returned. The **Filtering Status** App Shortcut is not a saved shortcut, so
`shortcuts run 'Filtering Status'` cannot find it; save a named shortcut instead.
For a retryable preview or correction, supply the caller's saved UUID as the
action's Request UUID rather than generating another UUID during a retry. Then
invoke the saved shortcut using Apple's CLI, for example:

```sh
shortcuts run 'SpamWise Status' --output-path "$PWD/status.json" </dev/null
```

An AppleScript can invoke that saved shortcut with `do shell script`. SpamWise does
not add an AppleScript dictionary or accept arbitrary source text in a URL. The
existing `spamwise://check-inbox` trigger remains subject to app safety settings.

## Testing

Package tests cover preview replay, mismatched-UUID rejection and one correction or
action per completed request; build-time metadata extraction must list all four
intents. Package tests alone do not establish native automation.

The native UI test is opt-in. It runs all four intents out of process through
`AppIntentsTesting` against one isolated fixture app: a mock classifier, one
synthetic selected message, and every other Mail script denied, so it makes no
provider call and no Mail operation. Install and launch the current signed debug
build so macOS indexes it, then pass its absolute path so XCTest launches the same
app that App Intents resolves:

```sh
TEST_RUNNER_SPAMWISE_INTENTS_TEST=1 \
TEST_RUNNER_SPAMWISE_INTENTS_APP_PATH="$HOME/Applications/SpamWise.app" \
  Scripts/ui-check.sh
```

The ordinary UI suite reports this test as skipped; it still exercises onboarding,
corrections, undo, corpus management and statistics.

### Registration problems

Keep only the test's SpamWise process running. Every SpamWise build shares the bundle
identifier, so with two running, intent execution can reach one process while XCTest
inspects the other's temporary store. The explicit app path applies to every app
launch in the suite.

`AppIntentsServicesMetadataErrorDomain Code=400` ("codes.tim.SpamWise is not
present") means Launch Services resolves the bundle identifier to a copy without
`Contents/Resources/Metadata.appintents`, typically an older installed build. Building
and launching a new copy under `.build` does not change that resolution. Check which
copy is selected and whether it carries metadata:

```sh
osascript -e 'POSIX path of (path to application id "codes.tim.SpamWise")'
ls ~/Applications/SpamWise.app/Contents/Resources/Metadata.appintents
```

To test a different copy, unregister the stale one and register the one under test,
then re-register the original afterward:

```sh
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u ~/Applications/SpamWise.app
"$lsregister" -f /path/to/SpamWise-under-test.app
```

`linkd` logs when it indexes the copy's `extract.actionsdata`. If `shortcuts run`
fails with `LNConnectionErrorDomain Code=1200` ("AppleEvents communication failed"),
another SpamWise process is still running: quit it and retry. Shortcuts shows its
**What's New** panel once on first launch; dismiss it before the SpamWise actions
appear in the action library.

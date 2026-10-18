# SpamWise support

Publication draft · Contact [Tim Morgan](mailto:tim@tim.codes)

SpamWise is a free macOS 27 application for Apple Mail. Optional external model
usage is billed by the provider. Public distribution is still being prepared.
There is no published download or App Store listing to link yet.

## Getting started

1. Open SpamWise and complete its setup, and allow SpamWise to control Mail when
   macOS asks. The Mail extension is needed only for its optional preview route.
2. Start with dry run enabled. Choose an available on-device model or configure an
   explicit provider. Enter API keys only in SpamWise, where they are saved in
   Keychain; grant mail-sharing permission separately for a remote provider.
3. Use Account settings to connect Mail; the check validates each account’s Inbox
   and Junk mailboxes without changing mail. Keep dry run on until you have
   reviewed its results, then turn it off in General and confirm.
4. Inspect Activity. Decisions, attempted mail actions and action failures are
   separate. Confidence thresholds are provisional and do not promise a particular
   accuracy rate.

SpamWise and Mail must remain running for monitoring. Closing SpamWise’s windows
leaves its menu-bar app running; quitting stops its monitor. Launch at login is
optional in General settings. Screen lock and sleep/wake acceptance remain under
test; no immediate-delivery guarantee is made.

## If mail is not being classified

Check Pause, account inclusion, the selected provider and mail-sharing permission.
Open Accounts and scan health for the last successful scan or reported failure.
Unreadable mail stays in place while later readable messages can be processed.
Permission failures and timeouts leave mail untouched. In System Settings →
Privacy & Security → Automation, check SpamWise’s Mail permission. Contacts access
is optional and is separate from Mail access.

The optional Mail extension preview cannot filter by account and never moves
mail. The account sweep route supplies filtering; large or changing mailboxes may
take several sweeps. See the [tested compatibility matrix](mail-compatibility.md).

## Correcting a decision

Use the Activity inspector or SpamWise’s menu-bar commands for selected Mail
messages. Ordinary corrections create address rules. Choose domain scope explicitly
when you intend to affect a whole domain. Address rules take precedence over domain
rules and relationship trust. A saved correction can remain in effect even if its
mail action fails; check the displayed action outcome.

Review Junk provides a bounded, read-only list until you explicitly choose to
restore a message. Junk membership alone is not treated as a human training label.
SpamWise never deletes messages. If another filter or server rule moves mail again,
inspect that filter’s configuration; a confirmed client-side move is not a promise
that a server will leave the message there.

## Provider and cost problems

A missing key, rate limit, unavailable model, refusal or timeout leaves a message
unclassified. SpamWise does not silently choose another provider. Check the selected
provider’s account, billing and limits. Never email an API key, password or recovery
key to support. Usage costs are estimates; conservative budget reservations can
exceed billed usage. Dry run does not disable paid model requests.

See [privacy](privacy.md) before allowing cloud processing. Gemini’s unpaid terms
require particular care for personal mail. The on-device option’s current quality
is not established as a replacement for a trained spam detector.

## Reporting a problem

Email [tim@tim.codes](mailto:tim@tim.codes) with the SpamWise version, macOS version,
account provider, the steps you took, the expected result and the displayed error.
Use a synthetic message where possible. Share a redacted diagnostic export if it
helps, after reviewing it. Avoid sending real message source or screenshots that
expose other mail unless necessary and deliberately chosen.

For upgrades, recovery, login-item removal and optional data removal, follow the
[lifecycle guide](lifecycle.md). Back up learning before replacing a build, and keep
the recovery key separately. Removing SpamWise must not involve deleting Mail’s
databases, mailboxes or containers.

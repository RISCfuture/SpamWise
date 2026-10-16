# SpamWise support

Publication draft · Contact [Tim Morgan](mailto:tim@tim.codes)

SpamWise is a free macOS 27 application for Apple Mail. Optional external model
usage is billed by the provider. Public distribution is still being prepared.
There is no published download or App Store listing to link yet.

## Getting started

1. Open SpamWise and complete its setup, and allow SpamWise to control Mail when
   macOS asks.
2. Start with dry run enabled. In setup, or later in Settings → Classifier, choose
   Apple's on-device model or a cloud provider. Enter API keys only in SpamWise,
   where they are saved in Keychain; a cloud provider also needs its own permission
   to receive mail.
3. In Settings → Accounts, choose Check Mail Connection. The check finds each
   account’s Inbox and Junk mailboxes without changing mail. Keep dry run on until
   you have reviewed its results, then turn it off in Settings → General and
   confirm.
4. Inspect Activity. Decisions, attempted mail actions and action failures are
   separate. Confidence thresholds are provisional and do not promise a particular
   accuracy rate.

SpamWise and Mail must remain running for monitoring. Closing SpamWise’s windows
leaves its menu-bar app running; quitting stops its monitor. Launch at login is
optional in Settings → General. Screen lock and sleep/wake acceptance remain under
test; no immediate-delivery guarantee is made. The SpamWise menu-bar menu and the
bottom of the Activity window show what filtering is doing, such as dry run, paused,
offline or failing.

## If mail is not being classified

Check whether filtering is paused (Filtering → Resume Filtering), each account's
Filter this account switch in Settings → Accounts, and the provider, API key and mail
sharing in Settings → Classifier. Contacts, reply history and Good corrections let
mail skip classification only in accounts with a trusted mail server, so that the
sender's authentication can be checked; otherwise they count only as evidence for the
model. Each account in Settings → Accounts shows its trusted mail server, or a server
SpamWise detected for you to trust. Its Status shows the last check, a late, failing
or stalled check, and how much older mail is still to check. Select an unclassified
message in Activity and choose Classify Again once the cause is fixed. Unreadable
mail stays in place while later readable messages can be processed.
Permission failures and timeouts leave mail untouched. In System Settings →
Privacy & Security → Automation, check SpamWise’s Mail permission. Contacts access
is optional and is separate from Mail access.

SpamWise filters by scanning each account's Inbox through Mail; large or changing
mailboxes may take several sweeps. Enabling SpamWise in Mail's extension settings is
not required. See the [tested compatibility matrix](mail-compatibility.md).

## Correcting a decision

Use the Filtering menu or the inspector in Activity, or the menu-bar commands for
messages selected in Mail; a Correct Selected Mail shortcut in Shortcuts can do the
same from a key while Mail is in front. Ordinary corrections create address rules.
Choose domain scope explicitly when you intend to affect a whole domain. When
SpamWise can't verify a sender, it asks before blocking the address, because the From
address may be forged. Address rules take precedence over domain
rules and relationship trust. A saved correction can remain in effect even if its
mail action fails; check the displayed action outcome.

Review Junk, in the Filtering menu, provides a bounded, read-only list that says why
each message is there, until you explicitly choose to restore one. It asks first when
restoring would replace a Block rule. Junk membership alone is not treated as a human training label.
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

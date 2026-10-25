# SpamWise support

Publication draft · Contact [Tim Morgan](mailto:tim@tim.codes)

SpamWise is a free macOS 27 application for Apple Mail. Optional external model
usage is billed by the provider. Public distribution is still being prepared.
There is no published download or App Store listing to link yet.

## Getting started

1. Open SpamWise and complete its setup, and allow SpamWise to control Mail when
   macOS asks.
2. In setup, or later in Settings → Provider, choose Apple's on-device model or a
   cloud provider. Enter API keys only in SpamWise, where they are saved in Keychain;
   a cloud provider also needs its own permission to receive mail.
3. In Settings → Accounts, choose Check Mail Connection. The check finds each
   account’s Inbox and Junk mailboxes without changing mail.
4. SpamWise starts in dry run: Activity shows what it would do, and mail stays where
   it is. When the results look right, choose Start Filtering… in Activity, the
   Filtering menu or the menu bar menu, or turn off dry run in Settings → General,
   and confirm. Confidence thresholds are provisional and do not promise a particular
   accuracy rate.

SpamWise and Mail must both be open for filtering. Closing SpamWise’s windows keeps it
filtering; quitting stops it. Open SpamWise at login is optional in Settings →
General. SpamWise checks each Inbox about once a minute, so a new message can wait a
minute or more, and nothing is filtered while the Mac sleeps. The SpamWise menu bar
menu and the bottom of the Activity window show what filtering is doing, such as dry
run, paused, offline or failing. If you hide the menu bar item in Settings → General,
click SpamWise in the Dock to open Activity.

## If mail is not being classified

Check whether filtering is paused (Filtering → Resume Filtering), each account's
Filter this account switch in Settings → Accounts, and the provider, API key and mail
sharing in Settings → Provider. Contacts, reply history and Good corrections let
mail skip classification only in accounts with a trusted mail server, so that the
sender's authentication can be checked; otherwise they count only as evidence for the
model. Each account in Settings → Accounts shows its trusted mail server, or a server
SpamWise detected for you to trust. Its Status shows the last check, a late, failing
or stalled check, and how much older mail is still to check. Select an unclassified
message in Activity and choose Classify Again once the cause is fixed; saving a
missing API key retries the waiting mail by itself. Unreadable mail stays in place
while later readable messages are processed. Messages over 2 MB are left
unclassified.

Permission failures and timeouts leave mail untouched. In System Settings → Privacy &
Security → Automation, check SpamWise’s Mail permission. Contacts access is optional
and is separate from Mail access.

If an account says Mail hasn't set a Junk mailbox, select that account's junk folder
in Mail (create one on the server first if it has none), choose Mailbox › Use This
Mailbox For › Junk, then choose Check Mailboxes under the account's Mailboxes and
Details in Settings → Accounts. If Mail shows more than one Junk mailbox, keep the
role on one folder only.

SpamWise filters by checking each account's Inbox through Mail; large or changing
mailboxes may take several checks. Enabling SpamWise in Mail's extension settings is
not required. See [Mail compatibility](mail-compatibility.md).

## Correcting a decision

Use the Filtering menu or the inspector in Activity, or the menu bar commands for
messages selected in Mail; a Correct Selected Mail shortcut in Shortcuts can do the
same from a key while Mail is in front. Ordinary corrections create address rules.
Choose domain scope explicitly when you intend to affect a whole domain. When
SpamWise can't verify a sender, it asks before blocking the address, because the From
address may be forged. Address rules take precedence over domain rules and
relationship trust. A saved correction can remain in effect even if its mail action
fails; check the displayed action outcome.

If you move a message SpamWise put in Junk back to the Inbox in Mail, or choose Not
Junk, SpamWise treats it as marked Good on its next check and allows the sender. That
doesn't happen in dry run, or, with Apple Mail, within about 30 seconds of SpamWise's
move, while it confirms that the move held. Learning from it moves no mail. Once a
message marked Good is confirmed in the Inbox, SpamWise clears Mail's own junk mark on
it; it never sets that mark.

Review Junk, in the Filtering menu, provides a bounded, read-only list that says why
each message is there, until you explicitly choose to restore one. It asks first when
restoring would replace a Block rule. Junk membership alone is not treated as a
human training label. SpamWise never deletes messages.

Mail has its own Junk Mail filter, which is on by default. It can color and mark
Inbox messages in ways that look like SpamWise's Review mark, or move mail to Junk
itself. To leave sorting to SpamWise, open Mail → Settings → Junk Mail and turn off
Enable junk mail filtering; if you keep it on, its marks and moves are separate from
SpamWise's. If another filter or a server rule moves mail again, check that filter's
settings; a move SpamWise confirmed in Mail doesn't stop a server from moving the
message later.

## Provider and cost problems

A missing key, rate limit, unavailable model, refusal or timeout leaves a message
unclassified. SpamWise does not silently choose another provider. Check the selected
provider’s account, billing and limits. Never email an API key, password or recovery
key to support. Costs shown in SpamWise are estimates from the provider's published
prices, not your bill. With a monthly limit set, SpamWise counts each request's
largest possible cost until the request finishes, so it can stop at the limit
slightly before your bill would reach it. Dry run does not stop paid model requests.

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
[lifecycle guide](lifecycle.md). Back up learning before replacing the app, and keep
the recovery key separately. Removing SpamWise must not involve deleting Mail’s
databases, mailboxes or containers.

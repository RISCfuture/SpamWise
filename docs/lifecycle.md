# Install, upgrade, recover and remove

SpamWise comes in two editions: a notarized download from GitHub Releases and a Mac
App Store edition. Both share one identity, store and Keychain group, so keep exactly
one installed copy in Applications. Install a downloaded build only after its
signature, notarization, stapling and Gatekeeper checks pass. Development exports are
not release updates. Mail's extension list includes SpamWise, but filtering does not
depend on enabling it; the extension leaves every message to Mail.

## Upgrade and recovery

Before replacing the app, pause filtering and export an encrypted backup from
Settings. Save its recovery key separately. Quit SpamWise and Mail, replace the app
with the verified build, then reopen both and inspect Accounts and Activity in dry
run. Preserve the original App Group and Keychain identities. Account destination
validation is not transferable to another Mac, endpoint or account.

If startup or migration fails, keep filtering paused. Retain the prior signed app
and backup; an older executable is not guaranteed to read newer state. Restore a
compatible backup through the app rather than replacing a live SwiftData database.
Restore clears action validation, pauses filtering and keeps dry run on. It does not
reset budget commitments or duplicate-action protection. Revalidate destinations
before resuming actions. API keys remain in Keychain and are excluded from backups.

The download edition checks GitHub Releases on the schedule set in Settings →
General → App updates, or when you choose Check for Updates…. When you accept an
update it downloads the release's disk image; quit SpamWise and replace the app from
it as above. The App Store edition updates through the App Store. To switch editions,
install the new copy, launch it and confirm Accounts and Activity, then remove the old
one. The [distribution ledger](distribution-differences.md) lists what differs between
the editions.

## Stop background operation

Turn off **Open SpamWise at login** in Settings → General. Check System Settings →
General → Login Items if approval is pending or registration fails. Pause, then quit
SpamWise to stop its monitor; closing its windows leaves the menu-bar app running.

## Remove the app and optionally its data

Quitting and removing the app leaves learned state and Keychain credentials intact
for reinstall. To remove personal state as well, export anything you want to retain,
turn off the login item and quit both Mail and SpamWise first. In Finder,
use Go → Go to Folder to inspect only SpamWise's containers:

- `~/Library/Group Containers/group.codes.tim.SpamWise/` holds shared state, action
  claims, budget accounting, the Contacts snapshot and the domain-age cache.
- `~/Library/Containers/codes.tim.SpamWise/` holds app preferences and sandbox data.
- The extension container uses its preserved bundle identifier
  `codes.tim.SpamWise.MailExtension`; confirm the identifier on the installed bundle
  before removing its matching container.

Remove these only if you intend to discard that state. Full removal also discards
historical spending/replay protection; restore or reauthorize a spending limit before
running paid evaluation again. Do not remove Mail's containers, databases or mailboxes.

In Keychain Access, remove only SpamWise credentials whose service starts with
`codes.tim.SpamWise.` and which you intend to discard: provider API keys, the
Spamhaus query key and IMAP credentials. Never remove team-wide signing keys.
Delete independently saved backups/recovery keys only when you no longer need them.
SpamWise does not remove messages as part of uninstall.

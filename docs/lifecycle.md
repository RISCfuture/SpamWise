# Install, upgrade, recover and remove

SpamWise comes in two editions: a notarized download from GitHub Releases and a Mac
App Store edition. Both share one identity, store and Keychain group, so keep exactly
one installed copy in Applications. Install only a release from GitHub Releases or the
App Store. Mail's extension list includes SpamWise, but filtering does not depend on
enabling it; the extension leaves every message to Mail.

## Upgrade and recovery

Before replacing the app, pause filtering and choose File → Export Backup… (also in
Settings → Advanced, under Backup and restore). Save its recovery key separately.
Quit SpamWise and Mail, replace the app with the new release, then reopen both and
check Accounts and Activity while dry run is on. A mailbox check doesn't carry over to
another Mac or account; choose Check Mail Connection there.

If SpamWise opens with “Some SpamWise data couldn’t be read”, it has set that data
aside and runs with everything else, leaving mail unchanged. Choose Save a Copy… to
keep the set-aside data, then restore a backup there, or choose Keep Current
Settings… to discard it. If SpamWise can't start, keep filtering paused, and keep the
previous version of the app and your backup until the new version works: an older
version can't open data that a newer version has saved. Restore a backup through the
app (File → Restore from Backup…) rather than copying its data folder between Macs.

Restore pauses filtering, turns dry run on and clears the mailbox check, so choose
Check Mail Connection again before you leave dry run. It doesn't change this Mac's
monthly spending or forget which messages SpamWise has already acted on. It also keeps
this Mac's **Keep text of reviewed messages** setting: while that is off, the backup's
saved message text, including the excerpts kept with corrections, isn't restored. API
keys stay in Keychain and are never part of a backup.

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
SpamWise to stop filtering; closing its windows leaves it running, reachable from its
menu bar item or, when that is hidden, its Dock icon.

## Remove credentials

SpamWise keeps provider API keys, the Spamhaus query key and the IMAP password in its
shared Keychain group, which Keychain Access may not show. Remove them from SpamWise:

- **One credential:** in Settings → Accounts → Keys and passwords, choose Remove next
  to it. Mail isn't classified with that provider until you add a key again.
- **The IMAP connection:** in Settings → Accounts, choose Forget Connection…. SpamWise
  deletes the IMAP password, revokes that connection's mailbox check and switches back
  to Apple Mail with dry run on.
- **Everything:** choose Remove All SpamWise Keys and Passwords… under Keys and
  passwords.

Do this before removing the app if you won't reinstall it. Removing the app alone
leaves these credentials in Keychain.

## Remove the app and optionally its data

Quitting and removing the app leaves learned state and Keychain credentials intact
for reinstall. To remove personal state as well, export anything you want to keep,
remove credentials as above, turn off the login item and quit both Mail and SpamWise
first. In Finder, use Go → Go to Folder to inspect only SpamWise's containers:

- `~/Library/Group Containers/group.codes.tim.SpamWise/` holds shared state, action
  records, spending, the Contacts snapshot and the domain-age cache.
- `~/Library/Containers/codes.tim.SpamWise/` holds app preferences and sandbox data.
- `~/Library/Containers/codes.tim.SpamWise.MailExtension/` belongs to the Mail
  extension.

Remove these only if you intend to discard that state. Removing them also discards
this month's spending record and SpamWise's record of the messages it has acted on;
set your monthly spending limit again after reinstalling. Do not remove Mail's
containers, databases or mailboxes.

Delete independently saved backups and recovery keys only when you no longer need
them. SpamWise does not remove messages as part of uninstall.

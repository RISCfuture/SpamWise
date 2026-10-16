# Install, upgrade, recover and remove

SpamWise comes in two editions: a notarized download from GitHub Releases and a Mac
App Store edition. Both share one identity, store and Keychain group, so keep exactly
one installed copy in Applications. Install a downloaded build only after its
signature, notarization, stapling and Gatekeeper checks pass. Development exports are
not release updates. Mail's extension list includes SpamWise, but filtering does not
depend on enabling it; the extension leaves every message to Mail.

## Upgrade and recovery

Before replacing the app, pause filtering and choose File → Export Backup… (also in
Settings → Advanced, under Backup and restore). Save its recovery key separately.
Quit SpamWise and Mail, replace the app with the verified build, then reopen both and
inspect Accounts and Activity in dry run. Preserve the original App Group and Keychain
identities. Account destination validation is not transferable to another Mac,
endpoint or account.

If SpamWise opens with “Some SpamWise data couldn’t be read”, it has set that data
aside and runs with everything else, leaving mail unchanged. Choose Save a Copy… to
keep the set-aside data, then restore a backup there, or choose Keep Current
Settings… to discard it. If startup or migration fails, keep filtering paused. Retain
the prior signed app and backup; an older executable is not guaranteed to read newer
state, and an older build cannot open a store migrated to a newer schema. Restore a
compatible backup through the app (File → Restore from Backup…) rather than replacing
a live SwiftData database. Restore clears action validation, pauses filtering and keeps dry run on. It does not
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

## Remove credentials

SpamWise keeps provider API keys, the Spamhaus query key and the IMAP password or
token in its shared Keychain group, which Keychain Access may not show. Remove them
from SpamWise:

- **One credential:** in Settings → Accounts → Keys and passwords, choose Remove next
  to it. Mail isn't classified with that provider until you add a key again.
- **The IMAP connection:** in Settings → Accounts, choose Forget Connection…. SpamWise
  deletes the IMAP password, revokes that connection's validation and switches back to
  Apple Mail with dry run on.
- **Everything:** choose Remove All SpamWise Keys and Passwords… under Keys and
  passwords.

Do this before removing the app if you won't reinstall it. Removing the app alone
leaves these credentials in Keychain. A setup key saved for the evaluation tools with
`Scripts/store-provider-key.swift` is a separate login-Keychain item; remove it in
Keychain Access, where its service starts with `codes.tim.SpamWise.` and ends in
`.setup`.

## Remove the app and optionally its data

Quitting and removing the app leaves learned state and Keychain credentials intact
for reinstall. To remove personal state as well, export anything you want to retain,
remove credentials as above, turn off the login item and quit both Mail and SpamWise
first. In Finder,
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

Never remove team-wide signing keys. Delete independently saved backups and recovery
keys only when you no longer need them. SpamWise does not remove messages as part of
uninstall.

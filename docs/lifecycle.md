# Install, upgrade, recover and remove

Use the Developer ID app only after signature, notarization, stapling and Gatekeeper
checks pass for that exact artifact. Keep one installed copy in Applications and
enable SpamWise in Mail → Settings → Extensions. Development exports are not release
updates. App Store distribution remains separately pending App Review.

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

The preferred update path is the Mac App Store, pending the
[feasibility and release gates](app-store-feasibility.md). A store build must use
App Store updates. If that distribution proves unsuitable, the authorized fallback
is GitHub Releases with the owner’s GitHubUpdateChecker library. No external update
mechanism is enabled. SS-20 remains open until the chosen distribution and upgrade
path are tested; a successful archive alone does not establish this.

## Stop background operation

Turn off **Open SpamWise at login** in Settings → General. Check System Settings →
General → Login Items if approval is pending or registration fails. Pause, then quit
SpamWise to stop its monitor; closing its windows leaves the menu-bar app running.
Disable SpamWise in Mail → Settings → Extensions before removal.

## Remove the app and optionally its data

Quitting and removing the app leaves learned state and Keychain credentials intact
for reinstall. To remove personal state as well, export anything you want to retain,
disable its extension/login item and quit both Mail and SpamWise first. In Finder,
use Go → Go to Folder to inspect only SpamWise's containers:

- `~/Library/Group Containers/group.codes.tim.SpamWise/` holds shared state, action
  claims, budget accounting and evidence caches.
- `~/Library/Containers/codes.tim.SpamWise/` holds app preferences and sandbox data.
- The extension container uses its preserved bundle identifier
  `codes.tim.SpamWise.MailExtension`; confirm the identifier on the installed bundle
  before removing its matching container.

Remove these only if you intend to discard that state. Full removal also discards
historical spending/replay protection; restore or reauthorize a spending limit before
running paid evaluation again. Do not remove Mail's containers, databases or mailboxes.

In Keychain Access, remove only SpamWise credentials whose service starts with
`codes.tim.SpamWise.` and which you intend to discard. This includes the optional
setup credential and provider credentials; never remove team-wide signing keys.
Delete independently saved backups/recovery keys only when you no longer need them.
SpamWise does not remove messages as part of uninstall.

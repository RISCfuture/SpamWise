# Live Mail follow-up

These checks used an installed, notarized Developer ID build on macOS 27, with two
authorized cross-account messages addressed to the owner's iCloud account. Native
signed-app actions and independent Mail Apple Events inspection supplied the
observations. Typed Store helpers staged bounded settings and restored snapshots;
this was not a fresh-onboarding acceptance run. Status for the items it covers is in
[TODO.md](../../TODO.md).

## Observed results

| Check | Observation | Limit |
| --- | --- | --- |
| Mark read after Junk | The signed menu correction moved the selected generated message to iCloud Junk; it stayed unread while the move settled, then became read after confirmation | One generated message; the observation is not a server acknowledgement |
| Historical folder preview | The selected generated folder held one message; Preview this page completed with no action and `consentRequired` | No model-quality claim; provider consent stayed off |
| Renamed folder | Renaming the generated folder made the stored old path fail closed; its message stayed unread in the renamed folder | The build's error text was misleading; the corrected wording has not been seen at runtime |
| Closed windows | With no SpamWise windows open, the iCloud scan cursor advanced by one page and recorded success | The Mac stayed awake and connected |
| App relaunch | After a graceful relaunch and closing the startup window, the cursor advanced another page with success | One observed startup; no latency guarantee |
| Correction cleanup | Removing the sole generated rule and forgetting the sole reviewed label through the signed UI restored zero rules, correction examples and labels | Audit and activity records remain as observations |

The Junk correction recorded both the action outcome and the read-status outcome as
`applied`, with no read-status error. Exact-source SHA-256 values matched before and
after the move. The received message's local ID changed, as Mail moves do.

The build reported more than one message matching the identity after the folder
rename, although the configured folder no longer existed. Unresolved account and
folder paths now map to a folder error that asks for the folder to be selected again.

At the time, the Mail extension also recorded when Mail delivered message bodies to
it, and those timestamps updated about two seconds after a controlled delivery once a
stale extension registration ("other version in use") was cleared by restarting Mail.
The extension now returns no decision and records nothing, because MailKit messages
carry no account identity SpamWise can trust.

## Cleanup and preserved state

Both generated received copies and both Google Sent copies were matched by exact
account, Message-ID, subject and local ID before operator cleanup. All four were
verified in their accounts' Trash, with no matching copies in Inbox, Junk or Sent. No
Trash was emptied and no ordinary message was changed. The generated empty folder was
deleted through Mail's native confirmation and verified absent.

Complete saved preferences were restored: Pause off, dry run on, Claude selected,
provider consent off, both prior validated routes retained, no generated account or
folder scope, and the original read preference. Generated rules, correction examples,
reviewed labels and the generated folder-health row were removed. The run made no
paid model calls.

An optional OpenAI operational-key import could not complete: the helper's
login-Keychain read blocked inside SecurityServer decryption despite requesting a
noninteractive read, and left a Keychain prompt that expired unapproved. No key was
printed, placed in arguments or a file, or saved by the signed app.

## Provider disclosure inspection

A development-signed build launched with `--ui-testing --ui-visual-fixture` and an
English, Spanish or French language argument used isolated temporary storage and
preferences, with monitoring disabled. In Accounts, with Gemini selected and its
sharing disclosure expanded, all three languages showed the full unpaid-service
model-improvement and human-review warning, the data description, the revocation and
retention text and the localized retention link, without overlap or clipping at the
default Settings window size. The consent toggle stayed off, and the link points to
`https://ai.google.dev/gemini-api/terms`.

## Not covered

Slow or offline responses and cancellation, delivery coverage, screen
lock/sleep/wake/restart, second-device training-folder placement, coexistence with
another active filter, signed notification delivery and deep links, and OpenAI
operational-key import. Nothing here establishes representative classifier accuracy
or calibrated production thresholds.

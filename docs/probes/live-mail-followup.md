# Live Mail follow-up — October 16, 2026

These checks used the installed, notarized Developer ID app at `f7635ac` on
macOS 27, with two authorized cross-account messages addressed to the user's
iCloud account. Native signed-app actions and independent Mail Apple Events
inspection supplied the observations. Typed Store helpers staged bounded settings
and restored snapshots; this was not a fresh-onboarding acceptance run.

## Observed results

| Check | Observation | Limit |
| --- | --- | --- |
| Incoming MailKit body | After a graceful Mail restart, delivery at 23:21:43 PDT updated both signed extension/body timestamps at 23:21:45 | No account bridge, deadline stress, server-routed Junk or provider call was exercised |
| Mark read after Junk | The signed menu correction moved the selected generated message to iCloud Junk; it remained unread during settling, then became read after confirmation | One generated message; the 30-second observation is not a server acknowledgement |
| Historical folder preview | The selected generated folder contained one message; Preview this page completed with no action and `consentRequired` | No model-quality claim; provider consent remained off |
| Renamed folder | Renaming the generated folder caused the stored old path to fail closed; its message stayed unread in the renamed folder | Installed error text was misleading; corrected source wording was not runtime verified here |
| Closed windows | With zero SpamWise windows, the iCloud scan cursor advanced from 160 to 180 and recorded success at 23:31:19 | Mac remained awake and connected |
| App relaunch | After graceful relaunch at 23:32:09 and closing the startup window, the cursor advanced to 200 with success at 23:33:11 | One observed startup; no latency guarantee |
| Correction cleanup | Removing the sole generated rule and forgetting the sole reviewed label through the signed UI restored zero rules, correction examples and labels | Audit/activity records remain as observations |

The Junk correction recorded both action outcome and read-status outcome as
`applied`, with no read-status error. Exact-source SHA-256 values matched before and
after the move. The received message's local ID changed, as expected for Mail moves.

The first incoming probe did not update heartbeat timestamps. Mail logs reported
PlugInKit Code 16, “other version in use,” and ended with “Extension not found while
attempting to find action.” No visible compose window was open. Mail quit normally,
the installed extension was re-added without unregistering shared build copies,
and Mail was reopened. The next generated delivery updated both timestamps. This
establishes a successful callback observation after refreshing the host, rather than
uninterrupted extension availability across app replacement.

The installed renamed-folder diagnostic said more than one message matched the
identity, although the configured folder no longer existed. The later source fix
maps this case to an unresolved-folder diagnostic asking for selection again.
The fail-open behavior was observed here; the revised wording needs the new build.

## Cleanup and preserved state

Both generated received copies and both Google Sent copies were matched by exact
account, Message-ID, subject and local ID before operator cleanup. All four were
verified in their accounts' Trash, with no matching copies in Inbox, Junk or Sent.
No Trash was emptied and no ordinary message was changed. The generated empty
folder was deleted through Mail's native confirmation and verified absent.

Complete saved preferences were restored: Pause off, dry run on, Claude selected,
provider consent off, both prior validated routes retained, no generated account or
folder scope, and the original read preference. Generated rules, correction examples,
reviewed labels and the generated folder-health row were removed. Existing activity
and account scan observations remain. Recorded cost stayed at $0.000936; this run
made no paid model calls. SpamWise was left closed, own Mail probe windows closed,
and Mail hidden. Mail remains running after its graceful restart; its restored
All Inboxes window is hidden rather than recreating the prior Settings window.

An optional OpenAI operational-key import could not complete: the private helper's
login-Keychain read blocked inside SecurityServer decryption. Only that helper was
stopped. No key was printed, placed in arguments or a file, transferred to the field,
or saved by the signed app. No Verify request was made. The operational import gate
remains open. A later XCTest recording revealed a lingering login-Keychain prompt
for that stopped helper, despite requesting a noninteractive read. The prompt
expired without approval; subsequent inspection found no helper or SecurityAgent
process/window. The first final UI run failed its two startup assertions while
that prompt was visible; its unchanged retry is tracked separately.

## Provider disclosure inspection

The newly built development-signed app in
`.build/cb38d7c0-dd6a-48b3-b59d-6cc4c75083d0/DerivedData/Build/Products/Debug/SpamWise.app`
was launched by explicit path with `--ui-testing --ui-visual-fixture` and a separate
English, Spanish or French language argument. Each launch used isolated temporary
storage and preferences, with monitoring disabled. Production preferences were not
used for these checks.

In Accounts, Gemini was selected and its sharing disclosure expanded. All three
languages showed the full unpaid-service model-improvement/human-review warning,
the data description, revocation/retention text and the localized retention link
without overlap or clipped text at the default Settings window size. The consent
toggle stayed off. The link exposed `provider.privacyTerms`; source inspection
confirmed the Gemini destination `https://ai.google.dev/gemini-api/terms`. No browser,
provider request or credential operation was needed. The isolated app was closed.

## Evidence and remaining gates

Private local artifacts are under
`.build/ad8f9d1c-5d0d-427e-8d37-ce12c3701956/`:

- `baseline.json`, `callback-after-relaunch.json`, `mailkit-startup.log`:
  incoming callback and stale-host observations.
- `mark-read-result.json`, `probe-source.sha256`, `probe-after-junk.sha256`:
  confirmed action, read outcome and source equality.
- `folder-preview.json`, `health-before-close.json`,
  `health-windows-closed.json`, `health-after-relaunch.json`:
  preview, missing-folder failure and background progression.
- `windows-closed-time.txt`, `relaunch-time.txt`: observation boundaries.
- `original-settings.json`, `full-settings.json`, `restored-state.json`:
  restoration evidence.
- `cleanup-mail.applescript`, `cleanup-confirmation.txt`: exact cleanup guards and
  final identities for four copies.
- `key-import-sample.txt`: blocked credential-access stack without credential data.
- `disclosure-en.png`, `disclosure-es.png`, `disclosure-fr.png`, with corresponding
  `.txt` accessibility captures: expanded localized Gemini disclosures.
- `ui-failed-activities.json`, `ui-failed-attachments/`, `ui-failure.png`:
  XCTest startup failure evidence showing the temporary owned Keychain prompt.

Still unverified are slow/offline responses and cancellation, delivery coverage and
MailKit account identity, screen lock/sleep/wake/machine restart, second-device
training-folder placement, coexistence with another active filter, signed notification
delivery/deep links, and OpenAI operational-key import. No result here establishes
representative classifier accuracy or calibrated production thresholds.

# Live selected corrections and Junk rescue

On 2026-10-16, the installed notarized standard app at
`~/Applications/SpamWise.app` completed both flows against one disposable,
uniquely named cross-account message. This acceptance used the existing validated
Google and iCloud accounts, with Google sending to the iCloud receiving account.
No provider request was made.

## Isolation and results

Automatic filtering was paused before launch. Both account filtering switches
were then disabled, leaving an explicit empty account scope and no configured
folder plans. Provider consent stayed off. Only after verifying those settings
were Pause and dry run temporarily disabled for manual actions.

| Native flow | Observed result |
| --- | --- |
| Select the exact received message in Mail; choose Mark as Junk from SpamWise's menu | Correction saved; applied Junk move; unique receiving-account Junk copy and zero Inbox copies after settling |
| Review Junk; select iCloud; load the page; select the exact probe; choose Mark Good and restore | Correction saved; applied Inbox move; unique receiving-account Inbox copy and zero Junk copies after settling |

The Junk correction began at 22:30:39 PDT. The restore began at 22:34:13 PDT and
was confirmed after the adapter's 30-second observation window. Independent
Apple Events reads confirmed both locations, changed local message IDs, and
identical source SHA-256 before and after each move. This verifies the observed
Mail client state, not a separate server acknowledgement. The probe's private
identity and source digest are retained under
`.build/14903120-a82f-4ad9-8b2a-fd2ffef477ae/`.

The selected-message results sheet displayed “Correction saved. Mail action:
Applied.” Review Junk displayed the generated message text and the restore
control without clipping. Native accessibility inspection through System Events
was necessary for sheets whose hierarchy was empty in the screenshot tool.

An initial menu invocation while an automatic empty sweep was busy produced no
correction or move. The successful invocation followed confirmation that the
menu item was enabled. Empty account scope prevented automatic classification,
but the sweep could still perform read-only history maintenance.

## Cleanup and limits

Pause and dry run were restored before cleanup. The generated address rule and
reviewed label were removed through the UI. The installed build's Forget action
left two correction examples with absent sample IDs; a guarded typed Store
transaction removed only their captured UUIDs. Independent reads verified the
probe sender's rule and example counts returned to their zero baselines, and the
probe label was absent. This finding prompted the separately tested correction
identity fix; these live actions used the earlier installed build.

Only the exact received and Sent copies were moved to their respective account
Trash as authorized test cleanup, guarded by account, mailbox, local ID,
Message-ID, and exact subject. This cleanup is an agent operation; SpamWise's
product action set contains no delete or Trash action. Original filtering
preferences were restored from the saved typed snapshot: monitoring resumed,
dry run enabled, all-account scope and no folder plans. The correction-identity
update passed the offline correction UI flow, was notarized, and replaced the
installed app after these live actions and cleanup completed.

This check establishes one live selected-message Junk correction and one live
Junk rescue. It does not establish MailKit delivery, classifier accuracy, an
independent server acknowledgement, or unattended filtering quality.

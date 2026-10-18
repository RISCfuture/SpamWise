# Mail.app compatibility and acceptance

SpamWise targets **macOS 27** and Apple Mail. The package and app require Swift 6.4 /
Xcode 27 for development. Builds and runtime checks in this repository used an
Apple-silicon Mac. Intel execution and older macOS versions are unverified; do not
lower the deployment target as a compatibility claim. Apple's on-device classifier
also requires Apple Intelligence availability and downloaded model assets. Provider
availability is checked at runtime and never causes a silent model substitution.

## Observed account behavior

The matrix below comes from signed-app probes with generated cross-account messages.
It describes those probes, not blanket provider certification; open coverage is
tracked in [TODO.md](../TODO.md), and the
[live Mail follow-up](probes/live-mail-followup.md) records the newer workflows.

| Mail.app account | Apple Events connection | Inbox/Junk round trip | Orange flag | Offline/reconnect | Newer workflows |
| --- | --- | --- | --- | --- | --- |
| iCloud | Passed | Passed | Passed | Pending | Confirmed Junk then read status, historical preview, renamed-folder fail-closed, closed-window and relaunch scanning |
| Google | Passed | Passed | Passed | Pending | Pending |
| Exchange / Microsoft 365 in Mail | Not tested | Not tested | Not tested | Not tested | Not tested |
| Other accounts in Mail | Not tested | Not tested | Not tested | Not tested | Not tested |

Probes are sent from another account so that the receiving account holds no Sent copy
with the same Message-ID; same-account duplicates are ambiguous and left untouched. A
move immediately after self-sent mail arrived proved unstable: Mail later put the
message in Recovered Messages. After each move, SpamWise polls the message every two
seconds and confirms the move after two consecutive matching observations, giving up
after 30 seconds. That is an observation of Mail's local state, not a server
acknowledgement, and the Apple Events handlers rewritten since these probes still need
a fresh signed run.

Mail's account-specific special Inbox/Junk roles are used for moves; SpamWise does
not guess a destination by name. Accounts → Mailbox destinations reads those roles
without reading message bodies or enabling actions. Names alone do not prove Gmail
system labels. During authorized probe cleanup, Mail's Google Trash role mapped to a
custom Deleted Messages folder; operator cleanup required exact-message Gmail system
TRASH verification. The product exposes no Trash/delete action. A Junk role must be
validated on its own, not inferred from the behavior of another role.

## Incoming routes

The signed Apple Events route polls Mail.app and supports bounded account/folder
sweeps. It needs SpamWise and Mail running on an awake Mac, Automation permission,
and available message sources. Keep dry run enabled for comparisons with SpamSieve
and server rules. Their classifications and folder membership are not human labels.

Mail also lists SpamWise's MailKit extension, which returns no decision for any
message. MailKit messages carry no account identity SpamWise can trust, so the
extension cannot pick an account's own Junk mailbox; all filtering happens through
the Apple Events sweeps above.

## Repeatable acceptance matrix

For each configured account, use uniquely identified, disposable cross-account mail
and retain its exact identities. Record initial role mapping, delivery time, first
scan time, decision path, source mailbox, intended action and settled outcome.
Exercise Inbox delivery, server-routed folders, repeated sweeps, restart, wake,
reconnect and a changing multi-page mailbox. Compare two filters with
SpamWise in dry run first. Never send ordinary Junk through training automatically.

New workflows also need explicit selected corrections, Junk restore, mark-as-read,
dedicated training-folder placement from a second device, and renamed/missing-folder
checks. Only generated messages may be used for action probes. Clean up their exact
received/Sent/draft copies when finished, without emptying Trash or touching ordinary
Junk. Preserve unexplained gaps and uncertain actions as failures, not successes.

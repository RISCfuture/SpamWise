# Mail.app compatibility and acceptance

SpamWise targets **macOS 27** and Apple Mail. The package and app require Swift 6.4 /
Xcode 27 for development. Builds and runtime checks in this repository used an
Apple-silicon Mac. Intel execution and older macOS versions are unverified; do not
lower the deployment target as a compatibility claim. Apple's on-device classifier
also requires Apple Intelligence availability and downloaded model assets. Provider
availability is checked at runtime and never causes a silent model substitution.

## Observed account behavior

The evidence below is from signed-app probes recorded in `CLAUDE.md` on October 16,
2026. It describes those probes, not blanket provider certification or acceptance of
all later parity features.

| Mail.app account | Apple Events connection | Inbox/Junk round trip | Orange flag | Offline/reconnect | New parity workflows |
| --- | --- | --- | --- | --- | --- |
| iCloud | Passed | Passed at 08:42 PDT, with 30-second settling per move | Passed | Pending | Pending |
| Google | Passed | Passed at 08:45 PDT, with 30-second settling per move | Passed | Pending | Pending |
| Exchange / Microsoft 365 in Mail | Not tested | Not tested | Not tested | Not tested | Not tested |
| Other accounts in Mail | Not tested | Not tested | Not tested | Not tested | Not tested |

The cross-account probes avoided duplicate Message-IDs in the receiving account's
Sent mailbox. Same-account duplicates remain ambiguous and untouched. An earlier
immediate self-mail move was unstable and appeared in Recovered Messages; subsequent
settled cross-account probes passed. Thirty seconds is an observation interval,
not an independent server acknowledgement.

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

MailKit's principal object launches, but incoming/body callback timestamps were
absent during the installed-app probe. Stable account identity and timing under
server-routed Junk, delays and cancellation are still unvalidated. MailKit remains
dry-run only; a successful extension build does not establish delivery coverage.

## Repeatable acceptance matrix

For each configured account, use uniquely identified, disposable cross-account mail
and retain its exact identities. Record initial role mapping, delivery time, first
scan time, decision path, source mailbox, intended action and settled outcome.
Exercise Inbox delivery, server-routed folders, no MailKit callback, repeated sweeps,
restart, wake, reconnect and a changing multi-page mailbox. Compare two filters with
SpamWise in dry run first. Never send ordinary Junk through training automatically.

New workflows also need explicit selected corrections, Junk restore, mark-as-read,
dedicated training-folder placement from a second device, and renamed/missing-folder
checks. Only generated messages may be used for action probes. Clean up their exact
received/Sent/draft copies when finished, without emptying Trash or touching ordinary
Junk. Preserve unexplained gaps and uncertain actions as failures, not successes.

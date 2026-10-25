# Live acceptance, October 25, 2026

A development-signed Debug build of the App Store edition, installed as the only
registered copy, ran against the owner's Mail with an iCloud account and a Gmail
account (configured in Mail as a generic IMAP account). Setup had just finished with
Claude Haiku as the provider and mail-sharing consent on. Four unread Inbox messages
that the owner identified as spam or graymail, and generated `[SpamWise Probe]`
messages sent cross-account with Mail's AppleScript, were the only mail acted on.
Independent Apple Events reads by Message-ID, the app's own store (read-only), and
Gmail label reads supplied the observations. Status for each item is in
[TODO.md](../../TODO.md).

## Results

| Area | Check | Result |
| --- | --- | --- |
| Accessibility | Menu bar item's accessibility name | Fixed: it read "Get Mail" (the envelope symbol's description); it now reads "SpamWise: *state*" |
| Dry run | Preview Selected Mail (Shortcuts) on the four owner-identified messages | Four Review verdicts (two promotion, one cold outreach, one transactional; confidence 62–80); Activity outcome Dry run; no flag, move or mailbox change in Mail |
| Going live | Start Filtering… and its confirmation | Passed; the dialog explains Junk moves, Review marks, move checks and no retry or reversal. Earlier previews were not applied |
| Automatic filtering | 16 probes, plain and HTML, spammy and benign, both directions | Benign Gmail-received probes stayed in Inbox; scams, promotions and cold outreach got Review with an orange flag; Sender-rule Block gates moved seven probes to Junk and confirmed each move. The model returned no Junk verdict, so no model-driven Junk move ran |
| Server filtering | Gmail-to-iCloud probes | iCloud's server put all three in Junk before SpamWise saw them; one iCloud-to-Gmail probe bounced |
| Corrections | Mark as Good, Mark as Junk, Mark for Review from the menu bar | Passed: flag removed, confirmed Junk move, flag added; each wrote the expected address rule |
| Unverified sender | Junk correction without trusted authentication | Confirmation offered Cancel, Skip Unverified Senders and Block All |
| Domain scope | Allow Senders' Domains on a shared-provider address | Skipped with an explanation; Block Senders' Domains on a company domain wrote a domain rule and moved the message |
| Batch and Stop | Six-message Junk batch, Stop after starting | Four corrections already in flight finished; the other two did not start. In-flight moves stayed "Sent to Mail" |
| Undo | Undo Latest Correction after a batch | Reverted only the last message's correction; the batch's Block rule stayed |
| Review Junk | Restore two probes from iCloud Junk | Moved to Inbox and recorded Good. Fixed: the list now fills the sheet and the result stays visible after the row leaves the page |
| Learning from Mail | Move an automatically junked probe back to Inbox in Mail | After about 90 seconds an implicit Good correction replaced the Block rule; the message was not moved again |
| Lifecycle | Hide the menu bar item; reopen from the Dock and `open -a` | Activity opened each time |
| URL | `open -g spamwise://check-inbox` with Mail frontmost | Mail stayed frontmost, no window opened, both accounts were checked within a second, while running and when the URL launched the app |
| Pause | Pause, deliver a probe, Resume | Nothing was checked while paused; Resume checked within seconds |
| App Intents | Preview Selected Mail, Correct Selected Mail | Both brought SpamWise to the front; Shortcuts asked once to allow the app's actions and output |

## Fixture criterion

The five fixtures ran once against Claude Haiku with `--state eval/fixture-state.json`
and a private budget ledger: both good fixtures went to Inbox, the graymail fixture to
Review, and both junk fixtures to Review (one model Junk verdict at confidence 72,
below the Balanced threshold; one Review verdict). The criterion's two Junk outcomes
were not met. Five provider calls used 12,810 input and 427 output tokens, an
estimated $0.0015.

## Findings

- With no trusted receiving server configured, the model cited unverified
  authentication and chose Review for every scam and spam probe; across the run no
  model verdict produced an automatic Junk move.
- In Mail, the Gmail account's Junk role is a custom "Junk" label and its Trash role a
  custom "Deleted Messages" label, not Gmail's system Spam and Trash. Junk moves
  therefore never reach Gmail's Spam, and the setup check did not flag the custom label.
- Restoring a message as Good moves it but leaves Mail's own junk mark, so Mail still
  shows it as junk in Inbox.
- One automatic Review flag applied in Mail but its outcome stayed unconfirmed.
- Each selected-message correction adds two Activity rows: the selection record and
  the correction.
- One Preview Selected Mail run from the `shortcuts` command line waited three minutes
  with no request reaching the app; the next run finished in seconds.

## Cost, prompts and cleanup

Classification in the app cost an estimated $0.006 for 15 provider requests, which
include two ordinary messages that arrived while filtering was live. A macOS Contacts
prompt for SpamWise stayed unanswered throughout and needs the owner.

All 15 Gmail-received copies and 3 Gmail Sent copies were moved to Mail's Trash role
for that account, the custom "Deleted Messages" label; the available tools could not
apply Gmail's system Trash label, so those 18 messages still need trashing in Gmail.
All iCloud Sent copies, received copies, two leftover drafts and one delivery-failure
notice generated by a probe are in the iCloud account's Deleted Messages. No Trash was
emptied and no other mail moved.

Probe rules and the 14 probe-derived reviewed labels were removed. The four
owner-identified messages are in their accounts' Junk, with their Junk labels and
Block rules kept. Dry run is on again and the menu bar item is shown.

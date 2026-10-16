# SpamSieve parity implementation

The Mail.app-only backlog is in [TODO.md](../TODO.md). A checked implementation
step does not establish server interoperability, calibration or runtime acceptance.
No live API calls or test messages have been needed for this implementation batch.

## Reliability and privacy

- SS-01: Inbox scans now page each account independently. Progress is stored only
  after processing a page, survives restart and wraps for another sweep. One failed
  account does not stop the remaining accounts. Accounts shows last successful page,
  observed size, cursor and sanitized failure. Paging a mutating mailbox still needs
  repeated sweeps; unread-message counts and guaranteed delivery are not inferred.
- SS-03: explicit local mode blocks cloud providers before credentials or spending
  reservations and suppresses RDAP, DNS evidence and local sidecars that may call
  external services. Mail.app synchronization remains separate. Choosing local mode
  does not silently change the selected model. Local model quality is uncalibrated.
- SS-06: monitoring belongs to the application rather than an Activity window task.
  A menu-bar entry provides access with windows closed. Launch-at-login uses
  `SMAppService.mainApp` and displays approval requirements. No login item is enabled
  by development or UI tests. Locked-screen, restart and wake acceptance remain open.
- SS-15: Mail account discovery collects own addresses and excludes them from implicit
  Contacts/history trust by default. Users can edit additional alias/sender exclusions;
  validation is atomic. Explicit sender rules retain precedence. Self-mail, forwarding,
  mailing-list and forged-header fixtures retain unknown authentication. Claimed
  pass/fail/alignment headers never become authentication proof on their own.

## Daily workflows

- SS-04: bounded selected-message corrections save rules and examples before an
  independently reported Mail action. They do not invoke a classifier first.
  Menu-bar commands and app keyboard shortcuts cover Good, Junk and Review.
- SS-07: a paged, account-scoped Junk browser reads messages without classification
  or automatic movement. Plain-text previews load no remote resources. Explicit
  Good/restore follows the usual dry-run, validation, ambiguity and action checks.
- SS-08/09: explicit account/path plans select non-Inbox folders with a received-date
  boundary, persisted progress and cancellable, bounded dry-run previews. Missing or
  renamed paths fail closed to scope expansion. Training requires an empty baseline
  and the dedicated `SpamWise Train Good` or `SpamWise Train Junk` name. Correction
  claims are atomic; uncertain/failed moves remain claimed for manual review. Ordinary
  Junk membership never trains. Second-device and server-routed acceptance are pending.
- SS-10: staged content rules support subject, body, List-ID, recipients, Reply-To
  top-level content type, attachment names and attachment MIME types. Attachment
  metadata is an untrusted header claim and never opens a file. Sender rules precede content rules; newest matching
  content rules precede relationship trust. Expressions have bounded input and a
  shared evaluation deadline. Preview uses the selected Mail message without moving
  it. Per-rule counts survive Activity truncation. Versioned content-rule import/export
  validates the entire archive before a single merge; repeated imports deduplicate.
- SS-11: the reviewed corpus shows class balance, partition, label source and content
  retention. Import accepts up to 20 explicitly reviewed `.eml` files per batch and
  500 retained labels, deduplicates delivery-independent content and creates no sender
  rules or Mail actions. Held-out imports never enter correction prompts or learning.
  Relabel/forget update linked features/examples without requiring retained bodies.
  Statistical estimates derive from the current samples on demand. Latest-correction
  undo previews rule/example counts and atomically restores learning only if unchanged;
  it preserves the Mail outcome and requires a separate correction for a new action.
- SS-12: Activity supports search, account/path/outcome filters, corrections-only
  Today and custom dates. Details expose revision and source mailbox, plain-text preview and
  exact-identity Open in Mail. Content-free diagnostics omit sender, subject,
  account identity and arbitrary error text. Raw-source export requires an exact
  live identity and explicit destination. A separate, searchable, bounded audit trail
  records settings, rule edits, corrections, corpus changes, restore and undo in their
  mutation transactions. Previews use native text only, with no remote-content loader.
- SS-13: statistics provide date/account selection, daily trends, decision and
  reviewed-disagreement counts, unresolved Review, action failures, cost and JSON
  export. They explicitly cover the retained log and do not imply accuracy from
  uncorrected mail. Held-out evaluator metrics remain separate.
- SS-16: AES-GCM backups use independent random 256-bit recovery keys. They include
  rules, policy, corrections, reviewed labels, learned state and selected preferences;
  reviewed message text is opt-in. Restores authenticate and validate before a single
  transaction, pause filtering, clear action validation and invalidate retries.
  Credentials, spending commitments and action claims are not imported or reset.
  The recovery key must be stored separately; it is not bundled into the backup.

## Verification

Isolated build resources: `.build/26e096e9-f0a7-465e-90b7-aa67c5b2b2f7/`.

Package regression coverage includes durable account progress, local-mode provider
and RDAP suppression, own-address trust, sender-rule precedence, selected corrections,
query/statistics semantics, redacted diagnostics, encrypted restore, wrong keys,
tampering and pathological regular-expression cancellation. Generated Mail scripts
compile against the installed Mail dictionary without executing real Mail actions.

Direct inspection of the development-signed app used isolated fixtures. Activity,
Statistics, the denied-permission Junk view, startup settings and local-mode conflict
were readable without overlap. XCTest exposed a windowless launch after adding the
menu-bar scene; Activity now declares its launch presentation explicitly. The fresh
UI run passed both onboarding and corrections/statistics flows with zero failures
(77.188 seconds). Result: `Test-SpamWise-2026.10.16_14-02-40--0700.xcresult` in the
isolated DerivedData test logs. The package suite passed 75 tests, including bounded
regex cancellation. Warning-free app/extension builds and strict SwiftLint passed.

The next batch passed 78 package tests and warning-free app/extension builds. New
coverage checks atomic training claims, retained uncertain moves, explicit previews
after action claims, corpus deduplication and held-out isolation, forgetting and
relabeling without sender-rule changes, stale undo rejection, audit rollback,
attachment metadata and complete content-rule archive validation. XCTest passed both
flows in 104.669 seconds, including undo and forgetting while retaining sender rules.
Result: `Test-SpamWise-2026.10.16_14-24-01--0700.xcresult`.

## Migration boundary

SpamSieve documents [dragging corpus messages to Finder to export raw source](https://c-command.com/spamsieve/help/corpus).
Those messages can be reviewed and imported as `.eml` examples. Its
[training transfer instructions](https://c-command.com/spamsieve/help/how-can-i-copy-my-train)
describe copying its application data to another SpamSieve installation, not a stable
interchange schema. No private database reader or undocumented rule migration is
implemented. Predicted/auto-trained SpamSieve labels require human review before import.

## External prerequisites

SS-05, SS-21, SS-22 and SS-23 need independently reviewed mail and measured comparison
runs. SpamSieve's accumulating Junk folders remain candidate sources, not ground
truth. No new collection or relabeling has run. The $150 ceiling remains a ceiling.

SS-20 now follows the owner’s App Store-first decision. The
[guidelines/code assessment](app-store-feasibility.md) finds a viable path with
Mail exception review and explicit release gaps. GitHub Releases plus the owner’s
GitHubUpdateChecker library is the fallback if App Store distribution proves unsuitable.
No external updater, release or store submission is enabled.

## API references

- [Apple: launch-at-login registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple: regular-expression progress callbacks](https://developer.apple.com/documentation/foundation/nsregularexpression/matchingoptions/reportprogress)

## Notifications, attachments and automation

- SS-14: opt-in local notifications contain counts only, with persistent batching,
  overnight quiet hours, authorization/denied states and a link to the review queue.
  Review ranks action failures and model/evidence disagreement before lower confidence;
  the score remains uncalibrated. Optional mark-as-read runs only after a confirmed Junk
  move and rechecks source and current account-specific Junk membership. Its outcome is
  separate from the move and is never automatically retried. Live notification delivery
  and signed Mail read-status acceptance remain pending.
- SS-17: opt-in bounded plain-text/HTML attachment extraction uses the existing lexical
  parser without executing scripts or loading resources. OCR accepts verified static
  PNG/JPEG/GIF/TIFF/HEIC images within byte, image-count and pixel limits. Animated and
  multipage images are rejected. PDF/Office content remains unread: safe hard resource
  limits require a separately isolated extraction boundary. Unreadable optional content
  is unknown, never independent Junk evidence. Attached text remains untrusted prompt
  content and can reach the selected cloud provider; local parsing does not imply local
  classification.
- SS-19: four App Intents share the app's store, credentials, pipeline, action safety
  and budget. Persistent caller-UUID claims prevent replay after Activity retention.
  See [automation](automation.md) for result semantics and the unresolved macOS intent
  registry acceptance failure. No native automation success is claimed.

Corpus and configuration history now live in Tools, keeping Filter focused on mail
operations. Direct inspection found readable corpus/content-rule/backup views, including
Spanish/French corpus at the minimum window size. Folder-plan and transfer-popup visual
inspection still need completion.

## Destinations, comparison tooling and lifecycle

SS-02 now exposes per-account Inbox/Junk role names behind a disclosure, read through
the same Mail special-mailbox collections used by actions. Missing/ambiguous roles
remain visible and names do not certify provider-side labels. No preview enables
mail actions. Coexistence and slow/offline synchronization acceptance remain open.

SS-05/21/22/23 now have an offline paired-comparison report. It validates human-review
and frozen-learning attestations, identical cohorts and campaign separation; reports
abstentions, exact false-positive bounds, latency, throughput, observed review effort,
resource usage and cost; and preserves unknown prior exposure. A synthetic fixture
checks plumbing only. No independently labeled personal corpus or comparison outcome
has been invented, and no paid request is needed to run this reporting path.

The [Mail.app matrix](mail-compatibility.md) documents the specific signed iCloud/Google
probes and their limits. The [lifecycle guide](lifecycle.md) covers install, manual
upgrade/recovery, login-item removal and optional personal-data removal. SS-18 remains
open for offline/account coverage; SS-20 remains open for App Store prerequisites
and release acceptance. GitHub Releases and GitHubUpdateChecker are the fallback
only if the store path proves unsuitable.

The current batch passes 82 package tests, warning-free package/app/extension builds,
strict formatting and SwiftLint. The frozen-comparison CLI smoke test reads only the
synthetic manifest and produces the expected incomplete-comparison status. XCTest
passes onboarding and corrections/statistics/undo/corpus flows in 103.196 seconds;
the native-intent test is explicitly skipped pending registration acceptance.
Result: `Test-SpamWise-2026.10.16_14-56-59--0700.xcresult`. The UI test exposed duplicate
Corpus sheets when Tools opened another Activity window; Activity is now a single
window and Tools brings it forward. No API charges or generated mail were incurred.

## Store build and mail-sharing permission

The App Store assessment remains viable with review gates, so no external updater
has been introduced. `APP_STORE` disables external executable evidence and the
ungranted PCC option at the settings and request boundaries. Restored preferences
cannot enable those requests. The unsigned optimized store archive passes with
warnings treated as errors; its compiler log confirms the condition reaches
SpamWiseCore. The archive contains the UserDefaults required-reason manifest.
This does not establish distribution signing, collection-label correctness or
App Review acceptance.

Cloud mail sharing requires explicit provider-specific permission in onboarding
or Account settings, including for existing stores. Saving a key grants no mail
permission. Paid requests check before credential access and spending reservation,
then recheck immediately before calling the provider. Revocation cannot recall
already dispatched requests. Domain-age evidence has a separate off-by-default
permission to share sender domains. Local mode overrides it. Help and disclosures
are updated in English, Spanish and French.

The existing provider and privacy tests now cover absent/granted/revoked permission,
no credential access or budget commitment when denied, and domain-age opt-in/local
mode precedence. All 82 package tests and the warning-free app build pass.
XCTest's correction flow passed in 89.645 seconds. The updated onboarding flow
passed in 15.237 seconds, verifying consent starts off, can be enabled and revoked,
then completing denied-permission setup, dry-run status and Pause. Its final result
is `Test-SpamWise-2026.10.16_15-13-49--0700.xcresult`. Earlier consent test failures
were locator/value-type assumptions: the native control is a Switch with a numeric
accessibility value. The native-intent acceptance test remains explicitly skipped.
Swift formatting, strict SwiftLint, shellcheck, Markdown and plist checks pass.

Direct fixture inspection also verified the notification-denied state, one Corpus
sheet from Tools, and `spamwise://review` reopening the closed Activity window with
Weekly Review. Notification delivery, live Mail actions, folder-plan layout and
native intent registration remain distinct pending acceptance checks. No new mail
or paid API calls were created during this batch.

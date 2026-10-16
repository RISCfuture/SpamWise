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

SS-20 needs an update-feed/download host; this checkout has no Git remote. The host
question is pending. No updater destination, release or automatic update has been
invented or enabled.

## API references

- [Apple: launch-at-login registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple: regular-expression progress callbacks](https://developer.apple.com/documentation/foundation/nsregularexpression/matchingoptions/reportprogress)

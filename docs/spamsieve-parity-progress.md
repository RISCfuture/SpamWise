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
  Contacts/history trust by default. Explicit sender rules retain precedence.
  Untrusted Authentication-Results never become authentication proof.

## Daily workflows

- SS-04: bounded selected-message corrections save rules and examples before an
  independently reported Mail action. They do not invoke a classifier first.
  Menu-bar commands and app keyboard shortcuts cover Good, Junk and Review.
- SS-07: a paged, account-scoped Junk browser reads messages without classification
  or automatic movement. Plain-text previews load no remote resources. Explicit
  Good/restore follows the usual dry-run, validation, ambiguity and action checks.
- SS-10: staged content rules support subject, body, List-ID, recipients, Reply-To
  and top-level content type. Sender rules precede content rules; newest matching
  content rules precede relationship trust. Expressions have bounded input and a
  shared evaluation deadline. Preview uses the selected Mail message without moving
  it. Per-rule counts survive Activity truncation. Attachment metadata beyond the
  top-level MIME type and standalone content-rule transfer remain open.
- SS-12: Activity supports search, account/path/outcome filters, corrections-only
  and Today. Details expose revision and source mailbox, plain-text preview and
  exact-identity Open in Mail. Content-free diagnostics omit sender, subject,
  account identity and arbitrary error text. Raw-source export and a full policy
  change audit trail remain open.
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

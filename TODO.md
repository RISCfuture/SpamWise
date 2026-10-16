# Roadmap implementation and acceptance

The signed Apple Mail move spike passed for generated cross-account probes in iCloud and Google. The user then authorized implementing the deferred roadmap. Optional capabilities remain off by default; production thresholds remain uncalibrated. Implementation and live acceptance are tracked separately below.

Mail.app is the sole client integration target. Other-client adapters, Microsoft
Graph integration and standalone IMAP expansion/acceptance are outside the current
roadmap. Existing IMAP code is retained; account coverage below means accounts
configured in Mail.app.

## Implemented and verified offline

- [x] Explicit Apple on-device, Private Cloud Compute, OpenAI and Gemini classifiers alongside Claude. Fresh sessions, bounded prompts/results, measured usage where available, explicit prices, refusal handling and no fallback. PCC still requires Apple's managed entitlement.
- [x] Address/domain rule editing, validated atomic import and export. Address rules precede domain rules and trusted relationships.
- [x] Policy suggestions from consistent corrections, applied only by the user.
- [x] Retrieval of similar reviewed examples within the correction limit.
- [x] Bounded regularized evidence weights and Bayes as optional weak signals, with minimum reviewed-data gates and held-out statistical samples.
- [x] Anchored campaign fingerprints from explicit Junk corrections, suppressed by conflicting Good examples.
- [x] Optional Spamhaus DBL domain lookups with explicit terms acknowledgement and unknown results for service errors.
- [x] Optional local Rspamd symbols through bounded `rspamc` execution; sandbox denial remains unknown.
- [x] Bounded Vision OCR of embedded PNG/JPEG parts without remote image loading.
- [x] TLS IMAP adapter and headless executable, with UIDVALIDITY/UID identity, SPECIAL-USE discovery, capability checks, disposable-message validation and verified move identities. Existing implementation retained; further development and live acceptance are deferred under the Mail.app-only scope.
- [x] Local weekly digest of unresolved Review items, without sending email.
- [x] Explicit Good/Junk/Review label collection and optional bounded reviewed-text export for later evaluation.
- [x] Persistent conservative spending reservations. The authorized additional evaluation ceiling is $150, not a spending target.
- [x] Mac App Store archive preflight and local export configuration. These do not submit or publish an app.
- [x] Finish Spanish/French catalog verification, localized Help indexing and UI checks.
- [x] Finish whole-change review, package/app/UI/archive checks, signed commits and notarized delivery.

See [roadmap progress](docs/roadmap-progress.md), [evidence](docs/evidence.md), [IMAP](docs/imap.md), [evaluation](docs/evaluation.md), and [App Store preparation](docs/app-store.md) for limits and reproducible commands.

## Live acceptance and external prerequisites

- [ ] Verify each newly selected provider with its own credentials and evaluate quality before relying on it. OpenAI/Gemini credentials were not supplied. Apple on-device completed five synthetic requests but returned Review for every fixture; quality remains unvalidated. PCC entitlement/quota remain runtime gates; refusal is never spam evidence.
- [ ] Validate optional DNS service terms/resolver, local Rspamd availability and real OCR fixtures on the signed distribution. A sandbox-denied optional operation remains unknown.
- [ ] Complete signed live onboarding/correction acceptance and incoming MailKit callback/account/deadline observations. Apple Mail's validated account-scoped route remains independent of MailKit's unresolved account bridge.
- [ ] Extend move synchronization coverage to slow/offline servers and longer observation windows. Existing 30-second cross-account observations are not a separate server acknowledgement; ambiguous same-account Sent copies remain untouched.
- [ ] Measure automatic sweep latency on large and mutating mailboxes. Bounded repeating scans do not promise immediate coverage.
- [ ] Accumulate independently reviewed labels and calibrate on a representative held-out corpus. No labeled personal corpus exists yet. Conservative 99, Balanced 95 and Aggressive 90 remain provisional. Approximately 1,500 good examples with zero false positives are needed for a rule-of-three upper bound of 0.2%; mock fixtures do not establish that target.
  - The user is accumulating SpamSieve-classified mail in each account’s Junk folder over the coming weeks. Preserve these folders as candidate sources; keep SpamSieve predictions separate from human-confirmed labels. Include reviewed wanted mail and graymail, exclude generated probes, deduplicate, and reserve a holdout before tuning. See `docs/evaluation.md`.
- [ ] Obtain PCC managed entitlement approval and matching profiles if PCC is desired.
- [ ] Complete App Store Connect metadata/privacy disclosures, Mail Automation exception justification, signed store export, store validation and App Review. Drafts and a signed archive exist; local export stopped at Apple Distribution Keychain access before producing a package. No upload or publication has been performed.

## SpamSieve comparison — researched 2026-10-16

Baseline: SpamSieve **3.3.2**, released September 18, 2026, according to its
[product page](https://c-command.com/spamsieve/). Research uses C-Command’s
[feature list](https://c-command.com/spamsieve/features) and the linked manual
sections below. Accuracy statements there are vendor claims, not a benchmark we
have reproduced. Priorities and proposed improvements are our assessment of the
SpamWise code at `6a42881`, not claims that SpamSieve lacks every proposed capability.

These unchecked items are a research-backed backlog, not implementation or live
validation. Existing acceptance prerequisites above remain in force. P0 blocks a
credible everyday replacement; P1 closes important workflow gaps; P2 broadens
coverage. SS-01, SS-02 and SS-05 refine existing acceptance work rather than
creating separate completion criteria for the same work.

Implementation is underway; see [parity progress and verification](docs/spamsieve-parity-progress.md).
Parent items remain open until their full acceptance criteria are met.

### Current foundation to retain

| Area | SpamWise today | Remaining distinction |
| --- | --- | --- |
| Personalized filtering | Explicit provider choice, natural-language policy, correction retrieval, optional Bayes/weights/fingerprints | Learned signals are supporting evidence; neither local nor cloud accuracy is calibrated |
| Trusted senders and rules | Contacts/history gates, address/domain rules, rule import/export | No rich header/body rules, rule diagnostics, or own-address trust exclusion |
| Mail integration | Apple Mail adapter and bounded Inbox polling | MailKit acceptance unresolved; no synchronized-folder training or arbitrary-folder selection |
| Corrections | Good/Junk/Review in the Activity inspector; rules persist despite action failures | No general selected-Mail-message training command, bulk initial training, or correction undo |
| Inspection and evaluation | Verdict/action/outcome separation, evidence details, CLI metrics/cache, reviewed export | No searchable corpus, app statistics dashboard, safe message preview, or complete backup/restore |
| Safety and review | Persist-before-action, fail open, deduplication, dry run, Review stays in Inbox, local weekly digest | Need sustained runtime coverage and faster review workflows; no superiority claim yet |

### P0 — dependable replacement

- [ ] **SS-01 — Prove complete incoming coverage and expose integration health.**
  SpamSieve supplements its extension with an
  [Inbox polling workaround](https://c-command.com/spamsieve/help/check-inboxes-for-new-m).
  Validate our existing sweeps when MailKit delivers nothing, after sleep/relaunch,
  during offline recovery, and in large or changing mailboxes. Show each account’s
  last successful scan, backlog and actionable failures; distinguish unseen mail
  from reviewed, unclassified and classified mail. Pass with zero unexplained gaps
  in controlled delivery tests and measured end-to-end latency, without Mail
  database access or Full Disk Access.
- [ ] **SS-02 — Validate mailbox roles and multi-filter coexistence.** SpamSieve
  documents [distinguishing its actions from server filtering](https://c-command.com/spamsieve/help/spam-message-colors-in).
  Add per-account destination previews and verify provider semantics, especially
  Gmail system labels versus similarly named custom folders. Exercise SpamSieve,
  server rules and SpamWise without competing moves or duplicate classifications;
  default comparison runs to dry run. Extend the existing slow-server and uncertain
  move tests; preserve source-folder/action provenance and clean up generated probes.
- [ ] **SS-03 — Offer a genuinely local filtering mode.** SpamSieve’s
  [documented privacy baseline](https://c-command.com/spamsieve/features) is processing
  mail on the Mac. An on-device model alone does not meet that baseline: SpamWise
  currently supplies RDAP even with that backend. Add one explicit local-mode policy
  that disables cloud classification, RDAP, DNS reputation and other outbound
  evidence, while allowing Mail.app to synchronize accounts. Verify with network
  observation and offline fixtures. Evaluate a useful trained local classifier;
  the current five-fixture on-device run returning only Review is not parity.
- [ ] **SS-04 — Correct selected mail without leaving Mail.** Match SpamSieve’s
  [menu-bar/Dock commands and keyboard shortcuts](https://c-command.com/spamsieve/help/train-as-good-spam)
  with accessible Good/Junk/Review actions for selected Mail messages, including
  messages absent from Activity. Support bounded multi-selection with a per-message
  result summary. Preserve account identity, explicit domain scope, latest-rule
  precedence, and separate training success from move failure. Verify the entire
  select → correct → locate result flow without switching to Activity first.
- [ ] **SS-05 — Demonstrate quality and performance against SpamSieve.** Use its
  [published accuracy statistics](https://c-command.com/spamsieve/help/statistics)
  as a comparison category, not evidence of an achieved target. Build a reviewed,
  representative corpus from both accounts’ accumulating Junk plus wanted mail and
  graymail. Record SpamSieve/server/unknown provenance separately from human labels;
  never train from Junk membership alone. Compare both products on the same frozen
  holdout with both learning states frozen and auto-training disabled. Record any
  prior exposure; use newly collected unseen mail where that cannot be excluded.
  Report false positives, missed junk, abstentions, review burden,
  p50/p95 latency, throughput, memory/CPU and cost. Keep campaign duplicates out of
  both training and holdout; do not retune on the holdout. Retain the 0.2% good-mail
  false-positive bound and $150 ceiling above; no new spend is authorized by this item.
- [ ] **SS-06 — Make unattended operation a supported setup path.** SpamSieve’s
  [drone workflow](https://c-command.com/spamsieve/help/drone-setup-and-remote)
  filters synchronized accounts while its Mac is running. SpamWise monitoring
  depends on its app lifecycle, and no login service is installed. Add
  opt-in launch-at-login/background operation, visible paused/offline states and
  restart recovery. Validate filtering with windows closed, screen locked, after
  restart and after sleep; explain when the Mac and Mail.app must remain running. Finish
  fresh-user live onboarding and package the actual accepted build.

### P1 — daily workflows and control

- [ ] **SS-07 — Review and rescue good mail already in Junk.** SpamSieve provides a
  [rescue script](https://c-command.com/spamsieve/help/rescuing-good-messages).
  Add a bounded, per-account Junk review queue with explanations and explicit
  restore-to-Inbox. Start read-only; any later automatic rescue requires separate
  opt-in, validated destinations and measured precision. Preserve the original
  filter provenance, avoid rescuing user-blocked senders, and prevent move loops
  with SpamSieve/server filters. Do not treat the user’s growing sample folders as
  permission to move or relabel their contents automatically.
- [ ] **SS-08 — Train through Mail.app’s synchronized folders.** Match
  SpamSieve’s [dedicated training mailboxes](https://c-command.com/spamsieve/help/drone-setup-and-remote)
  with explicitly configured, account-scoped Good/Junk training folders read through
  Mail.app. Folder placements may synchronize from another device without requiring
  integration with its mail client. Process each deliberate placement once,
  save the correction before moving it to the
  intended Inbox/Junk destination, and reconcile reconnects and duplicate deliveries.
  Ordinary Junk moves and server classifications must not count as user training.
  Test from a second device and preserve failures for review.
- [ ] **SS-09 — Select accounts and folders to filter, and refilter deliberately.**
  SpamSieve [filters selected non-Inbox mailboxes](https://c-command.com/spamsieve/help/filter-spam-messages-in)
  and supports [manual refiltering](https://c-command.com/spamsieve/help/requirements).
  Extend our Inbox-only sweep configuration with account/folder inclusion and
  exclusion, a start boundary, progress, cancellation and a dry-run preview. Handle
  renames/removals without silently broadening scope; keep Junk rescue separate.
  Test server-routed mail and explicit historical refiltering without replaying
  old actions or allowing the message to establish its own trusted history.
- [x] **SS-10 — Expand rules beyond literal sender addresses/domains.** SpamSieve
  has [header/body matchers, regex, rule state and match statistics](https://c-command.com/spamsieve/help/rule-columns-locations).
  Add a staged rule builder for mailing-list headers, recipients, Reply-To,
  subject/body and attachment metadata; support enabled state, notes, bounded
  regex and a test-against-samples preview. Show which rule won and potential
  conflicts. Specify new-rule ordering before implementation while preserving
  address → domain → trusted gates and latest same-scope correction; no lock option
  may silently defeat a user’s later correction. Include schema migration/export.
- [x] **SS-11 — Add initial training and a manageable corpus.** SpamSieve supports
  [initial examples](https://c-command.com/spamsieve/help/do-an-initial-training), a
  [corpus browser](https://c-command.com/spamsieve/help/corpus) and
  [controlled auto-training](https://c-command.com/spamsieve/help/auto-train-as-needed).
  Our corrections and bounded learning store need a review/import workflow,
  deduplication, class-balance indicators, label provenance and retention controls.
  Support correcting/forgetting examples and rebuilding derived learning without
  losing explicit rules. Make bulk corpus import distinct from sender-rule creation;
  ordinary corrections retain their established address-rule behavior. Investigate
  supported SpamSieve export formats before promising rule/corpus migration. Add undo
  with a preview of affected rules/examples and a separately verified mail action.
  Keep predicted labels separate and never promote them into held-out truth.
- [x] **SS-12 — Make Activity a useful troubleshooting log.** SpamSieve’s
  [log](https://c-command.com/spamsieve/help/log) records predictions, training,
  rule changes and failures, with message/source inspection. Add search and filters
  for account, sender, date, path, outcome and correction; retain a policy/rule
  revision trail. Add safe local previews, an unambiguous open-in-Mail action and
  opt-in raw-source export. Offer a redacted diagnostic bundle with no keys or mail
  content by default. Verify that previews never fetch remote resources.
- [x] **SS-13 — Bring meaningful statistics into the app.** Match SpamSieve’s
  [date-filtered statistics](https://c-command.com/spamsieve/help/statistics) using
  existing evaluator primitives: per-account trends, reviewed mistakes, unresolved
  Review, action failures and provider cost. Show reviewed sample counts and
  uncertainty; never assume an uncorrected prediction was correct. Separate
  operational counters from held-out quality, with export and date ranges.
- [ ] **SS-14 — Provide restrained notifications and review prioritization.**
  SpamSieve offers [good-mail and uncertain-spam notifications](https://c-command.com/spamsieve/help/notification-center-sho),
  [uncertainty thresholds](https://c-command.com/spamsieve/help/uncertain-spam-messages)
  and optional [mark-as-read](https://c-command.com/spamsieve/help/mark-it-as-read).
  Add opt-in notifications, batching/quiet controls and direct correction links;
  prioritize likely mistakes in the existing digest. Offer mark-as-read only as an
  explicit supported preference after a confirmed Junk action. Keep text labels,
  sparse color and uncalibrated-score warnings; do not overwrite users’ flags or
  claim that Apple Mail background colors synchronize to mobile devices.
- [x] **SS-15 — Protect against own-address and trusted-sender spoofing.** SpamSieve
  has an [own-address exception to Contacts trust](https://c-command.com/spamsieve/help/catch-spam-sent-from-my).
  Add explicit own-address/alias discovery and configurable exclusions from automatic
  relationship trust. Evaluate authenticated alignment and forged-contact cases
  without trusting sender-supplied Authentication-Results. Preserve explicit user
  rule precedence; missing or untrusted authentication remains unknown. Include
  legitimate self-mail, forwarding and mailing-list fixtures before changing gates.
- [x] **SS-16 — Back up, restore and migrate learned state safely.** SpamSieve
  documents [training-data transfer/restore](https://c-command.com/spamsieve/help/how-can-i-copy-my-train)
  and [storage management](https://c-command.com/spamsieve/help/settings-storage).
  Go beyond our rules-only import/export: versioned, validated backups of rules,
  policy, labels, derived learning and selected settings, with optional encrypted
  retained content. Exclude credentials and do not transfer live-action validation
  to a different account/endpoint. Test migration, corruption recovery and restore
  with actions paused; avoid synchronizing a live SwiftData database between Macs.

### P2 — Mail.app coverage and product lifecycle

- [ ] **SS-17 — Analyze more attachment-only spam locally.** SpamSieve advertises
  [image and document inspection](https://c-command.com/spamsieve/). Our embedded
  PNG/JPEG OCR is partial coverage. Evaluate bounded local PDF/text/document
  extraction and additional image formats, with malicious, encrypted and oversized
  fixtures. Keep attachment content untrusted, never execute macros or fetch remote
  content, and distinguish unreadable attachments from spam evidence.
- [ ] **SS-18 — Publish a verified Mail.app/account compatibility matrix.** Use
  SpamSieve’s [requirements](https://c-command.com/spamsieve/help/requirements) as
  a documentation baseline. Verify account types through Mail.app, including
  account-specific special mailboxes, synchronization and offline recovery. Distinguish
  MailKit observations from Apple Events acceptance and document unsupported cases.
  Document macOS 27 and hardware requirements; older-macOS support needs a feasibility
  decision rather than an automatic deployment-target downgrade. No additional
  mail-client adapters or direct server integrations are required.
- [ ] **SS-19 — Expose documented automation.** SpamSieve supplies an
  [AppleScript interface and integration SDK](https://c-command.com/spamsieve/help/customizing-using-apple).
  Design supported CLI/Shortcuts/Apple Events entry points for SpamWise and Mail.app:
  classify-preview, explicit correction, status and export. Keep account identity, cancellation,
  idempotency, spending limits and action authorization consistent with the app.
  The existing Inbox-trigger URL and evaluator/daemon do not cover these workflows.
- [ ] **SS-20 — Finish maintainable distribution and lifecycle support.** SpamSieve
  has [installation/update, migration and removal workflows](https://c-command.com/spamsieve/help/SpamSieveManual_toc).
  Add a tested signed-update path for direct distribution, clear upgrade/recovery
  guidance, login-item removal and user-controlled data removal on uninstall.
  Finish the existing notarized-release/App Store prerequisites without treating
  archive success as distribution or review approval.

### Opportunities to exceed the baseline — prove, then claim

- [ ] **SS-21 — Show a measurable benefit from semantic preferences.** Evaluate
  unwanted marketing, abandoned carts, expected receipts and forged shipping
  notices against SpamSieve on independently labeled messages. Ground explanations
  in actual correspondence/order evidence, retain unknown-history distinctions,
  and test prompt injection and contradictory examples. Policy text and extra
  providers alone are not evidence of better filtering.
- [ ] **SS-22 — Reduce review effort without hiding risk.** Rank Review and rescue
  candidates by disagreement and likely error; explain the specific rule/evidence
  that drove each decision and the effect of a proposed correction. Measure minutes
  and corrections needed per 1,000 messages at the same false-positive bound as the
  baseline. Keep detailed diagnostics behind disclosures and preserve accessible,
  uncluttered English/Spanish/French flows.
- [ ] **SS-23 — Make local/cloud tradeoffs explicit and measurable.** After SS-03
  and SS-05, evaluate an opt-in local-first classifier policy with separately
  authorized cloud escalation for uncertain cases. Show what would leave the Mac,
  why, and its estimated cost; allow preview/cancel. Benchmark privacy, quality,
  latency and spend together. Never introduce a silent provider fallback or treat
  the $150 ceiling as a target.

### Deliberate differences

- Keep the product’s **no Trash/delete** contract. SpamSieve documents
  [age-based cleanup](https://c-command.com/spamsieve/help/automatically-deleting)
  and [score-based Trash actions](https://c-command.com/spamsieve/help/move-it-to-the-trash-if);
  feature parity does not justify adding them here.
  Authorized cleanup of our generated test mail is an operator task, not a product
  filtering action. Preserve the user’s growing Junk corpus.
- Keep fail-open behavior for parsing, evidence, storage and integration failures;
  do not adopt encoding/language-only blocking from the competitor’s configurable
  rules. Preserve user rules first and explicit domain-level corrections.
- Use Mail.app’s public MailKit and Apple Events interfaces, with runtime validation
  for each route. Avoid private Mail database access, legacy plug-in injection and
  Full Disk Access. Document performance limits and validate the polling fallback.

Suggested delivery order: SS-01/02/05/06 for reliability and evidence, SS-03/04 for
local privacy and correction access, then SS-07/08 and the remaining P1 work.
P2 and superiority experiments follow measured user benefit. Research
and this backlog do not enable features, change live-mail settings or schedule
collection/evaluation.

# Roadmap implementation and acceptance

This file is the single status source for SpamWise. Feature documents under `docs/`
describe behavior and limits only. A checked item records implementation or an
observed result; an unchecked parent stays open until its whole acceptance criterion
is met. Optional capabilities stay off by default, and production thresholds stay
uncalibrated.

Apple Mail is the primary integration. The IMAP route, built on swift-nio-imap, stays
selectable in Settings and in the headless `spamwise-daemon`, but has had no live
acceptance (see below). Other mail clients and Microsoft Graph are out of scope; account
coverage below means accounts configured in Mail.app.

## General detectors and personal preferences

The product separates spam, graymail, phishing and spearphishing, with overlapping
fraud and malware findings. Public training data supports general detectors; small
amounts of reviewed personal mail personalize graymail. Collecting thousands of
personal labels is not a prerequisite for an out-of-box model or zero-shot preference
handling. See [detection design](docs/detection-design.md) and
[dataset research](docs/training-data.md).

- [x] Specify independent threat findings and personal preferences, separate from Inbox/Review/Junk actions.
- [x] Research free bulk datasets, checking collection dates, original label meanings and published training terms.
- [x] Download and inventory September 2026 Guenter spam, 2025 Nazario phishing and the synthetic Marketeam corpus locally; preserve source snapshots and hashes.
- [x] Screen pinned tiny and multilingual local models; record newsletter, targeting, multilingual and legitimate-payment results in [model screening](docs/probes/local-model-screening.md). Neither model is selected for automatic actions.
- [ ] Audit source labels and campaign duplicates; build separate spam/phishing training sets and real/synthetic holdouts with legitimate difficult negatives.
  - [x] Implement hash-pinned corpus preparation, preserved source labels, conflict abstention, bounded MIME/archive handling, duplicate/template grouping and separate objective indices. Six offline behavioral tests pass.
  - [x] Prepare 18,201 unique text records from the three acquired sources; quarantine 12 records and merge 184 duplicates. Reserve 259 real and 2,523 synthetic holdout records without scoring them.
  - [x] Keep evaluation-only sources and their linked duplicates out of training; count false alarms only against explicitly negative labels. Acquire and audit 250 historical hard-ham messages, accept 232 and quarantine 18; preserve every existing holdout assignment.
  - [x] Audit frozen source-label/index fidelity and real/synthetic provenance, preserve all 18,201 original assignments and 2,782 holdouts, derive conservative development campaign groups, and record inferred language/time coverage plus pretrained-exposure disclosures. See [integrity audit](docs/probes/corpus-integrity-audit.md).
  - [x] Acquire and hash-pin CC BY 4.0 SpaPhish v5: 1,395 Spanish messages with explicit phishing labels, including 664 legitimate examples. Keep this separate development source outside the existing frozen corpus; group duplicates/templates before partitioning. See [source audit and baseline](docs/probes/spaphish-baseline.md).
  - [ ] Independently review source labels, unresolved campaign links and contemporary multilingual legitimate negatives; resolve pretrained exposure or collect unseen evaluation data before declaring the sets validated.
- [ ] Evaluate and package useful pretrained local spam and phishing detection with independently measured thresholds and English/Spanish/French coverage.
  - [x] Run the pinned multilingual candidate on 259 real development records at 384 and 1,024 tokens, preserving the reserved holdout. Record detection counts, truncation, latency and memory; no production model or threshold selected.
  - [x] Screen the same candidate against 232 difficult legitimate development messages. Spam false alarms at 0.5 are 60.8%/65.5% at 384/1,024 tokens; reject this candidate for production. Historical evaluation-only negatives do not establish contemporary or multilingual quality.
  - [x] Screen pinned OpenTextShield at 96/384 tokens on the same 491 real development messages and 11 separate synthetic cases. Spam false alarms on difficult legitimate mail are 40.5%/43.1%; reject this raw-input candidate for production. See [results and preprocessing limits](docs/probes/opentextshield-screening.md). Reserved holdouts remain unscored.
  - [x] Train and evaluate a fixed local character-TF-IDF/logistic Spanish phishing baseline using subject/body only. At score 0.5, development validation detects 188/212 phishing messages with 5/176 legitimate false alarms; at 0.9, detection falls to 46/212 with zero observed false alarms. No production threshold or model is selected; frozen holdouts remain untouched and API spend is zero.
- [x] Persist independent assessments, provenance and unknown states; keep historical records unassessed and update evaluation/cache identities. See [assessment behavior](docs/threat-assessments.md).
- [ ] Assess threats on trusted-contact/history paths without silently overriding explicit action rules or presenting unscanned mail as safe.
  - [x] Add the bounded independent detector path to all successful classifications, preserve rule actions and exclude preference-derived learning scores; show absent coverage explicitly in the inspector.
  - [ ] Connect a quality-validated production detector. The app reports unassessed coverage; synthetic injected detectors establish orchestration only.
  - [ ] Hide the inspector's threat section when no detector ran.
- [ ] Evaluate targeted impersonation, payment diversion and other fraud using account-scoped context; preserve unknown history.
- [ ] Evaluate zero-shot graymail preferences and incremental private personalization; distinguish example retrieval from actual model fine-tuning.
  - [x] Run a reproducible 12-context EN/ES/FR synthetic policy-only/two-example comparison; record labels, effective actions, usage and limitations in [preference results](docs/probes/graymail-preferences.md). Examples showed no categorical improvement; this is not fine tuning or independent real-mail quality.
- [ ] Establish dedicated attachment/malware coverage without treating text-model predictions as antivirus results.

## Implemented and verified offline

- [x] Explicit Apple on-device, OpenAI and Gemini classifiers alongside Claude, from one model catalog. Fresh sessions, bounded prompts/results, measured usage where available, explicit prices, refusal handling, retried Anthropic server errors and no fallback. A missing key is reported as a missing credential. Private Cloud Compute is hidden in both editions and rejected if restored, because neither holds Apple's managed entitlement.
- [x] Address/domain rule editing, validated atomic import and export. Address rules precede domain rules, content rules and relationships. Block rules always apply; Allow rules need trusted aligned authentication.
- [x] Per-account trusted receiving servers. Authentication-Results are trusted only from the account's configured servers; Allow rules, Contacts, reply and receipt history need a trusted aligned pass and are otherwise model evidence. Receiving servers are sampled from up to 50 messages per account to detect a consistent set. The forged-contact fixture passes with no exclusion configured.
- [x] Policy suggestions from consistent corrections, applied only by the user.
- [x] Retrieval of up to five similar same-account reviewed examples, quoting domains rather than full addresses and shortening quoted text.
- [x] Bounded regularized evidence weights and Bayes as optional weak signals, with minimum reviewed-data gates. Product learning uses every label; the 20% hold-out applies only to evaluation.
- [x] Anchored campaign fingerprints from explicit Junk corrections, suppressed by conflicting Good examples and Review signatures. Matches go to Review, never straight to Junk. Junk anchors need a trusted DMARC pass, so fingerprints stay inert until an account trusts its receiving servers.
- [x] Optional Spamhaus DBL lookups for From, Reply-To, Return-Path and link domains, with explicit terms acknowledgement and unknown results for service errors. Public DNS uses in-process resolver queries to one configured resolver and works in both editions.
- [x] Optional user-keyed Spamhaus HTTPS transport, shared Keychain storage, explicit service selection, bounded requests and fail-open handling. Live authorization awaits an HTTPS-enabled account; free DNS access does not establish HTTPS entitlement. See [setup and limits](docs/spamhaus.md).
- [x] Optional local Rspamd symbols through the fixed-loopback HTTP transport; errors remain unknown. It works in the signed sandbox harness without new entitlements, defaults off and is blocked in local-only mode. No external executable transport exists.
- [x] Bounded Vision OCR of embedded PNG/JPEG/GIF/TIFF/HEIC parts without remote image loading.
- [x] IMAP adapter on swift-nio-imap with implicit TLS, UIDVALIDITY/UID identity, SPECIAL-USE discovery, capability checks, Review as `$SpamWiseReview` or `\Flagged`, verified move identities, and implicit Good corrections for mail rescued from Junk in another client. The headless `spamwise-daemon` (`run`, `validate`, `probe`) records daemon-scoped validation.
- [x] Local weekly digest of unresolved Review items, without sending email.
- [x] Explicit Good/Junk/Review label collection and optional bounded reviewed-text export for later evaluation.
- [x] Production spending: an optional user-set monthly limit, off by default, reserves each paid request's token-bound maximum and settles it to measured usage. The conservative lifetime ledger is confined to `spamwise-eval`, which requires an explicit `--budget-store`; its authorized additional evaluation ceiling is $150, not a spending target.
- [x] Retain unstarted persistent retries when cancellation interrupts a batch; individual atomic claims reject superseded jobs. Transient failures retry with backoff for up to three days, and Pause or dry-run edits no longer invalidate pending work.
- [x] Shared state in real SwiftData entities with change tokens and slice-scoped loads, a cross-process lock, retention limits and a set-aside path for unreadable legacy state. The legacy import has been tested only against a synthetic unversioned store.
- [x] Finish Spanish/French catalog verification, localized Help indexing and UI checks. Each SpamWiseCore module resolves its strings from its own catalog through `bundle: .module`; `Scripts/check-core-localizations.py` enforces the bundle, es/fr values, matching specifiers and unused keys.
- [ ] Localize the `spamwise-eval` and `spamwise-daemon` executables: embed an Info.plist declaring `CFBundleLocalizations` so their catalogs resolve at runtime, and route the daemon's `print()` output through localized strings.

See [evidence](docs/evidence.md), [IMAP](docs/imap.md), [evaluation](docs/evaluation.md)
and [packaging](docs/packaging.md) for limits and reproducible commands.

## Live acceptance and external prerequisites

The owner has deferred provider access, supervised device sessions, personal labeling
and App Store account steps. These items stay open. Spamhaus stays disabled until an
eligible user configures [optional access](docs/spamhaus.md).

- [ ] Meet the brief's §8 fixture criterion. **Unmet:** the offline fixture check gets its two Inbox, two Junk and one Review outcomes from hand-written mock verdicts, so it exercises plumbing, not the prompt, instructions or evidence; the only real-backend run, on-device, returned Review for all five. Run the five fixtures once against Claude within the $150 ceiling, with `--state eval/fixture-state.json`, and record the labels.
- [ ] Verify each newly selected provider with its own credentials and evaluate quality before relying on it. OpenAI setup-key storage and read access in login Keychain work; the one synthetic OpenAI request was rate-limited (HTTP 429) with no verdict or usage, and the $150 ledger retains its $1 reservation. Successful classification and operational shared-Keychain import remain pending. Gemini waits for a key. Apple on-device completed five synthetic requests but returned Review for every fixture. Refusal is never spam evidence.
- [ ] Validate optional DNS service terms/resolver, local Rspamd availability and real OCR fixtures on the signed distribution. A sandbox-denied optional operation remains unknown.
  - [x] Verify six synthetic EN/ES/FR PNG/JPEG/GIF/TIFF cases through native Vision in a signed sandboxed harness, with malformed/remote-only inputs unknown. Observe local-mode guards and a network-observer positive control. See [runtime evidence and limits](docs/probes/local-evidence-runtime.md).
  - [x] Build pinned Rspamd 4.2.2 and verify the HTTP adapter against a disposable local scanner, including empty results, stopped-service unknown, redirects without forwarding, streaming overflow, service errors, shortened deadlines, cancellation and concurrent scans. See [scanner evidence](docs/probes/rspamd-runtime.md). Installed service rules and representative quality remain separate.
  - [ ] Confirm in-process DNS queries from the signed, sandboxed app against a real resolver.
- [ ] Complete signed live onboarding and correction acceptance.
  - [x] Verify signed menu-bar Junk correction and Junk-review restore on one generated cross-account message, independently checking source and settled mailbox after each action. See [live corrections](docs/probes/live-corrections.md).
  - [x] Verify post-Junk read status, scanning with all windows closed and persisted scan progress after app relaunch. See [live follow-up](docs/probes/live-mail-followup.md).
  - [ ] Complete fresh-user live onboarding, timed against the brief's five-minute target.
  - [ ] Run the rewritten Apple Events handlers from the signed app: account and special-mailbox resolution, the `whose` queries, message-size agreement between lookup and action, the received-date filter, and the move polling window under iCloud and Google synchronization.
- [ ] Accept IMAP before relying on it. The route is selectable in Settings → Accounts, where a read-only connection check validates the account for actions, but no live TLS authentication, SPECIAL-USE discovery, move or Review keyword has run against a real server. Test with disposable probes on at least one provider supporting `UID MOVE`, including OAuth bearer authentication, reconnects and the daemon's `validate`/`probe`/`run --actions` path.
- [ ] Make trusted receiving servers usable and safe.
  - [ ] Settings → Accounts lists each account's trusted servers or detection status, with Confirm, Edit and Stop trusting. Until then no account trusts anything, so relationships and Allow rules are model evidence only.
  - [ ] Before a Junk correction writes a Block rule for an unauthenticated sender, warn that the From address may be forged.
  - [ ] Make an address lose its authenticated receipt credit when one of its messages is later labeled Junk or Review, including corpus relabels, and confirm through the pipeline that a persisted receipt count without trusted aligned authentication never allows a sender.
  - [ ] Give the headless daemon a way to confirm trusted servers; today it can only use trust set through the shared store.
- [ ] Extend move synchronization coverage to slow/offline servers and longer observation windows. Move confirmation polls every two seconds and accepts two consecutive matching observations within 30 seconds; that is a client observation, not a server acknowledgement. Ambiguous same-account Sent copies remain untouched.
- [ ] Measure automatic sweep latency on large and mutating mailboxes. Bounded repeating scans do not promise immediate coverage.
- [ ] Calibrate general detectors on source-audited public holdouts and evaluate personalization incrementally on independently reviewed mail. No labeled personal corpus exists yet; it is not a universal-training or initial-use prerequisite. Conservative 99, Balanced 95 and Aggressive 90 remain provisional; the evaluator's calibration targets (0.1%, 0.2% and 0.5% false-positive bounds) are provisional too. Approximately 1,500 independent good examples with zero false positives are needed for a rule-of-three upper bound of 0.2%; mock fixtures do not establish that target.
  - The user is accumulating SpamSieve-classified mail in each account's Junk folder. Preserve these folders as candidate sources; keep SpamSieve predictions separate from human-confirmed labels. Include reviewed wanted mail and graymail, exclude generated probes, deduplicate, and reserve a holdout before tuning. See [evaluation](docs/evaluation.md).
- [ ] Obtain PCC managed entitlement approval and matching profiles if PCC is desired.
- [ ] Get an early App Review decision on the `com.apple.mail` Apple Events temporary exception before further store work. Every action path depends on it and the extension alone does nothing, so a refusal also risks a minimum-functionality rejection. If it is refused, decide between an IMAP-only store build and no store edition. Developer ID is the primary channel meanwhile. See [App Store feasibility](docs/app-store-feasibility.md).
- [ ] Complete App Store Connect metadata/privacy disclosures, the exception justification, signed store export, store validation and App Review. Authenticated validation stops because no App Store Connect app record exists for `codes.tim.SpamWise` (error 19). No upload or publication has been performed. See [App Store packaging](docs/app-store.md).
  - [x] Prepare provider-retention disclosures, a source/artifact privacy audit, Mail exception/reviewer notes, and a responsive static marketing/privacy/support site under `docs/`. Publication and final privacy answers remain separate steps.
  - [x] Declare Emails or Text Messages and Other User Content (App Functionality, not linked to tracking) in the app's privacy manifest; give the extension a manifest declaring no collection.

## Remaining gates and who can close them

| Gate | Affected work | Needed next |
| --- | --- | --- |
| Provider/account access | New-provider acceptance, §8 fixture run, PCC | Unlock the saved OpenAI setup key for operational import and supply usable quota; provide the Gemini key; authorize the Claude fixture run; obtain Apple's PCC grant if desired |
| Publisher/release decisions | Store acceptance, SS-20 | Approve making `RISCfuture/SpamWise` public and publishing the site; create the App Store Connect record; obtain the Mail exception decision and reviewer access |
| Interactive environment coverage | Fresh onboarding, IMAP, SS-01/02/06/07/08/09/14/18 | A fresh macOS user/permission flow, notification permission, controlled sleep/lock/reboot/offline/reconnect sessions, a second device, an IMAP test account and additional account/hardware configurations |
| Independent quality evidence | General spam/phishing, targeted fraud, graymail, calibration, SS-03/05/21/22/23 | Contemporary licensed legitimate negatives, reviewed language/objective labels and unseen campaign-separated evaluation; private preferences need the user's judgments. Current screened models failed specificity, so none is shipped as a universal detector |
| Technical containment and threat coverage | PDF production, SS-17, malware | Resolve hard memory containment and worker lifecycle/cancellation before app integration; obtain adversarial document/malware evidence |
| Optional evidence services | DNS/Rspamd/OCR acceptance, SS-03 | Service eligibility and a configured resolver for public DNS evidence; representative real images and service-aware network observation |
| Direct distribution | SS-20 | A public repository, a published release and signed artifacts to exercise discovery, the disk-image install and edition switching |

No remaining checkbox authorizes importing personal mail as trusted labels,
weakening sandboxing, spending the remaining API budget merely to exhaust it, or
turning on automatic mail actions. The held-out corpus and growing Junk folders
remain preserved.

## SpamSieve comparison

Baseline: SpamSieve **3.3.2**, released September 18, 2026, according to its
[product page](https://c-command.com/spamsieve/). Research uses C-Command's
[feature list](https://c-command.com/spamsieve/features) and the linked manual
sections below. Accuracy statements there are vendor claims, not a benchmark we
have reproduced. Priorities and proposed improvements are our assessment, not claims
that SpamSieve lacks every proposed capability.

P0 blocks a credible everyday replacement; P1 closes important workflow gaps; P2
broadens coverage. SS-01, SS-02 and SS-05 refine existing acceptance work rather than
creating separate completion criteria for the same work.

### Implemented foundation; remaining acceptance is tracked below

| Area | SpamWise today | Remaining distinction |
| --- | --- | --- |
| Personalized filtering | Explicit provider choice, natural-language policy, correction retrieval, optional Bayes/weights/fingerprints | Learned signals are supporting evidence; neither local nor cloud accuracy is calibrated |
| Trusted senders and rules | Address/domain and content rules, per-account trusted receiving servers, Contacts/history as authenticated gates or evidence, own-address exclusions, import/export | Trust confirmation UI and broader real-mail spoofing and forwarding acceptance remain open |
| Mail integration | Apple Mail adapter, persisted repeating sweeps with stalled-page fallback, folder plans and dedicated-folder training | Second-device training and sustained delivery acceptance remain open |
| Corrections | Activity and selected-Mail commands, reviewed import, undo; rules persist despite action failures | Corrections still pull the user into Activity; one generated live correction/rescue passed |
| Inspection and evaluation | Evidence details, searchable corpus, statistics, safe preview, versioned backup/restore and CLI reports | Per-account trends, uncertainty and representative calibration remain open |
| Safety and review | Persist-before-action, fail open, deduplication, dry run, Review stays in Inbox, local weekly digest | Need sustained runtime coverage, honest aggregate status and faster review workflows |

### P0 — dependable replacement

- [ ] **SS-01 — Prove complete incoming coverage and expose integration health.**
  SpamSieve supplements its extension with an
  [Inbox polling workaround](https://c-command.com/spamsieve/help/check-inboxes-for-new-m).
  Validate our sweeps after sleep/relaunch, during offline recovery, and in large or
  changing mailboxes. Show each account's last successful scan, backlog and actionable
  failures; distinguish unseen mail from reviewed, unclassified and classified mail.
  Pass with zero unexplained gaps in controlled delivery tests and measured end-to-end
  latency, without Mail database access or Full Disk Access.
  - [x] Persist per-account paging and display scan health.
  - [x] Check each account's new Inbox mail first on every tick and Mail-rule trigger, then continue a bounded backfill to a per-account start boundary: setup completion, the time a later account is first checked or included, or the upgrade time for existing installations; IMAP reads UIDs above a per-UIDVALIDITY high-water mark first. Queue triggers that arrive during a scan, keep processed identities in a durable index independent of Activity, and filter older mail only through an explicit dry-run preview before applying. Verified offline against date-filtered fixtures.
  - [ ] Confirm in a live run that the date-filtered page script orders mail newest first and that Mail filters a large Inbox within the 8-second script limit.
  - [x] Keep oversized or unavailable sources from blocking later readable mail; persist unreadable counts, retry on the next sweep and preserve training claims on incomplete reads. See [paging behavior and limits](docs/probes/unreadable-mail-pages.md).
  - [x] Fall back when a page keeps timing out: halve the page after each consecutive timeout (one message after four) and skip a backfill position that still times out after six. Record per-account coverage (visited, classified, reviewed, unclassified), consecutive failures and timeouts, and the latest pass start.
  - [x] Verify controlled incoming delivery and continuing scans with windows closed and after app relaunch.
  - [ ] Show coverage categories, unseen backlog, stalled state and a late-heartbeat warning in Accounts health and the menu.
  - [ ] Extend coverage to wake, OS restart, offline recovery and sustained mutating-mailbox latency.
  - [x] Add a core retry for unclassified records, so a settled persistent or exhausted transient failure can be reconsidered without an unrelated settings change.
  - [ ] Add a Retry action for unclassified mail to Activity.

- [ ] **SS-02 — Validate mailbox roles and multi-filter coexistence.** SpamSieve
  documents [distinguishing its actions from server filtering](https://c-command.com/spamsieve/help/spam-message-colors-in).
  Add per-account destination previews and verify provider semantics, especially
  Gmail system labels versus similarly named custom folders. Exercise SpamSieve,
  server rules and SpamWise without competing moves or duplicate classifications;
  default comparison runs to dry run. Extend the existing slow-server and uncertain
  move tests; preserve source-folder/action provenance and clean up generated probes.
  - [x] Expose account-specific special-mailbox destination previews.
  - [ ] Verify concurrent-filter behavior and slow/offline provider synchronization.

- [ ] **SS-03 — Offer a genuinely local filtering mode.** SpamSieve's
  [documented privacy baseline](https://c-command.com/spamsieve/features) is processing
  mail on the Mac. An on-device model alone does not meet that baseline. Add one
  explicit local-mode policy that disables cloud classification, RDAP, DNS reputation
  and other outbound evidence, while allowing Mail.app to synchronize accounts. Verify
  with network observation and offline fixtures. Evaluate a useful trained local
  classifier; the five-fixture on-device run returning only Review is not parity.
  - [x] Block cloud providers and outbound evidence under explicit local mode.
  - [x] Observe the signed local-mode harness with all outbound options enabled: remote backends reject before credential access, on-device inference completes, and process network counters stay empty while the positive control is observed.
  - [ ] Complete shipping-app/service-aware network observation and useful local-model quality. Per-process counters do not establish absence of delegated traffic.

- [ ] **SS-04 — Correct selected mail without leaving Mail.** Match SpamSieve's
  [menu-bar/Dock commands and keyboard shortcuts](https://c-command.com/spamsieve/help/train-as-good-spam)
  with accessible Good/Junk/Review actions for selected Mail messages, including
  messages absent from Activity. Support bounded multi-selection with a per-message
  result summary. Preserve account identity, explicit domain scope, latest-rule
  precedence, and separate training success from move failure. Verify the entire
  select → correct → locate result flow without switching to Activity first.
  - [x] Add menu-bar selected-message corrections with individual outcomes.
  - [x] Skip unreadable or oversized selected messages individually and report how many were skipped.
  - [x] Verify selected generated mail through the signed live correction flow. One iCloud-received cross-account probe completed the menu-bar Junk action, with unchanged source and independently confirmed Junk location. See [acceptance evidence](docs/probes/live-corrections.md).
  - [ ] Report selected-message results through the menu or a notification instead of opening Activity.
  - [ ] Provide shortcuts that work while Mail is frontmost, such as a Service or an App Intent; MenuBarExtra shortcuts fire only while its menu is open.
  - [ ] Offer explicit domain scope for selected-message corrections.
  - [ ] Overlap or batch move verification, and queue or explicitly reject requests while a sweep or correction is running.
  - [ ] Verify Good and Review corrections and a multi-message selection live.

- [ ] **SS-05 — Demonstrate quality and performance against SpamSieve.** Use its
  [published accuracy statistics](https://c-command.com/spamsieve/help/statistics)
  as a comparison category, not evidence of an achieved target. Build a reviewed,
  representative general-model corpus from audited public sources. Use both
  accounts' accumulating mail for a separate, incremental personal comparison,
  including wanted mail and graymail. Record SpamSieve/server/unknown provenance separately from human labels;
  never train from Junk membership alone. Compare both products on the same frozen
  holdout with both learning states frozen and auto-training disabled. Record any
  prior exposure; use newly collected unseen mail where that cannot be excluded.
  Report false positives, missed junk, abstentions, review burden,
  p50/p95 latency, throughput, memory/CPU and cost. Keep campaign duplicates out of
  both training and holdout; do not retune on the holdout. Retain the 0.2% good-mail
  false-positive bound and $150 ceiling above; no new spend is authorized by this item.
  - [x] Add validated frozen-cohort paired reports and observed performance/review metrics.
  - [ ] Collect independent labels and execute a frozen SpamSieve comparison.

- [ ] **SS-06 — Make unattended operation a supported setup path.** SpamSieve's
  [drone workflow](https://c-command.com/spamsieve/help/drone-setup-and-remote)
  filters synchronized accounts while its Mac is running. SpamWise monitoring
  depends on its app lifecycle, and no login service is installed. Add
  opt-in launch-at-login/background operation, visible paused/offline states and
  restart recovery. Validate filtering with windows closed, screen locked, after
  restart and after sleep; explain when the Mac and Mail.app must remain running. Finish
  fresh-user live onboarding and package the actual accepted build.
  - [x] Keep monitoring independent of windows and provide opt-in login registration.
  - [x] Verify scan progress with all app windows closed and persisted scope/progress after app quit/relaunch.
  - [ ] Replace the menu's "SpamWise is running" with an aggregate status: setup incomplete, dry run, permission denied, failing or offline.
  - [ ] Launch at login in the background, without presenting a window.
  - [ ] Evaluate App Nap during unattended sweeps, for example with `ProcessInfo.beginActivity`.
  - [ ] Verify screen-lock, OS restart, sleep/wake and fresh-user acceptance.

### P1 — daily workflows and control

- [ ] **SS-07 — Review and rescue good mail already in Junk.** SpamSieve provides a
  [rescue script](https://c-command.com/spamsieve/help/rescuing-good-messages).
  Add a bounded, per-account Junk review queue with explanations and explicit
  restore-to-Inbox. Start read-only; any later automatic rescue requires separate
  opt-in, validated destinations and measured precision. Preserve the original
  filter provenance, avoid rescuing user-blocked senders, and prevent move loops
  with SpamSieve/server filters. Do not treat the user's growing sample folders as
  permission to move or relabel their contents automatically.
  - [x] Implement bounded read-only Junk review and explicit restore.
  - [x] Verify signed rescue on generated mail through Review Junk → Mark Good and restore, with unchanged source and independently confirmed Inbox location.
  - [x] Detect when a restore would replace an explicit Block rule and say so in the status line.
  - [ ] Explain each listed message by joining it to its decision record or matching rule, and label its provenance unknown or other when SpamWise has no record.
  - [ ] Ask for confirmation before a restore replaces an explicit Block rule.
  - [ ] Extend coexistence coverage beyond the single settled probe to repeated SpamSieve/server filtering and reconnects.

- [ ] **SS-08 — Train through Mail.app's synchronized folders.** Match
  SpamSieve's [dedicated training mailboxes](https://c-command.com/spamsieve/help/drone-setup-and-remote)
  with explicitly configured, account-scoped Good/Junk training folders read through
  Mail.app. Folder placements may synchronize from another device without requiring
  integration with its mail client. Process each deliberate placement once,
  save the correction before moving it to the
  intended Inbox/Junk destination, and reconcile reconnects and duplicate deliveries.
  Ordinary Junk moves and server classifications must not count as user training.
  Test from a second device and preserve failures for review.
  - [x] Implement dedicated-folder baseline, atomic training claims and retained failures.
  - [ ] Verify deliberate placement from a second device and reconnect behavior.

- [ ] **SS-09 — Select accounts and folders to filter, and refilter deliberately.**
  SpamSieve [filters selected non-Inbox mailboxes](https://c-command.com/spamsieve/help/filter-spam-messages-in)
  and supports [manual refiltering](https://c-command.com/spamsieve/help/requirements).
  Extend our Inbox-only sweep configuration with account/folder inclusion and
  exclusion, a start boundary, progress, cancellation and a dry-run preview. Handle
  renames/removals without silently broadening scope; keep Junk rescue separate.
  Test server-routed mail and explicit historical refiltering without replaying
  old actions or allowing the message to establish its own trusted history.
  - [ ] Implement account/folder plans, folder-plan date boundaries and cancellable dry-run refiltering.
    - [x] Exact account/path plans, date boundaries, cancellable dry-run preview, and a core plan lifecycle (disable and remove) with a specific error when the 20-plan limit is reached.
    - [ ] List saved plans independently of folder discovery, including unresolved ones, with Disable and Remove, and show plan errors beside Save.
    - [ ] Support folder exclusion; the Inbox is always swept for selected accounts.
  - [x] Verify signed historical preview in a generated folder and fail-closed behavior after renaming that folder; the saved scope remains unchanged and the generated message stays untouched.
  - [ ] Extend coverage to actual server rules and reconnects.

- [x] **SS-10 — Expand rules beyond literal sender addresses/domains.** SpamSieve
  has [header/body matchers, regex, rule state and match statistics](https://c-command.com/spamsieve/help/rule-columns-locations).
  Add a staged rule builder for mailing-list headers, recipients, Reply-To,
  subject/body and attachment metadata; support enabled state, notes, bounded
  regex and a test-against-samples preview. Show which rule won and potential
  conflicts. Specify new-rule ordering before implementation while preserving
  address → domain → trusted gates and latest same-scope correction; no lock option
  may silently defeat a user's later correction. Include schema migration/export.
- [x] **SS-11 — Add initial training and a manageable corpus.** SpamSieve supports
  [initial examples](https://c-command.com/spamsieve/help/do-an-initial-training), a
  [corpus browser](https://c-command.com/spamsieve/help/corpus) and
  [controlled auto-training](https://c-command.com/spamsieve/help/auto-train-as-needed).
  Our corrections and bounded learning store need a review/import workflow,
  deduplication, class-balance indicators, label provenance and retention controls.
  Support correcting/forgetting examples and rebuilding derived learning without
  losing explicit rules. Make bulk corpus import distinct from sender-rule creation;
  ordinary corrections retain their established address-rule behavior. SpamSieve's
  corpus messages can be exported as raw source and imported as reviewed `.eml`
  examples; it has no stable interchange schema, so no rule or database migration is
  offered. Add undo with a preview of affected rules/examples and a separately verified
  mail action. Keep predicted labels separate and never promote them into held-out truth.
  - [ ] Show reviewed-label capacity, warn before an import rolls off correction labels, and add a Rebuild learning control.
- [x] **SS-12 — Make Activity a useful troubleshooting log.** SpamSieve's
  [log](https://c-command.com/spamsieve/help/log) records predictions, training,
  rule changes and failures, with message/source inspection. Add search and filters
  for account, sender, date, path, outcome and correction; retain a policy/rule
  revision trail. Add safe local previews, an unambiguous open-in-Mail action and
  opt-in raw-source export. Offer a redacted diagnostic bundle with no keys or mail
  content by default. Verify that previews never fetch remote resources.
  - [ ] Page the Activity table through the store's paged activity queries instead of filtering the in-memory record set.
- [ ] **SS-13 — Bring meaningful statistics into the app.** Match SpamSieve's
  [date-filtered statistics](https://c-command.com/spamsieve/help/statistics) using
  existing evaluator primitives: per-account trends, reviewed mistakes, unresolved
  Review, action failures and provider cost. Show reviewed sample counts and
  uncertainty; never assume an uncorrected prediction was correct. Separate
  operational counters from held-out quality, with export and date ranges.
  - [x] Date and account selection, daily decision totals, reviewed-disagreement counts, unresolved Review, action failures, cost and JSON export.
  - [ ] Chart a trend per account, labeled by account name rather than raw account ID.
  - [ ] Show exact one-sided binomial bounds next to reviewed counts, using the evaluator's Clopper-Pearson bound.
- [ ] **SS-14 — Provide restrained notifications and review prioritization.**
  SpamSieve offers [good-mail and uncertain-spam notifications](https://c-command.com/spamsieve/help/notification-center-sho),
  [uncertainty thresholds](https://c-command.com/spamsieve/help/uncertain-spam-messages)
  and optional [mark-as-read](https://c-command.com/spamsieve/help/mark-it-as-read).
  Add opt-in notifications, batching/quiet controls and direct correction links;
  prioritize likely mistakes in the existing digest. Offer mark-as-read only as an
  explicit supported preference after a confirmed Junk action. Keep text labels,
  sparse color and uncalibrated-score warnings; do not overwrite users' flags or
  claim that Apple Mail background colors synchronize to mobile devices.
  - [x] Implement quiet batched notifications, review ranking and separate post-Junk read status.
  - [x] Verify a generated message remains unread during Junk settling, then becomes read only after the confirmed Junk outcome; independently compare unchanged source.
  - [ ] Verify signed notification delivery and deep links after permission is granted.

- [ ] **SS-15 — Protect against own-address and trusted-sender spoofing.** SpamSieve
  has an [own-address exception to Contacts trust](https://c-command.com/spamsieve/help/catch-spam-sent-from-my).
  Add explicit own-address/alias discovery and configurable exclusions from automatic
  relationship trust. Evaluate authenticated alignment and forged-contact cases
  without trusting sender-supplied Authentication-Results. Preserve explicit user
  rule precedence; missing or untrusted authentication remains unknown. Include
  legitimate self-mail, forwarding and mailing-list fixtures before changing gates.
  - [x] Discover own addresses and aliases, and exclude them and user-listed senders from relationship trust.
  - [x] Require trusted, aligned authentication from the account's configured receiving servers before the Contacts, reply and receipt gates or an Allow rule can decide; otherwise pass the relationship to the model as evidence. The forged-contact fixture passes with no exclusion configured.
  - [ ] Let the user confirm, edit and stop trusting receiving servers (tracked under trusted receiving servers above); until then the gates never fire.
  - [ ] Warn before a correction writes a Block rule for an unauthenticated sender.

- [x] **SS-16 — Back up, restore and migrate learned state safely.** SpamSieve
  documents [training-data transfer/restore](https://c-command.com/spamsieve/help/how-can-i-copy-my-train)
  and [storage management](https://c-command.com/spamsieve/help/settings-storage).
  Go beyond our rules-only import/export: versioned, validated backups of rules,
  policy, labels, derived learning and selected settings, with optional encrypted
  retained content. Exclude credentials and do not transfer live-action validation
  to a different account/endpoint. Test migration, corruption recovery and restore
  with actions paused; avoid synchronizing a live SwiftData database between Macs.
  - [ ] Build a recovery screen on the store's set-aside legacy state; today only a status line reports that recovery is needed.

### P2 — Mail.app coverage and product lifecycle

- [ ] **SS-17 — Analyze more attachment-only spam locally.** SpamSieve advertises
  [image and document inspection](https://c-command.com/spamsieve/). Our embedded
  image OCR is partial coverage. Evaluate bounded local PDF/text/document
  extraction and additional image formats, with malicious, encrypted and oversized
  fixtures. Keep attachment content untrusted, never execute macros or fetch remote
  content, and distinguish unreadable attachments from spam evidence.
  - [x] Add bounded text/HTML attachments and additional verified still-image formats.
  - [x] Complete isolated PDF/document extraction evaluation and encrypted/resource-limit fixtures. See [ten-case probe and limits](docs/probes/document-inspection.md).
  - [x] Build and test a signed restricted XPC harness with mutual code requirements, bounded data-only messages, sandbox file/network denial and crash/CPU/wall/resident-watchdog recovery. See [worker behavior and shipping limits](Tools/DocumentWorker/README.md).
  - [ ] Establish enforceable memory containment, acceptable lifecycle latency and adversarial coverage before integrating production PDF extraction. The sampled watchdog demonstrably overshoots; PDFs remain unsupported in the app.
  - [x] Research public macOS resource controls and established parser alternatives; document the distinction between allocator budgets and whole-process containment, including MuPDF licensing and a possible bounded WebAssembly experiment. See [containment decision](docs/probes/pdf-containment.md).
  - [x] Implement cancellation before/during worker requests, first-wins completion, connection-loss termination and recovery in a different process. Keep one document per process to preserve CPU accounting and allocation reclamation; launchd restart latency remains an integration limit.

- [ ] **SS-18 — Publish a verified Mail.app/account compatibility matrix.** Use
  SpamSieve's [requirements](https://c-command.com/spamsieve/help/requirements) as
  a documentation baseline. Verify account types through Mail.app, including
  account-specific special mailboxes, synchronization and offline recovery. Document
  unsupported cases, macOS 27 and hardware requirements; older-macOS support needs a
  feasibility decision rather than an automatic deployment-target downgrade. No
  additional mail-client adapters or direct server integrations are required.
  - [x] Publish the specific iCloud/Google evidence and unsupported/runtime-pending matrix.
  - [ ] Complete offline recovery and broader account/hardware acceptance.

- [x] **SS-19 — Expose documented automation.** SpamSieve supplies an
  [AppleScript interface and integration SDK](https://c-command.com/spamsieve/help/customizing-using-apple).
  Design supported CLI/Shortcuts/Apple Events entry points for SpamWise and Mail.app:
  classify-preview, explicit correction, status and export. Keep account identity, cancellation,
  idempotency, spending limits and action authorization consistent with the app.
  The existing Inbox-trigger URL and evaluator/daemon do not cover these workflows.
  - [x] Implement documented App Intents and durable UUID replay protection.
  - [x] Execute the status intent through AppIntentsTesting on a signed build after correcting a stale installed-app registration; see [automation](docs/automation.md).
  - [x] Verify native preview/correction parameter binding, durable replay, retained rules after denied actions, and redacted diagnostics export against one signed fixture process. These checks use synthetic mail and a mock classifier; real selected-mail acceptance remains SS-04.
  - [x] Run a saved status shortcut in the editor, through the Shortcuts CLI and through its AppleScript bridge, with an explicit **Stop and Output** action.

- [ ] **SS-20 — Finish maintainable distribution and lifecycle support.** SpamSieve
  has [installation/update, migration and removal workflows](https://c-command.com/spamsieve/help/SpamSieveManual_toc).
  Add a tested signed-update path for direct distribution, clear upgrade/recovery
  guidance, login-item removal and user-controlled data removal on uninstall.
  Finish the notarized-release/App Store prerequisites without treating archive
  success as distribution or review approval.
  - [x] Document upgrade/recovery, login-item removal and optional data removal.
  - [x] Research Apple's distribution rules and document the Mail exception and remaining review gates. Developer ID is the primary channel; the store edition depends on the exception decision.
  - [x] Add revocable provider mail-sharing permission and opt-in domain-age lookups; hide PCC in both editions.
  - [x] Maintain a [functionality ledger](docs/distribution-differences.md) for the two editions.
  - [x] Build separate `SpamWise-MAS` and `SpamWise-download` targets over the shared `SpamWise Common` framework. The download edition runs scheduled and manual GitHubUpdateChecker checks and hands the user the downloaded disk image; the store edition links no updater. See [updating](docs/updating.md).
  - [x] Add fastlane lanes that archive both editions, notarize and staple the download app and its disk image, upload the store build, and a tag-driven release workflow with `CHANGELOG.md` notes.
  - [x] Add CI: `ci.yml` runs the package tests, builds both editions and the extension, and runs the hostless unit tests on pushes and pull requests to `main`; `lint.yml` runs SwiftLint.
  - [ ] Add signed UI-test and DocC jobs to CI.
  - [x] Prepare and browser-check five static prerelease pages at desktop and mobile widths, with local assets and no analytics.
  - [x] Create the private `RISCfuture/SpamWise` repository with a manually deployed Pages workflow and restricted site artifact. Publication remains subject to review; see [repository approval](docs/repository-approval.md).
  - [ ] Publish a release from the public repository and verify discovery, the download, offline errors, rate limiting, prereleases and version ordering with a signed, notarized build.
  - [ ] Verify replacing an installed copy from the downloaded disk image, including Mail extension and login-item registration afterwards, and switching between editions.
  - [ ] Finish App Store prerequisites and release acceptance, after the exception decision above.

### Opportunities to exceed the baseline — prove, then claim

- [ ] **SS-21 — Show a measurable benefit from semantic preferences.** Evaluate
  unwanted marketing, abandoned carts, expected receipts and forged shipping
  notices against SpamSieve on independently labeled messages. Ground explanations
  in actual correspondence/order evidence, retain unknown-history distinctions,
  and test prompt injection and contradictory examples. Policy text and extra
  providers alone are not evidence of better filtering.
  - [x] Support frozen policy/no-policy comparisons in the offline reporting tool.
  - [ ] Compare zero-shot preferences with small increments of private corrections; do not require universal training from personal graymail.
  - [x] Complete the synthetic multilingual policy/example smoke test with $0.0020729 estimated new cost and $1.20 conservative reservations; leave thresholds unchanged.
  - [ ] Measure semantic-preference benefit on independently reviewed unseen mail.

- [ ] **SS-22 — Reduce review effort without hiding risk.** Rank Review and rescue
  candidates by disagreement and likely error; explain the specific rule/evidence
  that drove each decision and the effect of a proposed correction. Measure minutes
  and corrections needed per 1,000 messages at the same false-positive bound as the
  baseline. Keep detailed diagnostics behind disclosures and preserve accessible,
  uncluttered English/Spanish/French flows.
  - [x] Rank review by action failure, disagreement and uncertainty; report observed review effort.
  - [ ] Measure review effort at the matched false-positive bound.

- [ ] **SS-23 — Make local/cloud tradeoffs explicit and measurable.** After SS-03
  and SS-05, evaluate an opt-in local-first classifier policy with separately
  authorized cloud escalation for uncertain cases. Show what would leave the Mac,
  why, and its estimated cost; allow preview/cancel. Benchmark privacy, quality,
  latency and spend together. Never introduce a silent provider fallback or treat
  the $150 ceiling as a target.
  - [x] Report paired local/cloud quality, latency, resources, review effort and cost.
  - [ ] Complete local/quality prerequisites before implementing authorized cloud escalation.

### Deliberate differences

- Keep the product's **no Trash/delete** contract. SpamSieve documents
  [age-based cleanup](https://c-command.com/spamsieve/help/automatically-deleting)
  and [score-based Trash actions](https://c-command.com/spamsieve/help/move-it-to-the-trash-if);
  feature parity does not justify adding them here.
  Authorized cleanup of our generated test mail is an operator task, not a product
  filtering action. Preserve the user's growing Junk corpus.
- Keep fail-open behavior for parsing, evidence, storage and integration failures;
  do not adopt encoding/language-only blocking from the competitor's configurable
  rules. Preserve user rules first and explicit domain-level corrections.
- Use Mail.app's public Apple Events interface, with runtime validation for each route.
  The MailKit extension leaves every message to Mail, because MailKit messages carry no
  account identity SpamWise can trust. Avoid private Mail database access, legacy
  plug-in injection and Full Disk Access.

Suggested delivery order: SS-01/02/05/06 for reliability and evidence, SS-03/04 for
local privacy and correction access, then SS-07/08 and the remaining P1 work.
P2 and superiority experiments follow measured user benefit. Research
and this backlog do not enable features, change live-mail settings or schedule
collection/evaluation.

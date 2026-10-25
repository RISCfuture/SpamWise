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
  - [x] Add the bounded independent detector path to all successful classifications, preserve rule actions and exclude preference-derived learning scores. Records and diagnostics mark mail no detector assessed as unassessed rather than safe.
  - [ ] Connect a quality-validated production detector. The app reports unassessed coverage; synthetic injected detectors establish orchestration only.
  - [x] Hide the inspector's threat section when no detector ran.
- [ ] Evaluate targeted impersonation, payment diversion and other fraud using account-scoped context; preserve unknown history.
- [ ] Evaluate zero-shot graymail preferences and incremental private personalization; distinguish example retrieval from actual model fine-tuning.
  - [x] Run a reproducible 12-context EN/ES/FR synthetic policy-only/two-example comparison; record labels, effective actions, usage and limitations in [preference results](docs/probes/graymail-preferences.md). Examples showed no categorical improvement; this is not fine tuning or independent real-mail quality.
  - [x] Screen the default against 16 private Junk candidates, four real wanted controls and eight synthetic wanted controls, with a sender-disjoint reserved set; tune unknown promotions to Review and preserve ordinary wanted mail. Compare one simulated correction and four deceptive challenges in [first-run results](docs/probes/graymail-oobe.md). One-shot benefit and broad quality remain unproven.
  - [x] Screen 495 account-holder-confirmed unwanted Junk messages and 15 provisional wanted controls with sender-disjoint development and holdout sets; add category preferences, a setup Junk-folder import and category-level correction follow-ups, and fix reason-length failures (21 of 86 shipped requests). Account-equivalent preferences flagged 40/40 unwanted holdout messages but moved none, since no confidence reached 95; they also flagged 7/9 wanted controls. The Junk import showed no measurable benefit. See [Junk-folder results](docs/probes/junk-folder-oobe.md).
  - [ ] Validate a clean signed-app setup and provider request, independent account holders and campaigns, independently adjudicated labels, multilingual mail and repeated runs before claiming general zero-shot or one-shot quality.
- [ ] Establish dedicated attachment/malware coverage without treating text-model predictions as antivirus results.

## Implemented and verified offline

- [x] Explicit Apple on-device, OpenAI and Gemini classifiers alongside Claude, from one model catalog. Fresh sessions, bounded prompts/results, measured usage where available, explicit prices, refusal handling, retried Anthropic server errors and no fallback. A missing key is reported as a missing credential. Private Cloud Compute is hidden in both editions and rejected if restored, because neither holds Apple's managed entitlement.
- [x] Address/domain rule editing, validated atomic import and export. Address rules precede domain rules, content rules and relationships. Block rules always apply; Allow rules need trusted aligned authentication.
- [x] Per-account trusted receiving servers. Authentication-Results are trusted only from the account's configured servers; Allow rules, Contacts, reply and receipt history need a trusted aligned pass and are otherwise model evidence. Receiving servers are sampled from up to 50 messages per account to detect a consistent set. The forged-contact fixture passes with no exclusion configured.
- [x] Identify Microsoft 365 and Outlook.com receiving servers, whose topmost Authentication-Results header names none, from the provider's lone instance-1 ARC-Authentication-Results set. The ARC set only names the server; the provider's own topmost header supplies the trusted results. See [receiving-server trust](docs/evidence.md#receiving-server-trust).
- [x] Policy suggestions from consistent corrections, applied only by the user.
- [x] Retrieval of similar reviewed examples, five by default (0–20), from the same account or, for imported reviewed examples, any account, quoting domains rather than full addresses and shortening quoted text. `sameSender` is set only for a trusted aligned sender.
- [x] Bounded regularized evidence weights and Bayes as optional weak signals, with minimum reviewed-data gates. Product learning uses every label; the 20% hold-out applies only to evaluation.
- [x] Anchored campaign fingerprints from explicit Junk corrections, suppressed by conflicting Good examples and Review signatures. Matches go to Review, never straight to Junk. Junk anchors need a trusted DMARC pass, so fingerprints stay inert until an account trusts its receiving servers.
- [x] Optional Spamhaus DBL lookups for From, Reply-To, Return-Path and link domains, with explicit terms acknowledgement and unknown results for service errors. Public DNS uses in-process resolver queries to one configured resolver and works in both editions.
- [x] Optional user-keyed Spamhaus HTTPS transport, shared Keychain storage, explicit service selection, bounded requests and fail-open handling. Live authorization awaits an HTTPS-enabled account; free DNS access does not establish HTTPS entitlement. See [setup and limits](docs/spamhaus.md).
- [x] Optional local Rspamd symbols through the fixed-loopback HTTP transport; errors remain unknown. It works in the signed sandbox harness without new entitlements, defaults off and is blocked in local-only mode. No external executable transport exists.
- [x] Bounded Vision OCR of embedded PNG and JPEG parts without remote image loading. Other formats are not decoded until OCR moves into a separate worker (SS-17).
- [x] IMAP adapter on swift-nio-imap with implicit TLS, UIDVALIDITY/UID identity, SPECIAL-USE discovery, capability checks, Review as `$SpamWiseReview` or `\Flagged`, verified move identities, and implicit Good corrections for mail rescued from Junk in another client. Each message is read once; a backfill runs only after a burst deeper than the 2,000-message scan. The app signs in with a password; the headless `spamwise-daemon` (`run`, `validate`, `probe`) also accepts an OAuth bearer token and records daemon-scoped validation.
- [x] Learn implicit Good corrections from Apple Mail messages dragged from Junk back to Inbox or marked Not Junk, as IMAP does, only for a Junk move recorded as settled (on Apple Mail, still in place at its 30-second recheck). The correction moves no mail and acts only where the sweep saw the message.
- [x] Move and verify corrections of mail without a Message-ID by recorded size and exact content; automatic moves still leave such mail in place and say why.
- [x] Local weekly digest of unresolved Review items, without sending email.
- [x] Explicit Good/Junk/Review label collection. With **Keep text of reviewed messages** on (Settings → Advanced → Learning from corrections), Reviewed Messages keeps and exports bounded reviewed text for later evaluation; with it off, imported examples keep no body excerpt and a restore withholds a backup's message text.
- [x] Production spending: an optional user-set monthly limit, off by default, reserves each paid request's token-bound maximum and settles it to measured usage. The conservative lifetime ledger is confined to `spamwise-eval`, which requires an explicit `--budget-store`; its authorized additional evaluation ceiling is $150, not a spending target.
- [x] Retain unstarted persistent retries when cancellation interrupts a batch; individual atomic claims reject superseded jobs. Transient failures retry with backoff for up to three days, and Pause or dry-run edits no longer invalidate pending work.
- [x] Shared state in real SwiftData entities with change tokens and slice-scoped loads, a cross-process lock, retention limits and a set-aside path for unreadable state. Pre-1.0 stores are not imported: a single-document snapshot from a build before the entity schema is set aside for recovery.

See [evidence](docs/evidence.md), [IMAP](docs/imap.md), [evaluation](docs/evaluation.md)
and [packaging](docs/packaging.md) for limits and reproducible commands.

## Engineering follow-ups

- [ ] Complete Spanish and French coverage.
  - [x] Give each SpamWiseCore module its own catalog with `defaultLocalization: "en"`, resolved through `bundle: .module`. `Scripts/check-core-localizations.py` enforces the bundle, es/fr values, matching specifiers and unused keys; the app catalog holds only strings the app targets extract.
  - [x] Rewrite the Help book's sixteen task pages in English, Spanish and French and rebuild each search index; `Scripts/check-help-book.py` checks every anchor the app opens in all three languages.
  - [ ] Give count strings plural variants in the app and package catalogs.
  - [ ] Inspect the reworked Settings, Activity, setup and correction screens in Spanish and French for wrapping, truncation and footer layout. Include the Backup and restore and Your addresses and exceptions sections, the folder-plan discard confirmation, the storage-unavailable main window, the local-only key note and the About panel's notices.
- [ ] Check the bundled third-party notices whenever a pinned package changes. `SpamWise/ThirdPartyNotices.txt`, `SpamWise-download/DownloadThirdPartyNotices.txt` and the NOTICE excerpts in `CREDITS.md` reproduce the pinned checkouts verbatim, but no script regenerates or verifies them against `Package.resolved`.
- [ ] Give `spamwise-daemon`'s failure messages CLI-specific recovery suggestions. Both executables embed an Info.plist declaring `CFBundleLocalizations`, and the daemon's output goes through localized strings.
- [ ] Decide whether to run `swiftlint analyze`. It stays out of CI: its `explicit_self` findings contradict the house style, its `unused_declaration` findings were false positives, and its `unused_import` autofix removed imports the build needs. A useful gate would disable those rules and read a full `xcodebuild` log.
- [x] Save Settings text and stepper edits, and trust-exclusion edits, still inside their debounce window when the app quits.
- [x] Show an IMAP account that was never checked as not validated, rather than Dry run, when Apple Mail accounts are validated; `FilteringStatus` counts only the selected transport's validated accounts, telling IMAP accounts by their `imap:` identifier prefix.
- [x] Ask for the same unverified-sender confirmation in the Correct Selected Mail App Intent that the app's Junk corrections ask for.
- [x] Add Help buttons for the newer Help pages (rules, folders, Review Junk, backup, notifications, reviewed messages, statistics, IMAP) on the screens they describe.
- [x] Test a selected-message correction batch in the hostless unit tests against a stub Apple Events runner.
- [x] Resolve correction records left pending when the process ends between saving a correction and recording its mail outcome, or when storage stays locked through every retry of that outcome. Each sweep records a correction pending for more than ten minutes (`Pipeline.unstartedCorrectionAgeSec`) without its message's action claim as failed and not attempted; a correction no longer pending is never claimed, and one holding its claim keeps its outcome.
- [x] Stop repeating embedded-image OCR for a message the monthly spending limit defers. The pipeline keeps the image text of up to 500 deferred messages in memory, by raw-message digest, for their later sweeps, and forgets it once the message is processed otherwise.
- [ ] Give the store's keyed documents (`Store.read(_:default:)` and its update) a set-aside path. They decode strictly, so an unreadable document fails every read and update of it instead of being set aside for recovery like other unreadable state.
- [ ] Add a reason-category column to `RecordRow` so Activity can filter and count by status category from the store rather than by decoding every reason.
- [ ] Owner action: reset a store written by builds before 1.0 once. SpamWise clears only the orange Review marks it recorded setting, and those builds recorded none, so corrections leave their marks in place.
- [ ] Make Apple Mail handler calls interruptible. Interactive calls (corrections, lookups, selections, account and destination reads, the probe) and background calls (sweeps, pages, automatic actions) run on separate queues with separate OSAKit component instances, so a correction no longer waits behind a page script, and each call has a 30-second wall-clock limit. A call that times out or is cancelled still runs to completion on its lane, because in-process OSA execution cannot be stopped. `NSUserAppleScriptTask` is not a fit: it runs only scripts the user installs in `~/Library/Application Scripts` and has no cancellation. A terminable XPC helper needs its own `automation.apple-events` entitlement and Mail temporary exception, a signed check that macOS attributes its Automation consent to the app rather than prompting for the helper, and a design for launchd's roughly ten-second restart spacing seen with the document worker; killing it still would not stop an Apple Event Mail has already received. This needs signed runtime work.

### Dependencies and code-review follow-ups

Open findings from code reviews and audits, each confirmed against the current code.

- [ ] Fix the dependencies upstream, then bump their pins:
  - [ ] ClaudeForFoundationModels: let SpamWise inject a hardened URL session. Claude requests use the SDK's default session (shared cookies and cache, same-origin redirects, no response cap), unlike the ephemeral, redirect-refusing OpenAI and Gemini client, and the per-request timeout gives every classification a new executor and session.
  - [x] XCUITestKit: its `ios-release.yml` ran unpinned actions and `curl | bash` alongside signing secrets. 1.1.1 pins every action to a commit, installs `sentry-cli` from its Homebrew cask, keeps the certificates token out of Git config and limits jobs to read-only access; `release.yml` pins 1.1.1.
- [ ] Classification and app behavior:
  - [ ] Show model confidence as an uncalibrated score out of 100, as Help describes it, rather than as a percentage in the inspector.
  - [ ] Keep the images already accepted when a later embedded image is excess or invalid; today one such image drops OCR for the whole message.
  - [ ] Cache the fitted learned-weight and Bayes models; with learning on, both are refitted for every message, inside the classification budget and again while admitting a prediction.
  - [ ] Decide whether Bayes self-training should admit high-confidence model verdicts at all. Contradiction, contact and history guards limit it, but a prompt-injected verdict can still become a weak sample.
  - [ ] Run the RDAP and Spamhaus lookups concurrently under the shared deadline instead of one after the other.
  - [ ] Move the hourly Contacts enumeration off the cooperative thread pool.
  - [ ] Key monthly costs and weekly digests by a fixed Gregorian calendar rather than `Calendar.current`.
  - [ ] Export statistics with labeled ISO-8601 days; daily counts encode as an unlabeled alternating array.
  - [x] Let a training-folder placement whose move failed before any command was sent be retried by placing the message again. A record says whether dispatch stopped before sending any command, so only those failed moves release their claim; every failed or unconfirmed move that may have been sent keeps it.
  - [x] Remember the user's quiet hours after turning them off and on again across a Settings reload. `NotificationPreferences` stores `quietHoursEnabled` beside the chosen hours, and a stored value with equal start and end hours reads as off with the default 22–8.
- [ ] Command-line tools:
  - [ ] Require the daemon configuration's `allowsActions` as well as `--actions`; the flag replaces it today.
  - [ ] Give `spamwise-daemon` and `spamwise-eval` domain-age lookups when the setting is on, or say they are unavailable.
  - [ ] Freeze learning and drop corpus-matching corrections in `spamwise-eval corpus --state`, and offer a label-free way to supply additional instructions for held-out runs, recorded in the report.
  - [ ] Create `spamwise-eval` exports, reports and caches as private (0700 directories, 0600 files); Mail exports and reports use the default umask.
  - [ ] Move `spamwise-eval`'s argument guards and report logic into a tested library.
  - [ ] Report `Scripts/store-probe.swift` argument errors as usage errors, not `StoreError.invalidPath`.
- [ ] Research tools:
  - [ ] Corpus: quarantine records whose MIME parsing raises `IndexError`, read JSONL line by line in `audit.py` (U+2028 splits records today), time `bsdtar` by inactivity, keep precise failure reasons, compute SpaPhish cross-split counts after assignment, verify pinned model weights, tokenizer and config hashes before loading, and split bundled tests.
  - [ ] `Tools/Preferences/run.py` and `Scripts/evaluate-with-keychain.swift`: a timeout kills only the launcher, leaving the evaluator, which holds the key, running.
  - [ ] Document worker: fail the symbol check when `nm` fails, retry a reconnect that reaches the cancelled worker, keep text from other pages when one page has none, and test the pure logic outside the signed harness.
  - [ ] Site generator: derive each table's label from its heading and deduplicate heading anchors.
  - [ ] Record a tool hash in every result artifact and regenerate or annotate stale ones; key mock responses by fixture rather than by raw-byte hash.
- [ ] Tests: URLProtocol tests for the loopback Rspamd transport's limits; a test that fails a write after a successful load to prove persistence before action; assertions moved out of fixture closures; specific error assertions in place of `(any Error).self`; a domain Block over a contact case; injected clocks in place of wall-clock waits; and predicate waits before UI absence checks.
- [ ] Code structure and documentation: replace bare-string Help anchors, routes and categories, unit-less money and time values and hand-written clamps with named types and helpers; map `ReviewTreatment` with an exhaustive switch; replace the `@_exported` core re-exports with explicit imports; give `CachedThreatDetector` a caller or make it internal; share the latest-record reduction and resource limits instead of repeating them; and give public enum cases DocC comments.

## Live acceptance and external prerequisites

The owner has deferred provider access, supervised device sessions, personal labeling
and App Store account steps. These items stay open. Spamhaus stays disabled until an
eligible user configures [optional access](docs/spamhaus.md).

- [x] Meet the brief's §8 fixture criterion with Claude: filler-text spam and the stranger cart go to Junk or Review, and the order confirmation and personal mail to Inbox. Claude Haiku with `--state eval/fixture-state.json` returns Inbox for both good fixtures and Review for the graymail and both junk fixtures, repeatably, for about $0.0015 a run. The offline fixture check's outcomes come from hand-written mock verdicts, so it exercises plumbing, not the prompt. Apple on-device returns Review for all five, including the good fixtures, so it does not meet the criterion.
- [x] Let clear-cut model Junk verdicts reach Junk at the current thresholds. The prompt no longer asks for precision or puts scams in Junk or Review; it anchors confidence of 95 or more to content no legitimate sender would send, says unverified authentication doesn't weaken a verdict the content settles, and summarizes the claims of an account without trusted receiving servers in one line. On Claude Haiku, 17 of 50 public spam and phishing messages reached Junk under Balanced (2 before) while none of 80 SpamAssassin hard-ham messages or the good fixtures got a model Junk verdict at any confidence. See [prompt evaluation](docs/probes/2026-10-25-junk-prompt-eval.md).
- [x] Let a graymail Junk preference act on how sure the model is of the category. Verdicts carry `categoryConfidence` (0–100, independent of whether the mail is wanted; schema `spamwise-verdict-v4` in every provider), and the prompt defines it beside the label confidence. For a graymail category the user chose Junk for, a category confidence at or above `FilteringStrength.graymailThreshold` moves the message to Junk whatever its label, with the reason "You chose Junk for …"; below it the label policy applies as before. Keep, Flag, other categories, gates, rules, relationships, dry run, pause and claims are unchanged, records without a category confidence keep the label policy, and such decisions never self-train Bayes. `spamwise-eval` reports list each message's label, confidence, category, category confidence, action and preference.
- [ ] Calibrate `FilteringStrength.graymailThreshold` on reviewed real graymail with wanted controls of the same kinds before relying on it. The values 95, 90 and 85 in `Decision.swift` were chosen on the development split of the [preference-adherence evaluation](docs/probes/2026-10-25-preference-adherence.md), which used synthetic mail labeled by two Claude labelers, Claude Haiku alone and two of its five profiles. Colleague mail that the model calls cold outreach at category confidence up to 85 sets the Balanced value.
- [ ] Calibrate per-model Junk thresholds on a labeled holdout with legitimate difficult negatives before changing the provisional 90, 95 and 99 (`Decision.swift`); the 80 hard-ham messages above shaped the prompt's wording, so they are development data, not a holdout. Filler-spam reaches 88–90, so the fixture criterion's two Junk outcomes still need either calibration or a trusted receiving server (about 8 points in the investigation). Haiku sometimes returns confidence 0–5 for an Inbox or Review label (11 of 80 hard-ham messages), apparently scoring junk likelihood; settle the confidence wording before calibrating. Graymail categories default to Review (`CategoryPreferences.defaults`), so promotions, carts and cold outreach reach Junk only when the user chooses it.
- [ ] Verify each newly selected provider with its own credentials and evaluate quality before relying on it. OpenAI setup-key storage and read access in login Keychain work; the one synthetic OpenAI request was rate-limited (HTTP 429) with no verdict or usage, and the $150 ledger retains its $1 reservation. Successful classification and operational shared-Keychain import remain pending. Gemini waits for a key. Apple on-device completed five synthetic requests but returned Review for every fixture. Refusal is never spam evidence.
- [ ] Validate optional DNS service terms/resolver, local Rspamd availability and real OCR fixtures on the signed distribution. A sandbox-denied optional operation remains unknown.
  - [x] Verify six synthetic EN/ES/FR PNG/JPEG/GIF/TIFF cases through native Vision in a signed sandboxed harness, with malformed/remote-only inputs unknown. The app has since stopped decoding GIF and TIFF. Observe local-mode guards and a network-observer positive control. See [runtime evidence and limits](docs/probes/local-evidence-runtime.md).
  - [x] Build pinned Rspamd 4.2.2 and verify the HTTP adapter against a disposable local scanner, including empty results, stopped-service unknown, redirects without forwarding, streaming overflow, service errors, shortened deadlines, cancellation and concurrent scans. See [scanner evidence](docs/probes/rspamd-runtime.md). Installed service rules and representative quality remain separate.
  - [ ] Confirm in-process DNS queries from the signed, sandboxed app against a real resolver.
- [ ] Complete signed live onboarding and correction acceptance.
  - [x] Verify signed menu-bar Junk correction and Junk-review restore on one generated cross-account message, independently checking source and settled mailbox after each action. See [live corrections](docs/probes/live-corrections.md).
  - [x] Verify post-Junk read status, scanning with all windows closed and persisted scan progress after app relaunch. See [live follow-up](docs/probes/live-mail-followup.md).
  - [x] Settle a Review flag or background Mail doesn't confirm: SpamWise reads the message until it shows the change, within the 30-second settling window, without sending it again, and otherwise records the result as unknown. When Mail didn't answer the request, a mark that then shows stays the user's, so a correction doesn't clear it. An inspector's Preview, Open in Mail or Export replaces the request before it, can be stopped, and is abandoned when the selection changes or the inspector closes, so a stale request never opens Mail.
  - [ ] Complete fresh-user live onboarding, timed against the brief's five-minute target.
  - [ ] Run the rewritten Apple Events handlers from the signed app: account and special-mailbox resolution, the `whose` queries (including the local-ID-first and size-first candidate queries), message-size agreement between lookup and action, the 1,000-mailbox walk for a recorded folder, the received-date filter, the separate interactive and background OSAKit lanes, the move polling window and settled recheck under iCloud and Google synchronization, the Review read-back after Mail doesn't confirm a flag, and the `junk mail status` clear and read-back after a Good correction.
  - [ ] Run the remaining reworked corrections on generated mail from the signed app: Classify Again on an unclassified message and Review Junk's Block-rule prompt. A development-signed run passed a menu-bar batch with progress and Stop, domain scope (including the shared-provider refusal), the unverified-sender confirmation and Review Junk's restore. See [live acceptance](docs/probes/2026-10-25-live-acceptance.md).
  - [x] Make Undo Latest Correction undo a whole selected-message batch. It restores the rules and learning from before the batch and says how many of the batch's corrections stay when another change was saved partway through; it still needs a live rerun.
  - [x] Finish the move check for corrections already sent to Mail when a batch stops. Corrections already started run to the end, including their move checks; Stop Correcting keeps the rest from starting and is unavailable once every message has started.
  - [x] Clear Mail's own junk mark on mail marked Good. Once a Good correction's move to Inbox is confirmed, including a Review Junk restore and mail taken out of Junk in Mail, SpamWise clears Mail's `junk mail status` and reads it back; over IMAP it removes `$Junk` and `Junk` with one `UID STORE`, sending none when neither is set and leaving `$NotJunk` alone. The step has its own claim saved before it is sent and its own outcome (applied, no action when there was no mark, sent, failed), is never retried, and doesn't run in dry run or Pause; the inspector shows it as Mail's junk mark cleared. SpamWise never sets the mark, including on Junk corrections. It still needs a live run.
  - [ ] Check on a running build: file and notification window requests handled at the scene with the item hidden, and VoiceOver itself reading the menu bar item. Hiding the item in General, reopening Activity from the Dock and `open -a` with it hidden, and the `check-inbox` URL passed live; the item's accessibility name now reads "SpamWise: *state*" instead of the envelope symbol's "Get Mail".
- [ ] Accept IMAP before relying on it. The route is selectable in Settings → Accounts, where Check Connection, a read-only check, validates the account for actions, but no live TLS authentication, SPECIAL-USE discovery, move, Review keyword or junk-keyword removal has run against a real server. Test with disposable probes on at least one provider supporting `UID MOVE`, including password sign-in from the app, reconnects, switching transports, Forget Connection, and the daemon's OAuth bearer authentication and `validate`/`probe`/`run --actions` path. A connection saved with an OAuth token by an earlier build now signs in with it as a password and fails open; re-enter a password.
  - [x] Going live does not revisit IMAP mail checked during dry run: IMAP reads each message once, so that mail stays where it is, unlike Apple Mail. The General footer says so for each connection.
- [ ] Make trusted receiving servers usable and safe.
  - [x] Settings → Accounts shows each account's trusted mail server or detection progress, with Trust Detected Server, Enter Server…, Edit… and Stop Trusting. Until the user trusts a server, relationships and Allow rules in that account are model evidence only.
  - [x] Before a Junk correction writes a Block rule for an unauthenticated sender, ask for confirmation in the inspector, the digest and selected-message batches, saying the From address may be forged.
  - [ ] Make an address lose its authenticated receipt credit when one of its messages is later labeled Junk or Review, including corpus relabels, and confirm through the pipeline that a persisted receipt count without trusted aligned authentication never allows a sender.
  - [ ] Give the headless daemon a way to confirm trusted servers; today it can only use trust set through the shared store.
- [ ] Extend move synchronization coverage to slow/offline servers and longer observation windows. An automatic or correction move is confirmed after two consecutive matching observations two seconds apart, and the pipeline rechecks it once the 30-second settling window ends, marking the outcome unconfirmed if the message is no longer its destination's one copy. The disposable probe waits the full window for each move. These are client observations, not server acknowledgements. A recheck pending when the app quits is lost, and that move never counts as settled, so rescuing its message teaches nothing. Ambiguous same-account Sent copies remain untouched.
- [ ] Measure automatic sweep latency on large and mutating mailboxes. Bounded repeating scans do not promise immediate coverage.
- [ ] Calibrate general detectors on source-audited public holdouts and evaluate personalization incrementally on independently reviewed mail. No labeled personal corpus exists yet; it is not a universal-training or initial-use prerequisite. Conservative 99, Balanced 95 and Aggressive 90 remain provisional; the evaluator's calibration targets (0.1%, 0.2% and 0.5% false-positive bounds) are provisional too. Approximately 1,500 independent good examples with zero false positives are needed for a rule-of-three upper bound of 0.2%; mock fixtures do not establish that target.
  - The user is accumulating SpamSieve-classified mail in each account's Junk folder. Preserve these folders as candidate sources; keep SpamSieve predictions separate from human-confirmed labels. Include reviewed wanted mail and graymail, exclude generated probes, deduplicate, and reserve a holdout before tuning. See [evaluation](docs/evaluation.md).
- [ ] Obtain PCC managed entitlement approval and matching profiles if PCC is desired. Private Cloud Compute has no token-counting API, so its context fit can't be measured before a request, unlike the on-device model's.
- [ ] Get an early App Review decision on the `com.apple.mail` Apple Events temporary exception before further store work. Every action path depends on it and the extension alone does nothing, so a refusal also risks a minimum-functionality rejection. If it is refused, decide between an IMAP-only store build and no store edition. Developer ID is the primary channel meanwhile. See [App Store feasibility](docs/app-store-feasibility.md).
- [ ] Complete App Store Connect metadata/privacy disclosures, the exception justification, signed store export, store validation and App Review. Authenticated validation stops because no App Store Connect app record exists for `codes.tim.SpamWise` (error 19). No upload or publication has been performed. See [App Store packaging](docs/app-store.md).
  - [x] Prepare provider-retention disclosures, a source/artifact privacy audit, Mail exception/reviewer notes, and a responsive static marketing/privacy/support site under `docs/`. Publication and final privacy answers remain separate steps.
  - [x] Declare Emails or Text Messages and Other User Content (App Functionality, not linked to tracking) in the app's privacy manifest; give the extension a manifest declaring no collection.
  - [x] Category: Utilities, in the bundle and the [App Store draft](docs/app-store.md).

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
| Trusted senders and rules | Address/domain and content rules, per-account trusted receiving servers, Contacts/history as authenticated gates or evidence, own-address exclusions, import/export | Receipt-credit loss after Junk labels and broader real-mail spoofing and forwarding acceptance remain open |
| Mail integration | Apple Mail adapter, persisted repeating sweeps with stalled-page fallback, folder plans and dedicated-folder training | Second-device training and sustained delivery acceptance remain open |
| Corrections | Activity, Filtering-menu and menu-bar selected-Mail commands with progress and Stop, reviewed import, undo; rules persist despite action failures | Generated live corrections, a batch with Stop, rescues and implicit learning passed; batch undo awaits a live rerun |
| Inspection and evaluation | Evidence details, searchable corpus, statistics with per-account trends and binomial bounds, safe preview, versioned backup/restore and CLI reports | Representative calibration remains open |
| Safety and review | Persist-before-action, fail open, deduplication, dry run, Review stays in Inbox, local weekly digest, aggregate filtering status | Need sustained runtime coverage and faster review workflows |

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
  - [x] Confirm in a live run that Mail stays frontmost and Activity stays closed when `open -g spamwise://check-inbox` fires, both while SpamWise runs and when it launches SpamWise; both accounts were checked within a second. The command was run directly, not from an installed Mail rule.
  - [x] Keep oversized or unavailable sources from blocking later readable mail; persist unreadable counts, retry on the next sweep and preserve training claims on incomplete reads. See [paging behavior and limits](docs/probes/unreadable-mail-pages.md).
  - [x] Fall back when a page keeps timing out: halve the page after each consecutive timeout (one message after four) and skip a backfill position that still times out after six. Record per-account coverage (visited, classified, reviewed, unclassified), consecutive failures and timeouts, and the latest pass start.
  - [x] Verify controlled incoming delivery and continuing scans with windows closed and after app relaunch.
  - [x] Show each account's last check, late, failing and stalled states, coverage categories and older-mail backlog in Settings → Accounts; the menu bar and Activity footer report failing, including a stalled account in scope, and offline.
  - [ ] Extend coverage to wake, OS restart, offline recovery and sustained mutating-mailbox latency.
  - [x] Add a core retry for unclassified records, so a settled persistent or exhausted transient failure can be reconsidered without an unrelated settings change.
  - [x] Offer Classify Again for unclassified mail in the inspector and the Filtering menu, under the same pause and dry-run rules.

- [ ] **SS-02 — Validate mailbox roles and multi-filter coexistence.** SpamSieve
  documents [distinguishing its actions from server filtering](https://c-command.com/spamsieve/help/spam-message-colors-in).
  Add per-account destination previews and verify provider semantics, especially
  Gmail system labels versus similarly named custom folders. Exercise SpamSieve,
  server rules and SpamWise without competing moves or duplicate classifications;
  default comparison runs to dry run. Extend the existing slow-server and uncertain
  move tests; preserve source-folder/action provenance and clean up generated probes.
  - [x] Expose account-specific special-mailbox destination previews.
  - [ ] Verify concurrent-filter behavior and slow/offline provider synchronization.
  - [ ] Verify coexistence with Mail's own Junk Mail filter, on by default, in both its mark-only mode (whose colors can resemble Review) and its move-to-Junk mode.
  - [x] Flag a Gmail-hosted account whose Junk role is a custom label. On the owner's Mac, Mail maps a Gmail account set up as generic IMAP to custom "Junk" and "Deleted Messages" labels, so SpamWise's confirmed Junk moves never reach Gmail's Spam. Setup and the account's mailboxes warn, without withholding validation, when the Junk role is outside the [Gmail] or [Google Mail] folder; Help explains how to give Spam the Junk role.

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
  - [x] Run selected-message corrections without opening Activity: the menu shows progress, Stop and a result summary, and opens the results only on request or when a confirmation is needed.
  - [x] Correct the Mail selection from a key: the Correct Selected Mail App Intent takes a keyboard shortcut in Shortcuts, as Help describes. Menu-bar items carry no key equivalents, because those fire only while the menu is open.
  - [x] Offer explicit domain scope for selected-message corrections.
  - [x] Reject a new selected-message correction while one runs; automatic sweeps don't block user corrections.
  - [ ] Overlap or batch post-move verification; moves still settle one at a time.
  - [ ] Verify a Shortcuts keyboard shortcut for Correct Selected Mail while Mail is frontmost live. Good and Review corrections, multi-message selections and the shortcut run from Shortcuts passed live.
  - [x] Check at runtime whether Preview and Correct Selected Mail, which declare `.foreground`, bring SpamWise forward: both do, and SpamWise stays in front. Shortcuts asks once to allow the app's actions and its output.

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
  - [x] Report one aggregate filtering state in the menu bar and Activity footer: setup incomplete, paused, Mail not authorized, Mail not running, offline, failing, mailboxes not found, dry run or filtering.
  - [x] Open at login without presenting a window: a login launch closes the Activity window that SwiftUI opens.
  - [x] Keep App Nap off while Mail work runs with no window visible, through `ProcessInfo.beginActivity`, still allowing idle sleep. Sustained unattended timing stays under SS-01's latency item.
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
  - [x] Explain each listed message from its decision record: SpamWise's reason, a user correction, or no record.
  - [x] Ask for confirmation before a restore replaces an explicit Block rule.
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
  - [x] Move a placement trained during dry run once filtering goes live, only while its correction stands (not undone or corrected again). A complete traversal releases claims it no longer finds, and a folder over 5,000 messages completes with a noted limit.
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
    - [x] List saved plans independently of folder discovery, including unresolved ones, with a Process toggle and confirmed Remove, and show plan errors under Save Plan.
    - [ ] Support folder exclusion; the Inbox is always swept for selected accounts.
  - [x] Verify signed folder resolution and a no-action historical preview in a generated folder, and fail-closed behavior after renaming that folder; the saved scope remains unchanged and the generated message stays untouched. Classification was not exercised: provider consent was off, so the preview returned `consentRequired`.
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
  - [x] Show reviewed-label capacity, warn before an import rolls off correction labels, and add Rebuild Learning.
- [x] **SS-12 — Make Activity a useful troubleshooting log.** SpamSieve's
  [log](https://c-command.com/spamsieve/help/log) records predictions, training,
  rule changes and failures, with message/source inspection. Add search and filters
  for account, sender, date, path, outcome and correction; retain a policy/rule
  revision trail. Add safe local previews, an unambiguous open-in-Mail action and
  opt-in raw-source export. Offer a redacted diagnostic bundle with no keys or mail
  content by default. Verify that previews never fetch remote resources.
  - [x] Page the Activity table 200 rows at a time through the store's activity queries, with store-backed sorting that survives paging.
- [x] **SS-13 — Bring meaningful statistics into the app.** Match SpamSieve's
  [date-filtered statistics](https://c-command.com/spamsieve/help/statistics) using
  existing evaluator primitives: per-account trends, reviewed mistakes, unresolved
  Review, action failures and provider cost. Show reviewed sample counts and
  uncertainty; never assume an uncorrected prediction was correct. Separate
  operational counters from held-out quality, with export and date ranges.
  - [x] Date and account selection, daily decision totals, reviewed-disagreement counts, unresolved Review, action failures, cost and JSON export.
  - [x] Chart daily counts per account, labeled by account name.
  - [x] Show the exact one-sided 95% Clopper-Pearson upper bound next to reviewed mistakes.
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
  - [ ] Decide whether notifications offer correction actions, as this item's direct correction links ask, or stay count-only with Review in SpamWise.

- [ ] **SS-15 — Protect against own-address and trusted-sender spoofing.** SpamSieve
  has an [own-address exception to Contacts trust](https://c-command.com/spamsieve/help/catch-spam-sent-from-my).
  Add explicit own-address/alias discovery and configurable exclusions from automatic
  relationship trust. Evaluate authenticated alignment and forged-contact cases
  without trusting sender-supplied Authentication-Results. Preserve explicit user
  rule precedence; missing or untrusted authentication remains unknown. Include
  legitimate self-mail, forwarding and mailing-list fixtures before changing gates.
  - [x] Discover own addresses and aliases, and exclude them and user-listed senders from relationship trust.
  - [x] Require trusted, aligned authentication from the account's configured receiving servers before the Contacts, reply and receipt gates or an Allow rule can decide; otherwise pass the relationship to the model as evidence. The forged-contact fixture passes with no exclusion configured.
  - [x] Let the user confirm, edit and stop trusting receiving servers; until then the gates never fire in that account.
  - [x] Confirm before a correction writes a Block rule for an unauthenticated sender.
  - [ ] Finish the open trusted-server items above: receipt-credit loss and daemon confirmation.

- [x] **SS-16 — Back up, restore and migrate learned state safely.** SpamSieve
  documents [training-data transfer/restore](https://c-command.com/spamsieve/help/how-can-i-copy-my-train)
  and [storage management](https://c-command.com/spamsieve/help/settings-storage).
  Go beyond our rules-only import/export: versioned, validated backups of rules,
  policy, labels, derived learning and selected settings, with optional encrypted
  retained content. Exclude credentials and do not transfer live-action validation
  to a different account/endpoint. Test migration, corruption recovery and restore
  with actions paused; avoid synchronizing a live SwiftData database between Macs.
  - [x] Show a recovery screen when stored data can't be read: save a copy of the set-aside data, restore a backup, or keep the current settings.

### P2 — Mail.app coverage and product lifecycle

- [ ] **SS-17 — Analyze more attachment-only spam locally.** SpamSieve advertises
  [image and document inspection](https://c-command.com/spamsieve/). Our embedded
  image OCR is partial coverage. Evaluate bounded local PDF/text/document
  extraction and additional image formats, with malicious, encrypted and oversized
  fixtures. Keep attachment content untrusted, never execute macros or fetch remote
  content, and distinguish unreadable attachments from spam evidence.
  - [x] Add bounded text/HTML attachment extraction.
  - [ ] Decode GIF, TIFF and HEIC images for OCR in an isolated worker. The app reads only PNG and JPEG, checking each part's signature before ImageIO sees it.
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
  - [x] Publish tested iCloud and Google behavior and untested account types on the [Mail compatibility](docs/mail-compatibility.md) page; the per-check probe matrix is in the [live Mail follow-up](docs/probes/live-mail-followup.md).
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
  - [x] Add CI: on pushes and pull requests to `main`, `ci.yml` runs the source checks and Python tool tests on Linux, the package tests, Release builds of both editions with the icon check and of the extension, and the hostless unit tests, failing on any build diagnostic; `lint.yml` runs a pinned SwiftLint.
  - [x] Add CI jobs that run the UI tests against an ad-hoc-signed App Store edition in test mode and build the package's DocC, failing on any warning in SpamWiseCore sources.
  - [ ] Confirm the UI job passes on a hosted runner; XCUITest Accessibility there and the ad-hoc runner without a provisioning profile are unexercised.
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
    - [x] Compare shipped, category-preference and Junk-import conditions on a frozen private holdout; the import changed no effective decision ([Junk-folder results](docs/probes/junk-folder-oobe.md)).
  - [x] Complete the synthetic multilingual policy/example smoke test with $0.0020729 estimated new cost and $1.20 conservative reservations; leave thresholds unchanged.
  - [ ] Measure semantic-preference benefit on independently reviewed unseen mail.
  - [ ] Evaluate adversarial prompt injection and contradictory examples. Classifier tests cover escaping and separation only.

- [ ] **SS-22 — Reduce review effort without hiding risk.** Rank Review and rescue
  candidates by disagreement and likely error; explain the specific rule/evidence
  that drove each decision and the effect of a proposed correction. Measure minutes
  and corrections needed per 1,000 messages at the same false-positive bound as the
  baseline. Keep detailed diagnostics behind disclosures and preserve accessible,
  uncluttered English/Spanish/French flows.
  - [x] Rank review by action failure, disagreement and uncertainty; report observed review effort.
  - [ ] Measure review effort at the matched false-positive bound.
  - [ ] Show the effect of a proposed correction in the inspector before it is saved.

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

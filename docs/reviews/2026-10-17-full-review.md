# SpamWise code review — 2026-10-17

> **Status, 2026-10-18:** all High findings and 13 related entries (§1.16, §2.20, §2.21, §2.29, §2.93, §2.141, §4.20, §5.28, §7.11, §9.8, §9.23, §9.39, §10.1) were fixed in commits `9cd385f` and `a9fcb38` and have been removed from this document, and the scorecard counts exclude them. The summary paragraph and scorecard headlines still describe the code as reviewed, and cross-references to removed entries point to fixed problems.

SpamWise is not shippable through either the Developer ID or the Mac App Store channel. The core code is carefully bounded, and its main safety rules hold: there is no delete or Trash path, decisions are persisted before any action, dry run is on by default, and provider consent is checked before every paid request, retries included. The package tests pass and both app builds are warning-free. The trouble is that the agent's own acceptance and evaluation scaffolding became product behavior, and the logic that decides which mail gets classified fails silently. Three risks dominate. First, filtering stops for good: every production call draws on the developer's $150 lifetime evaluation ledger, so cloud classification ends after about 1,500 Haiku messages. Second, coverage: nothing scans automatically until the user passes a hand-built `[SpamWise Probe]` move test. Once scanning starts, sweeps walk the whole existing Inbox with no priority for new mail, and they dedupe against a 5,000-record display log, so large Inboxes are re-sent to the provider indefinitely. Third, trust: the allow gates trust the forgeable From header (one receipt-like message allow-lists all of gmail.com), and an `@` in a display name or a single bad byte leaves a message unclassified. The Mail extension also sends every account's mail to the cloud regardless of the account scope the user chose. These defects mostly leave spam in the Inbox rather than moving good mail to Junk. Around the code, the repository cannot be built from a fresh clone, has no CI, and ships no app icon. The 24 High entries below collapse to 15 distinct problems, because several sections reported the same root cause. Nothing was rated Critical.

## Scorecard

| Dimension | Verdict | Critical | High | Medium | Low | Headline |
|---|---|---|---|---|---|---|
| 1. Security and privacy | Needs work | 0 | 0 | 15 | 23 | Consent, credential storage and transports are sound. The allow gates trust the forgeable From header, attacker-triggered parse failures guarantee "unclassified", and the extension ignores account scope. |
| 2. Correctness | Needs work | 0 | 0 | 62 | 92 | The safety rules hold, but filtering stops for good at the $150 ledger, and whole-message fail-open plus log-based dedupe leave much mail unclassified. |
| 3. Progress through the TODO list | Overstated | 0 | 0 | 8 | 11 | Most checked items are real. Six SpamSieve parents (notably SS-04 and SS-15) are checked without meeting their own acceptance text, and no CI backs any "verified" claim. |
| 4. Swift and SwiftUI conventions | Partial | 0 | 0 | 24 | 67 | Swift 6 setup, concurrency and test naming are right. The gaps are bare-string domain values, duplicated limits, reused error cases, drifted duplicate logic, and a weakened SwiftLint config with 429 hidden findings. |
| 5. Comments and documentation | Partial | 0 | 0 | 20 | 85 | Public DocC is nearly complete, but much of it is templated or wrong. CLAUDE.md, docs/ and the Help book read as a contradictory agent diary. |
| 6. Project configuration vs. SubTrack and Zephyr | Behind sisters | 0 | 0 | 8 | 15 | The package is well configured. An unpushed local library dependency breaks fresh clones, nothing runs in CI, the main scheme is unshared, and editions exist only as a script flag. |
| 7. Distribution readiness | Not ready | 0 | 0 | 11 | 8 | Signing and notarization work. The $150 lifetime cap, the whole-Inbox sweep, the probe-gated start and the missing icon block both channels, and the release pipeline lacks versioning, a stapled container, updates and license notices. |
| 8. Front-end design | Needs work | 0 | 0 | 37 | 26 | Native SwiftUI and AppKit parts are used throughout. A developer probe gates real filtering, decision reasons are unlocalized debug strings, and a shared busy flag, a single status string and uncoordinated sheets make the UI feel unreliable. |
| 9. Temporary code and configuration | Needs cleanup | 0 | 0 | 12 | 20 | Test fixtures are fenced behind `#if DEBUG`. The evaluation ledger and the probe move test became product behavior, and ledger copy leaks into Settings and Help. |
| 10. Architecture and simplicity | Needs simplification | 0 | 0 | 12 | 10 | The module graph is sound. All state is one JSON blob rebuilt about 10 times per message, infrastructure is duplicated, and speculative features run on the hot path. |

Info entries are not shown: §1 has 12, §4 has 4, §2 and §5 have 3 each, §7, §8 and §9 have 2 each, and §6 and §10 have 1 each.

## Top priorities

1. **Medium.** Add CI modeled on Zephyr, with package tests, warning-free builds of both editions and the App Store variant, and lint. `.github/workflows/site.yml:3`. See §6.2, §3.2, §6.3.
2. **Medium.** Define the App Store and download editions in the project, with their own targets or configurations and shared schemes, instead of a command-line `APP_STORE` override. `Scripts/app-store-check.sh:44`. See §6.5, §7.5, §9.5.

## What is solid

- **Safety rules.** The project-level invariants hold in every module reviewed. No path deletes mail or moves it to Trash, decisions are persisted before the action claim, dry run starts on, and failures never move good mail to Junk. `ConsentCheckedClassifier` re-checks consent just before each request, so revoking consent also stops queued retries (§1, §2).
- **Security mechanics.** Credentials live in the data-protection Keychain as `AfterFirstUnlockThisDeviceOnly` and are never synced or logged. The OpenAI, Gemini, Spamhaus and Rspamd clients use ephemeral sessions that refuse redirects and cap response size. AppleScript and IMAP escaping is sound, and backups use AES-GCM with validation before an atomic replace (§1).
- **Build and test health.** The package reports 89 passed tests and 1 opt-in skip, with zero warnings under `-warnings-as-errors`. Both app builds are warning-free, and every Python suite passes ruff and its tests (§2, §6).
- **Swift 6 package setup.** The package uses tools 6.4, Swift 6 mode, and the full upcoming-feature set plus strict memory safety on every target. Production code has a single `@unchecked Sendable` (`CompletionOnce`). Tests use Swift Testing with raw-identifier names (§4, §6).
- **Module structure.** The module graph matches the contract: SpamWiseCore imports no MailKit or SwiftUI, Signals never imports Store, and Decision is a small pure policy layer (§10).
- **Native UI parts.** The app uses `Table` with `.inspector` and `.searchable`, a real `Settings` scene, `MenuBarExtra`, `ContentUnavailableView` and Swift Charts. Color is restrained, all 12 SF Symbols resolve on macOS 27, and every active string has Spanish and French values with matching placeholders (§8).
- **Signing and evidence.** Sandbox, hardened runtime, notarization, stapling and Gatekeeper assessment have all passed. The store package excludes the updater and the `dig` path. Most checked TODO items are genuinely wired, and the corpus reports are hash-pinned with figures that match the TODO text (§3, §7).
- **Hygiene basics.** Public DocC coverage is nearly complete. There is no commented-out code and there are no untracked TODO markers. UI-test fixtures are behind `#if DEBUG`, no secrets are tracked, and the one workflow is SHA-pinned with least-privilege permissions (§5, §6, §9).

## How this review was done

Fifty-nine reviewers (56 planned plus 3 gap reviews, none failed) covered the ten lenses above across slices of the code: core parsing and signals, classifier and learning, pipeline and store, mail integration, app logic, views, tests, tools, evaluation scripts and repository docs. Adversarial verification checked all 978 raised findings, kept 965 (53 High, 309 Medium, 558 Low, 45 Info, no Critical), refuted 13 and left none unverified; the kept findings were then merged into the section entries counted above. Tooling runs included `swift test` with warnings as errors, unsigned `xcodebuild` builds of both apps plus `build-for-testing`, the Python unittest and ruff suites, SwiftLint under the house parent config, Periphery, and a fresh-clone `xcodebuild -list`. There were no live Mail, network or UI-test runs, signing and notarization were not rerun, runtime UI behavior was inferred from SwiftUI and AppKit semantics, and some design screenshots predate the latest UI changes.

## 1. Security and privacy

**The foundations are good.**

- **Consent gating:** every production model call, whether from the app, the Mail extension, App Intents or the daemon, goes through `ConfiguredClassifier`. It enforces local-only mode and per-provider consent. `ConsentCheckedClassifier` then checks consent again right before the request, so revoking consent also stops queued retries.
- **Credentials:** stored in the data-protection keychain with `AfterFirstUnlockThisDeviceOnly`, never synchronized, and never placed in URLs or logs.
- **Network clients:** the OpenAI, Gemini, Spamhaus and Rspamd clients use ephemeral sessions that refuse redirects and cap response size.
- **AppleScript and IMAP command construction:** escaping is sound. Reviewers tested the AppleScript side locally without involving Mail.
- **Backups:** AES-GCM with a random 256-bit key, validated before an atomic replace. Restore pauses filtering and forces dry run.
- **Invariants:** "never expose delete/Trash", "persist before acting" and "start in dry run" hold in every module reviewed.

**The serious problems are about trust, not missing gates.**

- **From header:** every deterministic allow gate trusts the unauthenticated From header. That covers address and domain Allow rules, Contacts, prior correspondence and receipt history. `trustedAuthServers` is never set in production, so authentication never takes part, and the "trusted fail" checks are dead code.
- **Receipt gate:** this is the worst case. One message containing "Your receipt", "order" and a price can permanently allow every sender at its registrable domain, including `gmail.com`. The manual onboarding import even counts unclassified spam that is sitting in the Inbox. Six reviewers found this independently.

**Fail-open has become an evasion primitive.** Under the stated "fail open on every error" rule, any error leaves a message unclassified and unflagged, and the attacker can trigger many of those errors from message structure:

- an `@` in the display name;
- an invalid encoded-word, charset or quoted-printable escape;
- a header-less MIME part;
- a field over 16,000 characters when a content rule is enabled;
- oversized evidence that pushes the prompt past 64 KiB;
- a duplicate Message-ID that makes every Apple Mail move ambiguous.

Separately, the HTML-to-text regexes are quadratic. A single 2 MB message can block the Pipeline actor for minutes and freeze the Review list on the main thread.

**Data leaves the device more widely than users would expect.**

- **Extension scope:** the Mail extension classifies every incoming message from every account while the route is `.unverified`. It ignores the account scope and transport the user chose.
- **Repeated transmission:** automatic sweeps re-send old Inbox mail to the provider once it falls out of the 5,000-record Activity window.
- **Other people's mail in every request:** each request carries up to 40 other correspondents' senders and subjects.
- **Credentials can't be removed:** stored keys have no delete path. An IMAP password is reused against a new host when the user edits the host but leaves the credential field blank.
- **Documentation:** the privacy manifest and the two privacy-policy drafts do not match what the code does.

**Spending ceiling.** The lifetime $150 evaluation ledger also caps production classification, and the App Store build depends on `temporary-exception.apple-events`. The verified findings record both under other dimensions, so they are not repeated here.

**Tooling and dependencies are mostly hygiene issues.**

- Command-line passwords visible to same-user processes.
- Export directories created with default `umask` permissions.
- An orphaned evaluator process left holding an API key after a timeout.
- One latent dependency risk: GitHubUpdateChecker's installer never verifies code signatures. SpamWise does not link it today, but TODO.md plans to adopt it.

### Data flows

| Data | Destination | Gate | Enforced at | Bypass risk |
|---|---|---|---|---|
| Sender, display name, subject, about 6,000 body characters, evidence, policy, up to 40 correction examples; attachment/OCR text when enabled | Claude / OpenAI / Gemini | Per-provider `mailSharingConsent`; not local-only | `ConfiguredClassifier.swift:28-36, 71-76` | Extension ignores account scope and transport (§1.1). Evicted and dry-run mail is re-sent (§1.2). Examples come from all accounts (§1.19). Daemon `--model` switches the shared backend (§1.41). |
| Same prompt | Apple Private Cloud Compute | Consent; not local-only; direct build only | `ConfiguredClassifier.swift:31-44` | Low: entitlement not granted, so it fails closed. |
| Same prompt | On-device model | None (local) | n/a | None. |
| Synthetic test message, key, IP, SDK User-Agent | Anthropic (Verify key) | None | `AppModelCredentials.swift:13` | Runs even in local-only mode (§1.48). |
| Sender registrable domain | IANA, then RDAP servers | `domainRegistrationLookup`; not local-only | `PipelineClassification.swift:156-159` | Uses `URLSession.shared` and an on-disk cache (§1.34). |
| Sender and link domains (at most 5) | Spamhaus via `dig` or HTTPS with key | `domainBlocklist` + `termsAcknowledged`; not local-only; DNS only in direct builds | `PipelineClassification.swift:169-170`; `ExternalEvidence.swift:177` | Attacker-ordered domain selection (§1.17). Acknowledgement is not reset when the resolver changes. |
| Full raw message source | Rspamd at 127.0.0.1:11333 or `rspamc` | Transport selected; not local-only; not paused | `Pipeline.swift:53-56` | Port is unauthenticated (§1.35). Child processes inherit daemon secrets (§1.53). |
| IMAP password / OAuth token | Configured IMAP host over TLS | User configuration | `IMAPProtocol.swift:194-210` | Reused after a host or mechanism change (§1.27). |
| Provider, Spamhaus and IMAP secrets | Data-protection Keychain, shared group | n/a | `Keychain.swift` | No delete path (§1.20). |
| Selected-message preview or correction result | Shortcuts output | `.requiresLocalDeviceAuthentication`; pipeline consent | `AutomationIntents.swift:25, 51` | Low: model reason text can quote content. |
| Status and diagnostics (counts only) | Shortcuts, exported file, Notification Center | Opt-in for notifications | `AutomationIntents.swift:73-93`; `LocalNotifications.swift:42` | None. |
| Rules, corrections, learning, labels (+ text if opted in) | Encrypted backup file | User action + recovery key | `StateBackup.swift` | Restore turns on retention (§1.39). Restore leaves learning state unvalidated (§1.40). Key copied to plain pasteboard (§1.26). Snippets kept with retention off (§1.36). |
| Decisions, retries, corrections, learning tokens, Contacts email snapshot, history indexes | App Group store, `rdap-cache.json` | Local | `State.swift` | Contacts snapshot and RDAP cache are missing from privacy.md (§1.34, §1.21). |
| Raw exported mail, eval reports, verdict cache | User-chosen directory | Developer CLI, `SPAMWISE_LIVE_API=1` | `AppleMailAdapter.swift:356`; `SpamWiseEval/main.swift` | Default `umask` permissions (§1.28). |
| Version check | GitHub (direct build) | Manual | `DirectUpdateModel.swift` | None; no content is sent. |

### Findings

| # | Severity | Location | Finding |
|---|---|---|---|
| 1.6 | Medium | `SpamWise/PrivacyInfo.xcprivacy:4` | Privacy manifest declares no collected data although mail goes to third-party AI providers |
| 1.7 | Medium | `SpamWiseCore/Sources/Classifier/Types.swift:262` | Unbounded evidence fields let any spammer force `contextExceeded` |
| 1.8 | Medium | `SpamWiseCore/Sources/Classifier/Types.swift:314` | Sender-triggered quoted-reply stripping hides the body from the model |
| 1.9 | Medium | `SpamWiseCore/Sources/Learning/CampaignLearning.swift:52` | Campaign fingerprints send mail to Junk at confidence 100 using forgeable anchors |
| 1.10 | Medium | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:161` | Apple Mail actions ignore the source mailbox and can move mail the user filed elsewhere |
| 1.11 | Medium | `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:28` | Full-source envelope reads have no size guard; one large message stalls history and selection |
| 1.12 | Medium | `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:202` | Duplicate Message-ID makes every Apple Mail action fail permanently |
| 1.13 | Medium | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:77` | Duplicate boundary/charset parameters are accepted silently (parser differential) |
| 1.14 | Medium | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:97` | Inline text parts with a filename are dropped from classifier input |
| 1.15 | Medium | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:136` | All-or-nothing parse errors give cheap ways to guarantee "unclassified" |
| 1.17 | Medium | `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:178` | Attacker-ordered and encoded URLs hide malicious domains from Spamhaus and link evidence |
| 1.18 | Medium | `SpamWiseCore/Sources/Signals/Gates.swift:97` | Allow gates and correction rules trust the unauthenticated From header; trusted-auth is never wired |
| 1.19 | Medium | `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:62` | Every cloud request carries up to 40 other messages' senders, subjects and gists |
| 1.20 | Medium | `SpamWiseCore/Sources/Store/Keychain.swift:25` | Stored provider, Spamhaus and IMAP credentials can never be removed |
| 1.21 | Medium | `docs/app-store.md:206` | Two privacy-policy drafts and data inventories have diverged |
| 1.22 | Low | `.build/.../ClaudeForFoundationModels/.../ClaudeExecutor.swift:149` | Claude refusals and `max_tokens` cut-offs are reported as configuration errors |
| 1.23 | Low | `~/Repositories/Libraries/GitHubUpdateChecker/.../AppInstaller.swift:288` | Update installer (planned adoption) never checks code signature, Team ID or bundle ID |
| 1.24 | Low | `CLAUDE.md:67` | Committed docs record credential-handling details and personal-mailbox operations |
| 1.25 | Low | `Scripts/store-provider-key.swift:46` | Provider-key helper uses the clipboard and an accessibility class that has no effect |
| 1.26 | Low | `SpamWise/BackupSettingsView.swift:24` | Backup recovery key copied to the general pasteboard without concealed/transient markers |
| 1.27 | Low | `SpamWise/IMAPConnectionModel.swift:130` | Saved IMAP secret is reused after host, port, username or mechanism changes |
| 1.28 | Low | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:356` | Exported raw mail, reports and caches use default `umask` permissions |
| 1.29 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:52` | Daemon credential read can block on a login-Keychain prompt despite claiming to be non-interactive |
| 1.30 | Low | `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:130` | AppleScript "exact source" and Message-ID comparisons ignore case |
| 1.31 | Low | `SpamWiseCore/Sources/MessageModel/DomainResolver.swift:11` | Public-suffix lookup ignores punycode, so IDN suffixes become registrable domains |
| 1.32 | Low | `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:14` | Optional OCR decodes untrusted TIFF/GIF/HEIC in the privileged app process |
| 1.33 | Low | `SpamWiseCore/Sources/Signals/Evidence.swift:91` | Authentication-Results parser matches tokens anywhere in the header |
| 1.34 | Low | `SpamWiseCore/Sources/Signals/RDAP.swift:18` | RDAP uses `URLSession.shared`, buffers unbounded responses, and persists undisclosed domain caches |
| 1.35 | Low | `SpamWiseCore/Sources/Signals/RspamdLoopbackHTTP.swift:29` | Loopback Rspamd sends full raw mail to whatever process holds port 11333 |
| 1.36 | Low | `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:54` | Imported body snippets are kept, sent and backed up with content retention off |
| 1.37 | Low | `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:59` | Model-generated reasons become "user correction" examples |
| 1.38 | Low | `SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift:106` | Rule imports apply without preview and can flip Block rules to Allow |
| 1.39 | Low | `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:83` | Backup restore turns on "Retain reviewed text" without asking |
| 1.40 | Low | `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:104` | Backup restore leaves learning state and correction field lengths unvalidated |
| 1.41 | Low | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:122` | Daemon `--model` silently changes the app and extension provider |
| 1.42 | Low | `Tools/Corpus/prepare.py:74` | Crafted MIME header raises IndexError and aborts corpus preparation |
| 1.43 | Low | `Tools/DocumentWorker/PDFExtraction.swift:17` | Document worker caps text in Characters but replies in JSON bytes, so the worker exits |
| 1.44 | Low | `Tools/Preferences/run.py:155` | Probe timeout orphans the evaluator holding the API key |
| 1.45 | Info | `.build/.../ClaudeForFoundationModels/.../ClaudeExecutor.swift:62` | Claude transport is less hardened than the OpenAI/Gemini transport |
| 1.46 | Info | `~/Repositories/Libraries/GitHubUpdateChecker/.../ReleaseNotesView.swift:45` | Release-notes view would load remote images |
| 1.47 | Info | `Scripts/export-store-match.py:103` | Temporary signing-keychain password on argv; signing borrows SubTrack's `MATCH_PASSWORD` |
| 1.48 | Info | `SpamWise/AppModelCredentials.swift:13` | Claude key verification runs in local-only mode |
| 1.49 | Info | `SpamWise/AppModelNavigation.swift:8` | `spamwise://check-inbox` triggers sweeps without the 60-second throttle |
| 1.50 | Info | `SpamWise/SpamhausSettingsView.swift:64` | Key-presence check reads the secret on the main thread |
| 1.51 | Info | `SpamWiseCore/Sources/Classifier/Types.swift:33` | Decoded `TokenUsage` skips clamping, so `estimatedCost` can overflow |
| 1.52 | Info | `SpamWiseCore/Sources/Learning/LearningState.swift:193` | Injection-steerable model verdicts are admitted as Bayes training data |
| 1.53 | Info | `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:47` | Daemon environment secrets are inherited by `dig`/`rspamc` children |
| 1.54 | Info | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:157` | Hidden HTML text and control/bidi characters reach the classifier |
| 1.55 | Info | `Tools/Corpus/screen.py:145` | "Pinned" model snapshot is verified only by directory name |
| 1.56 | Info | `Tools/DocumentWorker/check.sh:88` | Diagnostic-symbol guard silently passes if `nm` or `rg` fails |

#### 1.6 Privacy manifest declares no collected data although mail goes to third-party AI providers — Medium

- **Where:** `SpamWise/PrivacyInfo.xcprivacy:4` (the extension bundle has no manifest)
- **Problem:** The manifest declares only `NSPrivacyTracking = false` and the UserDefaults reason `CA92.1`; it has no `NSPrivacyCollectedDataTypes`. With consent, subjects, senders, body text and correction examples go to providers that retain them for up to 30 days, and domains go to Spamhaus and RDAP. docs/app-store.md already drafts "Emails or Text Messages", so the shipped manifest contradicts the project's own inventory. Whether a user's own-key provider relationship counts as developer "collection" is debatable.
- **Scenario:** The App Privacy answers are filled in from Xcode's privacy report as "Data Not Collected", which contradicts privacy.md and creates a guideline 5.1.2 risk.
- **Fix:** Make the decision explicitly. Add Emails or Text Messages and Other User Content (App Functionality, no tracking) to the app and extension manifests, with Zephyr-style comments, and keep the App Store Connect answers consistent.
<!-- sources: distribution/product#12, distribution/packaging#13, security/app-logic#11 -->

#### 1.7 Unbounded evidence fields let any spammer force `contextExceeded` — Medium

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:262` (also `Types.swift:297`, `Signals/Evidence.swift:60, 66`, `SpamWiseCore/ConfiguredClassifier.swift:55`)
- **Problem:** PromptBuilder truncates the subject and body but JSON-encodes the whole EvidenceBundle. That includes the From display name (up to the 64 KB header limit), unbounded Authentication-Results claims and auxiliary findings, and `<`/`>` and control characters expand to six bytes each. Above 64 KiB the prompt throws `contextExceeded`, which is not retried and produces no Review flag. The prompt is built before the budget check, so the bypass costs the attacker nothing and works with every provider.
- **Scenario:** A 60,000-character display name, or about 7,000 repeated `spf=pass` tokens, leaves the spam message "unclassified" in the Inbox under default settings.
- **Fix:** Cap every evidence string and collection: display name around 256 characters, about 20 auth results, link-domain cap for findings. Fit the prompt by encoded byte length by trimming the body and examples rather than throwing. Treat an oversized message as a weak Junk signal so it at least reaches Review.
<!-- sources: security/core-classifier-learning#1 -->

#### 1.8 Sender-triggered quoted-reply stripping hides the body from the model — Medium

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:314` (also `Types.swift:315-316`)
- **Problem:** `unquotedText` stops at the first "On … wrote:" or "-----Original Message-----" line and drops every `>` line, without checking that the message is a reply. The sender controls the body, so they can choose what the model sees, while Mail shows the user everything.
- **Scenario:** A phish that begins with "On Monday, Support wrote:" reaches the model as an empty body and stays in the Inbox.
- **Fix:** Strip quoted text only for real replies (In-Reply-To/References that match known history, or a marker that follows unquoted content). Keep a minimum share of the original text, and tell the model how much was removed.
<!-- sources: security/core-classifier-learning#2 -->

#### 1.9 Campaign fingerprints send mail to Junk at confidence 100 using forgeable anchors — Medium

- **Where:** `SpamWiseCore/Sources/Learning/CampaignLearning.swift:52` (also `CampaignLearning.swift:56, 81`, `SpamWiseCore/PipelineClassification.swift:27-35`)
- **Problem:** A Junk fingerprint matches any later message that shares one anchor and has at least 80% shingle overlap. Anchors are link domains and the unauthenticated From domain. The match skips the model and always clears the strength threshold, because the verdict is confidence 100.
- **Scenario:** With fingerprints enabled (off by default), the user junks a phish that copies bank.com's template and links to bank.com/privacy. The bank's genuine alert that uses the same template then goes straight to Junk.
- **Fix:** Build Junk anchors only from trusted, aligned DKIM/DMARC identity, and never let link domains be the only shared anchor. Send fingerprint matches to Review, or pass them to the model as evidence, instead of issuing a final verdict.
<!-- sources: security/core-classifier-learning#3 -->

#### 1.10 Apple Mail actions ignore the source mailbox and can move mail the user filed elsewhere — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:161` (also `MailScripts.swift:123-126, 202`, `Pipeline.swift:306`)
- **Problem:** `lookup` compares only the account and content hash. `MailScripts.resolve` searches every mailbox in the account, Trash included, and moves the match without comparing it to `identity.mailbox`. The IMAP adapter does pin the source mailbox. Sequential classification, the 30-second settle after each move and the retry queue create windows of several minutes between read and action.
- **Scenario:** A user files message #20 into "Receipts" while earlier Junk moves are settling. SpamWise then moves it from Receipts to Junk, or pulls a message the user trashed back into Junk or Inbox.
- **Fix:** In the action script, compare the resolved message's mailbox and account against `identity.mailbox` and raise an error on a mismatch. Exempt only explicit selection-based corrections. Add a stub-runner test where the mailbox differs.
<!-- sources: security/mail-integration#1 -->

#### 1.11 Full-source envelope reads have no size guard; one large message stalls history and selection — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:28` (also `AppleMailAdapter.swift:126, 205-206, 225, 295`)
- **Problem:** `recent`, `selected` and `selectedBatch` use the `envelope` handler, which copies each message's full source with no size check, up to 1,000 messages per call. Swift then throws `scriptFailed` for the whole result if any one source exceeds 2 MB. `nextPage` throws before advancing its cursor. The unreadable-entry handling added to `pageEnvelope` was never applied to these paths.
- **Scenario:** One 5 MB Sent message stalls incremental history on that page indefinitely, so reply and receipt history stop updating. Batch Mark as Junk fails whenever that message is part of the selection.
- **Fix:** Apply `pageEnvelope`-style size checks, skip oversized entries, advance the cursor by visited count, and cap the aggregate size per call (as IMAP does at 4 MB).
<!-- sources: security/mail-integration#4 -->

#### 1.12 Duplicate Message-ID makes every Apple Mail action fail permanently — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:202` (also `MailScripts.swift:14, 204`, `Pipeline.swift` failure path)
- **Problem:** Lookup matches the Message-ID, which the sender chooses, across the whole account and raises -1701 "ambiguous" if the count is not 1. The pipeline records the action as failed and never retries it. This also blocks legitimate restores when an unrelated message reuses the ID.
- **Scenario:** A spammer delivers two identical copies with the same Message-ID. Both are classified Junk, both moves fail, and both stay in the Inbox even with dry run off.
- **Fix:** Search the expected source mailbox first, break ties by content hash and local ID, and fail only when the candidates have identical content.
<!-- sources: security/mail-integration#3 -->

#### 1.13 Duplicate boundary/charset parameters are accepted silently (parser differential) — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:77` (used at `:97, :277, :319`; compare `EmbeddedImages.swift:134`)
- **Problem:** `parameter(_:in:)` collects every match but returns the first. That contradicts the contract that ambiguous critical headers fail, and it disagrees with EmbeddedImages, which rejects duplicates.
- **Scenario:** `boundary="a"; boundary="b"`: SpamWise classifies the harmless parts split on "a", while a client that uses "b" shows the spam.
- **Fix:** Return nil or throw `.malformed` when there is more than one hit for boundary, charset or filename/name. Share one strict parameter parser with EmbeddedImages, and add a duplicate-boundary fixture.
<!-- sources: conventions/core-parsing-signals#1 -->

#### 1.14 Inline text parts with a filename are dropped from classifier input — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:97` (also `MIMEParser.swift:271-273`, `AdvancedSettings.swift:57`)
- **Problem:** A Content-Type `name=` or Disposition `filename=` parameter marks a part as an attachment even when it is `inline`. With default settings its text and URLs are discarded before rules, Bayes, DBL and the model see them. Mail still renders the part inline.
- **Scenario:** A single-part `text/html; name="offer.html"` pitch with `Content-Disposition: inline` reaches the model as an empty body, and DBL gets no link domains.
- **Fix:** Treat text parts as attachments only when the disposition is explicitly `attachment`. When a text part is skipped, emit a "body content omitted" finding.
<!-- sources: security/core-parsing-signals#7 -->

#### 1.15 All-or-nothing parse errors give cheap ways to guarantee "unclassified" — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:136` (also `:82, :103-105, :119, :229, :243, :252-255, :310`, `Pipeline.swift:72-77`)
- **Problem:** Each of these throws for the whole message, and the pipeline then records "unclassified, no action": an invalid encoded-word, an unknown charset, one bad QP escape, a header-less part, a second Content-Type, an over-long `application/*` type, or stray base64 characters. Failing open is documented, but nothing addresses its adversarial use.
- **Scenario:** Bulk spam adds `Subject: =?utf-8?B?***?= Cheap meds`, and every copy stays in the Inbox unflagged.
- **Fix:** Degrade locally: keep undecodable words verbatim, blank undecodable parts with a finding, treat header-less parts as text/plain, and fall back to lossy decoding. Reserve message-level failure for identity-critical ambiguity, and send parse anomalies to Review.
<!-- sources: security/core-parsing-signals#8 -->

#### 1.17 Attacker-ordered and encoded URLs hide malicious domains from Spamhaus and link evidence — Medium

- **Where:** `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:178` (also `MIMEParser.swift:222, 321`, `Evidence.swift:73-75`)
- **Problem:** Every limit keeps the lexicographically first items: 5 DBL queries, 40 URLs, 20 domains. The From domain is dropped if five link domains sort before it. URLs are extracted from raw HTML, comments included, before entity decoding, so decoys cost nothing, and `https&#58;//`, `//host` and backslash forms are missed.
- **Scenario:** Five `a.com`…`e.com` decoys in an HTML comment mean neither the DBL-listed link domain nor the From domain is ever queried.
- **Fix:** Always query the From domain first. Rank link domains by significance (visible anchors first) rather than by sort order. Extract after entity decoding with normalization, and record a "truncated" finding when a limit is hit.
<!-- sources: security/core-parsing-signals#6 -->

#### 1.18 Allow gates and correction rules trust the unauthenticated From header; trusted-auth is never wired — Medium

- **Where:** `SpamWiseCore/Sources/Signals/Gates.swift:97` (also `Gates.swift:85-99`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:100-123, 135, 214-215`, `Signals/Evidence.swift:57`, `Learning/StatisticalLearning.swift:28`, `Learning/CorrectionLearning.swift:30`, `PipelineCorrections.swift:40-53`, `TODO.md:302`)
- **Problem:** Address/domain Allow rules, the Contacts match, reply history and receipt history all return Inbox at confidence 100 from `message.fromAddress`, before the model runs. No production caller passes `trustedAuthServers`, so every `AuthResult.trusted` is false, and the "trusted fail" contradiction checks are dead code. A forged sender also gets the retrieval sender bonus, and a correction on a forged message writes an address Block rule against the real sender. TODO.md marks SS-15 done although its forged-contact evaluation was never implemented. The address > domain > contacts/history precedence comes from the brief, but the missing authentication check is a real defect.
- **Scenario:** A phish from a forged `colleague@partner.example` (DMARC p=none) gets "gate: contact" and skips the model. Marking a forged `alice@friend.com` spam as Junk sends Alice's genuine mail to Junk afterwards.
- **Fix:** Configure trusted authserv-ids per account. Require a trusted, aligned DMARC pass (or aligned DKIM) before relationship gates, Allow rules or the retrieval bonus apply; otherwise pass the relationship to the model as evidence. Warn before writing a Block rule for an unauthenticated sender. Wire up or delete the dead checks, and reopen SS-15 until forged-contact fixtures pass.
<!-- sources: security/core-parsing-signals#5, security/core-classifier-learning#4, security/core-pipeline-store#1, security/app-logic#1, correctness/core-parsing-signals#5, correctness/core-pipeline-store#4 -->

#### 1.19 Every cloud request carries up to 40 other messages' senders, subjects and gists — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:62` (also `State.swift:27`, `AdvancedSettings.swift:47`, `CorpusManagement.swift:50-55`, `OnboardingView.swift:72`)
- **Problem:** `retrieveExamples` defaults to false, so every prompt includes the 40 most recent corrections from all accounts. Each carries a sender, domain, subject and gist, and imported examples carry 160 body characters. The onboarding copy says "relevant examples".
- **Scenario:** Corrections on family or medical mail travel with every later newsletter classification from any account, about 40 times the exposure per request.
- **Fix:** Default to similarity retrieval with a small limit (around 5), scope examples to the message's account, send domains instead of full addresses where possible, and state the count and fields in the consent copy.
<!-- sources: privacy-dataflow#4 -->

#### 1.20 Stored provider, Spamhaus and IMAP credentials can never be removed — Medium

- **Where:** `SpamWiseCore/Sources/Store/Keychain.swift:25` (also `Keychain.swift:42, 54`, `SpamWise/IMAPSettingsView.swift:38`, `SpamWise/ProviderConsentView.swift:56-57`, `docs/lifecycle.md`)
- **Problem:** `APIKeychain` has only `read()` and `save()`. `SecItemDelete` appears nowhere in the app, extension or core, and the UI has no "Remove key" control. Data-protection items are not normally visible in Keychain Access, so the manual removal that lifecycle.md documents may not be possible.
- **Scenario:** A user stops using OpenAI, or rotates away from a leaked IMAP app password, and has no way to make SpamWise forget it. The secret stays readable by any build signed into the team access group.
- **Fix:** Add `APIKeychain.delete()`, "Remove key" / "Forget connection" controls, and "Remove all SpamWise credentials" in the data-removal flow. Delete the superseded IMAP item, and correct the consent and lifecycle copy.
<!-- sources: privacy-dataflow#6, security/app-logic#3 -->

#### 1.21 Two privacy-policy drafts and data inventories have diverged — Medium

- **Where:** `docs/app-store.md:206` (also `docs/app-store.md:213, 220-221, 236-242`, `docs/privacy.md:74-77`, `docs/privacy-audit.md:9-23`)
- **Problem:** app-store.md carries its own policy draft and inventory. They omit the Spamhaus HTTPS key flow and the Gemini unpaid-terms caveat that privacy.md documents. Conversely, privacy.md omits the IMAP credentials that the app ships with, and the Contacts snapshot and RDAP cache (§1.34). privacy-audit.md's Spamhaus row predates the HTTPS transport.
- **Scenario:** The app-store.md draft is pasted into App Store Connect and contradicts the published privacy.html.
- **Fix:** Keep one policy (privacy.md) and one inventory (privacy-audit.md). Make them complete, covering IMAP, Spamhaus HTTPS, the Contacts snapshot and the domain caches, and link to them from app-store.md.
<!-- sources: comments/repo-docs#8 -->

#### 1.22 Claude refusals and `max_tokens` cut-offs are reported as configuration errors — Low

- **Where:** `.build/053e029e-a477-4600-94f0-b8d53af1b4d7/swiftpm/checkouts/ClaudeForFoundationModels/Sources/ClaudeForFoundationModels/ClaudeExecutor.swift:149` (also `EventTranslator.swift:161`, `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:87-88`)
- **Problem:** The bridge acts only on `pause_turn`. A `refusal` or `max_tokens` stop (thinking shares the 1,024-token cap) arrives as a decoding failure, which ClaudeClassifier maps to `.configuration`. `.refused` behaves the same way, so the real effect is a misleading failure reason, not a new bypass.
- **Scenario:** A campaign that trips Haiku's safety classifier stays in the Inbox, and Activity says "The selected model configuration is unavailable."
- **Fix:** Map Claude decoding failures to `.refused` or `.invalidOutput`, and ask upstream for typed stop-reason errors. Consider sending refusals to Review, and give the token cap headroom for thinking.
<!-- sources: gap/dependency-trust-path#3 -->

#### 1.23 Update installer (planned adoption) never checks code signature, Team ID or bundle ID — Low

- **Where:** `~/Repositories/Libraries/GitHubUpdateChecker/Sources/GitHubUpdateChecker/Installation/AppInstaller.swift:288` (also `AppInstaller.swift:323`, `PrivilegeEscalation.swift:89`, `DMGHandler.swift:25`, `GitHubRelease.swift:99`)
- **Problem:** `verifyInstallation` checks only that the bundle files exist. The installer then removes quarantine, can run a PKG as root, mounts DMGs with `-noverify`, and falls back to `assets.first`. SpamWise links only GitHubReleaseDiscovery today, so none of this ships, but TODO.md:368 plans to adopt the full updater.
- **Scenario:** A compromised release delivers an unsigned app that replaces SpamWise, with Mail Automation and Keychain access, or a PKG that runs as root.
- **Fix:** Before adopting it, check the bundle with `SecStaticCodeCheckValidity` against a pinned requirement (Team `2NFSK2WB24`, identifier `codes.tim.SpamWise`), require a higher version, keep quarantine, drop `-noverify` and the `assets.first` fallback, and disallow PKG installs.
<!-- sources: gap/dependency-trust-path#1 -->

#### 1.24 Committed docs record credential-handling details and personal-mailbox operations — Low

- **Where:** `CLAUDE.md:67` (also `CLAUDE.md:93, 105, 212`, `docs/packaging.md:42`)
- **Problem:** No secret values appear. However, the history records that SubTrack's `MATCH_PASSWORD` unlocks this team's signing, the Keychain service/account names of the provider setup key, and operations on the owner's personal mailboxes. The owner is weighing making the repository public.
- **Scenario:** After the repository goes public, these details help a targeted attack on the owner's signing and credentials.
- **Fix:** Scrub these operational details before any visibility change, and consider rewriting the `codex/phase-one` history.
<!-- sources: comments/repo-docs#13 -->

#### 1.25 Provider-key helper uses the clipboard and an accessibility class that has no effect — Low

- **Where:** `Scripts/store-provider-key.swift:46` (also `:10, :39-42`, `Scripts/evaluate-with-keychain.swift:41-47`)
- **Problem:** The documented workflow is `pbpaste | swift …`, and the clipboard is never cleared. Without `kSecUseDataProtectionKeychain` the item lands in the file-based login keychain, where `kSecAttrAccessible` is ignored, and the update path never sets it. The ACL trusts the Swift toolchain binary.
- **Scenario:** The key stays on the pasteboard and can sync through Universal Clipboard, and the stored item lacks the protection the code implies.
- **Fix:** Read the key from a no-echo TTY prompt, or use `op run --env-file`. Drop the ineffective attribute, or store the item from a signed tool in the data-protection keychain.
<!-- sources: security/eval-scripts#4 -->

#### 1.26 Backup recovery key copied to the general pasteboard without concealed/transient markers — Low

- **Where:** `SpamWise/BackupSettingsView.swift:24` (lines 23-26)
- **Problem:** The only secret that decrypts the backup (rules, corrections, learning, optionally message text) is written as plain `.string`, without `org.nspasteboard.ConcealedType`/`TransientType`, and is never cleared. The key appears only in a SecureField, so copying is the main way to save it.
- **Scenario:** A clipboard-history manager or Universal Clipboard keeps the key indefinitely. Together with the `.spamwisebackup` file, that is enough to decrypt it.
- **Fix:** Declare the concealed and transient types and clear the pasteboard after a timeout, or offer to save the key to Passwords, Keychain or a file instead.
<!-- sources: privacy-dataflow#11, security/app-logic#7, correctness/app-views-settings#12, conventions/app-views-settings#2 -->

#### 1.27 Saved IMAP secret is reused after host, port, username or mechanism changes — Low

- **Where:** `SpamWise/IMAPConnectionModel.swift:130` (also `IMAPConnectionModel.swift:24, 132`, `SpamWise/AppModelIMAP.swift:9`, `IMAPSettingsView.swift:38`)
- **Problem:** The Keychain service is derived only from the persisted account ID. If the credential field is left blank (as the UI suggests), the old secret is sent to an edited endpoint, or used as a bearer token when OAuth is toggled. Action validation is fingerprinted to the endpoint, but the credential is not.
- **Scenario:** A typo produces a lookalike host with a valid certificate, and "Check" sends it the real mailbox password.
- **Fix:** Bind the credential to id, host, port, username and mechanism, or store it as `kSecClassInternetPassword`. Require re-entry whenever any of those change, and delete the old item.
<!-- sources: privacy-dataflow#5, security/app-logic#4 -->

#### 1.28 Exported raw mail, reports and caches use default `umask` permissions — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:356` (also `SpamWiseEval/main.swift:40, 52, 184`, `CachedClassifier.swift:48-49`, `CachedThreatDetector.swift:50-51`)
- **Problem:** `spamwise-eval --export` writes up to 1,000 raw messages, Sent included, under default modes. Reports, which can quote reasons, are also written that way and echoed to stdout. Cache files are chmod-ed only after the atomic rename, and an existing directory is never tightened.
- **Scenario:** An export to `/Users/Shared` or a synced folder is readable by other local accounts.
- **Fix:** Create export, report and cache directories as 0700 and enforce that on existing ones. Write files through 0600 descriptors (or set `umask` 077), and skip echoing the report when `--output` is given.
<!-- sources: security/eval-scripts#2 -->

#### 1.29 Daemon credential read can block on a login-Keychain prompt despite claiming to be non-interactive — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:52` (also `:42, :53`)
- **Problem:** The query targets the legacy login keychain, where `LAContext.interactionNotAllowed` does not suppress ACL prompts. `SecItemCopyMatching` is synchronous, so cancellation cannot interrupt it. Whether a prompt actually appears depends on the item's ACL and was not verified.
- **Scenario:** A polling daemon blocks on an unseen prompt and does not respond to Ctrl-C.
- **Fix:** Add `kSecUseAuthenticationUIFail` (or its current equivalent), map `errSecInteractionNotAllowed` to `authenticationFailed`, or use the data-protection keychain. Correct the doc comment.
<!-- sources: security/mail-integration#7 -->

#### 1.30 AppleScript "exact source" and Message-ID comparisons ignore case — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:130` (also `MailScripts.swift:14, 158, 182`, `AppleMailAdapter.swift:236`)
- **Problem:** AppleScript ignores case in text comparisons by default, so the "Message changed" guard and the `whose message id is` lookup are case-insensitive. The Swift hash check shortly before keeps the practical window small.
- **Scenario:** A source that changed only in case passes the guard.
- **Fix:** Wrap the comparisons in `considering case` (plus diacriticals, punctuation and white space), or compare a hash computed in Swift.
<!-- sources: security/mail-integration#9 -->

#### 1.31 Public-suffix lookup ignores punycode, so IDN suffixes become registrable domains — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/DomainResolver.swift:11` (also `public_suffix_list.dat:1311`, `MIMEParser.swift:42-44`)
- **Problem:** PSL rules are loaded in Unicode while hosts arrive as `xn--` labels, so no IDN rule ever matches. For example, `shop.xn--55qx5d.hk` resolves to the public suffix itself.
- **Scenario:** An explicit domain Allow for `xn--55qx5d.hk` allows every registrant under 公司.hk, and history is merged across unrelated registrants.
- **Fix:** Convert IDN rules to punycode at build time, keeping the exception and wildcard logic, and add `xn--` boundary tests.
<!-- sources: security/core-parsing-signals#11 -->

#### 1.32 Optional OCR decodes untrusted TIFF/GIF/HEIC in the privileged app process — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:14` (also `EmbeddedImages.swift:30-34`, `EmbeddedImageOCR.swift:21`, `Pipeline.swift:50`)
- **Problem:** When enabled (off by default), inline images from unopened mail are decoded by ImageIO and Vision inside the process that holds the Keychain group and Mail Apple Events access. The project built an XPC worker for PDFs but decodes images in-process.
- **Scenario:** A crafted TIFF that exploits an ImageIO bug runs zero-click, with access to the user's API keys and Mail automation.
- **Fix:** Restrict OCR to PNG/JPEG, or decode in a sandboxed XPC service without Keychain, network or Apple Events entitlements. State the risk in the feature's consent text.
<!-- sources: security/core-parsing-signals#13 -->

#### 1.33 Authentication-Results parser matches tokens anywhere in the header — Low

- **Where:** `SpamWiseCore/Sources/Signals/Evidence.swift:91` (also `Evidence.swift:86, 105`)
- **Problem:** The regex runs over the whole header, including comments and property values, so `smtp.mailfrom=dmarc=pass@x` produces a pass. Results are not tied to `header.d`/`header.from`, and every header naming a trusted server would be trusted, not only the topmost. Today all claims are untrusted (§1.18), but they still reach the model as attacker-shaped "pass" evidence.
- **Scenario:** A forged A-R header plus envelope sender `dmarc=pass@x` lists several passes in the evidence. If trusted servers are wired up later, the forgery would be trusted immediately.
- **Fix:** Parse per RFC 8601, recording method, result and relevant property, and trust only the topmost header whose authserv-id matches the account's server. Wire this before using it in gates.
<!-- sources: security/core-parsing-signals#10 -->

#### 1.34 RDAP uses `URLSession.shared`, buffers unbounded responses, and persists undisclosed domain caches — Low

- **Where:** `SpamWiseCore/Sources/Signals/RDAP.swift:18` (also `RDAP.swift:17-21, 96-98`, `SpamWise/AppModel.swift:99-101`, `State.swift:193`, `docs/privacy.md`)
- **Problem:** Unlike the Spamhaus and Rspamd clients, RDAP follows redirects (the app sets no ATS exceptions, so HTTPS is still enforced) and uses the shared on-disk URLCache and cookies. It applies the 2 MB limit only after the full download, under an idle timeout. `rdap-cache.json` (up to 2,048 sender domains) and the full Contacts email snapshot are persisted, and privacy.md lists neither.
- **Scenario:** A hostile bootstrap-listed RDAP server redirects the sender domain to a third party and streams hundreds of megabytes before the check runs. A user who relies on privacy.md does not know their address book and correspondent domains are stored.
- **Fix:** Use an ephemeral session with no cache or cookies, reject redirects, stream with a byte cap and set a resource timeout. Document the Contacts snapshot and domain caches, and clear the snapshot when Contacts permission is lost.
<!-- sources: security/core-parsing-signals#12, conventions/core-parsing-signals#20, privacy-dataflow#12 -->

#### 1.35 Loopback Rspamd sends full raw mail to whatever process holds port 11333 — Low

- **Where:** `SpamWiseCore/Sources/Signals/RspamdLoopbackHTTP.swift:29` (also `RspamdLoopbackHTTP.swift:29-34`, `Pipeline.swift:55-61`)
- **Problem:** The transport authenticates nothing about its peer on an unprivileged port, and it runs before the rule gates. The feature is opt-in and off by default, local-only mode blocks it, and docs/probes/rspamd-runtime.md acknowledges the risk.
- **Scenario:** While rspamd is down, another user or a sandboxed app with `network.server` binds the port, receives every message (including 2FA mail) and returns empty symbols.
- **Fix:** Prefer a Unix socket in a user-owned directory, or verify the listener's owner or signature. At minimum, state the multi-user risk next to the transport picker.
<!-- sources: privacy-dataflow#9, security/core-parsing-signals#9 -->

#### 1.36 Imported body snippets are kept, sent and backed up with content retention off — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:54` (also `CorpusManagement.swift:50-58`, `StateBackup.swift:51`, `PipelineClassification.swift:62-68`)
- **Problem:** With retention off, only `ReviewedLabel.message` is cleared. Each correction example still keeps the sender, subject and the first 160 body characters. These travel with prompts and appear in backups described as excluding content.
- **Scenario:** A "content-free" backup that is shared contains 20 subjects, senders and body openings.
- **Fix:** Without retention, build gists from non-content features, strip subject and gist from content-free backups, or disclose that they are included.
<!-- sources: security/core-pipeline-store#8 -->

#### 1.37 Model-generated reasons become "user correction" examples — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:59` (also `PipelineCorrections.swift:55-60`, `Classifier/Types.swift:259`)
- **Problem:** A correction stores `decision.reason`, which a prompt injection can steer, as the example gist next to the attacker's subject, and replays it in the preferences block. The fixed instructions forbid following text in correction quotations, and the gist is bounded to 160 characters, so the impact is limited.
- **Scenario:** An injected reason such as "bulk senders are always wanted" is quoted in up to 40 later prompts.
- **Fix:** Use a fixed gist derived from the label and evidence instead of model output.
<!-- sources: security/core-pipeline-store#9 -->

#### 1.38 Rule imports apply without preview and can flip Block rules to Allow — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift:106` (also `SpamWise/AppModelRules.swift:44`, `RuleEditorView.swift:61-64`, `ContentRuleEditorView.swift:68-77`)
- **Problem:** An imported file is merged immediately. An audit entry and a status message are written, but there is no preview or confirmation. A newer imported Allow wins over the user's Block rule, and domain Allows for freemail providers are accepted.
- **Scenario:** A "community" list containing `gmail.com → allow` silently whitelists every gmail.com sender.
- **Fix:** Show a confirmation sheet listing added and replaced rules before writing, and warn about or refuse domain Allows for freemail and shared-hosting domains.
<!-- sources: security/app-logic#8 -->

#### 1.39 Backup restore turns on "Retain reviewed text" without asking — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:83`
- **Problem:** Restore sets `retainReviewedContent` to whether any restored label contains text, overriding this Mac's setting, and the restore copy does not mention it.
- **Scenario:** After a user restores a backup from another Mac, new corrections start storing up to 16,000 characters of message text each.
- **Fix:** Keep the current setting and drop restored text when retention is off, or ask during the restore confirmation.
<!-- sources: privacy-dataflow#10 -->

#### 1.40 Backup restore leaves learning state and correction field lengths unvalidated — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:104` (also `StateBackup.swift:77-78`, `Classifier/Types.swift:107-110`)
- **Problem:** Validation covers counts, rules and labels, but not `LearningState`. `CorrectionExample` decoding bypasses the truncating init. Restore pauses filtering and forces dry run, so the effect is delayed until actions are re-enabled.
- **Scenario:** A shared "starter" backup injects fingerprints that send bank statements to Junk, plus 1 MB gists that make every prompt throw `contextExceeded`.
- **Fix:** Validate LearningState bounds, add a custom `init(from:)` that truncates, and cap each section of the restored payload.
<!-- sources: security/core-pipeline-store#10 -->

#### 1.41 Daemon `--model` silently changes the app and extension provider — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:122` (also `main.swift:58`)
- **Problem:** Without a `statePath`, `--model` rewrites the backend in the shared App Group settings. Consent is stored per provider, so an earlier cloud consent becomes active again.
- **Scenario:** An IMAP test with `--model claude-haiku-5-5` makes the extension start sending Apple Mail to Anthropic, even though the user had chosen On-device.
- **Fix:** Apply `--model` as an in-process override, or allow it only with an explicit `statePath`.
<!-- sources: privacy-dataflow#7 -->

#### 1.42 Crafted MIME header raises IndexError and aborts corpus preparation — Low

- **Where:** `Tools/Corpus/prepare.py:74` (also `prepare.py:218, 415`, `audit.py:208`)
- **Problem:** `get_content_disposition()` raises IndexError on `attachment; filename*` (reproduced on CPython 3.14.8). The quarantine handler catches only ValueError, UnicodeError and RecursionError.
- **Scenario:** One spam message in a new archive aborts the whole run and leaves a partial output directory.
- **Fix:** Catch `Exception` per record (or add IndexError, AttributeError, TypeError and MessageError) and quarantine with the error's type name. Extend the MIME test, and apply the same handling to audit.py.
<!-- sources: security/tools#3 -->

#### 1.43 Document worker caps text in Characters but replies in JSON bytes, so the worker exits — Low

- **Where:** `Tools/DocumentWorker/PDFExtraction.swift:17` (also `Protocol.swift:5, 7`, `Worker.swift:83`, `Client.swift:176-178`)
- **Problem:** The 3,000-grapheme cap can exceed the 16,384-byte JSON reply once escaping and multi-scalar graphemes are counted, and the worker then calls `_exit(75)` instead of truncating. This is a harness only; production PDF extraction does not ship.
- **Scenario:** Control-character or combining-mark padding reliably suppresses document text coverage. Each attempt also costs a throttled relaunch.
- **Fix:** Budget by encoded bytes on scalar boundaries, or return raw UTF-8 data. Use the same unit on both sides, and add adversarial fixtures.
<!-- sources: security/tools#1 -->

#### 1.44 Probe timeout orphans the evaluator holding the API key — Low

- **Where:** `Tools/Preferences/run.py:155` (also `Scripts/evaluate-with-keychain.swift:89-98`)
- **Problem:** `subprocess.run(timeout=90)` kills only the Swift launcher. The `spamwise-eval` grandchild, with the key in its environment, keeps running. Spending is still bounded by the ledger.
- **Scenario:** A slow call is recorded as `evaluation_interrupted` but still completes, is billed, and writes results the runner never reports.
- **Fix:** Use `start_new_session=True` with `os.killpg`, or have the launcher `exec` the evaluator directly.
<!-- sources: security/tools#4 -->

#### 1.45 Claude transport is less hardened than the OpenAI/Gemini transport — Info

- **Where:** `.build/7ae09be2-7487-4cc9-900a-1c1b9fb169c9/swiftpm/checkouts/ClaudeForFoundationModels/Sources/ClaudeForFoundationModels/ClaudeExecutor.swift:62` (also `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:40`, `ModelHTTPClient.swift:9`)
- **Problem:** The SDK uses `URLSessionConfiguration.default`, which means shared cookies and cache, same-origin redirects followed and no response cap. It also creates a session per executor that is never invalidated. ModelHTTPClient is ephemeral, refuses redirects and caps responses at 64 KiB.
- **Scenario:** A misbehaving proxy's redirect or huge body is accepted on the Claude path and rejected on the other providers' paths.
- **Fix:** Inject a hardened transport if the SDK allows it; otherwise document the difference in privacy-audit.md.
<!-- sources: privacy-dataflow#16 -->

#### 1.46 Release-notes view would load remote images — Info

- **Where:** `~/Repositories/Libraries/GitHubUpdateChecker/Sources/GitHubUpdateChecker/UI/ReleaseNotesView.swift:45`
- **Problem:** MarkdownUI's default image provider fetches any image URL in the release body. SpamWise does not render release notes today.
- **Scenario:** If the UI is adopted, a tracking image in the notes reveals each user's IP address and timing to a third party.
- **Fix:** If adopted, use an ImageProvider that blocks network loads, or render with AttributedString Markdown.
<!-- sources: gap/dependency-trust-path#7 -->

#### 1.47 Temporary signing-keychain password on argv; signing borrows SubTrack's `MATCH_PASSWORD` — Info

- **Where:** `Scripts/export-store-match.py:103` (also `:105, :302-313`, `docs/app-store.md:83-85`)
- **Problem:** `create-keychain`, `unlock-keychain` and `set-key-partition-list` receive the password as an argument. Only same-user or root processes can read it, and they can already read the decrypted mode-600 p12 files and `MATCH_PASSWORD`, so the extra exposure is marginal. Signing also depends on another project's fastlane `.env`, and the hand-rolled helper duplicates fastlane match/gym.
- **Scenario:** Moving or rotating SubTrack's `.env` silently breaks SpamWise store packaging.
- **Fix:** Pass passwords on stdin where `security` supports it, shorten the lock timeout, and consider fastlane lanes with SpamWise's own secret configuration, as SubTrack does.
<!-- sources: tooling#10, distribution/packaging#17, security/eval-scripts#3 -->

#### 1.48 Claude key verification runs in local-only mode — Info

- **Where:** `SpamWise/AppModelCredentials.swift:13`
- **Problem:** "Verify and save key" calls ClaudeClassifier directly without checking `localOnly`. The request is synthetic, user-initiated and disclosed beside the button, so no mail data is exposed.
- **Scenario:** A user in local mode pastes a key for later use, and pressing Verify contacts Anthropic anyway.
- **Fix:** Disable Verify while `localOnly` is on, or offer save-without-verify.
<!-- sources: privacy-dataflow#8 -->

#### 1.49 `spamwise://check-inbox` triggers sweeps without the 60-second throttle — Info

- **Where:** `SpamWise/AppModelNavigation.swift:8` (also `SpamWise/Info.plist`, `Resources/SpamWiseRule.applescript`)
- **Problem:** Any caller can start an automatic sweep, gated only by `canScanAutomatically` and the busy guard. This is the Mail-rule route's intended trigger, so removing the host would break it. Already-seen mail is not reclassified, and browsers prompt before opening custom schemes.
- **Scenario:** A looping `open spamwise://check-inbox` drives continuous Apple Events history imports and sweeps.
- **Fix:** Coalesce bursts: treat the URL as a hint that schedules the next sweep, without dropping rule-triggered scans. Optionally skip `maintainHistory()` for URL-triggered sweeps.
<!-- sources: design/onboarding-consistency#28, privacy-dataflow#13, security/app-logic#6 -->

#### 1.50 Key-presence check reads the secret on the main thread — Info

- **Where:** `SpamWise/SpamhausSettingsView.swift:64` (also `Keychain.swift:43`)
- **Problem:** `onAppear` calls `read()` with `kSecReturnData` just to show "saved" or "not saved". The item is in the app's own access group, so no prompt appears.
- **Scenario:** The plaintext key is loaded into memory on every appearance for no reason.
- **Fix:** Add an attributes-only `APIKeychain.exists()`.
<!-- sources: security/app-logic#10 -->

#### 1.51 Decoded `TokenUsage` skips clamping, so `estimatedCost` can overflow — Info

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:33` (also `Types.swift:45-46`)
- **Problem:** Synthesized decoding bypasses the non-negative and `cached <= input` clamps, and the cost calculation subtracts `Int`s. Backups do not carry DecisionRecords, so the only realistic path is a state file the user supplies to `spamwise-eval`.
- **Scenario:** `{"input": Int.min, "cached": 1}` traps the evaluator.
- **Fix:** Add an `init(from:)` that validates through the clamping init, and compute in Double.
<!-- sources: security/core-classifier-learning#6 -->

#### 1.52 Injection-steerable model verdicts are admitted as Bayes training data — Info

- **Where:** `SpamWiseCore/Sources/Learning/LearningState.swift:193` (also `LearningState.swift:201, 220-244`, `StatisticalLearning.swift:49-50`)
- **Problem:** Verdicts at confidence 99-100 from unknown senders become samples with weight 0.1, capped at reviewed/4. A contradiction check (lines 220-230) rejects strongly conflicting predictions, which limits poisoning.
- **Scenario:** Repeated spam padded with the user's vocabulary nudges those tokens toward Junk.
- **Fix:** Train only on predictions backed by an independent signal, or keep Bayes training on explicit corrections only.
<!-- sources: security/core-classifier-learning#5 -->

#### 1.53 Daemon environment secrets are inherited by `dig`/`rspamc` children — Info

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:47` (also `Signals/EvidenceProcess.swift:32-37`, `ExternalEvidence.swift:153`, `RspamdLookup.swift:72-78`)
- **Problem:** `EvidenceProcess` never sets `process.environment`. A same-user process could already read the daemon's own environment, so the added exposure is small.
- **Scenario:** A wrapper `rspamc` script logs its environment, including `SPAMWISE_IMAP_PASSWORD`.
- **Fix:** Pass children a minimal explicit environment, and `unsetenv` secrets once they have been read.
<!-- sources: security/mail-integration#8 -->

#### 1.54 Hidden HTML text and control/bidi characters reach the classifier — Info

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:157` (also `MIMEParser.swift:172-181`)
- **Problem:** `display:none`, `hidden` and zero-size text, plus numeric-entity controls and bidi characters, pass through unmarked. Hidden text is the usual carrier for prompt injection and Bayes poisoning.
- **Scenario:** A hidden `<div>` tells the model to label the message inbox at confidence 100.
- **Fix:** Drop hidden elements during conversion, or mark them for the model. Strip C0 controls (except newline and tab) and bidi overrides.
<!-- sources: security/core-parsing-signals#14 -->

#### 1.55 "Pinned" model snapshot is verified only by directory name — Info

- **Where:** `Tools/Corpus/screen.py:145` (also `screen.py:172-174`)
- **Problem:** Only the snapshot directory name is compared with the revision. The weights hash is computed after loading and only reported, and tokenizer and config files are never hashed. Remote code is disabled, and the candidates were rejected anyway.
- **Scenario:** A substituted snapshot is scored and reported as the pinned revision.
- **Fix:** Store the expected weights, tokenizer and config hashes per candidate and verify them before `from_pretrained`.
<!-- sources: security/tools#5 -->

#### 1.56 Diagnostic-symbol guard silently passes if `nm` or `rg` fails — Info

- **Where:** `Tools/DocumentWorker/check.sh:88`
- **Problem:** Commands inside an `if` condition are exempt from `set -e`, so a pipeline failure (for example `rg` missing on stock macOS) takes the "not found" branch. The production worker is built from a hard-coded file list without the probe define, which limits the risk.
- **Scenario:** On a machine without ripgrep the check reports success without inspecting the binary.
- **Fix:** Capture `nm` output and fail if it errors, then test with `grep -Eq`, or check `command -v rg` up front.
<!-- sources: security/tools#2 -->
## 2. Correctness

The core is carefully bounded, and its main safety invariants hold:

- No code path exposes delete or Trash.
- Decisions are persisted before the action claim, and the claim before the Mail action.
- Provider consent is checked before any request leaves the device.
- Failures never move good mail to Junk.

Parsing and network evidence have resource limits. A failed lookup never becomes spam evidence. The evaluation statistics (Clopper-Pearson bounds, rule of three, confusion counts) are correct. The correctness problems sit around these invariants, and the most serious ones are silent: filtering stops, or mail is skipped, without anyone being told. They seldom put mail in the wrong folder.

**Spending ceiling.** The defect raised most often (15 reviewers, independently) is that production classification draws on the developer's $150 lifetime evaluation ledger (§2.9). Each Claude Haiku call permanently reserves $0.10, and each call to any other model reserves $1.00. The real cost of a Haiku call is about $0.00014. Nothing in the app can raise or reset the ledger, so cloud filtering stops for good after about 1,500 Haiku messages, or 150 on any other model.

**Whole-message fail-open.** The second pattern is that "fail open" is applied to the whole message, not to the part that failed. Each of these makes the whole message "unclassified":

- a display name containing "@" (§2.5)
- a single undecodable byte (§2.6)
- a body over 16,000 characters while any body content rule is enabled (§2.7)

A safety property has become a reliable way to bypass the filter, and the spoofed-name case is the most common phishing pattern.

**Which messages get processed, and when.** The rules deciding which messages to process are derived from a bounded 5,000-record display log and from revision equality. As a result:

- Large Inboxes are re-classified, and paid for, forever (§2.2).
- Messages that hit a transient failure are never revisited (§2.19).
- Parse failures add a new Activity row on every sweep (§2.21).
- Turning off dry run re-classifies every previewed message (§2.20).
- On IMAP, a message the user rescued from Junk is junked again (§2.52).
- Sweeps never prioritize newly arrived mail (§2.1).
- One oversized Sent message stalls history import permanently (§2.4).

**Trust signals.** The allow gates trust too much, and authentication too little. One receipt-like message allow-lists an entire freemail domain (§2.8). Domain suggestions offer one-click rules for gmail.com (§2.3). Authentication results are never trusted, so DMARC failures carry no weight (§2.62).

**Shared state.** All state lives in one JSON blob. Every access takes a non-blocking `flock` that is never retried, and the Mail extension opens a new Store for each callback (§2.66, §2.70). A single `busy` flag is shared between background sweeps and user actions (§2.14). Together these turn ordinary concurrency into lost outcomes, misleading records and controls that stay disabled. Error types are widely reused for unrelated conditions, so users see explanations that don't match the cause (§2.17, §2.25, §2.44).

**Tests.** The package suite is warning-free and passes, but it is weaker than the ledger suggests:

- Key invariants are tested only weakly: persist-before-act (§2.147) and rule precedence (§2.153).
- The UnitTests target is never run by any script (§2.11), and it is hosted by the production app (§2.12).
- The app-level orchestration has no unit tests (§2.73).
- The brief's fixture acceptance criterion is met only by injected mock verdicts (§2.74).

Several defects in this section would have been caught by a two-sweep test over a fixture mailbox.

| Check | Result |
|---|---|
| Package tests (`swift test -Xswiftc -warnings-as-errors`) | 90 functions / 125 cases: 89 passed, 1 skipped (opt-in live Haiku test), 0 failed; 0 warnings |
| SpamWise app build (unsigned, warnings as errors) | Succeeded, 0 warnings or errors |
| SpamWiseDirect build (unsigned, warnings as errors) | Succeeded, 0 warnings or errors |
| UnitTests and UITests (`build-for-testing`) | Compile with 0 warnings; not run (running needs the app test host) |
| Python suites (Tools/Site, Tools/Corpus, Tools/Preferences, Scripts) | 2/2, 8/8, 2/2, 3/3 passed; `ruff check` and `ruff format --check` clean |
| Fresh clone (`xcodebuild -list`) | Fails package resolution: the local `GitHubUpdateChecker` path is not accessible |
| Periphery 1.0.0.beta.8 (in-repo results) | 54 results: 11 unused, 43 redundant `public` |

UI tests, signing, archiving, notarization and the runtime probe scripts were not run for this review.

### Findings

| # | Severity | Location | Finding |
|---|---|---|---|
| 2.10 | Medium | `MailExtension/MessageActionHandler.swift:21` | MailKit route classifies with no account; history gates never apply |
| 2.11 | Medium | `Scripts/check.sh:9` | No command runs the UnitTests target |
| 2.12 | Medium | `SpamWise.xcodeproj/project.pbxproj:771` | UnitTests hosted by the production app |
| 2.13 | Medium | `SpamWise/AppModel.swift:162` | Whole shared state decoded and republished every 3 seconds |
| 2.14 | Medium | `SpamWise/AppModel.swift:219` | Background scans hold the global `busy` flag |
| 2.15 | Medium | `SpamWise/AppModel.swift:292` | IMAP history refresh discards stored correspondence |
| 2.16 | Medium | `SpamWise/AppModel.swift:294` | History maintenance reads 200 full messages every minute |
| 2.17 | Medium | `SpamWise/AppModelFolders.swift:17` | Folder plans cannot be removed; errors say "Mail service unavailable" |
| 2.18 | Medium | `SpamWise/AppModelFolders.swift:124` | One uncorrectable message stalls a training folder forever |
| 2.19 | Medium | `SpamWise/AppModelScanning.swift:113` | Transient failures treated as seen and never revisited |
| 2.22 | Medium | `SpamWise/AppModelScanning.swift:121` | Manual dry runs classify 20 per account and repeat on every click |
| 2.23 | Medium | `SpamWise/ContentRuleEditorView.swift:125` | Content-rule sheet errors are never shown |
| 2.24 | Medium | `SpamWise/ContentView.swift:129` | Eight sibling sheets collide |
| 2.25 | Medium | `SpamWise/CorpusView.swift:82` | Corpus and undo actions throw misleading error types |
| 2.26 | Medium | `SpamWise/EvidenceSettingsView.swift:71` | Some Evidence/Notification edits are lost unless a button is pressed |
| 2.27 | Medium | `SpamWise/EvidenceSettingsView.swift:79` | Settings drafts can be seeded from defaults and saved over real config |
| 2.28 | Medium | `SpamWise/GeneralSettingsView.swift:55` | Reopened setup sheet has no Cancel; Finish forces dry run on |
| 2.30 | Medium | `SpamWise/LearningSettingsView.swift:47` | Label export re-encodes on every render; can export an empty file |
| 2.31 | Medium | `SpamWise/MailReviewView.swift:32` | MIME parsing, statistics and file I/O on the main actor |
| 2.32 | Medium | `SpamWise/MailReviewView.swift:50` | Review Junk sheet shows stale messages and pages incorrectly |
| 2.33 | Medium | `SpamWise/MailReviewView.swift:88` | Corrections sheet cannot be dismissed for up to ~25 minutes |
| 2.34 | Medium | `SpamWise/SpamhausSettingsView.swift:62` | Spamhaus key status reports every Keychain error as "not saved" |
| 2.35 | Medium | `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:90` | Anthropic 5xx errors are non-retryable |
| 2.36 | Medium | `SpamWiseCore/Sources/Classifier/Types.swift:314` | Quote stripping lets a sender hide the body from the model |
| 2.37 | Medium | `SpamWiseCore/Sources/Evaluation/CachedClassifier.swift:42` | Eval counts budget/lock refusals as provider calls, exits 0 |
| 2.38 | Medium | `SpamWiseCore/Sources/Evaluation/Metrics.swift:119` | Calibration buckets too coarse to derive thresholds |
| 2.39 | Medium | `SpamWiseCore/Sources/Evaluation/ReviewedCorpus.swift:57` | Exported reviewed labels rejected as duplicates |
| 2.40 | Medium | `SpamWiseCore/Sources/Learning/LearningState.swift:171` | Later Junk correction never overrides a Good campaign fingerprint |
| 2.41 | Medium | `SpamWiseCore/Sources/Learning/LearningState.swift:200` | Prediction and correction sample identities differ with OCR/attachments |
| 2.42 | Medium | `SpamWiseCore/Sources/Learning/LearningState.swift:325` | Learning keeps only the alphabetically first 128 tokens |
| 2.43 | Medium | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:74` | AppleScript has no overall deadline and cannot be cancelled |
| 2.44 | Medium | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:82` | Overloaded AppleScript error numbers give wrong explanations |
| 2.45 | Medium | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:90` | Cancellation after a move records Failed |
| 2.46 | Medium | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:241` | Moves act on the message wherever it now is |
| 2.47 | Medium | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:253` | Each move holds the pipeline for 30 seconds |
| 2.48 | Medium | `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:148` | Daemon probe/model flags rewrite the app's route and model |
| 2.49 | Medium | `SpamWiseCore/Sources/MailIntegration/MailFolderScripts.swift:78` | Folder start date wrong under non-Gregorian calendars |
| 2.50 | Medium | `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:203` | Moves of mail without a Message-ID recorded as failed |
| 2.51 | Medium | `SpamWiseCore/Sources/MessageModel/DomainResolver.swift:11` | PSL ignores punycode; IDN suffixes become registrable |
| 2.52 | Medium | `SpamWiseCore/Sources/MessageModel/Identity.swift:18` | IMAP keys include UID; rescued mail is re-junked |
| 2.53 | Medium | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:62` | Alternative interleaving splits phrases |
| 2.54 | Medium | `SpamWiseCore/Sources/Signals/ContentRules.swift:104` | Content rules match raw, undecoded headers and filenames |
| 2.55 | Medium | `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:178` | URL/domain/DBL caps keep alphabetically first entries |
| 2.56 | Medium | `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:47` | Imported samples train on header-stripped evidence |
| 2.57 | Medium | `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:61` | Inconsistent 500-label cap: silent eviction vs hard failure |
| 2.58 | Medium | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:304` | Superseded claim never released |
| 2.59 | Medium | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:306` | IMAP Review flag always dispatched and always fails |
| 2.60 | Medium | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:321` | Post-move save failure adds a bogus unclassified record |
| 2.61 | Medium | `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:78` | Optional training write failure discards a paid verdict |
| 2.62 | Medium | `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:215` | Authentication results are never trusted |
| 2.63 | Medium | `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:9` | Review/Good corrections leave mail in the wrong state |
| 2.64 | Medium | `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:50` | Corrections overridden by other-scope rules |
| 2.65 | Medium | `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:102` | `correct()` commits the rule, then can throw before dispatch |
| 2.66 | Medium | `SpamWiseCore/Sources/SpamWiseCore/State.swift:191` | State grows without bound in one blob |
| 2.67 | Medium | `SpamWiseCore/Sources/SpamWiseCore/State.swift:270` | Every settings edit bumps revision, drops retries and undo |
| 2.68 | Medium | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:96` | Daemon poll mode exits on first transient error |
| 2.69 | Medium | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:98` | Daemon dedupe treats dry-run/paused/unclassified as done |
| 2.70 | Medium | `SpamWiseCore/Sources/Store/Store.swift:101` | Non-blocking flock with no retry loses work |
| 2.71 | Medium | `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:176` | Scenario tests bundle unrelated behaviors |
| 2.72 | Medium | `Tools/DocumentWorker/PDFExtraction.swift:17` | PDF worker caps characters, not bytes |
| 2.73 | Medium | `UnitTests/UnitTests.swift:1` | App-target orchestration has no unit tests |
| 2.74 | Medium | `eval/mock-responses.json:1` | Fixture acceptance met only by mock verdicts |
| 2.75 | Low | `.build/…/ClaudeForFoundationModels/RequestBuilder.swift:134` | Always-on prompt caching cost under-recorded |
| 2.76 | Low | `…/GitHubUpdateChecker/…/SemanticVersion.swift:118` | SemanticVersion ordering contradicts `==` |
| 2.77 | Low | `Scripts/evaluate-with-keychain.swift:97` | Timeouts orphan the paid evaluator |
| 2.78 | Low | `Scripts/store-probe.swift:9` | store-probe reports argument errors as invalid path |
| 2.79 | Low | `SpamWise/ActivityStatisticsView.swift:68` | Exported daily counts are an unlabeled flat array |
| 2.80 | Low | `SpamWise/AppModelMailReview.swift:64` | Preview/Open/Export use Apple Mail adapter for IMAP records |
| 2.81 | Low | `SpamWise/ContentRuleEditorView.swift:36` | Deleted content rule stays selected |
| 2.82 | Low | `SpamWise/ContentView.swift:37` | Time column has no date |
| 2.83 | Low | `SpamWise/ContentView.swift:77` | Filters show raw account IDs and path tokens |
| 2.84 | Low | `SpamWise/ContentView.swift:168` | Monthly cost rounds to $0.00 |
| 2.85 | Low | `SpamWise/CorpusView.swift:32` | Corpus can contain duplicate label ids |
| 2.86 | Low | `SpamWise/DecisionDetailView.swift:61` | Undo dialog on every row with misleading counts |
| 2.87 | Low | `SpamWise/DecisionDetailView.swift:193` | Uncalibrated confidence shown as a percentage |
| 2.88 | Low | `SpamWise/IMAPConnectionModel.swift:21` | IMAP load failure mints a new account ID |
| 2.89 | Low | `SpamWise/KeyEntryView.swift:9` | Stored API key status never shown |
| 2.90 | Low | `SpamWise/LocalNotifications.swift:5` | Foreground notifications suppressed but claimed |
| 2.91 | Low | `SpamWise/LocalNotifications.swift:40` | Post-claim settings re-check drops batches |
| 2.92 | Low | `SpamWise/MailMenuView.swift:9` | Status text claims filtering that is not running |
| 2.94 | Low | `SpamWise/NotificationSettingsView.swift:25` | Quiet-hours labels ignore locale |
| 2.95 | Low | `SpamWise/PolicyView.swift:5` | Policy length limit defined three times |
| 2.96 | Low | `SpamWise/PolicyView.swift:45` | Unchanged Save turns the default policy custom |
| 2.97 | Low | `SpamWise/SpamhausSettingsView.swift:62` | UI-testing mode uses the production Keychain |
| 2.98 | Low | `SpamWiseCore/Sources/Classifier/AppleClassifier.swift:57` | Apple path rejects long reasons |
| 2.99 | Low | `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:49` | New Claude executor and URLSession per message |
| 2.100 | Low | `SpamWiseCore/Sources/Classifier/ModelHTTPClient.swift:52` | HTTP 400 always reported as configuration |
| 2.101 | Low | `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:31` | Sonnet 5.5 cache-read price wrong |
| 2.102 | Low | `SpamWiseCore/Sources/Classifier/Types.swift:239` | Instructions don't explain newer evidence |
| 2.103 | Low | `SpamWiseCore/Sources/Classifier/Types.swift:299` | Attachment and OCR text truncated out of the prompt |
| 2.104 | Low | `SpamWiseCore/Sources/Classifier/Types.swift:314` | Reply attribution recognized only in English |
| 2.105 | Low | `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:173` | Manifest accepts missing labels, rejects fractional seconds |
| 2.106 | Low | `SpamWiseCore/Sources/Evaluation/ThreatMetrics.swift:90` | Threat-report errors print comparison diagnostics |
| 2.107 | Low | `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:71` | Learning models retrained per message |
| 2.108 | Low | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:22` | ScriptValue decoding lenient and truncates Int64 |
| 2.109 | Low | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:360` | Export combines `.atomic` with `.withoutOverwriting` |
| 2.110 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:92` | IMAP cursor saved before the page is processed |
| 2.111 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:337` | IMAP requires exact RFC822.SIZE match |
| 2.112 | Low | `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:86` | OCR is all-or-nothing |
| 2.113 | Low | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:147` | Mixed encoded-word headers decode to mojibake |
| 2.114 | Low | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:167` | HTML-to-text splits words and decodes few entities |
| 2.115 | Low | `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:55` | Deadline helper starts work after cancellation |
| 2.116 | Low | `SpamWiseCore/Sources/Signals/Evidence.swift:123` | Contacts enumeration blocks a cooperative thread |
| 2.117 | Low | `SpamWiseCore/Sources/Signals/RDAP.swift:9` | RDAP size "limit" applied after full download |
| 2.118 | Low | `SpamWiseCore/Sources/Signals/RDAP.swift:61` | RDAP duplicate fetches; cache evicts by name |
| 2.119 | Low | `SpamWiseCore/Sources/Signals/RspamdLookup.swift:60` | Rspamd keeps alphabetical symbols, drops score |
| 2.120 | Low | `SpamWiseCore/Sources/Signals/RspamdLoopbackHTTP.swift:25` | Loopback Rspamd HTTP bounds have no automated test |
| 2.121 | Low | `SpamWiseCore/Sources/SpamWiseCore/AutomationRequest.swift:52` | Automation claims never pruned; fail at 10,000 |
| 2.122 | Low | `SpamWiseCore/Sources/SpamWiseCore/CompletionOnce.swift:6` | CompletionOnce `@unchecked Sendable`; watchdog never cancelled |
| 2.123 | Low | `SpamWiseCore/Sources/SpamWiseCore/NotificationPlanning.swift:49` | Notifications never fire in dry run, with no indication |
| 2.124 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:72` | Every envelope failure labelled "parsing failed" |
| 2.125 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:116` | Paid verdicts discarded after the deadline |
| 2.126 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:192` | `RetryJob.dryRun` is always false |
| 2.127 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:244` | Retries drop auxiliary findings |
| 2.128 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:324` | Returned read status diverges from persisted state |
| 2.129 | Low | `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:77` | Previews mutate learning and rule statistics |
| 2.130 | Low | `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:159` | Independent enrichments run sequentially |
| 2.131 | Low | `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:177` | Spamhaus lookup not injectable for tests |
| 2.132 | Low | `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:59` | Correction gist is boilerplate |
| 2.133 | Low | `SpamWiseCore/Sources/SpamWiseCore/State.swift:163` | `schemaVersion` is never read |
| 2.134 | Low | `SpamWiseCore/Sources/SpamWiseCore/State.swift:215` | Ledger keys depend on the current calendar |
| 2.135 | Low | `SpamWiseCore/Sources/SpamWiseCore/TrainingFolders.swift:49` | Training observation cap blocks completion |
| 2.136 | Low | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:42` | Daemon discards sanitized error category |
| 2.137 | Low | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:62` | Daemon overrides config `allowsActions` |
| 2.138 | Low | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:88` | Domain-age setting ignored outside the app |
| 2.139 | Low | `SpamWiseCore/Sources/SpamWiseEval/Options.swift:66` | CLI guard and report logic untested |
| 2.140 | Low | `SpamWiseCore/Sources/SpamWiseEval/RunReport.swift:60` | Price arguments validated after paid calls |
| 2.142 | Low | `SpamWiseCore/Sources/SpamWiseEval/main.swift:149` | `--state` runs self-train on the test corpus |
| 2.143 | Low | `SpamWiseCore/Sources/SpamWiseEval/main.swift:234` | Symlinked files reported as over 2 MB |
| 2.144 | Low | `SpamWiseCore/Sources/Store/Store.swift:103` | Store blocks the cooperative pool; container per operation |
| 2.145 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionFixtures.swift:32` | Temporary test stores never removed |
| 2.146 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:319` | Retry test accepts losing an undispatched job |
| 2.147 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:389` | Persist-before-act not effectively tested |
| 2.148 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift:232` | `#expect` inside detached fixture closures |
| 2.149 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/MailIntegrationTests.swift:30` | Fake runner crashes the test process |
| 2.150 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/ParsingTests.swift:88` | Force unwraps and `any Error` expectations |
| 2.151 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:6` | Migration test has no frozen legacy fixture |
| 2.152 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:190` | Budget concurrency test assertions too loose |
| 2.153 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/SignalsTests.swift:18` | Precedence and consent tests skip key cases |
| 2.154 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/SignalsTests.swift:87` | Alias-exclusion auth assertion is vacuous |
| 2.155 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/ThreatAssessmentTests.swift:97` | Wall-clock waits and timing assertions |
| 2.156 | Low | `Tools/Corpus/audit.py:31` | `splitlines()` crashes on Unicode line separators |
| 2.157 | Low | `Tools/Corpus/prepare.py:135` | bsdtar kill timer counts consumer time |
| 2.158 | Low | `Tools/Corpus/prepare.py:415` | Corpus preparation discards its failure code |
| 2.159 | Low | `Tools/Corpus/spaphish.py:79` | Cross-split counts computed before splitting |
| 2.160 | Low | `Tools/Corpus/test_prepare.py:79` | Python tests bundle unrelated behaviors |
| 2.161 | Low | `Tools/DocumentWorker/Client.swift:99` | Post-cancel reconnect can reach the busy worker |
| 2.162 | Low | `Tools/DocumentWorker/PDFExtraction.swift:14` | One textless page makes the PDF unreadable |
| 2.163 | Low | `Tools/DocumentWorker/ProbeHost.swift:92` | Pure latch/extraction logic tested only in signed harness |
| 2.164 | Low | `Tools/DocumentWorker/check.sh:88` | Symbol check passes silently without ripgrep |
| 2.165 | Low | `Tools/Preferences/results-2026-10-16.json:6` | Committed artifacts don't match committed tools |
| 2.166 | Low | `Tools/Site/build.py:58` | Every table labelled "Compatibility table"; duplicate anchors |
| 2.167 | Low | `UITests/UITests.swift:74` | UI assertions read state without waiting |
| 2.168 | Low | `eval/mock-responses.json:2` | Mock keys are fragile raw-byte hashes |
| 2.169 | Info | `SpamWise/ActivityStatisticsView.swift:68` | Export buttons do nothing on encode failure |
| 2.170 | Info | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:199` | Latent cursor reentrancy in `nextPage` |
| 2.171 | Info | `SpamWiseCore/Sources/SpamWiseEval/Options.swift:66` | Held-out evaluation always uses the default policy |

#### 2.10 The MailKit route classifies with no account, so history gates never apply and paid dry runs are wasted — Medium

- **Where:** `MailExtension/MessageActionHandler.swift:21` (`MailExtension/MessageActionHandler.swift:30`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:206`, `SpamWise/AppModel.swift:201`)
- **Problem:** Extension callbacks always use `MessageIdentity(accountID: nil)`, so the history lookup lands on the empty key and finds nothing. The extension classifies whenever the route is neither `.mailRule` nor `.imap`. Nothing ever sets `.mailKit`, so in practice this happens only during the `.unverified` window after onboarding, when the extension is the only classifier. Its records never match the account-scoped keys that later sweeps produce.
- **Scenario:** A user has imported Sent history but not yet run the probe. A colleague they have replied to many times sends a message, and the extension makes a paid, model-path dry-run decision, possibly Review. After the route is validated, the same messages are classified and paid for again.
- **Fix:** Have the extension record only heartbeat and body-availability timestamps unless `.mailKit` is explicitly selected, or have it evaluate history across all accounts' indexes. Label any MailKit dry-run rows as having no history available.
<!-- sources: correctness/mail-integration#14, gap/brief-conformance#3 -->

#### 2.11 No project command runs the UnitTests target — Medium

- **Where:** `Scripts/check.sh:9` (`Scripts/ui-check.sh:7`, `SpamWise.xcodeproj/xcshareddata/xcschemes/SpamWiseDirect.xcscheme`, `UnitTests/DirectUpdateConfigurationTests.swift:5`)
- **Problem:**
  - `DirectUpdateConfigurationTests` is the only test of the direct-update owner/repository validation and the store-receipt check.
  - `check.sh` only builds the app.
  - `ui-check.sh` passes `-only-testing:UITests`.
  - The SpamWiseDirect scheme has no test action.
  - CI only builds the site.

  The tests compile but never run, and nothing exercises the direct product.
- **Scenario:** `DirectUpdateConfiguration` starts accepting `a%2Fb` or `../owner`, or loses the `_MASReceipt` check, and every documented check stays green.
- **Fix:** Add an `xcodebuild … -only-testing:UnitTests test` step to `check.sh`, preferably hostless (see §2.12), or share a SpamWise scheme whose test plan includes UnitTests. Give the direct variant a test action.
<!-- sources: tooling#2, config/swift-xcode#20, correctness/tests#7, comments/tests#10 -->

#### 2.12 UnitTests run inside the production app, which touches the shared store, Mail and notifications — Medium

- **Where:** `SpamWise.xcodeproj/project.pbxproj:771` (`SpamWise.xcodeproj/project.pbxproj:790`, `SpamWise/AppModel.swift:63`, `SpamWise/AppModel.swift:83`, `SpamWise/AppModel.swift:91`)
- **Problem:** `TEST_HOST` is SpamWise.app, and AppModel isolates itself only when launched with `--ui-testing`. It does not check `XCTestConfigurationFilePath`. A hosted unit-test run therefore:
  - opens the App Group store;
  - uses `SystemAppleEventRunner`;
  - configures notifications;
  - starts the monitor loop.
- **Scenario:** A developer whose onboarding is complete and whose dry run is off presses ⌘U. Within seconds the test host can start a live Inbox sweep and move real mail, or raise Automation prompts during an unattended run.
- **Fix:** Make UnitTests a hostless logic bundle by moving `DirectUpdateConfiguration` into a testable target. Alternatively, have AppModel treat `XCTestConfigurationFilePath` the same as `--ui-testing`.
<!-- sources: correctness/tests#3 -->

#### 2.13 The monitor decodes and republishes the whole shared state every 3 seconds — Medium

- **Where:** `SpamWise/AppModel.swift:162` (`SpamWise/AppModel.swift:131`, `SpamWise/AppModel.swift:159`, `SpamWise/AppModelScanning.swift:126`, `SpamWise/AppModelScanning.swift:136`)
- **Problem:** `refresh()` loads and decodes AppState and mail health, then assigns `state` unconditionally. That invalidates every view that observes it, including the 5,000-row Activity table, whether or not anything changed. `classify()` reloads state twice more for every message. Each load also takes the cross-process lock (§2.70).
- **Scenario:** With retained content and a full log, state is several megabytes of JSON. The app sits idle in the menu bar and still parses several megabytes per second indefinitely, which drains battery, causes hitches in Activity and widens lock contention with the extension.
- **Fix:**
  - Refresh only when something changed, using a cheap revision or modification counter.
  - Assign `state` only when the new value differs.
  - Move large, rarely used fields into separate keys.
  - Use the record the pipeline returns instead of reloading state for each message.
<!-- sources: correctness/app-logic#12, conventions/app-logic#21 -->

#### 2.14 Background scans hold the single `busy` flag, disabling and silently dropping user actions — Medium

- **Where:** `SpamWise/AppModel.swift:219` (`SpamWise/AppModelScanning.swift:11`, `SpamWise/AppModelScanning.swift:77`, `SpamWise/MailMenuView.swift:24`, `SpamWise/DecisionDetailView.swift:156`, `SpamWise/ContentRuleEditorView.swift:50`, `SpamWise/AppModelNavigation.swift:8`, `SpamWise/ContentView.swift:159`)
- **Problem:**
  - Automatic sweeps go through `run()`, which sets the same `busy` flag that every interactive operation uses and silently returns when the flag is already set.
  - A sweep can take minutes: history import, 20 messages per account at up to 15 s each, and a 30 s settle after each move.
  - `lastScan` is set when a scan starts, so the next sweep begins as soon as the previous one finishes.
  - The single Cancel button also aborts background work.
- **Scenario:**
  - A user spots a misfiled message and opens the menu bar, but Mark as Good is greyed out for most of the session.
  - A click on "Block domain" or "Restore and pause filtering" that lands during a scan does nothing and shows nothing.
  - The Content rules sheet's Done button stays disabled until the scan ends.
- **Fix:**
  - Run automatic scanning in its own task with its own progress state. Pipeline and the adapter are actors, so user work can safely interleave with a sweep.
  - Queue or report refused operations instead of dropping them.
  - Never disable a sheet's Done or Cancel because of `busy`.
  - Measure the scan interval from completion, not from start.
<!-- sources: concurrency#1, correctness/app-logic#8, correctness/app-views-settings#5 -->

#### 2.15 IMAP history refresh replaces stored correspondence with the latest 100 Sent messages — Medium

- **Where:** `SpamWise/AppModel.swift:292` (`SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:107`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:313`)
- **Problem:** `IMAPAdapter.importHistory` builds a new `HistoryIndex` from only the latest 100 Sent messages, and on every automatic sweep the caller assigns it over `state.histories[account]`. The Apple Mail path merges instead. The reply-counting logic is duplicated across the two adapters, and the copies have diverged.
- **Scenario:** An IMAP user replied to a sender 150 messages ago. On the next sweep that sender loses the prior-correspondence gate, and their mail goes to the model.
- **Fix:** Have adapters return envelopes only, and move ingestion into a core `HistoryIndex.ingest(sent:inbox:eligible:)` that always merges into the previous index. Use it from both transports.
<!-- sources: architecture#10 -->

#### 2.16 Automatic history maintenance reads 200 full messages every minute — Medium

- **Where:** `SpamWise/AppModel.swift:294` (`SpamWise/AppModelScanning.swift:79`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:312`)
- **Problem:** Every 60-second sweep begins by pulling 100 Sent and 100 Inbox full sources over Apple Events. It cycles through the mailboxes forever, even when nothing has changed, and adds each identity to the unbounded `importedIDs` set (§2.66).
- **Scenario:** On an account with 40,000 messages, SpamWise pulls tens of megabytes of raw source through AppleScript every minute, indefinitely, which keeps CPU and energy use high for both Mail and SpamWise.
- **Fix:** Fetch only the headers history needs, give maintenance its own slower schedule, stop once a full pass finds nothing new, and store a bounded high-water mark instead of every ID.
<!-- sources: correctness/app-logic#11 -->

#### 2.17 Folder plans cannot be removed, and validation failures say "Mail service unavailable" — Medium

- **Where:** `SpamWise/AppModelFolders.swift:17` (`SpamWise/AppModelFolders.swift:23`, `SpamWise/AppModelFolders.swift:31`, `SpamWise/FolderSettingsView.swift:17`)
- **Problem:**
  - Three different user errors throw `IntegrationError.unavailable`, which is shown as "The requested message or Mail service is unavailable": a wrong training-folder name, a training folder that is not empty, and the 20-plan limit.
  - No code path removes a plan.
  - The picker lists only folders discovered in the current session, so a plan for a renamed folder can be neither disabled nor deleted.
  - Enabled orphaned plans fail on every sweep and still count toward the limit.
- **Scenario:** A user renames "Orders" in Mail. Its filter plan fails on every sweep and cannot be reached from Settings. Saving a training plan for a folder that holds one message reports a Mail outage instead of "the folder must be empty".
- **Fix:** List saved plans, including those whose folder is missing, with Disable and Remove actions. Throw specific, localized errors with recovery suggestions and show them next to Save.
<!-- sources: correctness/app-logic#19, correctness/app-views-settings#8 -->

#### 2.18 One message that cannot be corrected stalls a training folder forever — Medium

- **Where:** `SpamWise/AppModelFolders.swift:124` (`SpamWise/AppModelFolders.swift:104`, `SpamWiseCore/Sources/SpamWiseCore/SelectedCorrections.swift:10`)
- **Problem:** `trainFolderPage` rethrows the first correction error. The caller records a health failure but never calls `complete`, so `nextOffset` does not advance and every later sweep fails on the same message.
- **Scenario:** Message 3 of 30 dragged into "SpamWise Train Junk" has an unparseable From header (§2.5). Messages 4 to 30 are never trained, and scan health shows a generic failure indefinitely.
- **Fix:** Catch errors per envelope. Record each failure together with an outcome claim so it is not retried every sweep, and still complete the visited positions. Add a test with one bad message followed by valid ones.
<!-- sources: correctness/app-logic#7 -->

#### 2.19 Transient failures are treated as "seen" and never revisited — Medium

- **Where:** `SpamWise/AppModelScanning.swift:113` (`SpamWise/AppModelScanning.swift:117`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:5`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:192`)
- **Problem:**
  - Any record at the current revision counts as seen, including unclassified failures.
  - Retryable errors get three retries, at 30, 60 and 120 seconds.
  - Dry run gets no retries at all, because of `guard !forceDryRun`.
  - Cancellation and lock contention also get no retries.
  - Once retries run out, the message is skipped until some unrelated edit bumps the revision, and Activity offers no way to retry it.
- **Scenario:** During a 10-minute provider outage, or after a 429, every message swept in that window stays unclassified in the Inbox for good. Pressing Cancel partway through a page does the same to the message in flight.
- **Fix:**
  - Leave unclassified records with transient causes out of the seen-set, or give them a retry-after time.
  - Back off over hours, bounded by message age, using a durable queue.
  - Queue cancellation and lock-contention failures for retry as well.
  - Add a "Retry unclassified" action to Activity.
<!-- sources: distribution/product#7, correctness/app-logic#13 -->

#### 2.22 Manual dry runs classify 20 messages per account and send them again on every click — Medium

- **Where:** `SpamWise/AppModelScanning.swift:121` (`SpamWise/AppModelScanning.swift:93`, `SpamWise/OnboardingView.swift:97`, `SpamWise/ContentView.swift:63`)
- **Problem:** Manual scans skip the seen filter and apply the limit to each account separately. Pipeline does not cache verdicts, so each click makes new paid calls and new ledger reservations and appends new Activity rows. Onboarding and Help promise "20 recent Inbox messages".
- **Scenario:** A user with three accounts presses "Dry run recent mail" five times while tuning the policy. That makes 300 paid calls, reserves $30 of the $150 ledger, and shows each message five times in Activity.
- **Fix:** Cap the merged batch at the advertised total, or change the text to "per account". Reuse an existing dry-run verdict when content, revision and policy are unchanged. Merge rows for the same identity and revision instead of appending.
<!-- sources: correctness/app-logic#9, correctness/app-views-main#4 -->

#### 2.23 Content-rule form and editor errors are never shown in the sheet — Medium

- **Where:** `SpamWise/ContentRuleEditorView.swift:125` (`SpamWise/ContentRuleEditorView.swift:126`, `SpamWise/ContentRuleEditorView.swift:132`, `SpamWise/ContentRuleEditorView.swift:68`, `SpamWise/AppModel.swift:222`, `SpamWise/SettingsView.swift:30`)
- **Problem:** Save, preview, import and remove all go through `model.run`, which writes errors to `model.status`. That status appears only in the Settings footer, behind two sheets. The form has no inline error, unlike RuleFormView, and `preview()` never clears `result`.
- **Scenario:** Saving a 101st rule, or testing with nothing selected in Mail, appears to do nothing. Or the previous "This rule wins…" text stays on screen after a preview fails.
- **Fix:** Use the completion-based pattern from RuleFormView, show errors in sheet-local state, dismiss only on success, and clear `result` at the start of each preview.
<!-- sources: correctness/app-views-settings#10, conventions/app-views-settings#3 -->

#### 2.24 Eight sibling sheets on one view collide, so Preview, results and Tools sheets fail to appear — Medium

- **Where:** `SpamWise/ContentView.swift:129` (`SpamWise/ReviewDigestView.swift:37`, `SpamWise/DecisionDetailView.swift:68`, `SpamWise/AppModel.swift:136`, `SpamWise/AppModelMailReview.swift:11`, `SpamWise/MailMenuView.swift:24`)
- **Problem:** Every model-level presentation flag is a sibling `.sheet` modifier on the ActivityView container, but a window can show only one sheet at a time. Raising a flag while another sheet is up fails, and the flag stays true. This happens with:
  - Preview, opened from the digest's nested decision sheet;
  - the automatic weekly digest;
  - menu-bar correction results;
  - the Tools sheets.

  Menu-bar corrections are also enabled before onboarding finishes, when no ActivityView exists to show their results.
- **Scenario:**
  - Review digest → decision → Preview message shows nothing.
  - With Statistics open, menu bar → Mark as Junk runs the corrections, but its results sheet never appears.
  - During onboarding, a menu-bar correction's results sheet appears unexpectedly once setup is finished.
- **Fix:** Use a single `enum ActivitySheet: Identifiable` with one `.sheet(item:)`. Present Preview inside the digest's own sheet hierarchy. Disable the menu-bar correction section until `onboardingComplete`.
<!-- sources: correctness/app-views-main#2 -->

#### 2.25 Corpus and undo actions throw unrelated error types, so users see misleading text — Medium

- **Where:** `SpamWise/CorpusView.swift:82` (`SpamWise/CorpusView.swift:90`, `SpamWise/CorpusView.swift:102`, `SpamWise/CorpusView.swift:110`, `SpamWise/DecisionDetailView.swift:52`, `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:15`, `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:61`)
- **Problem:**
  - Four unrelated conditions all throw `ParseError.tooLarge` ("The message exceeds the supported content limits"): more than 20 files, an unavailable store, a "[SpamWise Probe]" subject, and the 500-label cap.
  - Undo, Forget and Relabel touch only the store, yet their failures throw `IntegrationError.unavailable` ("The Mail action is unavailable").
  - One unparseable file aborts the whole batch without naming it.
  - The 20-file limit and the `2_000_001`-byte read size are unnamed magic numbers.
- **Scenario:** A user picks 25 small .eml files, is told a message is too large, and keeps retrying with smaller messages. A store failure during Undo reports a problem with Mail.
- **Fix:**
  - Add an app-level error type with cases such as `tooManyFiles(selected:limit:)`, `unreadable(filename:)`, `labelCapacityReached` and `storeNotReady`, each with an interpolated `failureReason`.
  - Report per-file failures by name.
  - Name both limits, and route the read that goes one byte past the parser maximum through a helper.
<!-- sources: correctness/app-views-main#10, conventions/app-views-main#1, comments/app-views-main#4 -->

#### 2.26 Some Evidence and Notification controls save only on a button, so edits are lost — Medium

- **Where:** `SpamWise/EvidenceSettingsView.swift:71` (`SpamWise/EvidenceSettingsView.swift:13`, `SpamWise/EvidenceSettingsView.swift:41`, `SpamWise/NotificationSettingsView.swift:13`, `SpamWise/GeneralSettingsView.swift:41`)
- **Problem:** Within the same group, some toggles save immediately: domain age, OCR, attachments and the digest. Controls that look identical only edit `@State` until a Save button is pressed: Spamhaus enable, consent and resolver; Rspamd transport and path; and every notification option. Drafts are reseeded when the view appears, and nothing marks unsaved changes.
- **Scenario:** The user turns on Spamhaus, ticks the terms toggle and closes Settings, and nothing is saved. Or they set Rspamd to Off and close the window, and the scanner keeps receiving message data.
- **Fix:** Make every control save the same way, either through field-level `editSettings` calls (with consent enforced in the binding) or in a clearly separate form that shows unsaved changes and prompts on dismissal.
<!-- sources: correctness/app-views-settings#6 -->

#### 2.27 Settings drafts can be seeded from default AppState and then saved over the real configuration — Medium

- **Where:** `SpamWise/EvidenceSettingsView.swift:79` (`SpamWise/NotificationSettingsView.swift:38`, `SpamWise/TrustExclusionsView.swift:30`, `SpamWise/AppModel.swift:126`)
- **Problem:** Drafts copy the settings once, when the view appears. SettingsView does not wait for a successful load, and `refresh()` sets `hasLoadedState` even when the load fails (for example with `lockUnavailable`), leaving `AppState()` defaults in place. Save then writes the whole sub-structure back.
- **Scenario:** Opening Settings right after launch, or while the extension holds the lock, shows an empty trust-exclusions list. Adding one alias and saving deletes every existing exclusion, and saving the evidence settings resets Spamhaus consent.
- **Fix:** Show SettingsView only after a load succeeds, reseed drafts that have no edits when the persisted value changes, and save only the fields the user edited.
<!-- sources: correctness/app-views-settings#7 -->

#### 2.28 Setup reopened from Settings has no Cancel, and Finish silently turns dry run back on — Medium

- **Where:** `SpamWise/GeneralSettingsView.swift:55` (`SpamWise/OnboardingView.swift:31`, `SpamWise/AppModel.swift:201`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:249`)
- **Problem:** The four-step setup sheet offers only Back, Continue and Finish setup, with no `.cancelAction`. Finish calls `finishSetup()`, which always writes `dryRun = true` through `editSettings`. That write also bumps the revision, clears retries and drops undo. When `storageReady` is false, Finish is disabled and the sheet cannot be dismissed at all.
- **Scenario:** A user in live mode opens Show setup to reread the privacy text. Nothing else closes the sheet, so they click through to Finish, and automatic Junk moves stop without any notice.
- **Fix:** Add a Cancel button with `.keyboardShortcut(.cancelAction)` that only dismisses the sheet. When onboarding is already complete, Finish should leave `dryRun` unchanged.
<!-- sources: correctness/app-views-main#1, correctness/app-views-settings#1 -->

#### 2.30 Reviewed-label export re-encodes every label on each render and can export an empty file — Medium

- **Where:** `SpamWise/LearningSettingsView.swift:47` (`SpamWise/LearningSettingsView.swift:44`)
- **Problem:** The `fileExporter` document is built inline in `body`. Every re-render, including the one from the 3-second state reassignment, pretty-encodes up to 500 labels, each with up to 16,000 characters of retained text. `try? … ?? Data()` turns an encoding failure into an empty export that reports success.
- **Scenario:** With retained content, leaving Settings → Advanced open re-encodes megabytes of JSON on the main actor every 3 seconds. An encoding failure produces an empty SpamWise-reviewed-labels.json that is reported as a successful export.
- **Fix:** Build the document in the Export action with do/catch, as `RuleEditorView.exportRules` does, keep it in `@State`, and report errors to the user.
<!-- sources: correctness/app-views-settings#9, conventions/app-views-settings#5 -->

#### 2.31 MIME parsing, statistics and corpus file I/O run on the main actor, often in view bodies — Medium

- **Where:** `SpamWise/MailReviewView.swift:32` (`SpamWise/MailReviewView.swift:39`, `SpamWise/AppModelMailReview.swift:15`, `SpamWise/AppModelMailReview.swift:67`, `SpamWise/ActivityStatisticsView.swift:15`, `SpamWise/CorpusView.swift:81`, `SpamWise/ContentRuleEditorView.swift:135`)
- **Problem:**
  - Review Junk fully MIME-parses every row (up to 2 MB each, 20 per page), plus the selected message, inside `body`.
  - `correctSelection` parses up to 50 messages on the main actor just to get their subjects.
  - The computed `statistics` property is evaluated about 8 times per render, plus once per chart bar, over 5,000 records.
  - Corpus import reads and parses up to 20 files of 2 MB each in a `@MainActor` closure.
  - When parsing fails, the row shows "Unclassified message", which is misleading.
- **Scenario:** A page of large newsletters stutters on every `busy` toggle and every selection change. The Statistics sheet recomputes about 40 times per render. A 20-file import freezes the window.
- **Fix:**
  - Parse each page once, off the main actor, when it loads, and store lightweight row models.
  - Compute statistics once per `body` evaluation, or keep them in `@State`.
  - Move corpus reading and parsing into a nonisolated helper.
  - On failure, show a specific "Couldn't read message" label.
<!-- sources: design/main-window#17, concurrency#7, correctness/app-views-main#5, conventions/app-views-main#2, comments/app-views-main#5 -->

#### 2.32 The Review Junk sheet shows the previous session's messages and pages with stale state — Medium

- **Where:** `SpamWise/MailReviewView.swift:50` (`SpamWise/MailReviewView.swift:7`, `SpamWise/MailReviewView.swift:47`, `SpamWise/MailReviewView.swift:53`, `SpamWise/MailReviewView.swift:63`, `SpamWise/AppModel.swift:27`)
- **Problem:**
  - `accountID` and `offset` reset each time the sheet opens, but `junkMessages` and `junkTotal` live on AppModel and survive dismissal.
  - `onChange(of: accountID)` does not run on appear and does not reset `junkTotal`.
  - Next page stays enabled with no account selected, or with another account's total.
  - `offset` changes before `loadJunk` runs and is not rolled back if the load fails.
- **Scenario:** Reopening the sheet shows account A's messages under "Choose account". Next page then sends an empty account ID, fails, and leaves `offset` at 20, so the next real load skips a page.
- **Fix:** Clear `junkMessages` and `junkTotal` on appear and on account change, or make them view-owned. Disable paging while `accountID` is empty. Commit the new offset only after a successful load. Load automatically when an account is chosen.
<!-- sources: design/main-window#16, correctness/app-views-main#9 -->

#### 2.33 The selected-message corrections sheet cannot be dismissed or cancelled for up to ~25 minutes — Medium

- **Where:** `SpamWise/MailReviewView.swift:88` (`SpamWise/AppModelMailReview.swift:9`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:224`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:252`)
- **Problem:** `correctSelection` presents CorrectionResultsView and then corrects up to 50 messages one after another, with each live move waiting through a 30-second settle. Done is disabled while `busy`, the sheet has no Cancel, and the only Cancel button sits behind the modal sheet.
- **Scenario:** Marking 40 selected messages as Junk locks the Activity window for about 20 minutes, with no way to stop the batch.
- **Fix:** Add a Cancel button that calls `model.cancel()`. Keep Done enabled, since results persist in Activity, or show progress somewhere non-modal. Consider settling moves in batches rather than one at a time.
<!-- sources: correctness/app-views-main#3 -->

#### 2.34 Spamhaus key status reads the secret on the main thread and reports every Keychain error as "not saved" — Medium

- **Where:** `SpamWise/SpamhausSettingsView.swift:62` (`SpamWise/SpamhausSettingsView.swift:59`, `SpamWise/SpamhausSettingsView.swift:73`, `SpamWiseCore/Sources/SpamWiseCore/Keychain.swift:47`)
- **Problem:** `refreshKeyStatus` runs `SecItemCopyMatching` with `kSecReturnData` in `onAppear`, loading the secret into memory only to check that it exists. `try?` turns every `KeychainError.status` (a missing entitlement, interaction not allowed) into "No query key saved", and the save path discards `failureReason`.
- **Scenario:** In a build with a misconfigured access group, an existing key shows as "No query key saved". Saving again fails with an opaque message, and lookups quietly return unknown.
- **Fix:** Add an attributes-only existence check to APIKeychain and call it off the main actor through AppModel. Show "not saved" only for `.missing`, and show other errors through `AppModel.describe`.
<!-- sources: correctness/app-views-settings#13, conventions/app-views-settings#7 -->

#### 2.35 Anthropic 5xx responses become non-retryable configuration errors — Medium

- **Where:** `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:90` (`SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:93`, `SpamWiseCore/Sources/Classifier/Types.swift:200`)
- **Problem:** The pinned provider maps HTTP 500, 502 and 503 to a package-scoped `APIError(.api)` that ClaudeClassifier cannot catch. The error falls through to the catch-all, which throws `.configuration`, and that case is not retryable. The OpenAI and Gemini paths map 5xx to `.network`, which is retried.
- **Scenario:** During a brief Anthropic outage on the default provider, every message is recorded as "unclassified: configuration", none is retried, and all of them stay unfiltered.
- **Fix:** Map provider errors by kind or HTTP status: 5xx to `.network`, permission errors to a credential error. Add a ProviderTests case with a stubbed 503.
<!-- sources: correctness/core-classifier-learning#5 -->

#### 2.36 Quote stripping lets a sender hide the whole body from the model — Medium

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:314`
- **Problem:** `unquotedText` runs on untrusted text. It stops at the first "On … wrote:" or "-----Original Message-----" line and drops every ">"-prefixed line, with no minimum amount of content kept.
- **Scenario:** A body that opens with "On Tue, Oct 13, 2026, Billing wrote:" followed by a phishing paragraph reaches the model with an empty text field.
- **Fix:** Strip quoted text only after some unquoted content has been seen, cap the fraction of the body that can be removed, or send the quoted region as a separate, labelled and truncated field.
<!-- sources: correctness/core-classifier-learning#6 -->

#### 2.37 Evaluation counts budget and lock refusals as provider calls and exits 0 — Medium

- **Where:** `SpamWiseCore/Sources/Evaluation/CachedClassifier.swift:42` (`SpamWiseCore/Sources/SpamWiseEval/RunReport.swift:57`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:144`)
- **Problem:** `misses` is incremented before the underlying classifier runs. When a call is refused with `BudgetError` or `StoreError.lockUnavailable`:
  - it is recorded as an unclassified observation;
  - it is still reported under `providerCalls`;
  - metrics are computed over a cohort that was only partly evaluated;
  - the process exits 0.
- **Scenario:** With $0.50 left in the ledger, a 100-message Haiku run reports 100 provider calls and about 5% junk recall, and 95 of its rows say "spending limit reached".
- **Fix:** Count only calls that actually reach the provider, or keep separate attempted, refused and completed counters. Treat budget and store errors as fatal and exit nonzero. Retry lock acquisition with a bounded backoff.
<!-- sources: correctness/eval-scripts#2 -->

#### 2.38 Calibration buckets are too coarse to derive the strength thresholds — Medium

- **Where:** `SpamWiseCore/Sources/Evaluation/Metrics.swift:119` (`SpamWiseCore/Sources/SpamWiseEval/RunReport.swift:32`)
- **Problem:** Buckets are 10 points wide, and the top bucket, 90 to 100, contains all three thresholds (90, 95 and 99). RunReport only re-scores those fixed values. At any corpus size, the harness cannot produce the data-derived thresholds that the brief (§3.5, §9) requires.
- **Scenario:** In a corpus where 90–94 has 97% precision and 95–100 has 99.9%, the two collapse into one bucket at about 99%, so nothing shows that Balanced should be 95.
- **Fix:** Report cumulative precision per point, at least from 85 upward, and the false-positive upper bound at each candidate threshold. On the training split, pick the lowest threshold that meets each strength's target, then validate those picks on the held-out split.
<!-- sources: gap/brief-conformance#6 -->

#### 2.39 The evaluator rejects reviewed labels the app exports, as duplicate content — Medium

- **Where:** `SpamWiseCore/Sources/Evaluation/ReviewedCorpus.swift:57` (`SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:134`, `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:32`, `SpamWise/LearningSettingsView.swift:47`)
- **Problem:** A correction replaces an earlier label only when the raw-message hash matches, so identical content delivered twice produces two labels. The evaluator dedupes on normalized sample identity and throws on the first collision. The export writes the label array as-is.
- **Scenario:** A user marks the same campaign message as Junk in both accounts. `spamwise-eval --reviewed labels.json` then fails with "duplicate content", and the only fix is to Forget samples one at a time.
- **Fix:** Dedupe by `sampleID` in `recordReviewedLabel`, as imports already do. In ReviewedCorpus, collapse duplicates that carry the same label and reject only conflicting ones, naming them in the error.
<!-- sources: correctness/eval-scripts#3 -->

#### 2.40 A later Junk correction never overrides an earlier Good/Review campaign fingerprint — Medium

- **Where:** `SpamWiseCore/Sources/Learning/LearningState.swift:171` (`SpamWiseCore/Sources/Learning/CampaignLearning.swift:72`)
- **Problem:** A Good or Review correction removes near-duplicate Junk fingerprints, but a Junk correction removes only the fingerprint with its own content ID. `isSuppressed` then lets any non-Junk fingerprint with at least 0.8 overlap block the match. Review signatures also suppress matches, although the documentation says only Inbox signatures do.
- **Scenario:** The user marks campaign issue A as Good, and later marks near-duplicate issue B as Junk. Issues C and D never trigger the fingerprint gate, and Junk predictions for the campaign are refused, so the Junk correction appears to have no effect.
- **Fix:** When recording a Junk fingerprint, also remove overlapping non-Junk fingerprints. Decide explicitly whether Review should suppress. Add a test that corrects Good first and then Junk.
<!-- sources: correctness/core-classifier-learning#2 -->

#### 2.41 Prediction and correction samples get different identities when attachment text or OCR is enabled — Medium

- **Where:** `SpamWiseCore/Sources/Learning/LearningState.swift:200` (`SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:39`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:115`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:130`)
- **Problem:** At classification time the identity hash covers text that includes extracted attachment and OCR text. Corrections re-parse the message with the plain parser. The two IDs differ, so the wrong prediction sample is never replaced, and Forget and relabel miss it.
- **Scenario:** An image-heavy receipt is predicted Junk at 100 and admitted to training. The user marks it Good, but the Junk sample stays and keeps pushing similar receipts toward Junk.
- **Fix:** Derive the learning identity from one canonical parse in both places, or store the classification-time `sampleID` on the DecisionRecord.
<!-- sources: correctness/core-classifier-learning#8 -->

#### 2.42 Learning samples keep only the alphabetically first 128 tokens — Medium

- **Where:** `SpamWiseCore/Sources/Learning/LearningState.swift:325`
- **Problem:** `LearningSample.make` dedupes the tokens, sorts them lexicographically and keeps the first 128. For long messages that leaves numbers and words from the start of the alphabet. Inference then intersects the message's full token set with this skewed vocabulary.
- **Scenario:** Thirty phishing corrections that all contain "verify" and "suspended" store neither word. A new "verify your suspended account" message gets no Bayes signal from either.
- **Fix:** Choose tokens by a criterion that does not depend on spelling: the first 128 distinct tokens in document order, or the 128 with the smallest `stableHash`, as campaign shingles already do. Apply the same rule at inference.
<!-- sources: correctness/core-classifier-learning#3 -->

#### 2.43 AppleScript execution has no overall deadline and cannot be cancelled — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:74` (`SpamWiseCore/Sources/MailIntegration/MailScripts.swift:21`, `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:198`)
- **Problem:**
  - All scripts run synchronously on one serial queue.
  - `with timeout of 8 seconds` bounds each Apple Event, not the script as a whole.
  - The recursive resolve across every mailbox, and the page scripts that read 100 to 1,000 sources, can run far longer.
  - Cancellation is checked only before and after a script.
  - The Automation permission prompt blocks the same queue until the user answers.
- **Scenario:** On an account with hundreds of mailboxes, a correction lookup takes about 40 seconds. Menu-bar corrections and Shortcuts requests queue up behind it, and pressing Cancel has no visible effect.
- **Fix:** Bound the work each script does: resolve through Inbox and Junk first, and cap the number of mailboxes searched. Run scripts through a mechanism that can be interrupted and enforces a wall-clock limit, such as `NSUserAppleScriptTask` or a helper process that can be terminated. Record the outcome as unknown when the limit is hit.
<!-- sources: concurrency#5 -->

#### 2.44 AppleScript error numbers are unnamed and overloaded, so users see wrong explanations — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:82` (`SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:83`, `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:69`, `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:114`, `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:120`, `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:204`, `SpamWiseCore/Sources/MailIntegration/MailFolderScripts.swift:10`, `SpamWiseCore/Sources/MailIntegration/MailFolderScripts.swift:17`, `SpamWiseCore/Sources/MailIntegration/MailFolderScripts.swift:27`)
- **Problem:** The Swift side maps -1701 to "ambiguous" and -1702 to "stale message", but the scripts use each number for several unrelated conditions:
  - -1701: zero matches, unresolved accounts and wrong selection counts.
  - -1702: a retained flag or colour, and the folder count and nesting limits.

  A genuine -1701 error from Mail looks the same as an intended "ambiguous".
- **Scenario:**
  - An empty selection reports "More than one message matches".
  - A Review flag skipped because the user already set a red flag reports "The message no longer matches its recorded state".
  - So does listing folders on an account with more than 1,000 mailboxes.
- **Fix:** Define a named error enum and interpolate its values into every script. Give each condition its own private error number, and map each one to an accurate IntegrationError.
<!-- sources: correctness/mail-integration#13, comments/mail-integration#4 -->

#### 2.45 Cancellation after a move script has run records the move as Failed — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:90` (`SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:253`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:311`)
- **Problem:** `run` checks for cancellation after `executeAndReturnError` returns, and `perform` then sleeps through a cancellable 30-second settle before verifying. A CancellationError that arrives after a successful move reaches dispatch, which sets `.failed` and skips mark-as-read. The model already has `.requested` for completion that was not confirmed, and that is the accurate state here.
- **Scenario:** The user presses Cancel during the settle window. Activity shows Failed for a message that is now in Junk, so the user never looks for it there.
- **Fix:** Once a mutating script has succeeded, do not treat cancellation as failure. Either shield the settle and verify steps from cancellation, or return `ActionReceipt(confirmed: false)` so the record becomes `.requested`.
<!-- sources: concurrency#4 -->

#### 2.46 Apple Mail actions move a message from wherever it now is — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:241` (`SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:245`, `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:202`)
- **Problem:** `perform` and `lookup` check only the account and the content hash. `resolve` searches every mailbox in the account, and nothing compares the mailbox it finds with `identity.mailbox`. Decisions are dispatched seconds to minutes after the page was read, and retries up to 24 hours later. The IMAP adapter, by contrast, SELECTs the recorded mailbox.
- **Scenario:** A message's classification times out and a retry is queued. The user files it into "Receipts/2026". Two minutes later the retry classifies it as Junk and moves it out of that folder.
- **Fix:** For automatic actions, require the resolved mailbox and account to equal `identity.mailbox` inside the action script, and fail open when they differ. Keep the any-mailbox resolution only for explicit user corrections.
<!-- sources: correctness/mail-integration#3 -->

#### 2.47 Each Apple Mail move holds the sequential pipeline for 30 seconds — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:253` (`SpamWise/AppModelScanning.swift:121`, `SpamWise/AppModel.swift:82`)
- **Problem:** `perform` sleeps for `moveSettlingTime` (30 s) after every Junk or Inbox move, and the batch is processed one message at a time, so N Junk verdicts take at least 30·N seconds. Meanwhile the remaining envelopes go stale, which widens the window in §2.46, and Pause takes effect only between messages.
- **Scenario:** Twenty spam messages arrive overnight, and the next sweep takes more than 10 minutes to move them. Each is acted on minutes after it was read, and the UI spends most of that time waiting.
- **Fix:** Record `.requested` and confirm the move in a separate verification pass, or poll at a short interval with an early exit, while the rest of the batch continues.
<!-- sources: security/mail-integration#5 -->

#### 2.48 Daemon `--probe` and `--model` silently change the shared app's route, transport and model — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:148` (`SpamWiseCore/Sources/SpamWiseDaemon/main.swift:58`, `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:71`, `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:122`, `SpamWise/AppModelIMAP.swift:25`)
- **Problem:** Without `statePath`, the daemon uses the App Group store that the app and extension share.
  - A successful `--probe` sets `route = .imap` and `transport = .imap`. That turns off the validated Mail-rule route, makes the extension skip its work, and points the app's sweeps at an IMAPAppConnection the GUI never saved.
  - `--model` rewrites the shared backend and model.
  - The CLI prints only "Dry run remains unchanged."
- **Scenario:** A user who filters with Apple Mail runs `spamwise-daemon --probe 42` to try a second account over IMAP. The app's next scan throws "The IMAP configuration is invalid", and Apple Mail filtering stops.
- **Fix:**
  - Record IMAP validation under a daemon-scoped key without touching the GUI's route or transport. Alternatively, require `statePath`, or refuse to probe while the shared transport is Apple Mail.
  - Keep `--model` scoped to the daemon's own store.
  - Print every setting a command changes.
<!-- sources: security/mail-integration#6, correctness/mail-integration#9 -->

#### 2.49 Folder start dates use Calendar.current components inside a Gregorian AppleScript date — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailFolderScripts.swift:78` (`SpamWise/AppModelFolders.swift:69`)
- **Problem:** The year, month and day come from the user's current calendar and are written into an AppleScript date, which is always Gregorian. Under the Buddhist calendar the year is 2569, under the Japanese calendar it is the era year 8, and the Hebrew and Islamic calendars number months differently.
- **Scenario:** Under the Buddhist calendar, a filter plan starting today matches nothing. Under the Japanese calendar it covers the folder's whole history, and once dry run is off it can move years-old mail to Junk.
- **Fix:** Build the components with `Calendar(identifier: .gregorian)` and the current time zone, or pass an epoch timestamp to the script.
<!-- sources: correctness/mail-integration#5 -->

#### 2.50 Moves of messages without a Message-ID are recorded as failed and "ambiguous" — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:203` (`SpamWiseCore/Sources/MailIntegration/MailScripts.swift:16`, `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:155`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:132`)
- **Problem:** A message with no Message-ID is located by its local ID, and Mail assigns a new local ID after a move. Verification looks the message up with the pre-move identity, finds nothing, raises -1701, and throws "ambiguous" after the move has already happened.
- **Scenario:** A spam message without a Message-ID, which is common for spam, is moved to Junk but recorded as Failed with "More than one message matches". Mark Good later cannot find it.
- **Fix:** Refuse automatic moves when `messageID` is nil, failing open before acting. Alternatively, return the post-move local ID through `ActionReceipt.updatedIdentity` and verify against that.
<!-- sources: correctness/mail-integration#4 -->

#### 2.51 Public Suffix List matching ignores punycode, so IDN public suffixes become "registrable domains" — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/DomainResolver.swift:11` (`SpamWiseCore/Sources/MessageModel/DomainResolver.swift:17`, `SpamWiseCore/Sources/MessageModel/DomainResolver.swift:19`, `SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift:47`, `public_suffix_list.dat:820`)
- **Problem:** The bundled PSL stores IDN rules only in Unicode and has no `xn--` rules. Sender hosts arrive as ASCII punycode, and neither side is ever converted to the other. If the PSL resource fails to load, the rule set is empty and every lookup quietly returns nil.
- **Scenario:** A domain Block made from <promo@shop.xn--55qx5d.cn> is stored as the rule `xn--55qx5d.cn`, which blocks every company registered under 公司.cn. A rule typed as `bücher.de` passes validation but never matches `xn--bcher-kva.de`.
- **Fix:** Normalize PSL rules and rule values to one IDNA form, either at load time or in the PSL refresh script. Treat a missing PSL as a `preconditionFailure`. Add IDN boundary tests.
<!-- sources: correctness/core-parsing-signals#8, correctness/tests#4, conventions/core-parsing-signals#2, comments/core-parsing-signals#24 -->

#### 2.52 IMAP identity keys include the UID, so mail rescued from Junk in another client is junked again — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/Identity.swift:18` (`SpamWiseCore/Sources/MailIntegration/IMAPPaging.swift:39`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:100`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:293`, `SpamWise/AppModelScanning.swift:113`)
- **Problem:** For IMAP, the dedupe key, the seen-set and the at-most-once action claim all hash the mailbox, UIDVALIDITY and UID. Moving a message back to INBOX in another client gives it a new UID, so it gets a new key with no claim. A UIDVALIDITY reset makes the whole Inbox look new and re-classifies it.
- **Scenario:** The user drags a wanted newsletter back to INBOX on their phone. Within a minute SpamWise pays to classify it again and moves it back to Junk, and this repeats every time they rescue it.
- **Fix:** Key dedupe and claims on account plus Message-ID plus content hash, as the Apple Mail key does, and use UID and UIDVALIDITY only for addressing the message. Treat a message that reappears in INBOX after a SpamWise Junk move as an implicit Good correction. Add a test.
<!-- sources: correctness/core-pipeline-store#5, correctness/app-logic#4 -->

#### 2.53 Interleaving MIME alternatives in 128-character chunks breaks phrases — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:62` (`SpamWiseCore/Sources/MessageModel/MIMEParser.swift:51`)
- **Problem:** When the plain and HTML alternatives differ, as they do for most HTML mail, `message.text` becomes alternating 128-character slices separated by "[Alternative N]" markers. Any phrase that crosses a slice boundary is split, which breaks body rules, the receipt heuristic and Bayes tokens, and the text roughly doubles in length.
- **Scenario:** The body rule "claim your prize" misses text that came out as "claim yo\n[Alternative 2] …\n[Alternative 1] ur prize".
- **Fix:** Keep each alternative contiguous and bounded. Interleave only in the prompt builder, if at all. Run content rules against each alternative separately.
<!-- sources: correctness/core-parsing-signals#7 -->

#### 2.54 Content-rule header and attachment fields match raw, undecoded values — Medium

- **Where:** `SpamWiseCore/Sources/Signals/ContentRules.swift:104` (`SpamWiseCore/Sources/MessageModel/MIMEParser.swift:97`)
- **Problem:** The recipients, List-ID and Reply-To fields use raw Latin-1 header values with encoded words left undecoded. The filename regex requires `filename=`, so RFC 2231 forms (`filename*=`, `filename*0=`) yield no name unless a legacy `name=` is also present.
- **Scenario:** An attachment rule `.html` → Block misses an attachment declared as `filename*=UTF-8''Invoice%20123.html`.
- **Fix:** Decode header fields before matching, covering encoded words and 8-bit UTF-8. Parse RFC 2231 extended and continued parameters. Cover both in the content-rule test.
<!-- sources: correctness/core-parsing-signals#9 -->

#### 2.55 URL, link-domain and Spamhaus caps keep the alphabetically first entries — Medium

- **Where:** `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:178` (`SpamWiseCore/Sources/MessageModel/MIMEParser.swift:222`, `SpamWiseCore/Sources/Signals/Evidence.swift:73`)
- **Problem:** Each bounded list is sorted alphabetically before it is cut:
  - The Spamhaus lookup turns its candidates into a Set, sorts them and queries five, discarding the sender-first order.
  - MIMEParser sorts URLs before applying its 40-item cap.
  - EvidenceBundle sorts link domains before taking 20.
- **Scenario:** A phish from zz-login.xyz contains links to apple.com, amazon.com, bit.ly, cdn.example and facebook.com, plus the payload link secure-update.top. Neither the sender domain nor the payload domain is checked.
- **Fix:** Bound in priority order: sender, Reply-To and Return-Path domains first, then link domains in order of first appearance, deduplicated with an ordered set. Apply the same rule to URLs and to `linkDomains`.
<!-- sources: correctness/core-parsing-signals#6 -->

#### 2.56 Imported corpus samples train logistic weights on header-stripped evidence — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:47` (`SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:24`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:149`)
- **Problem:** `importMessages` clears headers before building the EvidenceBundle, so every imported sample has the same feature values: auth failure 0, Reply-To mismatch 0, List-Unsubscribe 0 and domain-age-unknown 1. Live corrections use the real evidence, so the model learns where a sample came from, not whether it is spam. Importing the SpamSieve Junk the user is accumulating would make this the main training source.
- **Scenario:** The user imports 150 Junk samples, none with List-Unsubscribe, and marks 60 live newsletters as Good, all with it. The model learns that List-Unsubscribe means Inbox and pushes every spam message carrying that header toward Inbox.
- **Fix:** Compute the evidence before stripping headers and store only the derived features. Alternatively, exclude imported samples from logistic training and mark their header-derived features as unknown.
<!-- sources: correctness/core-classifier-learning#4 -->

#### 2.57 The 500-label cap is inconsistent: corrections silently evict imported labels, while imports fail outright — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:61` (`SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:144`, `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:101`)
- **Problem:** Corrections keep only the newest 500 labels, whatever their origin. That drops imported and held-out human labels without removing their learning contributions or examples, which Forget can then no longer reach. Imports, meanwhile, throw `ParseError.tooLarge` once the total would exceed 500, and the message does not mention the label limit.
- **Scenario:** After 480 imports and 20 corrections, every import fails with "too large". A further 100 corrections remove 100 imported labels, quietly shrinking the held-out set, while those labels' Bayes contributions remain.
- **Fix:** Apply one retention policy to both paths: never evict imported labels silently, or ask before doing so. Remove linked learning when a label is evicted. Use a dedicated "label limit reached" error. Show remaining capacity, and add a "rebuild learning from current labels" action.
<!-- sources: todo/spamsieve-b#6, correctness/core-pipeline-store#12 -->

#### 2.58 A revision change between claim and perform leaves the message claimed forever but never acted on — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:304` (`SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:293`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:100`)
- **Problem:** The claim is written in the first transaction. If the recheck after claiming finds a new revision, Pause or dry run, the record is saved as `.superseded` but the claim is not released, so every later `process()` call returns that record immediately.
- **Scenario:** A sweep claims a Junk move, and in that window the user toggles a notification preference. The spam stays in the Inbox permanently.
- **Fix:** When the recheck aborts before `adapter.perform`, remove `claimedActions[key]` in the same transaction. Nothing was dispatched, so at-most-once still holds.
<!-- sources: correctness/core-pipeline-store#8 -->

#### 2.59 Every Review decision on IMAP dispatches a flag the IMAP adapter always rejects — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:306` (`SpamWiseCore/Sources/Decision/Decision.swift:88`, `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:141`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:316`)
- **Problem:** Pipeline claims and dispatches the Review annotation without checking whether the adapter supports it. IMAPAdapter throws "unsupported" for anything other than a move, and the record becomes `.failed` with "delivery status unknown. Not retried."
- **Scenario:** An IMAP user gets 20 Review messages a week. All of them appear as failed actions and dominate the digest and the statistics, even though nothing was attempted.
- **Fix:** Add a supported-actions query to the adapter, or map Review to an IMAP flag or keyword such as `\Flagged` or `$SpamWiseReview`. When an action is unsupported, record `.noAction` without claiming. Give rejections that happen before any action their own message.
<!-- sources: correctness/core-pipeline-store#6, correctness/mail-integration#12 -->

#### 2.60 A save failure after a successful move adds an "unclassified" record and leaves the real one as requested — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:321` (`SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:139`)
- **Problem:** `try await save(completed)` runs after `perform` and outside any catch. A lock or store error therefore reaches `process()`'s catch, which saves a second record for the same identity: "unclassified: persistence or integration unavailable". The original record stays `.requested`, and mark-as-read is skipped.
- **Scenario:** A confirmed Junk move collides with the extension's write. The newest Activity row for the message says "unclassified", although the message sits in Junk because of a model verdict.
- **Fix:** Handle post-action save failures inside dispatch with a bounded retry. Never create a second failure record once an action has been dispatched.
<!-- sources: correctness/core-pipeline-store#7 -->

#### 2.61 A failed write for optional Bayes training discards a successful, paid verdict — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:78` (`SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:110`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:136`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:193`)
- **Problem:** `trainPrediction` and the content-rule hit counter use `try` on a `StateRepository.update` that throws `lockUnavailable` under contention. That error aborts classification as "persistence or integration unavailable", and no retry is scheduled, although the provider call has already been paid for.
- **Scenario:** With Bayes enabled, a Junk-99 verdict is lost because the extension held the lock during the training write.
- **Fix:** Make the training and hit-count writes best-effort, or fold them into the decision save after the record has been persisted.
<!-- sources: correctness/core-classifier-learning#7 -->

#### 2.62 Authentication results are never trusted, so DMARC/SPF/DKIM failures carry no weight — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:215` (`SpamWiseCore/Sources/Signals/Evidence.swift:57`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:135`, `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:28`, `SpamWiseCore/Sources/Classifier/Types.swift:244`)
- **Problem:** No production caller passes `trustedAuthServers`, and no setting fills it, so every AuthResult is `trusted: false`. Consequences:
  - The instructions weight only trusted failures, so a real failure counts for nothing.
  - The Bayes contradiction guard can never fire.
  - The learned auth-failure feature is always 0.
  - The inspector shows `"trusted": false` even for the user's own provider.

  `parse` also lowercases server names, but the trust set is not normalized. The brief treats an authentication failure as Strong evidence.
- **Scenario:** A lure from a throwaway domain fails DMARC at mx.google.com, and the model is told the result is untrusted. That removes the strongest deterministic signal for the brief's main target class.
- **Fix:** Determine each account's trusted authserv-id, either from the topmost Authentication-Results header added by its provider or by confirming it at setup. Lowercase it, pass it through `relationshipEvidence`, and add a pipeline test. Until then, say in the instructions and in Help that authentication results are not used.
<!-- sources: conventions/core-parsing-signals#3, gap/brief-conformance#1 -->

#### 2.63 Corrections leave mail in the wrong state — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:9` (`SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:13`, `SpamWiseCore/Sources/Decision/Decision.swift:26`, `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:111`)
- **Problem:** Review is defined as "leave in Inbox with a flag", but the correction actions do not produce that state:
  - A Review correction only adds the flag or background colour, wherever the message happens to be.
  - A Good correction only moves the message to Inbox.
  - The action vocabulary has no way to remove an annotation SpamWise added.
- **Scenario:** A message junked at 96 and corrected to Review stays in Junk with an orange flag. A Review-flagged newsletter marked Good keeps its orange flag and still looks like Review.
- **Fix:** Map a Review correction to a move to Inbox (when the message is elsewhere) followed by the annotation, as the probe already does. Add clear-annotation actions, and dispatch them for Good and Junk corrections of Review records. Cover both cases in tests.
<!-- sources: correctness/core-pipeline-store#10, gap/brief-conformance#2 -->

#### 2.64 A correction can be overridden by an existing rule at another scope — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:50` (`SpamWiseCore/Sources/Signals/Gates.swift:86`)
- **Problem:** A correction replaces only the rule at its own scope. A domain-scope correction leaves the sender's address rule in place, and the address rule takes precedence. A Review correction removes only the address rule, so a domain Block still applies.
- **Scenario:** An earlier `address:a@shop.com` block exists. The user corrects a message from that sender to Inbox with "All of shop.com", but the next message from <a@shop.com> goes straight back to Junk, while the audit says the correction was applied.
- **Fix:** At domain scope, remove or replace conflicting address rules for the corrected sender. For Review, add an address-level exception to a matching domain rule, or warn the user in the correction UI.
<!-- sources: correctness/core-pipeline-store#9 -->

#### 2.65 `correct()` commits the rule, then can throw before dispatch — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:102` (`SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:28`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:110`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:124`)
- **Problem:** The first transaction commits the rule, the example, a revision bump and a `.pending` record. `recordReviewedLabel` then performs loads and updates that can throw, and a throw skips the dispatch. Callers then report that no correction was saved.
- **Scenario:** Mark Good saves an allow rule, then `recordReviewedLabel` hits `lockUnavailable`. The UI says the correction failed, the message stays in Junk, and the row stays pending forever.
- **Fix:** Make label recording best-effort, or fold it into the first transaction. Always continue to dispatch, and report only dispatch problems, through the record's outcome.
<!-- sources: correctness/core-pipeline-store#11 -->

#### 2.66 Persistent state grows without bound inside one blob that every transaction decodes — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:191` (`SpamWiseCore/Sources/SpamWiseCore/State.swift:144`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:243`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:312`, `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:124`, `SpamWiseCore/Sources/SpamWiseCore/CorrectionUndo.swift:56`, `SpamWiseCore/Sources/Store/Store.swift:80`)
- **Problem:**
  - `claimedActions` and every `HistoryIndex.importedIDs` only ever grow.
  - The undo snapshot duplicates the rules, corrections, learning state and labels.
  - All of it lives under the single key `application-v1`, which is fully decoded and re-encoded about 10 to 14 times per message while the exclusive lock is held.
- **Scenario:** After a year of heavy mail, tens of thousands of claims and imported IDs add several megabytes to every transaction. Every step slows down, extension callbacks approach their deadline, and the lock window widens.
- **Fix:** Store the collections under separate keys or rows. Prune claims by age or by whether the message can still be resolved. Bound `importedIDs` with a rolling window or a high-water mark. Keep the undo snapshot under its own key.
<!-- sources: security/core-pipeline-store#6, correctness/core-pipeline-store#3, correctness/mail-integration#11 -->

#### 2.67 Every settings edit bumps the revision, drops all retries and undo, and logs a generic audit entry — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:270` (`SpamWiseCore/Sources/SpamWiseCore/State.swift:255`, `SpamWise/AppModelSettings.swift:32`, `SpamWise/NotificationSettingsView.swift:58`, `SpamWise/GeneralSettingsView.swift:41`)
- **Problem:** `StateRepository.editSettings` treats every change as a policy change, including the notification interval, the digest, mark-as-read and each Stepper click. Every edit:
  - increments `revision`, which supersedes in-flight decisions;
  - empties the retry queue;
  - clears `correctionUndo`;
  - writes the same generic audit entry.
- **Scenario:** Toggling the weekly digest during a sweep supersedes the decisions in flight, which are sent to the provider again later. It also deletes up to 100 queued retries and removes Undo. The audit trail cannot show when the policy text itself changed.
- **Fix:** Bump the revision, clear retries and invalidate undo only for fields that affect classification or actions. Save presentation preferences in a transaction that leaves those alone. Debounce steppers, and record which setting changed.
<!-- sources: todo/spamsieve-b#11, correctness/app-logic#14, correctness/app-views-settings#3 -->

#### 2.68 Daemon poll mode exits on the first transient error — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:96` (`SpamWiseCore/Sources/SpamWiseDaemon/main.swift:39`, `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:89`, `SpamWiseCore/Sources/MailIntegration/IMAPTransport.swift:75`)
- **Problem:** The poll loop has no per-iteration catch. A network blip, a server BYE, Wi-Fi sleep, the 30-second session cutoff or lock contention all reach `main`'s catch, which calls `exit(1)`, and nothing restarts the process.
- **Scenario:** After the Mac sleeps and wakes, the first connection fails. The daemon prints "Headless operation failed" and exits, and no more mail is filtered.
- **Fix:** In poll mode, catch errors other than cancellation on each iteration, log a sanitized category, back off and continue. Exit only on configuration errors or repeated authentication failures.
<!-- sources: correctness/mail-integration#8 -->

#### 2.69 Daemon dedupe treats dry-run, paused and unclassified records as done — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:98` (`SpamWise/AppModelScanning.swift:113`)
- **Problem:** The daemon skips any message that has any record. The app's predicate excludes paused, superseded, and stale dry-run or unclassified records.
- **Scenario:** The user runs the daemon with `--actions` while dry run is still on, then turns dry run off. None of the spam already recorded during the dry run is ever moved.
- **Fix:** Move a single seen predicate into SpamWiseCore, for example `StateRepository.processedKeys(dryRun:)`, and use it in both the app and the daemon.
<!-- sources: correctness/mail-integration#7 -->

#### 2.70 A non-blocking `flock` with no retry turns routine contention into lost work — Medium

- **Where:** `SpamWiseCore/Sources/Store/Store.swift:101` (`SpamWiseCore/Sources/Store/Store.swift:103`, `MailExtension/MessageActionHandler.swift:25`, `SpamWise/AppModelScanning.swift:115`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:321`, `SpamWiseCore/Sources/SpamWiseCore/EvaluationBudget.swift:50`)
- **Problem:**
  - Every Store operation takes `LOCK_EX | LOCK_NB` and throws `lockUnavailable` immediately if the lock is held.
  - flock locks belong to the open file description, and the extension creates a new Store for every callback, so concurrent callbacks conflict even within one process.
  - The app, daemon and CLI also compete for the same lock.
  - No caller retries, and StoreError is not a retryable classification error.
- **Scenario:**
  - During a burst of Mail callbacks, most fail open and leave no record or heartbeat.
  - A sweep's save collides with the extension and leaves either an unclassified record or a pending record that already has a verdict. The seen filter then skips that message forever.
  - A correction fails with "The shared storage lock could not be acquired."
- **Fix:**
  - Wait for the lock up to a bounded deadline, either by polling with `LOCK_NB` and backoff or by taking a blocking lock on a dedicated executor.
  - Share one Store per process, using a static in the extension.
  - Treat `lockUnavailable` as retryable, and retry saves that follow an action.
<!-- sources: concurrency#2, security/core-pipeline-store#5, correctness/core-pipeline-store#2 -->

#### 2.71 Scenario tests chain many unrelated behaviors under names that describe one — Medium

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:176` (`SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:39`, `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:83`, `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:5`, `SpamWiseCore/Tests/SpamWiseCoreTests/SignalsTests.swift:142`, `SpamWiseCore/Tests/SpamWiseCoreTests/SignalsTests.swift:159`, `SpamWiseCore/Tests/SpamWiseCoreTests/MailIntegrationTests.swift:191`, `UITests/UITests.swift:4`)
- **Problem:**
  - Tests of 50 to 80 lines run 5 to 15 behaviors on shared state. The retry-preview test, for example, also covers Review corrections, relabel, Forget, retention, Bayes and undo while paused.
  - They sit just under SwiftLint's body-length limit.
  - Their names don't say what they cover, and later checks inherit state left by earlier ones.
- **Scenario:** A regression in CorrectionUndo shows up as a failure of "preserves pending retries…", and no test name points to the local-only privacy coverage.
- **Fix:** Split each into tests named for the behavior they check. Share setup through fixtures or a suite `init`, and use `@Test(arguments:)` for table-style cases.
<!-- sources: correctness/tests#12, conventions/tests#5 -->

#### 2.72 The PDF worker caps characters, not bytes, so valid non-Latin text kills the worker — Medium

- **Where:** `Tools/DocumentWorker/PDFExtraction.swift:17` (`Tools/DocumentWorker/Worker.swift:83`, `Tools/DocumentWorker/Protocol.swift:5`)
- **Problem:** Text is truncated to 3,000 grapheme clusters, but the reply limit is 16,384 encoded bytes, and the worker calls `_exit(75)` when a reply exceeds it. Indic or Thai text, ZWJ emoji sequences or floods of combining marks can exceed the byte limit while staying under the character limit. The shipping plan reuses this extraction code.
- **Scenario:** An ordinary Hindi PDF comes back as "unavailable" instead of truncated text, and the attempt is logged as a worker failure.
- **Fix:** Truncate by encoded size, leaving headroom for JSON escaping, or return an explicit `outputLimit` status. Add Indic and combining-mark fixtures.
<!-- sources: correctness/tools#2 -->

#### 2.73 App-target orchestration has no unit tests, and UnitTests.swift is an import-only placeholder — Medium

- **Where:** `UnitTests/UnitTests.swift:1` (`SpamWise/AppModelScanning.swift:37`, `SpamWise/AppModelScanning.swift:107`, `SpamWise/AppModelFolders.swift:54`, `SpamWise/AppModelMailReview.swift:6`, `SpamWise/AppModel.swift:181`, `SpamWise/IMAPConnectionModel.swift`)
- **Problem:**
  - None of this app-target logic has unit tests:
    - the seen predicate;
    - per-account failure isolation;
    - cursor and classification ordering;
    - folder training;
    - batch corrections;
    - history maintenance;
    - the optimistic settings queue.
  - It all lives in `@MainActor` code.
  - UnitTests holds only DirectUpdateConfigurationTests and a file with two imports, and the target never runs (§2.11). CLAUDE.md suggests the placeholder may exist for AppIntents linkage.
  - Simple multi-sweep tests would catch several defects in this section (§2.18, §2.20, §2.21).
- **Scenario:** An edit to the seen predicate starts re-classifying already-handled messages on every sweep, or the catch in `scanMailAccounts` swallows CancellationError. No test fails, and SS-01 and SS-06 stay marked verified.
- **Fix:**
  - Move the sweep, folder-plan and selected-batch orchestration into SpamWiseCore behind MailClientAdapter, or extract pure helpers such as `ScanSelection.alreadyHandled`.
  - Cover them with Swift Testing and stub adapters.
  - Test `editSettings` ordering against `refresh()`.
  - Remove the placeholder, or document why it exists.
<!-- sources: todo/spamsieve-a#7, correctness/app-logic#21, conventions/app-logic#10, conventions/tests#4 -->

#### 2.74 The brief's §8 fixture acceptance is met only by hand-written mock verdicts — Medium

- **Where:** `eval/mock-responses.json:1` (`docs/evaluation.md:15`)
- **Problem:** The fixture outcomes (two Inbox, two Junk, one Review) come from verdicts injected by message hash. The check therefore never exercises the instructions, the prompt or the evidence, and the eval state has no history that a gate could use. The only real-backend run, on-device, returned Review for every fixture. The live Haiku run never completed. The docs do label the mock run as a plumbing check, but the brief's criterion is not tracked anywhere as unmet.
- **Scenario:** A regression in `PromptBuilder.instructions` or in evidence encoding, such as §2.62, leaves the fixture check passing.
- **Fix:** Mark the criterion as unmet in TODO.md. Run the five fixtures once against Claude within the ledger and record the labels. Seed history for the order-confirmation sender. Keep the mock run labelled as a plumbing check.
<!-- sources: gap/brief-conformance#7 -->

#### 2.75 Always-on prompt caching pays the cache-write premium on every unique message, recorded at the base rate — Low

- **Where:** `.build/053e029e-a477-4600-94f0-b8d53af1b4d7/swiftpm/checkouts/ClaudeForFoundationModels/Sources/ClaudeForFoundationModels/RequestBuilder.swift:134` (`…/ClaudeForFoundationModels/EventTranslator.swift:330`, `SpamWiseCore/Sources/Classifier/Types.swift:33`)
- **Problem:** The pinned provider always sends top-level `cache_control`, so the cache breakpoint lands after the unique message. Prompts over 512 tokens are written to the cache at 1.25 times the input price and never read back. Cache-creation tokens are folded into input and priced at the base rate.
- **Scenario:** A prompt of about 1,500 tokens is billed at 1.25×, so the monthly estimate undercounts input cost by up to 20%. The reservation ledger still over-reserves, so no ceiling is breached.
- **Fix:** Ask upstream for a way to disable automatic caching, or to place the breakpoint after the fixed prefix. Until then, price creation tokens at 1.25× if the library exposes them, or mark the cost as approximate.
<!-- sources: gap/dependency-trust-path#4 -->

#### 2.76 SemanticVersion ordering ignores the prerelease suffix and contradicts `==` — Low

- **Where:** `/Users/tmorgan/Repositories/Libraries/GitHubUpdateChecker/Sources/GitHubReleaseDiscovery/SemanticVersion.swift:118` (`SpamWise/DirectUpdateModel.swift:49`)
- **Problem:** `<` compares only major, minor and patch, while the synthesized `==` also compares the prerelease suffix. That violates Comparable, and semver orders a prerelease before its release.
- **Scenario:** Sorting or set membership of suffixed versions gives inconsistent results. A tag such as `v1.4.0-hotfix` published without GitHub's prerelease flag is offered to users as an update, under its suffixed name.
- **Fix:** Implement semver precedence, and have DirectUpdateModel reject versions that carry a suffix.
<!-- sources: gap/dependency-trust-path#6 -->

#### 2.77 Timeouts kill only the Keychain launcher, leaving the paid evaluator running — Low

- **Where:** `Scripts/evaluate-with-keychain.swift:97` (`Scripts/evaluate-with-keychain.swift:89`, `Tools/Preferences/run.py:155`)
- **Problem:** The launcher starts `spamwise-eval` as a child process with the live key in its environment and installs no signal handling. The 90-second timeout in `run.py` kills only the `swift` launcher and raises `TimeoutExpired`.
- **Scenario:** A slow call runs past 90 s. The orphaned evaluator finishes its reserved paid request and writes `report.json` and cache entries that the recorded results don't mention.
- **Fix:** Forward SIGINT and SIGTERM to the child, and terminate it when the launcher exits. Start the launcher in a new session and kill its process group on timeout.
<!-- sources: security/eval-scripts#5, correctness/tools#6 -->

#### 2.78 store-probe reports argument errors as `StoreError.invalidPath` — Low

- **Where:** `Scripts/store-probe.swift:9` (`Scripts/store-probe.swift:16`, `SpamWiseCore/Sources/Store/Store.swift:19`)
- **Problem:** A wrong argument count, or an invalid increment count, throws an error whose documented meaning is "the store path is a directory".
- **Scenario:** `store-probe state.store 5000` fails with the directory message, so the operator goes looking for a filesystem problem.
- **Fix:** Use a small private usage error, or print the usage text and exit 2.
<!-- sources: comments/eval-scripts#12 -->

#### 2.79 Exported statistics encode daily counts as an unlabeled flat array — Low

- **Where:** `SpamWise/ActivityStatisticsView.swift:68` (`SpamWiseCore/Sources/SpamWiseCore/ActivityQuery.swift:56`, `SpamWise/RulesDocument.swift:22`)
- **Problem:** `dailyCounts` is a `[Date: Int]`. JSONEncoder encodes a dictionary with non-String keys as an array that alternates keys and values, and encodes dates as seconds since 2001.
- **Scenario:** Exported JSON shows `[781228800, 3, 781315200, 5]`, which a spreadsheet cannot interpret.
- **Fix:** Export ISO-8601 day keys, or an array of `{day, count}` objects, and set `dateEncodingStrategy = .iso8601`.
<!-- sources: correctness/app-views-main#13 -->

#### 2.80 Preview, Open in Mail and Export raw source always use the Apple Mail adapter — Low

- **Where:** `SpamWise/AppModelMailReview.swift:64` (`SpamWise/AppModelMailReview.swift:60`, `SpamWise/DecisionDetailView.swift:71`, `SpamWise/AppModel.swift:355`)
- **Problem:** `correct()` selects the IMAP adapter for IMAP identities, but preview, open and export do not, and their buttons are always shown.
- **Scenario:** On the IMAP transport, Preview message and Export raw source fail with "The requested message or Mail service is unavailable."
- **Fix:** Route these lookups through the same adapter-selection helper that `correct()` uses, and hide Open in Mail for IMAP records.
<!-- sources: correctness/app-logic#15 -->

#### 2.81 The content rules table keeps a deleted rule selected — Low

- **Where:** `SpamWise/ContentRuleEditorView.swift:36` (`SpamWise/ContentRuleEditorView.swift:79`)
- **Problem:** `remove()` never clears `selection`, and Edit and Remove are disabled only when `selection == nil`, not when no matching rule exists. RuleEditorView avoids both problems.
- **Scenario:** After a removal, Edit opens a blank new-rule form. Clicking Remove again bumps the revision, clears retries and writes another audit entry.
- **Fix:** Derive a `selectedRule` from `rules`, base the button states on it, and clear `selection` after a successful remove.
<!-- sources: correctness/app-views-settings#11, conventions/app-views-settings#4 -->

#### 2.82 The Activity Time column shows only hour and minute — Low

- **Where:** `SpamWise/ContentView.swift:37`
- **Problem:** The log spans many days and has date-range filters, but rows show only `HH:mm`.
- **Scenario:** A user filtering the last 7 days cannot tell which of several "10:42" rows is from yesterday.
- **Fix:** Include the date for records not from today, for example `.dateTime.month(.abbreviated).day().hour().minute()`.
<!-- sources: correctness/app-views-main#6 -->

#### 2.83 Account and Path filters show raw account IDs and internal path tokens — Low

- **Where:** `SpamWise/ContentView.swift:77` (`SpamWise/ActivityStatisticsView.swift:36`)
- **Problem:** The Account pickers list Mail account UUIDs instead of the names in `model.accounts`. The Path picker shows unlocalized internal values such as "gate", "model" and "selection".
- **Scenario:** A user with iCloud and Google accounts sees two 36-character UUIDs and cannot tell which is which. In Spanish, the path entries appear as English code identifiers.
- **Fix:** Map account IDs to display names, falling back to the ID, and map paths to localized titles, as `ActionOutcome.localizedTitle` already does for outcomes.
<!-- sources: correctness/app-views-main#7 -->

#### 2.84 Monthly cost in the footer and statistics rounds sub-cent spend to $0.00 — Low

- **Where:** `SpamWise/ContentView.swift:168` (`SpamWise/ActivityStatisticsView.swift:52`, `SpamWise/DecisionDetailView.swift:204`)
- **Problem:** A typical Haiku call costs about $0.0001. The footer and statistics use the default two-decimal currency format, while the detail view shows six decimals.
- **Scenario:** After 30 paid classifications (about $0.004), the footer still reads "Month: $0.00".
- **Fix:** Use significant digits, for example `.precision(.significantDigits(2...4))`, or show "< $0.01".
<!-- sources: correctness/app-views-main#12 -->

#### 2.85 The reviewed corpus can hold two labels with the same identifier — Low

- **Where:** `SpamWise/CorpusView.swift:32` (`SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:32`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:138`)
- **Problem:** Corrections dedupe labels by content hash, while imports dedupe by semantic `sampleID`. A correction saved with retention and learning both off, followed by importing the same message's raw source, leaves two rows with the same `id`.
- **Scenario:** Selecting one row selects both, counts are inflated, and Relabel or Forget acts on both at once.
- **Fix:** Use the same dedupe key in both paths, or give each stored label a unique id.
<!-- sources: correctness/app-views-main#11 -->

#### 2.86 The undo dialog appears on every row and quotes snapshot totals — Low

- **Where:** `SpamWise/DecisionDetailView.swift:61` (`SpamWise/DecisionDetailView.swift:43`, `SpamWiseCore/Sources/SpamWiseCore/CorrectionUndo.swift:10`)
- **Problem:** The undo button appears in every record's inspector and never names the correction it reverts. "Restores N rules and M examples" counts the whole snapshot, not the changes.
- **Scenario:** A user with 120 rules corrects message A, then opens message B and sees "Restores 120 rules and 200 examples". The undo actually reverts a single sender rule from A's correction.
- **Fix:** Show the button only for the record matching `undo.recordID`, or name the sender in the dialog, and describe the actual change.
<!-- sources: correctness/app-views-main#8 -->

#### 2.87 The inspector shows uncalibrated model confidence as a percentage — Low

- **Where:** `SpamWise/DecisionDetailView.swift:193`
- **Problem:** The confidence is formatted with `.percent`, which reads as a probability, although Help says it is not calibrated and describes thresholds as integers ("at least 99").
- **Scenario:** A user sees "Confidence 99%" on a good message that was junked, concludes the filter is almost certainly right, and hesitates to correct it.
- **Fix:** Show "95 of 100 (uncalibrated)" to match the Help wording.
<!-- sources: gap/brief-conformance#9 -->

#### 2.88 An IMAP connection load failure silently creates a new account ID — Low

- **Where:** `SpamWise/IMAPConnectionModel.swift:21` (`SpamWise/IMAPConnectionModel.swift:14`)
- **Problem:** `load()` swallows every error, including transient lock contention, and keeps a freshly generated `imap:UUID` ID. Saving then creates a different account, with a new Keychain service, validation and cursor.
- **Scenario:** The user saves while the extension holds the lock. The credential lookup fails, and re-entering the password removes action permission from the previously validated account.
- **Fix:** Distinguish "no saved connection" from a load failure, show the error, and disable Save until a load succeeds.
<!-- sources: correctness/app-logic#17 -->

#### 2.89 Account settings never show whether an API key is stored — Low

- **Where:** `SpamWise/KeyEntryView.swift:9` (`SpamWise/AppModel.swift:12`, `SpamWise/AppModelCredentials.swift:17`, `SpamWise/ModelSettingsView.swift:62`)
- **Problem:** Key status exists only in memory after verification. The pane shows no masked indicator and has no Remove action, contrary to brief §6.
- **Scenario:** After a relaunch, the user can't tell whether a key is saved and pastes it again, which triggers another paid verification. A user who wants to stop paid use cannot delete the key from the app.
- **Fix:** Check Keychain for an existing item when the pane appears, show a masked suffix with Replace and Remove, and persist the last verification result.
<!-- sources: gap/brief-conformance#5 -->

#### 2.90 Notifications are suppressed while SpamWise is frontmost, yet their claims are consumed — Low

- **Where:** `SpamWise/LocalNotifications.swift:5` (`SpamWise/LocalNotifications.swift:40`)
- **Problem:** The delegate does not implement `willPresent`, so macOS hides banners while the app is active. `NotificationPlanning.claim` has already recorded the batch by then.
- **Scenario:** The user has Activity focused when a summary of three Review messages is due. No banner appears, and those three messages are excluded from every later notification.
- **Fix:** Implement `willPresent` and return `[.banner, .list]`.
<!-- sources: correctness/app-logic#16 -->

#### 2.91 Notification delivery re-checks settings after claiming, so a claimed batch can be dropped — Low

- **Where:** `SpamWise/LocalNotifications.swift:40` (`SpamWiseCore/Sources/SpamWiseCore/NotificationPlanning.swift:47`)
- **Problem:** After the at-most-once claim is written, `deliver` repeats the paused, dry-run and quiet-hours checks that `claim` already made.
- **Scenario:** The claim happens at 21:59:59.9 and quiet hours start at 22:00. The batch is marked as announced but never delivered.
- **Fix:** Remove the guard after the claim, or have `claim` return the options it evaluated.
<!-- sources: conventions/app-logic#19 -->

#### 2.92 Status texts claim activity that is not happening — Low

- **Where:** `SpamWise/MailMenuView.swift:9` (`SpamWise/OnboardingView.swift:38`)
- **Problem:** The menu bar says "SpamWise is running" before onboarding is complete, when no scans run. The setup account step always labels its button "Continue offline", even after the key was verified.
- **Scenario:** A user who has not finished setup believes their mail is being filtered.
- **Fix:** Use the same mode text as ActivityStatusView, plus a "Setup incomplete" state, and label the button "Continue" once a key is verified.
<!-- sources: correctness/app-views-main#14 -->

#### 2.94 Quiet-hours labels ignore locale and the 12/24-hour setting — Low

- **Where:** `SpamWise/NotificationSettingsView.swift:25` (`SpamWise/NotificationSettingsView.swift:28`)
- **Problem:** The labels are built as `$0.formatted() + ":00"`.
- **Scenario:** A US user with a 12-hour clock sees "13:00 … 23:00".
- **Fix:** Build a Date for each hour and format it with `.dateTime.hour()`.
<!-- sources: correctness/app-views-settings#14 -->

#### 2.95 The policy length limit is defined three times with conflicting values — Low

- **Where:** `SpamWise/PolicyView.swift:5` (`SpamWiseCore/Sources/Classifier/ClassificationLimits.swift:10`, `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:26`)
- **Problem:** The UI limit and the classifier limit are both 4,000, and backup restore accepts 8,000. Nothing ties the three together.
- **Scenario:** A restored 6,000-character policy disables Save in the editor, and the classifier silently drops the last 2,000 characters. Normal use is unlikely to produce one.
- **Fix:** Expose a single public constant from SpamWiseCore and use it in all three places.
<!-- sources: conventions/app-views-main#5 -->

#### 2.96 Saving Preferences unchanged turns the default policy into a custom one — Low

- **Where:** `SpamWise/PolicyView.swift:45` (`SpamWise/PolicyView.swift:39`)
- **Problem:** The editor swaps the core default for its localized text, which differs even in English (curly versus straight apostrophes). Save stores that text as a custom policy and goes through `editSettings`, which bumps the revision and clears retries and undo. The editor text is seeded only in `onAppear`.
- **Scenario:** A user presses ⌘S out of habit. The policy stops tracking the default, and pending retries and Undo disappear.
- **Fix:** Disable Save while the text is unchanged, map the localized default back to `PromptBuilder.defaultPolicy`, and reseed the text once state loads.
<!-- sources: correctness/app-views-main#15 -->

#### 2.97 UI-testing mode reads, and can write, the production shared Keychain — Low

- **Where:** `SpamWise/SpamhausSettingsView.swift:62` (`SpamWise/SpamhausSettingsView.swift:70`, `UITests/EvidenceScreen.swift:65`, `SpamWise/AppModelSettings.swift:20`, `SpamWise/AppModelCredentials.swift:22`, `SpamWise/AppModelIMAP.swift:34`)
- **Problem:** `--ui-testing` isolates preferences and the store, but not credentials. The Spamhaus settings screen that UI tests open reads the real item, and its Save button would overwrite it.
- **Scenario:** A future test that types a fixture key and clicks Save replaces the user's real Spamhaus key.
- **Fix:** Inject a credential store, using an in-memory or test-only service when `uiTesting` is set.
<!-- sources: correctness/tests#6 -->

#### 2.98 The Apple on-device path rejects verdicts with reasons longer than 240 characters — Low

- **Where:** `SpamWiseCore/Sources/Classifier/AppleClassifier.swift:57` (`SpamWiseCore/Sources/Classifier/AppleClassifier.swift:119`, `SpamWiseCore/Sources/Classifier/Types.swift:63`)
- **Problem:** The 240-character limit appears only in the `@Guide` description. A longer reason throws the non-retryable `invalidOutput`, while `Verdict.init` already truncates reasons and the Claude path relies on that.
- **Scenario:** A valid Junk-97 verdict with a 300-character reason is recorded as "unclassified: invalidOutput".
- **Fix:** Truncate through `Verdict.init` instead of rejecting the verdict.
<!-- sources: correctness/core-classifier-learning#12 -->

#### 2.99 Every Claude classification builds a new executor and URLSession — Low

- **Where:** `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:49` (`SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:53`)
- **Problem:** SpamWise passes the per-message remaining time as `timeout`, which is part of the executor's Hashable configuration. That defeats executor reuse, so every request pays a fresh TLS handshake and leaves an uninvalidated session. Earlier key values stay in cached configurations.
- **Scenario:** A long-running app or daemon accumulates sessions, and every request pays the handshake cost.
- **Fix:** Pass a constant timeout and keep enforcing the per-message deadline with `withDeadline`.
<!-- sources: gap/dependency-trust-path#2 -->

#### 2.100 HTTP 400 is always mapped to a configuration error — Low

- **Where:** `SpamWiseCore/Sources/Classifier/ModelHTTPClient.swift:52`
- **Problem:** Gemini reports an invalid key as HTTP 400, and OpenAI reports context overflow as 400, yet `contextExceeded` is never produced.
- **Scenario:** A user with a mistyped Gemini key is told the model configuration is unavailable, not that the key is wrong.
- **Fix:** Decode the provider's error body for 400 responses and map it to a credential or context error.
<!-- sources: correctness/core-classifier-learning#13 -->

#### 2.101 The Claude Sonnet 5.5 cache-read rate is recorded as $0.10/M instead of $0.20/M — Low

- **Where:** `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:31`
- **Problem:** The Sonnet cached rate is half the current price. Haiku 5.5 and Opus 5.5 are correct.
- **Scenario:** Sonnet runs that read from the cache under-report their estimated cost.
- **Fix:** Set the cached rate to 0.20 and re-verify the source and date.
<!-- sources: correctness/core-classifier-learning#10 -->

#### 2.102 The fixed instructions don't say how to weigh blocklist, Rspamd, Bayes or learned-margin evidence — Low

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:239` (`SpamWiseCore/Sources/Signals/Evidence.swift:46`)
- **Problem:** Brief §3.2 requires the relative importance of evidence to be conveyed in plain language. The newer fields reach the prompt as raw numbers and strings with no stated meaning, and they fall under the "untrusted" framing.
- **Scenario:** A Spamhaus DBL listing or a `bayesLogOdds` of 4.1 is ignored or misread, so turning these features on changes decisions unpredictably.
- **Fix:** Add one plain-language line per signal and update `schemaID` and the cache identity.
<!-- sources: gap/brief-conformance#8 -->

#### 2.103 Attachment and OCR text appended after the body is cut off by prompt truncation — Low

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:299` (`SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:51`)
- **Problem:** The extracted text is appended to the end of `message.text`, and the prompt keeps only the first 6,000 characters.
- **Scenario:** Image spam with 7,000 characters of filler never shows the model its OCR text, "Claim your $500 gift card".
- **Fix:** Send attachment and OCR text as a separate, separately bounded field, or reserve part of the budget for it.
<!-- sources: correctness/core-classifier-learning#9 -->

#### 2.104 Reply-attribution stripping recognizes only English attribution lines — Low

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:314`
- **Problem:** The app ships Spanish and French, but only "On … wrote:" is detected. Lines such as "El … escribió:" and "Le … a écrit :" are kept.
- **Scenario:** Quoted history in a localized reply, without ">" prefixes, uses up the body budget.
- **Fix:** Use a small table of localized attribution patterns behind a named helper. Keep the abuse limits from §2.36.
<!-- sources: comments/core-classifier-learning#17 -->

#### 2.105 Comparison manifests accept a missing label as an abstention and reject fractional-second timestamps — Low

- **Where:** `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:173` (`SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:51`)
- **Problem:** A synthesized optional `label` decodes a missing or misspelled key as nil. The default `ISO8601DateFormatter` rejects `…00.123Z`.
- **Scenario:** A run whose label key is spelled `Label` is scored as all abstentions. A valid manifest gets the generic campaign-disjoint error.
- **Fix:** Require the key to be present (it may still be null), and parse dates with fractional seconds allowed.
<!-- sources: correctness/eval-scripts#9 -->

#### 2.106 Threat-report errors reuse comparison and classification diagnostics — Low

- **Where:** `SpamWiseCore/Sources/Evaluation/ThreatMetrics.swift:90` (`SpamWiseCore/Sources/Evaluation/ThreatMetrics.swift:92`, `SpamWiseCore/Sources/SpamWiseEval/main.swift:31`, `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:186`)
- **Problem:** Duplicate IDs, unknown objectives and oversized files all throw `ComparisonError.invalidManifest`, which prints advice about frozen campaign-disjoint runs. Invalid assessments print "Classification is unavailable. Mail was left unchanged."
- **Scenario:** A user with two rows sharing one sample ID is told to fix campaign-disjoint paired results.
- **Fix:** Add a dedicated `ThreatReportError` with case-specific failure reasons and update the test.
<!-- sources: correctness/eval-scripts#6, comments/eval-scripts#1 -->

#### 2.107 Learning models are retrained from scratch for every message — Low

- **Where:** `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:71` (`SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:48`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:139`)
- **Problem:** `estimate` refits the logistic model (120 iterations over up to 2,000 samples) and rebuilds the Bayes tables inside the classification budget. `admitPrediction` repeats the work while holding the store lock. This only applies when the opt-in features are enabled.
- **Scenario:** With a mature corpus, an initial Inbox sweep spends tens to hundreds of milliseconds per message retraining, which also lengthens lock hold times.
- **Fix:** Cache the fitted weights on LearningState, invalidate the cache when samples change, and run the admission checks outside the transaction.
<!-- sources: conventions/core-classifier-learning#16 -->

#### 2.108 ScriptValue decoding is lenient and truncates 64-bit integers — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:22` (`SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:126`, `SpamWiseCore/Sources/MailIntegration/MailPage.swift:39`)
- **Problem:** `typeSInt64` is decoded through `int32Value`, unknown descriptors become empty strings, and `envelope(_:)` accepts an empty source, which `decodePage` rejects. Observed local IDs (about 63,000) are far below the Int32 limit.
- **Scenario:** A `missing value` source becomes an empty envelope that can reach correction. A future 64-bit ID would resolve to the wrong message.
- **Fix:** Throw on unsupported descriptor types, read `typeSInt64` as Int64, and reject empty sources.
<!-- sources: architecture#29, concurrency#16, conventions/mail-integration#14 -->

#### 2.109 Mail export combines `.atomic` with `.withoutOverwriting` — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:360` (`docs/evaluation.md:95`)
- **Problem:** Apple documents these two options as incompatible. File names are deterministic, so exporting again into the same directory either overwrites files or aborts partway through. Neither matches the documented "never overwritten".
- **Scenario:** A re-export silently replaces files the user has already reviewed, or stops with a generic error and no count.
- **Fix:** Create files with exclusive semantics (`O_CREAT|O_EXCL`), skip and count existing files, and test a double export.
<!-- sources: correctness/eval-scripts#10 -->

#### 2.110 The IMAP sweep cursor is saved before the page is processed — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:92` (`SpamWiseCore/Sources/SpamWiseDaemon/main.swift:100`, `SpamWise/AppModelScanning.swift:86`)
- **Problem:** The cursor advances before any message on the page is classified. The Apple Mail path commits only after classification.
- **Scenario:** The user pauses after 3 of 20 messages, and messages 4 to 20 wait for the next full wrap of the Inbox.
- **Fix:** Return the proposed cursor and commit it after the batch is processed.
<!-- sources: correctness/mail-integration#10 -->

#### 2.111 IMAP fetch requires the literal length to equal RFC822.SIZE exactly — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:337` (`SpamWiseCore/Sources/MailIntegration/IMAPPaging.swift:37`, `SpamWiseCore/Sources/MailIntegration/IMAPProtocol.swift:56`, `SpamWiseCore/Sources/MailIntegration/IMAPProtocol.swift:199`)
- **Problem:** Some servers report an approximate RFC822.SIZE. A mismatch on any one message fails the whole page or lookup. The tokenizer also rejects non-ASCII resp-text, and only OAUTHBEARER is supported. The failure is safe, but the IMAP route becomes unusable on those servers.
- **Scenario:** On a server whose sizes are off by a few bytes, every page throws `malformedResponse`, so nothing is ever classified.
- **Fix:** Treat the literal length as authoritative and cap it at 2 MB, skip only the offending message, treat resp-text as opaque, and consider adding XOAUTH2.
<!-- sources: security/mail-integration#11, correctness/mail-integration#16 -->

#### 2.112 Embedded-image OCR is all-or-nothing — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:86` (`SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:33`, `SpamWiseCore/Sources/MessageModel/EmbeddedImageOCR.swift:36`)
- **Problem:** A fifth image, an oversized image or one with a mislabelled type throws out of `extract`, and the OCR wrapper discards the images that had already been accepted.
- **Scenario:** Image-only spam adds four 1×1 GIF spacers, and the classifier sees an empty body.
- **Fix:** Skip excess or invalid images, recording a coverage finding, and keep scanning.
<!-- sources: correctness/core-parsing-signals#11 -->

#### 2.113 Headers that mix encoded words with raw UTF-8 decode to mojibake — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:147`
- **Problem:** The value is reinterpreted as UTF-8 only when it contains no encoded words.
- **Scenario:** `=?utf-8?q?Re:?= café` becomes "Re: cafÃ©", which shows mojibake in the UI and defeats subject rules.
- **Fix:** Reinterpret the unencoded segments between encoded words as UTF-8, falling back to Latin-1, and add a mixed-header fixture.
<!-- sources: comments/core-parsing-signals#4 -->

#### 2.114 HTML-to-text conversion splits words at inline tags and decodes few entities — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:167` (`SpamWiseCore/Sources/MessageModel/MIMEParser.swift:168`)
- **Problem:** Every tag becomes a space, and only six named entities are decoded. `&amp;` is decoded before numeric entities, so `&amp;#60;` comes out as "<". Soft hyphens and zero-width characters are not stripped.
- **Scenario:** `fr<span></span>ee g&#173;ift` does not match the rule "free gift".
- **Fix:** Drop inline tags without inserting a separator, use a full entity table in the correct order, and strip default-ignorable code points.
<!-- sources: correctness/core-parsing-signals#13 -->

#### 2.115 `withResourceDeadline` still starts the operation when the caller is already cancelled — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:55` (`SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:54`)
- **Problem:** `install` resumes the continuation at once, but the detached work task is still created and is cancelled only later, in `register`. Its `checkCancellation()` can pass in that window.
- **Scenario:** A cancelled sweep can still start a paid request, a process launch or a Spamhaus query whose result is thrown away.
- **Fix:** Have `install` report whether the race has already finished, and skip creating the task when it has.
<!-- sources: concurrency#11, correctness/core-parsing-signals#14 -->

#### 2.116 Contacts enumeration blocks a cooperative-pool thread — Low

- **Where:** `SpamWiseCore/Sources/Signals/Evidence.swift:123`
- **Problem:** `ContactsLookup` is a default-executor actor that calls the synchronous `enumerateContacts`. It runs hourly and at the start of each scan.
- **Scenario:** On a 20,000-contact address book, one of the few cooperative threads is held for seconds.
- **Fix:** Give the actor a dedicated serial executor, or bridge the call to a dispatch queue through a continuation.
<!-- sources: concurrency#10 -->

#### 2.117 The RDAP fetcher's "response size limit" is applied only after the full download — Low

- **Where:** `SpamWiseCore/Sources/Signals/RDAP.swift:9` (`SpamWiseCore/Sources/Signals/RDAP.swift:18`, `SpamWiseCore/Sources/Signals/RDAP.swift:20`)
- **Problem:** `URLSession.shared.data(for:)` buffers the whole body before the 2 MB check runs, and the shared session's cookies and cache are in effect. The Rspamd and Spamhaus transports stream with a byte cap.
- **Scenario:** A misbehaving RDAP endpoint streams a large body, which is fully buffered and only then rejected.
- **Fix:** Stream with `bytes(for:)` on an ephemeral session and stop at the cap, or reword the doc comment.
<!-- sources: comments/core-parsing-signals#20 -->

#### 2.118 RDAPLookup duplicates fetches across awaits and evicts its cache by name — Low

- **Where:** `SpamWiseCore/Sources/Signals/RDAP.swift:61` (`SpamWiseCore/Sources/Signals/RDAP.swift:88`, `SpamWiseCore/Sources/Signals/RDAP.swift:96`)
- **Problem:** State is checked before an `await` and assigned after it, so concurrent misses each download the IANA bootstrap file and the domain record. Bootstrap failures are not negatively cached. A full cache evicts the alphabetically first key, and the whole file is rewritten on every lookup.
- **Scenario:** Once the cache is full, a frequent correspondent such as apple.com keeps being evicted and looked up again.
- **Fix:** Share in-flight Tasks, briefly cache bootstrap failures, evict by `recordedAt`, and debounce writes.
<!-- sources: concurrency#12, correctness/core-parsing-signals#15, conventions/core-parsing-signals#21 -->

#### 2.119 Rspamd evidence keeps the 20 alphabetically first symbols and drops the score — Low

- **Where:** `SpamWiseCore/Sources/Signals/RspamdLookup.swift:60`
- **Problem:** Symbols are sorted by name and capped at 20. The aggregate `score`, `required_score` and `action` are not decoded at all.
- **Scenario:** URIBL_BLACK (7.5) is dropped in favor of zero-weight `ARC_NA`-style symbols.
- **Fix:** Decode the top-level score and action, and order symbols by descending absolute score.
<!-- sources: correctness/core-parsing-signals#10 -->

#### 2.120 The loopback Rspamd HTTP transport's limits have no automated test — Low

- **Where:** `SpamWiseCore/Sources/Signals/RspamdLoopbackHTTP.swift:25` (`SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift:155`, `Scripts/rspamd-runtime-check.sh:3`)
- **Problem:** The response-URL check, the 64 KiB streaming guard, the deadline and the redirect/auth handling are checked only by a manual signed harness that needs Rspamd built from source. The Spamhaus HTTPS transport, by contrast, has URLProtocol package tests.
- **Scenario:** A refactor drops the `response.url == endpoint` check, and package tests stay green.
- **Fix:** Add URLProtocol-stub tests for redirect, oversized, non-200 and timeout cases.
<!-- sources: todo/roadmap#10 -->

#### 2.121 Automation request claims are never pruned, so automation fails permanently after 10,000 requests — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/AutomationRequest.swift:52` (`SpamWiseCore/Sources/SpamWiseCore/AutomationRequest.swift:25`)
- **Problem:** Every Preview or Correct intent stores a permanent claim with its reply, and nothing removes old ones. At 10,000 claims every request throws a generic "unavailable" error. A claim left without a reply refuses replay forever.
- **Scenario:** A Shortcut that runs 30 times a day starts failing after about 11 months, with no reset path short of deleting the data container.
- **Fix:** Timestamp claims, expire completed ones after a window such as 30 days, and use a dedicated capacity error.
<!-- sources: todo/spamsieve-b#7, security/core-pipeline-store#11, security/app-logic#9, correctness/core-pipeline-store#18 -->

#### 2.122 CompletionOnce uses `@unchecked Sendable`, and the MailKit watchdog is never cancelled — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/CompletionOnce.swift:6` (`MailExtension/MessageActionHandler.swift:47`, `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:16`, `SpamWiseCore/Sources/MailIntegration/IMAPTransport.swift:130`)
- **Problem:** The public generic stores a callback that is not `@Sendable` behind an NSLock, with an unconstrained `Value`, while the rest of the code uses `Mutex` for the same pattern (four separate once-latches exist). The watchdog Task always sleeps the full 9 s. The current implementation is correct.
- **Scenario:** A future caller passes a non-Sendable value across threads without any diagnostic, and a burst of callbacks leaves one sleeping task per message.
- **Fix:** Constrain `Value: Sendable` and store the callback in a `Mutex`, or merge the latches into one checked utility. Race the work against the watchdog in a task group and cancel the loser.
<!-- sources: architecture#28, concurrency#8, conventions/core-pipeline-store#13, conventions/mail-integration#17 -->

#### 2.123 Notifications can be enabled in dry run but never fire, with no indication — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/NotificationPlanning.swift:49` (`SpamWiseCore/Sources/SpamWiseCore/NotificationPlanning.swift:58`, `SpamWise/NotificationSettingsView.swift:13`)
- **Problem:** Planning returns nil whenever dry run is on, which is the default, yet the settings let the user enable notifications and grant permission.
- **Scenario:** A new user waits all week for Review summaries during their dry-run trial, and none arrive.
- **Fix:** Send count-only previews of dry-run Review decisions, or annotate the toggle while dry run is on.
<!-- sources: todo/spamsieve-b#14 -->

#### 2.124 The envelope entry point labels every failure as "message parsing failed" — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:72` (`SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:35`)
- **Problem:** One catch block covers MIME parsing, the state load and document inspection, and it records sender "Unknown" with revision 0.
- **Scenario:** Lock contention shows up as a parse failure on a valid message, and Mark as Junk on that row fails.
- **Fix:** Separate the parse step from the state load, map errors the way the message-level `process` does, and carry the parsed sender forward.
<!-- sources: correctness/core-pipeline-store#15 -->

#### 2.125 Paid verdicts can be discarded after the call, uncosted, and paid for again on retry — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:116` (`SpamWiseCore/Sources/SpamWiseCore/State.swift:232`)
- **Problem:** The deadline check runs after `classify` has returned a paid verdict. The failure record carries no usage, while the budget reservation has already been consumed.
- **Scenario:** A response at 14.8 s, plus 0.3 s of bookkeeping, becomes "unclassified: timeout". The retry pays again.
- **Fix:** Don't apply the overall deadline to bookkeeping that happens after the verdict, and record measured usage on failure records.
<!-- sources: correctness/core-pipeline-store#13 -->

#### 2.126 `RetryJob.dryRun` is always false — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:192` (`SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:213`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:130`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:248`)
- **Problem:** `scheduleRetry` returns before creating any dry-run job, so the persisted field, its documentation and the `forceDryRun: job.dryRun` plumbing are all dead.
- **Scenario:** A reader assumes preview retries are queued and honored, when they never are.
- **Fix:** Remove the field, or document it as always false, and pass `false` explicitly.
<!-- sources: comments/core-pipeline-store#15 -->

#### 2.127 Retries drop the auxiliary findings from the first attempt — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:244` (`SpamWiseCore/Sources/SpamWiseCore/State.swift:115`)
- **Problem:** `RetryJob` does not persist Rspamd or attachment-coverage findings.
- **Scenario:** Rspamd scored a message 12.0, but the rate-limited retry classifies it without that finding and may reach a different verdict.
- **Fix:** Store bounded `auxiliaryFindings` on RetryJob and pass them through on retry.
<!-- sources: correctness/core-pipeline-store#16 -->

#### 2.128 The returned record's read status diverges from persisted state — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:324` (`SpamWiseCore/Sources/SpamWiseCore/PipelineReadStatus.swift:10`)
- **Problem:** If the mark-as-read claim or its completion throws, dispatch returns `.requested` regardless of what was actually saved.
- **Scenario:** An App Intent reports mark-as-read as requested, but a reload shows no read-status outcome at all.
- **Fix:** Report `.requested` only after the claim transaction has committed.
<!-- sources: correctness/core-pipeline-store#17 -->

#### 2.129 Previews and discarded classifications still change learning state and content-rule statistics — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:77` (`SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:110`)
- **Problem:** Hit counters and self-training ignore `forceDryRun` and run before the decision is persisted.
- **Scenario:** Previewing 20 messages three times reports 60 rule wins, and timed-out runs add training samples.
- **Fix:** Defer statistics and training until the decision has been persisted, and skip them for previews.
<!-- sources: correctness/core-pipeline-store#14 -->

#### 2.130 Independent network enrichments run sequentially — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:159`
- **Problem:** The Spamhaus lookup waits for the RDAP lookup, so the model gets less of the per-message budget.
- **Scenario:** A slow RDAP response uses up to 3 s before Spamhaus even starts, and more messages time out.
- **Fix:** Run both lookups concurrently under the shared deadline, using a task group or `async let`.
<!-- sources: conventions/core-pipeline-store#22 -->

#### 2.131 The pipeline's Spamhaus lookup cannot be injected for tests — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:177` (`SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:117`)
- **Problem:** The lookup is built inline with the live Keychain reader and live transports. The local-only privacy test therefore cannot stub it.
- **Scenario:** If the `localOnly` guard regressed, `swift test` would read the developer's Spamhaus key and query Spamhaus before the test failed.
- **Fix:** Inject a lookup factory, as `rdap` already is, and have the test supply a counting stub.
<!-- sources: correctness/tests#11 -->

#### 2.132 The correction "gist" is the prior decision's reason, often boilerplate — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:59`
- **Problem:** Gate, content-rule, pause and unclassified reasons are stored as the "message summary" and quoted to the model as examples.
- **Scenario:** A Junk example reaches the model with the gist "unclassified: timeout", using an example slot and adding noise.
- **Fix:** Derive the gist from bounded message text, as corpus import does, or store nil.
<!-- sources: correctness/core-classifier-learning#11 -->

#### 2.133 Persisted `AppState.schemaVersion` is never read — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:163`
- **Problem:** The version is written but never compared on decode, so nothing can detect a format change. Periphery flags it as unused.
- **Scenario:** A future incompatible change cannot be gated on the stored version.
- **Fix:** Check the version after decoding, or remove the field and rely on optional fields deliberately.
<!-- sources: tooling#6 -->

#### 2.134 Cost-ledger month keys and digest week keys depend on the user's current calendar — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:215` (`SpamWiseCore/Sources/SpamWiseCore/AdvancedSettings.swift:150`)
- **Problem:** The keys use `Calendar.current`, a `?? 0` sentinel and no zero padding.
- **Scenario:** Switching to the Buddhist calendar mid-month resets the month-to-date cost to $0.
- **Fix:** Use a fixed Gregorian calendar, or a typed `YearMonth`, formatted with zero padding.
<!-- sources: conventions/core-pipeline-store#20 -->

#### 2.135 The training-folder observation cap throws on every page once it is exceeded — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/TrainingFolders.swift:49`
- **Problem:** The check throws before observations are saved or reset, so a traversal of more than 5,000 messages can never complete.
- **Scenario:** A 6,000-message training folder reports an "unavailable" error on every sweep until it is emptied by hand.
- **Fix:** Reset observations, or mark the traversal incomplete, when the cap is reached, and show a specific status.
<!-- sources: correctness/core-pipeline-store#19 -->

#### 2.136 Daemon failure output discards the sanitized error category — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:42` (`SpamWiseCore/Sources/SpamWiseDaemon/main.swift:39`)
- **Problem:** Every failure prints the same "check settings and credentials" message, even though IMAPError and IntegrationError are designed to be safe to print.
- **Scenario:** `--validate` fails because the server's Junk role is ambiguous, but the user is told to check credentials.
- **Fix:** Print the `failureReason` for the module's own error types.
<!-- sources: comments/mail-integration#18 -->

#### 2.137 The daemon overwrites the configuration's `allowsActions` with the CLI flag — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:62` (`SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:113`)
- **Problem:** The documented opt-in field in the JSON configuration is replaced unconditionally by `--actions`.
- **Scenario:** A configuration that sets `allowsActions: false` as a safety lock still moves mail when a wrapper script passes `--actions`.
- **Fix:** Require both: `configuration.account.allowsActions && options.actions`.
<!-- sources: correctness/mail-integration#15 -->

#### 2.138 The domain-registration lookup setting is ignored outside the app — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:88` (`MailExtension/MessageActionHandler.swift:35`, `SpamWiseCore/Sources/SpamWiseEval/main.swift:161`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:159`)
- **Problem:** Only AppModel passes an `RDAPLookup`. The daemon, the extension and the eval CLI build Pipeline without one, so `domainAgeDays` is always nil there. The eval report does disclose this.
- **Scenario:** An IMAP daemon user enables domain age and never gets it, and evaluation cannot measure the configuration users opt into.
- **Fix:** Wire an RDAPLookup with an explicit cache path into the daemon and the eval CLI, or fail loudly when the setting is on but no lookup is available.
<!-- sources: correctness/core-parsing-signals#12, gap/brief-conformance#11 -->

#### 2.139 The CLI's argument guards and report logic are untested — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/Options.swift:66` (`SpamWiseCore/Sources/SpamWiseEval/RunReport.swift:32`, `SpamWiseCore/Sources/SpamWiseEval/RunReport.swift:59`)
- **Problem:** The ban on `--state` for held-out runs, the threshold recomputation and the cost estimate live in an executable target that no test imports.
- **Scenario:** The guard regresses, labels leak into a held-out evaluation, and no test fails.
- **Fix:** Move the pure parts into the Evaluation library and extend EvaluationTests.
<!-- sources: conventions/eval-scripts#5 -->

#### 2.140 Invalid price arguments are rejected only after every paid call — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/RunReport.swift:60` (`SpamWiseCore/Sources/SpamWiseEval/main.swift:174`)
- **Problem:** Price values are parsed in `RunReport.init`, after classification has finished.
- **Scenario:** `--input-price 2,0` spends money on every call and then writes no report.
- **Fix:** Parse and validate all values in `Options.init`.
<!-- sources: correctness/eval-scripts#5 -->

#### 2.142 Corpus runs with `--state` train on the model's own predictions and can leak labels into prompts — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/main.swift:149` (`SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:77`)
- **Problem:** The snapshot's Bayes and learned-weight flags, its learning state and its corrections are kept. Predictions are admitted into training during the run.
- **Scenario:** Renaming one fixture file changes the evidence sent for other messages, and with it their labels.
- **Fix:** Freeze learning during evaluation, or reject snapshots with learning enabled. Strip corrections that match corpus messages.
<!-- sources: correctness/eval-scripts#4 -->

#### 2.143 Symlinked or non-regular corpus files are reported as exceeding 2 MB — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/main.swift:234` (`SpamWiseCore/Sources/SpamWiseEval/Options.swift:110`)
- **Problem:** Any file for which `isRegularFile` is false throws `oversizedFile`, and the run aborts.
- **Scenario:** A corpus built from symlinks into a mail archive fails at once with "exceeds the 2 MB parser budget".
- **Fix:** Resolve symlinks first, or use a distinct error that names the file.
<!-- sources: correctness/eval-scripts#7 -->

#### 2.144 Store runs container creation and full-state JSON round trips on the cooperative pool — Low

- **Where:** `SpamWiseCore/Sources/Store/Store.swift:103` (`SpamWise/AppModelScanning.swift:126`, `SpamWise/AppModelScanning.swift:136`)
- **Problem:** Store is a default-executor actor. It builds a new ModelContainer and decodes and re-encodes the whole AppState for every operation, roughly 10 to 12 times per message.
- **Scenario:** A 20-message sweep performs more than 200 full-state round trips, which ties up cooperative threads and lengthens lock hold times.
- **Fix:** Give Store a dedicated serial executor, keep one container per Store, and remove the redundant per-message load.
<!-- sources: concurrency#6 -->

#### 2.145 Temporary SwiftData stores created by tests are never removed — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionFixtures.swift:32` (`SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:390`)
- **Problem:** About 25 tests leave stores, WAL files and lock files under `$TMPDIR/SpamWise-tests`. Other tests clean up with `defer`, and `dir` is an abbreviation the conventions discourage.
- **Scenario:** Repeated runs accumulate hundreds of store directories.
- **Fix:** Use a `TestScoping` trait or a fixture type that owns cleanup, and use it everywhere.
<!-- sources: correctness/tests#17, conventions/tests#12 -->

#### 2.146 The retry-cancellation test accepts losing a job cancelled before dispatch — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:319` (`SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:243`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:197`)
- **Problem:** The test expects account A's retry to vanish even though it was cancelled before any action was claimed. CLAUDE.md records this as a deliberate trade-off.
- **Scenario:** A quit during a slow retry consumes that message's last retry for good.
- **Fix:** Re-queue jobs that were cancelled before dispatch, and change the test's expectation.
<!-- sources: correctness/tests#8 -->

#### 2.147 No test checks the "persist before acting" invariant — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:389` (`SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:39`, `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionFixtures.swift:25`, `SpamWiseCore/Sources/Store/Store.swift:91`)
- **Problem:** The persistence-failure test fails at the first load and never reaches save or dispatch, and RecordingAdapter never inspects the store. Dispatch's own claim check covers the most likely reorder, but no test fails a write after a successful load.
- **Scenario:** Making save failures non-fatal, or a subtler reorder, would pass every test.
- **Fix:** Have the adapter assert that the claimed record exists when `perform` runs, inject a store that fails on its first write, and rename the current test.
<!-- sources: correctness/tests#2, conventions/tests#1 -->

#### 2.148 `#expect` calls inside fixture closures run on detached tasks — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift:232` (`SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift:86`, `SpamWiseCore/Tests/SpamWiseCoreTests/ThreatAssessmentTests.swift:15`, `SpamWiseCore/Tests/SpamWiseCoreTests/SignalsTests.swift:86`, `SpamWiseCore/Tests/SpamWiseCoreTests/ProviderTests.swift:89`, `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:55`)
- **Problem:** `withResourceDeadline` and URLProtocol callbacks run outside the test's task-local context, so failures are poorly attributed, and key assertions sit inside fixtures.
- **Scenario:** A regression in alias trust is reported apart from the test that caused it.
- **Fix:** Record what the fixture receives in a `Mutex` or actor, and assert on it in the test body.
<!-- sources: conventions/tests#8 -->

#### 2.149 The fake Apple Events runner crashes the whole test process on an unexpected script — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/MailIntegrationTests.swift:30`
- **Problem:** `responses.removeFirst()` traps when the queue is empty.
- **Scenario:** One extra lookup kills `swift test`, and no results are reported for the remaining suites.
- **Fix:** Record an Issue and throw instead.
<!-- sources: correctness/tests#14 -->

#### 2.150 Tests force-unwrap values and accept any error — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/ParsingTests.swift:88` (`SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift:17`, `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:204`, `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:225`)
- **Problem:** `#expect(throws: (any Error).self)` passes for any failure, including a missing fixture. `!` crashes the runner instead of failing the test.
- **Scenario:** A renamed fixture leaves the malformed-MIME test passing, and the case it was meant to cover goes untested.
- **Fix:** Assert specific `ParseError` cases, and use `try #require` in place of `!`.
<!-- sources: conventions/tests#9 -->

#### 2.151 The legacy-state migration test only removes keys from a freshly encoded state — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:6`
- **Problem:** No frozen JSON from an earlier schema is tested, so renames and new non-optional fields go undetected.
- **Scenario:** A new non-optional field on DecisionRecord breaks decoding of every existing store, and all mail fails open, while the test still passes.
- **Fix:** Commit golden AppState fixtures from earlier schemas and decode them in tests.
<!-- sources: correctness/tests#15 -->

#### 2.152 The budget concurrency test passes even when reservations fail for other reasons — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:190`
- **Problem:** The test asserts `successes <= 2`, `successes > 0` and `committedUSD <= 0.20`. The $0.20 limit also hides Double accumulation, since `0.1 + 0.1 + 0.1 > 0.3`.
- **Scenario:** Intermittent lock failures, or a wrongly rejected third reservation, both pass.
- **Fix:** Assert exact counts and amounts, and keep money in integer micro-dollars or Decimal.
<!-- sources: correctness/tests#9 -->

#### 2.153 Precedence and consent tests skip the domain-block-over-contact and Private Cloud Compute cases — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/SignalsTests.swift:18` (`SpamWiseCore/Tests/SpamWiseCoreTests/ProviderTests.swift:8`)
- **Problem:** The domain-rule case uses `contact: false` and an allow rule. The consent test omits `.privateCloudCompute`.
- **Scenario:** Reordering Gates so that contacts are checked first, or exempting PCC from consent, passes every test.
- **Fix:** Add a domain Block with `contact: true` and existing replies, and add PCC to the consent arguments.
<!-- sources: correctness/tests#10 -->

#### 2.154 The alias-exclusion test's authentication assertion holds whether or not the exclusion works — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/SignalsTests.swift:87`
- **Problem:** No trusted servers are configured, so every result is untrusted regardless of the exclusion.
- **Scenario:** A regression that trusts forwarded claims for excluded aliases still passes.
- **Fix:** Configure the fixture's authserv-id as trusted, then assert the intended outcome.
<!-- sources: correctness/tests#16 -->

#### 2.155 Wall-clock waits and timing assertions make the suite slow and potentially flaky — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/ThreatAssessmentTests.swift:97` (`SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift:224`, `SpamWiseCore/Tests/SpamWiseCoreTests/ClassifierTests.swift:47`, `SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift:96`)
- **Problem:** Deadline tests sleep past private production constants, adding about 5 s per run. Elapsed-time bounds of 0.5 s depend on machine load, although their margins are generous.
- **Scenario:** On a heavily loaded machine, a correct deadline test fails intermittently.
- **Fix:** Inject deadlines or a Clock, and assert on cancellation or timeout results rather than elapsed time.
<!-- sources: correctness/tests#18, conventions/tests#11 -->

#### 2.156 `audit.py` crashes on valid records containing U+0085, U+2028 or U+2029 — Low

- **Where:** `Tools/Corpus/audit.py:31` (`Tools/Corpus/prepare.py:312`, `Tools/Corpus/screen.py:61`)
- **Problem:** `prepare.py` writes JSONL with `ensure_ascii=False`, and `str.splitlines()` treats those three characters as line breaks. `screen.py` reads the same file correctly.
- **Scenario:** A spam message containing Windows-1252 byte 0x85, decoded as Latin-1, makes a valid frozen corpus impossible to audit.
- **Fix:** Iterate the file line by line, and add a round-trip test.
<!-- sources: correctness/tools#1 -->

#### 2.157 The 120-second bsdtar kill timer also counts the consumer's processing time — Low

- **Where:** `Tools/Corpus/prepare.py:135` (`Tools/Corpus/prepare.py:153`, `Tools/Corpus/prepare.py:24`)
- **Problem:** The generator's timer covers MIME parsing done between yields, so the documented 200,000-record limit is unreachable. A kill surfaces as a generic `archive_decode` error.
- **Scenario:** A valid large archive fails preparation partway through. The current pinned sources are small.
- **Fix:** Use an inactivity watchdog, or drain the archive to a bounded temporary file first, and report timeouts distinctly.
<!-- sources: correctness/tools#4 -->

#### 2.158 Corpus preparation discards its precise failure reason — Low

- **Where:** `Tools/Corpus/prepare.py:415`
- **Problem:** Content-free codes such as `source_hash:<id>` are replaced by one generic message. The other corpus CLIs show tracebacks instead.
- **Scenario:** One changed upstream source forces the operator to re-hash all four inputs by hand.
- **Fix:** Include the ValueError code in the exit message, and handle errors the same way in all four CLIs.
<!-- sources: conventions/tools#3, comments/tools#14 -->

#### 2.159 SpaPhish cross-split campaign counts are computed while every row is still "train" — Low

- **Where:** `Tools/Corpus/spaphish.py:79` (`Tools/Corpus/spaphish.py:103`)
- **Problem:** The published zeros could never be anything else, and one field is hard-coded. The real guarantee comes from the `campaign_leakage` raise.
- **Scenario:** A reviewer reads the zeros as measured evidence that no split overlaps.
- **Fix:** Compute the counts after splits are assigned, or remove the fields.
<!-- sources: correctness/tools#8 -->

#### 2.160 Python tests bundle unrelated behaviors under names describing only one — Low

- **Where:** `Tools/Corpus/test_prepare.py:79` (`Tools/Corpus/test_prepare.py:160`, `Tools/Corpus/test_prepare.py:371`)
- **Problem:** The "campaign audit" test also covers derived partitioning, language inference and SpaPhish grouping and conflicts.
- **Scenario:** A SpaPhish regression is reported as a campaign-audit failure.
- **Fix:** Split them into tests named for each behavior, with shared fixtures.
<!-- sources: conventions/tools#14, comments/tools#16 -->

#### 2.161 Reconnecting right after cancellation can reach the still-alive worker, which answers busy — Low

- **Where:** `Tools/DocumentWorker/Client.swift:99` (`Tools/DocumentWorker/Worker.swift:25`, `Tools/DocumentWorker/ProbeHost.swift:80`)
- **Problem:** On cancellation, "closed" means the client invalidated its connection, not that the process exited. The worker's static `active` flag is never reset. The harness checks for this reuse explicitly.
- **Scenario:** The next attachment is routed to the dying process and returns `.busy`.
- **Fix:** Retry the identity check until the process ID changes, or treat `.busy` as retryable once.
<!-- sources: correctness/tools#3 -->

#### 2.162 One textless PDF page makes the whole document "unreadable" — Low

- **Where:** `Tools/DocumentWorker/PDFExtraction.swift:14`
- **Problem:** A nil `page.string` aborts extraction and discards text from every other page. This depends on PDFKit returning nil for image-only pages.
- **Scenario:** An invoice with an image-only letterhead page loses its payment text.
- **Fix:** Treat nil as an empty string, and return unreadable only when no page has any text.
<!-- sources: correctness/tools#7 -->

#### 2.163 Pure ReplyLatch and PDFExtraction logic is tested only inside the signed harness — Low

- **Where:** `Tools/DocumentWorker/ProbeHost.swift:92` (`Tools/DocumentWorker/ProbeHost.swift:202`, `Tools/DocumentWorker/ProbeHost.swift:129`)
- **Problem:** In-process logic is checked with a hand-rolled `verify()`, and only after Developer ID signing.
- **Scenario:** A latch regression is caught only by a run that takes several minutes and needs signing.
- **Fix:** Move the pure parts into a SwiftPM test target using Swift Testing, and keep the harness for XPC and sandbox cases.
<!-- sources: conventions/tools#9 -->

#### 2.164 The production-worker symbol check passes silently without ripgrep — Low

- **Where:** `Tools/DocumentWorker/check.sh:88` (`Tools/DocumentWorker/check.sh:51`, `Tools/DocumentWorker/check.sh:64`)
- **Problem:** The `nm | rg` pipeline sits in an `if` condition, where `set -e` does not apply, so a missing `rg` or a failing `nm` passes the check. The sentinel file is created before the cleanup trap is installed.
- **Scenario:** On a machine without ripgrep, the claim that diagnostic symbols are absent is recorded as verified.
- **Fix:** Capture the `nm` output first, test it with `grep -Eq`, and install the trap earlier.
<!-- sources: correctness/tools#5 -->

#### 2.165 Committed result artifacts don't match the committed tools — Low

- **Where:** `Tools/Preferences/results-2026-10-16.json:6` (`Tools/Preferences/run.py:205`, `Tools/Corpus/reports/hard-ham-development-384.json`, `Tools/Corpus/screen.py:239`)
- **Problem:** `1.2000000000000002` cannot be produced by `round(..., 2)`, and the hard-ham reports lack keys that `screen.py` always writes. Only `spaphish.py` records a tool hash, and USD amounts are computed as binary floats.
- **Scenario:** A reviewer cannot tie the published 60.8% and 65.5% false-alarm figures, or the $1.20 bound, to the reviewed code.
- **Fix:** Record `tool_sha256` in every report, regenerate or annotate stale artifacts, and use `Decimal` for USD.
<!-- sources: correctness/tools#9, conventions/tools#13 -->

#### 2.166 The site generator labels every table "Compatibility table" and does not deduplicate anchors — Low

- **Where:** `Tools/Site/build.py:58` (`Tools/Site/build.py:42`)
- **Problem:** The `aria-label` is hard-coded for every table, and repeated headings produce duplicate ids. Both problems are latent with today's pages.
- **Scenario:** A table added to support.md is announced as "Compatibility table", and `#gmail` always jumps to the first matching heading.
- **Fix:** Derive the label from the nearest preceding heading or a caption, and use `mdit_py_plugins` anchors or track the slugs already used.
<!-- sources: conventions/tools#16 -->

#### 2.167 UI assertions read state immediately, without waiting — Low

- **Where:** `UITests/UITests.swift:74` (`UITests/UITests.swift:225`, `UITests/ReviewScreens.swift:19`, `UITests/EvidenceScreen.swift:84`)
- **Problem:** Negative `.exists` checks and counts are evaluated with no settling wait. The correction helpers do wait for specific labels, which reduces the risk.
- **Scenario:** A rule row that renders a frame late makes the absence assertion pass vacuously.
- **Fix:** Wait for a positive anchor first, or use predicate waits for absence and counts.
<!-- sources: correctness/tests#13 -->

#### 2.168 Mock responses are keyed by fragile raw-byte hashes — Low

- **Where:** `eval/mock-responses.json:2` (`SpamWiseCore/Sources/SpamWiseEval/main.swift:93`, `eval/fixtures/good/order-confirmation.eml:1`)
- **Problem:** The keys are SHA-256 hashes of the exact fixture bytes, and no `.gitattributes` protects the files from line-ending normalization. The file cannot be reviewed without recomputing hashes. Fixtures use registrable real-world domains, although this CLI makes no network queries.
- **Scenario:** A checkout with `core.autocrlf=true`, or a one-line fixture edit, makes every lookup throw `missingMock`.
- **Fix:** Key mocks by fixture path or Message-ID, keeping the hash as an optional integrity check. Add `eval/fixtures/** -text`, and use reserved domains such as `.example`.
<!-- sources: correctness/tools#10, conventions/tools#17 -->

#### 2.169 Export buttons do nothing visible when encoding fails — Info

- **Where:** `SpamWise/ActivityStatisticsView.swift:68` (`SpamWise/ActivityStatisticsView.swift:73`, `SpamWise/CorpusView.swift:54`, `SpamWise/DecisionDetailView.swift:179`)
- **Problem:** `try?` swallows encode errors, while the `fileExporter` failure paths in the same views do report errors. A realistic failure would need a non-finite Double.
- **Scenario:** If encoding ever fails, "Export statistics" does nothing, and the inspector's Evidence section disappears.
- **Fix:** Use do/catch and set `model.status`.
<!-- sources: conventions/app-views-main#16 -->

#### 2.170 `AppleMailAdapter.nextPage` reads and writes its cursor across an await — Info

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:199`
- **Problem:** Two concurrent callers using the same cursor would fetch the same page twice. Today the busy gate serializes all callers.
- **Scenario:** If background scanning is separated from `busy` (§2.14), history pages could be imported twice.
- **Fix:** Reserve the offset synchronously before the await, or serialize work per cursor.
<!-- sources: concurrency#13 -->

#### 2.171 Held-out evaluation always uses the default policy — Info

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/Options.swift:66` (`SpamWiseCore/Sources/SpamWiseEval/main.swift:149`)
- **Problem:** `--state` is correctly rejected for held-out runs, but there is no other way to supply the user's policy text and prompt budgets, and the report doesn't say that defaults were used.
- **Scenario:** A user reads the held-out metrics as describing their own configuration.
- **Fix:** Add a label-free `--policy` or settings-only import, and record the policy used in the report.
<!-- sources: correctness/eval-scripts#15 -->
## 3. Progress through the TODO list

The code behind most checked items in `TODO.md` exists and is wired end to end, from core types and persistence to Settings, Activity or CLI entry points, with Swift Testing coverage. The research and corpus items rest on real tools and hash-pinned reports, and their figures match the TODO text: 60.8%/65.5% and 40.5%/43.1% false-alarm rates, the 212/176 SpaPhish validation split, 18,201 records and 2,782 holdouts. Probe, harness and document deliverables mostly say what they are. The project's habit of separating "implemented" from "accepted" is real and worth keeping.

The list is still more optimistic than the code. There are three patterns:

- **Checked parents that miss their own acceptance text.** SS-04, SS-10, SS-11, SS-12, SS-13 and SS-15 are checked even though their item text names criteria that are not met. TODO.md:129 says parents stay open until their full criteria are met, which contradicts this. SS-15 matters most: the forged-contact half of spoofing protection was never built.
- **Engineering gaps hidden under acceptance wording.** Several open parents (SS-01, SS-06, SS-07, SS-08, SS-09) list only runtime acceptance, but the work they need first is ordinary engineering. Examples: new-mail priority and an Inbox start boundary, health and backlog categories, an aggregate status state, Junk-review explanations, and the folder-plan lifecycle. Read as written, the list says the engineering is finished and only observation remains.
- **Point-in-time events as permanent checkmarks.** L63 records a notarized delivery and review of a build several feature batches older than HEAD. No CI exists to re-establish any "verified offline" claim.

The list is also hard to read as a status document. It runs to 44 KB, about two-thirds of it completed items, session narration and research prose. Open work is spread across four overlapping structures, and `docs/spamsieve-parity-progress.md` and `docs/roadmap-progress.md` are frozen snapshots that contradict the current TODO in places. The roadmap reviewer also flagged L59: the $150 owner-authorized evaluation ceiling ships as a lifetime product spending cap. That issue is not among this section's verified findings, so it appears only in the table below. Reviewers worked read-only. Test-pass, notarization and live-Mail claims were checked against code, tests and probe documents, not rerun.

**Status of every TODO.md checkbox.** Kind values: *Verified* means done and verified (for runtime or harness items, the documented observation is consistent with the code); *Partial* means done but partial or unwired; *Eng*, *Runtime* and *External* are open work by what blocks it.

| Item | Claimed | Verified status | Evidence | Remaining | Kind |
| --- | --- | --- | --- | --- | --- |
| L19 Threat/preference spec | [x] | Doc delivered | docs/detection-design.md | — | Verified |
| L20 Dataset research | [x] | Doc delivered | docs/training-data.md | — | Verified |
| L21 Download/inventory sources | [x] | Hash pins present; local snapshots not in repo | Tools/Corpus/sources.json | — | Verified |
| L22 Screen tiny/multilingual models | [x] | Probe | docs/probes/local-model-screening.md | — | Verified |
| L23 Audit labels/build sets (parent) | [ ] | 5 of 6 children done | Tools/Corpus/{prepare,audit,spaphish}.py | L29 | External |
| L24 Corpus preparation tool | [x] | Tool and tests exist; text says 6 tests, there are 8 | Tools/Corpus/test_prepare.py | Fix count (§3.16) | Verified |
| L25 18,201 records, holdouts | [x] | Matches report | reports/corpus-integrity-audit.json | — | Verified |
| L26 Evaluation-only hard-ham | [x] | Matches report and tests | sources.json `evaluationOnly` | — | Verified |
| L27 Integrity audit | [x] | Tool and report | audit.py; 421 pairs, 29 moved, 37 unresolved | — | Verified |
| L28 SpaPhish acquisition | [x] | Tool, tests, report | spaphish.py; spaphish-development.json | — | Verified |
| L29 Independent label review | [ ] | Not done | — | Human review, unseen data | External |
| L30 Useful local detector (parent) | [ ] | All candidates rejected | reports/*.json | Validated detector | External |
| L31 Multilingual candidate, 259 real | [x] | Probe | local-model-development-{384,1024}.json | — | Verified |
| L32 Hard-ham screening | [x] | Figures match | hard-ham-development-*.json | — | Verified |
| L33 OpenTextShield screening | [x] | Figures match | opentextshield-development-*.json | — | Verified |
| L34 Spanish TF-IDF baseline | [x] | Split matches | spaphish-development.json | — | Verified |
| L35 Persist assessments/provenance | [x] | Wired and tested | ThreatAssessment.swift; EvaluationTests | — | Verified |
| L36 Threats on trusted paths (parent) | [ ] | Blocked only on L38 | PipelineClassification.swift:86 | L38 | Eng |
| L37 Bounded detector path on all paths | [x] | Wired and tested | ThreatAssessmentTests | — | Verified |
| L38 Production detector | [ ] | No detector configured | AppModel.swift:96 | Integration after L30 | Eng |
| L39 Fraud/impersonation evaluation | [ ] | Enum only | ThreatAssessment.swift:14 | Data, evaluation | External |
| L40 Graymail personalization (parent) | [ ] | Synthetic probe only | Tools/Preferences/run.py | Real reviewed mail | External |
| L41 12-context graymail probe | [x] | Probe | results-2026-10-16.json | — | Verified |
| L42 Attachment/malware coverage | [ ] | Text extraction only; PDF worker is a harness | Tools/DocumentWorker | Containment, AV-grade evidence | Eng |
| L46 Apple/PCC/OpenAI/Gemini/Claude | [x] | PCC selectable but unreachable in Developer ID builds | ModelSettingsView.swift:37 | Gate PCC (§3.10) | Partial |
| L47 Rule edit/import/export | [x] | Wired and tested | RuleManagement.swift; RoadmapStateTests | — | Verified |
| L48 Policy suggestions | [x] | Wired and tested | CorrectionLearning.swift:57 | — | Verified |
| L49 Similar-correction retrieval | [x] | Wired and tested | LearningTests | — | Verified |
| L50 Bayes/regularized weights | [x] | Wired and tested | StatisticalLearning.swift | — | Verified |
| L51 Campaign fingerprints | [x] | Wired; acts as a decisive Junk gate, contrary to its doc comment | CampaignLearning.swift | Fix doc comment | Verified |
| L52 Spamhaus DNS DBL | [x] | Offline tests | ExternalEvidenceTests | Live resolver (L76) | Verified |
| L53 Spamhaus HTTPS | [x] | Offline tests and UI test | SpamhausHTTPS.swift | Live key | Verified |
| L54 Rspamd HTTP/executable | [x] | HTTP transport has no unit tests, only the manual harness | RspamdLoopbackHTTP.swift | HTTP unit tests | Partial |
| L55 Vision OCR | [x] | Also accepts GIF/TIFF/HEIC; text says PNG/JPEG | EmbeddedImages.swift:15 | Fix text (§3.16) | Verified |
| L56 TLS IMAP + daemon | [x] | Exposed in Settings although out of scope | IMAPSettingsView.swift:26 | Hide or accept (§3.6) | Partial |
| L57 Weekly Review digest | [x] | Wired and tested | ReviewDigestView.swift | — | Verified |
| L58 Label collection/export | [x] | Wired and tested | PipelineCorrections.swift:126 | — | Verified |
| L59 Spending reservations | [x] | Evaluation ceiling ships as a lifetime, non-resettable product cap | EvaluationBudget.swift:27 | Productize spending control | Partial |
| L60 Retain unstarted retries | [x] | Wired and tested | Pipeline.swift:220; DecisionTests | — | Verified |
| L61 App Store preflight/export | [x] | Scripts only; store variant needs a CLI override | Scripts/app-store-check.sh | — | Verified |
| L62 ES/FR catalogs, Help | [x] | 107 stale keys; AppShortcuts strings `needs_review` | Localizable.xcstrings | Clean up, review | Partial |
| L63 Review, checks, notarized delivery | [x] | Point-in-time; notarization predates HEAD | CLAUDE.md:485, :584 | Recurring gate (§3.17) | Partial |
| L75 New-provider live verification | [ ] | HTTP 429; Gemini key absent | docs/evaluation.md | Keys, quota, quality | External |
| L76 DNS/Rspamd/OCR on signed build (parent) | [ ] | Harness evidence only | Scripts/evidence-runtime-probe.swift | Signed-app acceptance | Runtime |
| L77 Native Vision synthetic cases | [x] | Harness | docs/probes/local-evidence-runtime.md | — | Verified |
| L78 Rspamd 4.2.2 adapter | [x] | Harness | docs/probes/rspamd-runtime.md | — | Verified |
| L79 Loopback HTTP fault cases | [x] | Harness | Scripts/rspamd-runtime-check.sh | — | Verified |
| L80 Live onboarding/MailKit (parent) | [ ] | Partial; MailKit route dry-run only | MessageActionHandler.swift:21 | L83 | Runtime |
| L81 Live menu-bar correction | [x] | One generated message | docs/probes/live-corrections.md | — | Verified |
| L82 MailKit body callback, persisted progress | [x] | Documented run; cursor persisted in code | AppModelScanning.swift:48 | — | Verified |
| L83 Fresh-user onboarding, account bridge | [ ] | Not done | — | Fresh session, account bridge | Runtime |
| L84 Slow/offline sync | [ ] | Not done | AppleMailAdapter (30 s window) | Controlled sessions | Runtime |
| L85 Sweep latency, large mailboxes | [ ] | Latency is unbounded by design; measurement alone cannot pass | AppModelScanning.swift:48 | New-mail priority first (§3.1) | Eng |
| L86 Calibration/personalization (incl. L87 SpamSieve-sample note) | [ ] | Thresholds 99/95/90 provisional | Decision.swift:13 | Labeled corpus | External |
| L88 PCC entitlement | [ ] | Not granted | SpamWise.entitlements | Apple grant | External |
| L89 App Store Connect/review (parent) | [ ] | Error 19, no app record | docs/app-store.md | ASC record, review | External |
| L90 Privacy/support/site docs | [x] | Docs and site present | docs/*.html; site.yml | Publication | Verified |
| SS-01 Incoming coverage, health (parent) | [ ] | Untracked: backlog/unseen categories, heartbeat display, stalled-page fallback, new-mail priority | MailHealthView.swift:34 | §3.1, §3.7 | Eng |
| SS-01.1 Per-account paging, health | [x] | Tested in core; health is offset-only | MailPreferences.swift:24 | — | Verified |
| SS-01.2 Unreadable sources | [x] | Tested; whole-page timeout still stalls (probe doc only) | MailPage.swift:16 | §3.7 | Verified |
| SS-01.3 Live delivery/body callback | [x] | Documented; callback timestamps never displayed | MessageActionHandler.swift:27 | Show heartbeat | Verified |
| SS-01.4 Wake/restart/offline/latency | [ ] | Not done | — | Design change, then measure | Runtime |
| SS-02 Mailbox roles, coexistence (parent) | [ ] | Partial | — | SS-02.2 | Runtime |
| SS-02.1 Destination previews | [x] | Wired; script compiled in a test | MailDestinations.swift:17 | — | Verified |
| SS-02.2 Concurrent filters/sync | [ ] | Not done | — | Live multi-filter runs | Runtime |
| SS-03 Local filtering mode (parent) | [ ] | Partial; premise text stale (RDAP is opt-in) | TODO.md:172; AdvancedSettings.swift:41 | SS-03.3 | Runtime |
| SS-03.1 Local-mode blocking | [x] | Wired and tested | ConfiguredClassifier.swift:28; DecisionTests | — | Verified |
| SS-03.2 Signed harness observation | [x] | Harness | Scripts/evidence-runtime-probe.swift | — | Verified |
| SS-03.3 Shipping-app observation, model quality | [ ] | Not done | — | Service-aware observation, trained model | External |
| SS-04 Correct without leaving Mail (parent) | [x] | Opens Activity; menu-only shortcuts; address scope only; serial 30 s settles | MailMenuView.swift:17 | §3.8 | Partial |
| SS-04.1 Menu-bar corrections | [x] | Wired; core tested, batch untested | SelectedCorrections.swift | See parent | Verified |
| SS-04.2 Live selected correction | [x] | One message, Junk only | live-corrections.md | Good/Review, multi-select | Verified |
| SS-05 Quality vs SpamSieve (parent) | [ ] | Tooling only | — | SS-05.2 | External |
| SS-05.1 Paired reports | [x] | CLI and test | ComparisonReport.swift | — | Verified |
| SS-05.2 Labels and comparison | [ ] | Not done | — | Reviewed holdout | External |
| SS-06 Unattended operation (parent) | [ ] | Untracked: aggregate status/offline state, background login launch, App Nap | MailMenuView.swift:9; MyApp.swift:14 | §3.7 | Eng |
| SS-06.1 Window-independent monitor, login item | [x] | Wired | AppModel.swift:144; StartupSettingsView.swift | — | Verified |
| SS-06.2 Closed-window/relaunch progress | [x] | Documented run | live-mail-followup.md | — | Verified |
| SS-06.3 Lock/restart/sleep/fresh user | [ ] | Not done | — | Supervised sessions | Runtime |
| SS-07 Junk review and rescue (parent) | [ ] | Untracked: explanations, provenance, Block-rule guard | AppModelMailReview.swift:52 | §3.4 | Eng |
| SS-07.1 Read-only Junk review, restore | [x] | Wired; app flow untested | MailReviewView.swift | See parent | Verified |
| SS-07.2 Live rescue | [x] | One probe | live-corrections.md | — | Verified |
| SS-07.3 Coexistence | [ ] | Not done | — | Repeated filters, reconnects | Runtime |
| SS-08 Training folders (parent) | [ ] | Untracked: dry-run claims never moved, no review surface | TrainingFolders.swift:57 | §3.14, SS-08.2 | Eng |
| SS-08.1 Dedicated folders, atomic claims | [x] | Wired and tested | MailIntegrationTests:273 | — | Verified |
| SS-08.2 Second device, reconnect | [ ] | Not done | — | Live | Runtime |
| SS-09 Account/folder scope, refilter (parent) | [ ] | Untracked: plan lifecycle, exclusions, Inbox start boundary | FolderSettingsView.swift:17 | §3.5, §3.1 | Eng |
| SS-09.1 Plans, date boundaries, dry-run refilter | [x] | Folder plans only; no removal; Inbox unbounded | AppModelFolders.swift:31, :69 | §3.5 | Partial |
| SS-09.2 Live preview, rename fail-closed | [x] | Preview returned `consentRequired`; nothing classified | live-mail-followup.md | §3.19 | Partial |
| SS-09.3 Server rules, reconnects | [ ] | Not done | — | Live | Runtime |
| SS-10 Content rules | [x] | Winning rule shown as UUID; single-message preview; count-only conflicts; inflated hits; reviewer also reports long-body failure | PipelineClassification.swift:115 | §3.12 | Partial |
| SS-11 Corpus, import, undo | [x] | No retention controls; undo preview shows totals | CorrectionUndo.swift:10 | §3.11 | Partial |
| SS-12 Activity troubleshooting | [x] | Wired; no test that previews never fetch remote resources | ActivityQuery.swift; DecisionDetailView.swift | §3.18 | Partial |
| SS-13 Statistics | [x] | No per-account trends or uncertainty | ActivityStatisticsView.swift:43 | §3.3 | Partial |
| SS-14 Notifications, prioritization (parent) | [ ] | Direct correction links untracked | LocalNotifications.swift:13 | §3.20, SS-14.3 | Eng |
| SS-14.1 Batched notifications, ranking, read status | [x] | Wired and tested | NotificationPlanning.swift; RoadmapStateTests | — | Verified |
| SS-14.2 Live unread-to-read check | [x] | Documented run | live-mail-followup.md | — | Verified |
| SS-14.3 Signed delivery, deep links | [ ] | Code exists | LocalNotifications.swift:56 | Permission, delivery | Runtime |
| SS-15 Own-address and trusted-sender spoofing | [x] | Own-address half only; contact/history gates ignore authentication | Gates.swift:97 | §3.9 | Partial |
| SS-16 Backup, restore | [x] | AES-GCM, validation, tamper tests; narrow settings scope | StateBackup.swift | §3.13 | Verified |
| SS-17 Attachment analysis (parent) | [ ] | PDF not integrated | — | SS-17.4 | Eng |
| SS-17.1 Text/HTML attachments, image formats | [x] | Wired; GIF tested, TIFF/HEIC untested | EmbeddedImages.swift:14 | Fixtures | Verified |
| SS-17.2 PDF extraction evaluation | [x] | Probe | docs/probes/document-inspection.md | — | Verified |
| SS-17.3 Signed XPC harness | [x] | Harness | Tools/DocumentWorker | — | Verified |
| SS-17.4 Memory containment before PDF | [ ] | Watchdog overshoots | docs/probes/pdf-containment.md | Containment, integration | Eng |
| SS-17.5 Resource-control research | [x] | Doc | pdf-containment.md | — | Verified |
| SS-17.6 Worker cancellation, recovery | [x] | Harness only; wording reads as product work | Tools/DocumentWorker | Prefix "Harness:" | Verified |
| SS-18 Compatibility matrix (parent) | [ ] | Partial | — | SS-18.2 | Runtime |
| SS-18.1 iCloud/Google matrix | [x] | Doc | docs/mail-compatibility.md | — | Verified |
| SS-18.2 Offline, broader acceptance | [ ] | Not done | — | Accounts, hardware | Runtime |
| SS-19 Automation (parent) | [x] | Four intents with UUID replay; reviewer notes claim store never pruned | AutomationIntents.swift; AutomationRequest.swift | Prune claims | Verified |
| SS-19.1 App Intents, replay | [x] | Wired and tested | RoadmapStateTests:261 | — | Verified |
| SS-19.2 Native registration, status intent | [x] | Documented; env-gated test skipped by default | docs/automation.md | — | Verified |
| SS-19.3 Parameter binding, replay on fixture | [x] | Documented | docs/automation.md | — | Verified |
| SS-19.4 Shortcuts editor/CLI/AppleScript | [x] | Documented; parity doc contradicts | docs/automation.md | Update parity doc | Verified |
| SS-20 Distribution, lifecycle (parent) | [ ] | Partial | — | SS-20.8 | External |
| SS-20.1 Lifecycle docs | [x] | Doc; data removal is manual | docs/lifecycle.md | — | Verified |
| SS-20.2 Distribution research | [x] | Doc | docs/app-store-feasibility.md | — | Verified |
| SS-20.3 Consent, domain-age opt-in, store restrictions | [x] | Store restriction exists only via a CLI flag | DistributionCapabilities.swift; app-store-check.sh:44 | Project build configuration | Partial |
| SS-20.4 MAS/direct ledger | [x] | Doc | docs/distribution-differences.md | — | Verified |
| SS-20.5 Direct target, release discovery | [x] | Depends on an unpushed local library branch | project.pbxproj:998 | Publish or pin library | Partial |
| SS-20.6 Static pages, Match store signing | [x] | Files present; browser check not reproducible here | Tools/Site/build.py | — | Verified |
| SS-20.7 Private repo, Pages workflow, draft PR | [x] | Remote and site.yml present; TODO.md:101 topology now stale | .github/workflows/site.yml | §3.17 | Verified |
| SS-20.8 App Store gaps, direct release | [ ] | Not done | — | ASC record, review, host | External |
| SS-21 Semantic preferences (parent) | [ ] | Prompt-injection evaluation untracked | — | §3.20 | External |
| SS-21.1 Frozen comparison reporting | [x] | Wired and tested | ComparisonReport.swift | — | Verified |
| SS-21.2 Zero-shot vs increments | [ ] | Not done | — | Private labels | External |
| SS-21.3 Synthetic multilingual smoke test | [x] | Probe | docs/probes/graymail-preferences.md | — | Verified |
| SS-21.4 Benefit on unseen mail | [ ] | Not done | — | Independent labels | External |
| SS-22 Review effort (parent) | [ ] | Correction-effect preview untracked | — | §3.20 | Eng |
| SS-22.1 Ranking, observed effort | [x] | Wired | ReviewPriority.swift | — | Verified |
| SS-22.2 Matched-FP measurement | [ ] | Not done | — | Labeled cohort | External |
| SS-23 Local/cloud tradeoffs (parent) | [ ] | Depends on SS-03/05 | — | SS-23.2 | External |
| SS-23.1 Paired report | [x] | Generic paired report | ComparisonReport.swift | — | Verified |
| SS-23.2 Prerequisites before escalation | [ ] | Not started | — | Implement after SS-03/05 | Eng |

**Totals (135 checkboxes: 87 checked, 48 open):**

| Status | Count |
| --- | --- |
| Done and verified | 71 |
| Done but partial or unwired | 16 |
| Open engineering | 14 |
| Open runtime acceptance | 15 |
| Open external (labels, credentials, Apple, publication) | 19 |

### Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| 3.2 | Medium | `.github/workflows/site.yml:1` | No Swift build/test CI, and none tracked |
| 3.3 | Medium | `SpamWise/ActivityStatisticsView.swift:43` | SS-13 checked without per-account trends or uncertainty |
| 3.4 | Medium | `SpamWise/AppModelMailReview.swift:52` | SS-07 Junk review lacks explanation, provenance and Block-rule guard |
| 3.5 | Medium | `SpamWise/FolderSettingsView.swift:17` | SS-09 folder plans cannot be removed after a rename; generic cap error |
| 3.6 | Medium | `SpamWise/IMAPSettingsView.swift:26` | Out-of-scope IMAP is fully user-selectable |
| 3.7 | Medium | `SpamWise/MailHealthView.swift:34` | SS-01/SS-06 health and state work missing but tracked as runtime only |
| 3.8 | Medium | `SpamWise/MailMenuView.swift:17` | SS-04 checked, but corrections pull the user into Activity |
| 3.9 | Medium | `SpamWiseCore/Sources/Signals/Gates.swift:97` | SS-15 checked, but forged Contacts/history senders pass at confidence 100 |
| 3.10 | Low | `SpamWise/ModelSettingsView.swift:37` | PCC selectable in builds where it can never succeed |
| 3.11 | Low | `SpamWiseCore/Sources/SpamWiseCore/CorrectionUndo.swift:10` | Undo preview shows store totals, not the correction's changes |
| 3.12 | Low | `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:115` | SS-10 explanation and preview fall short |
| 3.13 | Low | `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:83` | Backup omits trust exclusions; restore changes retention silently |
| 3.14 | Low | `SpamWiseCore/Sources/SpamWiseCore/TrainingFolders.swift:57` | Dry-run training placements are never moved later |
| 3.15 | Low | `TODO.md:1` | TODO structure mixes narrative, finished work and evidence |
| 3.16 | Low | `TODO.md:24` | Stale counts, formats and status text in TODO and progress docs |
| 3.17 | Low | `TODO.md:63` | L63 "notarized delivery" is a point-in-time event shown as current |
| 3.18 | Low | `TODO.md:129` | Checked parents contradict the TODO's own completion rule |
| 3.19 | Low | `TODO.md:253` | SS-09 "verified historical preview" never classified anything |
| 3.20 | Low | `TODO.md:293` | Parent acceptance criteria with no tracking sub-item |

#### 3.2 No Swift build/test CI, and none tracked — Medium

- **Where:** `.github/workflows/site.yml:1`, `TODO.md:44`, `TODO.md:63`, `TODO.md:101`
- **Problem:** The only workflow validates the static site. Nothing reruns `swift test`, the warning-free app and extension build, the APP_STORE variant or SwiftLint on push or PR. SubTrack and Zephyr both have `ci.yml` and `lint.yml`. Every "verified offline" checkbox and every test-count claim therefore rests on local agent runs, and no TODO or SS-20 item tracks adding CI, even though the repository is on GitHub with a draft PR.
- **Scenario:** A later commit breaks a package test or the APP_STORE build and merges through the PR without any signal. The checked items keep claiming a state the tree may no longer satisfy.
- **Fix:** Add an SS-20 sub-item, then a `ci.yml` modeled on SubTrack/Zephyr. It should run `swift test` for SpamWiseCore, a warning-free `xcodebuild` of SpamWise and SpamWiseDirect, and the APP_STORE compile, plus a lint workflow. Resolve the local-path package dependency first so CI can build.
<!-- sources: todo/roadmap#3, todo/spamsieve-b#8 -->

#### 3.3 SS-13 checked without per-account trends or uncertainty — Medium

- **Where:** `SpamWise/ActivityStatisticsView.swift:43`, `SpamWiseCore/Sources/SpamWiseCore/ActivityQuery.swift:54`, `SpamWiseCore/Sources/Evaluation/Metrics.swift:56`, `TODO.md:285`
- **Problem:** SS-13 requires per-account trends and reviewed sample counts with uncertainty, built on evaluator primitives. The view shows scalar counts and one chart of total decisions per day. The account filter lists raw account IDs. `accountCounts` reaches only the JSON export, and the Clopper-Pearson `BinomialBound` is unused in the app.
- **Scenario:** A user comparing iCloud and Google cannot see per-account trends. "Reviewed disagreements: 1 of 3" appears with no bound, which invites the small-sample over-reading the item was meant to prevent.
- **Fix:** Uncheck SS-13 or add sub-items. Add a per-account series labeled by account name, and show exact binomial bounds next to reviewed counts using `BinomialBound`.
<!-- sources: todo/spamsieve-b#5 -->

#### 3.4 SS-07 Junk review lacks explanation, provenance and Block-rule guard — Medium

- **Where:** `SpamWise/AppModelMailReview.swift:52`, `SpamWise/MailReviewView.swift:30`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:53`, `TODO.md:230`
- **Problem:** SS-07 asks for a review queue "with explanations" that preserves filter provenance and avoids rescuing user-blocked senders. The view shows only subject and body. It does not say whether the message is in Junk because of SpamWise, SpamSieve or the server, or whether an explicit Block rule matches. "Mark Good and restore" replaces a same-scope Block with an Allow without warning. Replacement on explicit correction is the documented contract, but the missing conflict notice is not. The only open sub-item covers coexistence runtime work.
- **Scenario:** The user once blocked `billing@scam.example`. In Review Junk they restore a later message from that sender, and the Block silently becomes an Allow, so future mail from that sender passes the address gate.
- **Fix:** Add SS-07 sub-items and implement them. Join each Junk envelope to its DecisionRecord or rule match for an explanation, label provenance as unknown/other when no record exists, and ask for confirmation before replacing an explicit Block rule.
<!-- sources: todo/spamsieve-a#5 -->

#### 3.5 SS-09 folder plans cannot be removed after a rename; generic cap error — Medium

- **Where:** `SpamWise/FolderSettingsView.swift:17`, `SpamWise/FolderSettingsView.swift:55`, `SpamWise/AppModelFolders.swift:31`, `TODO.md:252`
- **Problem:** The plan picker lists only discovered folders, and plans are keyed by account and path. After a rename, the stale enabled plan cannot be selected, disabled or deleted. No code removes plans. It fails closed on every sweep and keeps one of the 20 slots forever. The 21st plan fails with a generic `IntegrationError.unavailable`. Folder exclusion is absent; Inbox is always swept for selected accounts.
- **Scenario:** The user renames "Receipts" to "Orders" in Mail. Every sweep records a failure for the old path, and the Folder sheet cannot remove it. After 20 such plans, any new plan fails with an unrelated message.
- **Fix:** List saved plans independently of discovery, including unresolved ones, with Disable and Remove actions. Give the cap a specific localized error. Mark SS-09.1 partial, with plan lifecycle and exclusions as open engineering.
<!-- sources: todo/spamsieve-a#6 -->

#### 3.6 Out-of-scope IMAP is fully user-selectable — Medium

- **Where:** `SpamWise/IMAPSettingsView.swift:26`, `SpamWise/IMAPSettingsView.swift:57`, `SpamWise/AccountSettingsView.swift:10`, `SpamWise/AppModel.swift:58`, `TODO.md:5`, `TODO.md:56`, `docs/imap.md:5`
- **Problem:** TODO.md:5-8 places IMAP outside the roadmap, and L56 defers its live acceptance, yet Settings > Accounts always shows an IMAP connection picker. It takes a password or OAuth token and offers a "Test Junk and restore Inbox" probe that validates the account for actions, and `canScanAutomatically` includes `.imap`. No live TLS authentication or move has ever run. Changing transport forces dry run on, but the probe itself moves mail.
- **Scenario:** A user picks IMAP, saves credentials and runs the probe on a UID. The account becomes action-validated, and once dry run is off, automatic sweeps move mail through a transport never accepted against a real server.
- **Fix:** Hide the IMAP picker and daemon behind a DEBUG or explicit feature flag while out of scope, and mark L56 "retained, not shipped". Alternatively, add an open TODO item for live IMAP acceptance before exposing it.
<!-- sources: todo/roadmap#2 -->

#### 3.7 SS-01/SS-06 health and state work missing but tracked as runtime only — Medium

- **Where:** `SpamWise/MailHealthView.swift:34`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:199`, `MailExtension/MessageActionHandler.swift:27`, `SpamWise/MailMenuView.swift:9`, `SpamWise/MyApp.swift:14`, `TODO.md:156`, `TODO.md:216`
- **Problem:** SS-01 asks for per-account backlog, actionable failures, and a split of unseen from reviewed, unclassified and classified mail. The health view shows only last page, observed total, next offset, the unreadable count and the failure text. The MailKit heartbeat timestamps are written but never read. SS-06 asks for visible paused/offline states, yet the menu says "SpamWise is running" whenever the app is not paused, whatever the onboarding, dry-run, permission or failure state. A page that times out every sweep never advances the cursor, which the probe doc acknowledges and TODO does not. Login launch always presents a window, and nothing addresses App Nap (low confidence). The open sub-items list only runtime observations.
- **Scenario:** Mail permission is revoked. Every sweep fails, visible only deep in Settings → Accounts, while the menu keeps saying "running". Or several large messages make one page time out on every sweep, and later mail in that account is never reached, with no stalled indicator.
- **Fix:** Add open engineering sub-items to SS-01 and SS-06, then implement them. They should cover backlog/coverage categories, a heartbeat display and a stalled-cursor fallback (shrink or skip after N timeouts). Also add an aggregate status state (setup incomplete, dry run, permission denied, failing, offline), background launch at login and an App Nap evaluation such as `ProcessInfo.beginActivity`.
<!-- sources: todo/spamsieve-a#3 -->

#### 3.8 SS-04 checked, but corrections pull the user into Activity — Medium

- **Where:** `SpamWise/MailMenuView.swift:17` (also :13, :21), `SpamWise/AppModelMailReview.swift:18`, `SpamWise/AppModel.swift:219`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:225`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:253`
- **Problem:** SS-04's goal is correcting selected mail "without leaving Mail" and "without switching to Activity first". Every menu command calls `openWindow(id: "activity")` and shows a results sheet. MenuBarExtra shortcuts fire only while the menu is open, so they do not work from Mail. Corrections use address scope only, despite the "explicit domain scope" criterion. Moves run serially with a 30-second settle each, which keeps the app busy and blocks monitoring. One message over 2 MB makes `rows.map(Self.envelope)` throw and aborts the whole selection. The menu section is disabled while busy, so requests are not dropped silently from the menu, but a documented live invocation during a sweep produced no correction. Live acceptance covered one message, Junk only.
- **Scenario:** The user selects 30 spam messages and presses ⌥⌘J; the keystroke goes to Mail. From the menu, Activity comes forward and SpamWise stays busy for about 15 minutes.
- **Fix:** Reopen SS-04 as partial. Report results through a menu status line or notification instead of opening Activity, and provide shortcuts that work inside Mail (Services or App Intent). Overlap or batch the settle verification, queue or explicitly reject busy requests, skip oversized messages individually, and offer a domain option.
<!-- sources: todo/spamsieve-a#4 -->

#### 3.9 SS-15 checked, but forged Contacts/history senders pass at confidence 100 — Medium

- **Where:** `SpamWiseCore/Sources/Signals/Gates.swift:97` (also :98-99), `SpamWiseCore/Sources/Signals/Evidence.swift:57`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:210`, `TODO.md:302`, `TODO.md:136`
- **Problem:** Only the own-address half of SS-15 exists. The contact, reply and receipt gates allow mail without consulting authentication. `trustedAuthServers` is set only in `SignalsTests.swift:66`, so aligned SPF/DKIM/DMARC can never be used in production. The forwarding and list fixtures pass only because they first add the address to `trustExclusions` by hand. The failure keeps phishing in the Inbox, which is no worse than having no filter and matches SpamSieve's Contacts behavior. It never moves good mail.
- **Scenario:** A phishing message sets `From: colleague@company.com`, a Contacts address, from unrelated infrastructure. `relationshipEvidence` returns `contact == true`, and the message gets an Inbox verdict at confidence 100 with no model classification. The same holds for any address ever replied to and any domain with a past receipt.
- **Fix:** Reopen SS-15. Require trusted, aligned authentication from configured, per-account receiving-server identities before applying the contact/history allow gates. Otherwise fall through to the model with the relationship as weak evidence. Add a forged-contact fixture with no exclusion configured.
<!-- sources: todo/spamsieve-b#1 -->

#### 3.10 PCC selectable in builds where it can never succeed — Low

- **Where:** `SpamWise/ModelSettingsView.swift:37`, `SpamWiseCore/Sources/SpamWiseCore/DistributionCapabilities.swift:12`, `SpamWiseCore/Sources/Classifier/AppleClassifier.swift:46`, `TODO.md:46`
- **Problem:** `DistributionCapabilities.privateCloudCompute` is true for every non-APP_STORE build, and its own doc comment calls the option experimental. No entitlements file has the PCC key, and `AppleClassifier` throws `.configuration` when the model is unavailable. A caption notes the entitlement requirement, which softens the impact.
- **Scenario:** A user selects Apple Private Cloud Compute and consents. Every message fails with a configuration error and is recorded as unclassified until they switch providers.
- **Fix:** Show PCC only when the entitlement is present at runtime, or behind a DEBUG flag. Restate L46 as "PCC implemented, not reachable until L88 is granted".
<!-- sources: todo/roadmap#5 -->

#### 3.11 Undo preview shows store totals, not the correction's changes — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/CorrectionUndo.swift:10` (also :12), `SpamWise/DecisionDetailView.swift:62`, `TODO.md:273`
- **Problem:** `ruleCount` and `exampleCount` count the entire pre-correction snapshot, so "Restores N rules and M examples" previews the whole store, not the "affected rules/examples" SS-11 asks for.
- **Scenario:** With 57 sender rules and 200 examples, undoing one address correction says "Restores 57 rules and 200 examples", which suggests a mass change.
- **Fix:** Compute the delta between snapshot and current state (rules and examples added, replaced or removed) and list those items in the confirmation.
<!-- sources: todo/spamsieve-b#10 -->

#### 3.12 SS-10 explanation and preview fall short — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:115` (also :110-114), `SpamWise/DecisionDetailView.swift:22`, `SpamWise/ContentRuleEditorView.swift:114`, `SpamWise/ContentRuleEditorView.swift:153`, `TODO.md:260`
- **Problem:** The winning content rule appears in Activity as a raw UUID that the rules table never shows. The "test-against-samples" preview tests only the message selected in Mail, conflicts are reduced to a count, and hit counts increase on every classification, including forced dry-run previews.
- **Scenario:** A user sees "gate: user content rule 6F1C…" on a wrongly junked newsletter and cannot identify the rule. After three manual dry runs, one message shows Matches = 3.
- **Fix:** Put the rule's field, pattern and note (or a short name) in the reason. Add a preview against retained reviewed samples that lists conflicting rules. Count hits per unique message, or exclude forced dry runs.
<!-- sources: todo/spamsieve-b#9 -->

#### 3.13 Backup omits trust exclusions; restore changes retention silently — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:83` (payload at :126-136)
- **Problem:** The versioned payload omits manual trust exclusions and learning toggles, and restore sets `retainReviewedContent` according to whether the backup happened to include text. SS-16 promises only "selected settings", own addresses are rediscovered from Mail, and matching retention to restored content is privacy-conservative, so the impact is minor.
- **Scenario:** A user restores on a new Mac. Their manual alias exclusions are gone, so forged-alias mail regains Contacts trust, and retain-content flips off without notice.
- **Fix:** Include trust exclusions and learning toggles in the payload. Keep the current retention preference unless the user changes it during restore, or state the change in the restore summary.
<!-- sources: todo/spamsieve-b#15 -->

#### 3.14 Dry-run training placements are never moved later — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/TrainingFolders.swift:57`, `SpamWise/AppModelFolders.swift:123`
- **Problem:** In the default dry run, a training-folder placement is trained with outcome `.dryRun` and left in place. Because it is still observed in the folder, its claim is never released, and `trainFolderPage` skips claimed keys, so the move never happens after dry run is turned off. SS-08's "preserve failures for review" has no surface beyond ordinary Activity rows.
- **Scenario:** During the dry-run period the user drags 40 messages into "SpamWise Train Junk". After disabling dry run, those messages stay in the training folder indefinitely with no explanation.
- **Fix:** After dry run is disabled, re-dispatch only the move for claimed dry-run placements still present, keeping the training. Add a training-folder status view of claimed, failed and uncertain placements, tracked under SS-08.
<!-- sources: todo/spamsieve-a#8 -->

#### 3.15 TODO structure mixes narrative, finished work and evidence — Low

- **Where:** `TODO.md:1`, `TODO.md:38`, `TODO.md:69`, `TODO.md:75`, `TODO.md:86`, `TODO.md:89`, `TODO.md:94`
- **Problem:** The 44 KB file has 87 checked and 48 open boxes, dated owner-direction narration and checkboxes carrying session history. L75, for example, recounts an HTTP 429, a $1 reservation and keychain details. Open work is spread across the General detectors list, Live acceptance, the Remaining gates table and the SS backlog, with repeats such as the SpamSieve-sample collection at L87, SS-05 and SS-07. L94-96 needs a prose note to explain how parent and child status relate. L38 and L30 are related, not duplicates (integration versus evaluation), but closing one does not visibly close the other. The repository has no CHANGELOG.md, while both sister repos have one.
- **Scenario:** Answering "what is left before release?" means reading 44 KB and reconciling four structures. Stale prose such as SS-03's RDAP premise survives because nobody rereads it.
- **Fix:** Rewrite TODO.md as open work only: one-line acceptance criteria with their kind, grouped as release blockers, acceptance, quality/calibration and SS backlog. Move completed items to CHANGELOG.md, the SpamSieve research to `docs/spamsieve-comparison.md`, and the narrative to `docs/probes`. Cross-reference L38 from L30 and L36.
<!-- sources: todo/roadmap#8, comments/repo-docs#9 -->

#### 3.16 Stale counts, formats and status text in TODO and progress docs — Low

- **Where:** `TODO.md:24`, `TODO.md:55`, `TODO.md:120`, `TODO.md:172`, `TODO.md:84`, `docs/roadmap-progress.md:4`, `docs/spamsieve-parity-progress.md:138`, `docs/spamsieve-parity-progress.md:150`, `docs/spamsieve-parity-progress.md:153`, `docs/spamsieve-parity-progress.md:220`
- **Problem:** Several statements are out of date:
  - L24 says six corpus tests; `test_prepare.py` has eight.
  - L55 says PNG/JPEG OCR; `EmbeddedImages.swift` also accepts GIF, TIFF and HEIC.
  - SS-03's premise ("SpamWise currently supplies RDAP even with that backend") is stale, because `domainRegistrationLookup` is opt-in and blocked in local mode.
  - L120 cites `6a42881`, which is in `origin/main` but not reachable from the squashed local `main`.
  - Slow-sync, latency and calibration gates are tracked both in Live acceptance and in SS-01/02/05.
  - `docs/roadmap-progress.md` reports 72 tests (the package now has about 90) and a notarized install, without saying it is a dated snapshot.
  - The parity doc says SS-14 read status is pending and "no native automation success is claimed", contradicting checked TODO items.
  - Folder-plan visual inspection is pending in the parity doc and in no TODO item.

  The reported `detection-design.md:52` contradiction does not hold and is excluded.
- **Scenario:** A reviewer believes only PNG/JPEG decoding is exposed and misjudges the attack surface, or a maintainer re-adds RDAP suppression that already exists.
- **Fix:** Drop counts from checkboxes or keep them current, and list the actual OCR formats. Update SS-03's premise and cite a commit reachable from `main`, or none. Keep each gate in one place with cross-references. Mark both progress docs as dated history or reconcile them, and add a folder-plan/transfer UI inspection sub-item under SS-09/SS-16.
<!-- sources: todo/roadmap#6, todo/spamsieve-a#10 -->

#### 3.17 L63 "notarized delivery" is a point-in-time event shown as current — Low

- **Where:** `TODO.md:63`, `TODO.md:101`, `CLAUDE.md:485`, `CLAUDE.md:584`
- **Problem:** L63 is an undated, checked record of a review and notarization that predate the Rspamd HTTP, retry-cancellation and keyed Spamhaus HTTPS batches, none of which was notarized. TODO.md:101 still describes draft PR #1 and a branch layout that no longer matches the local squashed `main` (`a66805e`), which diverges from `origin/main` (`d1284e5`).
- **Scenario:** A reader takes L63 to mean HEAD is reviewed and notarized and ships it, while the notarized artifact is several feature batches older.
- **Fix:** Replace L63 with a commit-pinned record ("notarized at <sha>"), or turn it into a recurring release gate that stays unchecked until HEAD is re-verified. Update the TODO.md:101 row to the current branch topology.
<!-- sources: todo/roadmap#4 -->

#### 3.18 Checked parents contradict the TODO's own completion rule — Low

- **Where:** `TODO.md:129`, `TODO.md:136`, `TODO.md:282`, `TODO.md:331`, `docs/spamsieve-parity-progress.md:151`, `docs/spamsieve-parity-progress.md:237`
- **Problem:** TODO.md:129 says parents stay open until their full acceptance criteria are met. Yet SS-15 is checked while L136 says spoofing acceptance remains open, and SS-12 is checked without a test for its "previews never fetch remote resources" criterion. SS-10, SS-11 and SS-13 likewise miss their own text (§3.3, §3.11, §3.12). The parity doc contradicts checked SS-19 items in the opposite direction. SS-17.6 describes harness work in product wording.
- **Scenario:** One reader concludes that spoofing protection and content-rule previews are finished; another, reading the parity doc, concludes native automation was never validated. Both are wrong.
- **Fix:** Reopen parents whose acceptance text is unmet and add explicit sub-items for the gaps. Replace superseded parity-doc paragraphs with current status or mark them historical, and prefix harness-only sub-items with "Harness:".
<!-- sources: todo/spamsieve-b#12 -->

#### 3.19 SS-09 "verified historical preview" never classified anything — Low

- **Where:** `TODO.md:253`, `docs/probes/live-mail-followup.md:15`
- **Problem:** The live run exercised folder resolution, rename fail-closed and the no-action guarantee, but classification returned `consentRequired`. So recomputing decisions without replaying actions or self-established trust was never observed. The wording overstates by implication, not explicit claim.
- **Scenario:** A reader treats SS-09 historical refiltering as runtime-verified although the signed app produced no decision.
- **Fix:** Reword to "folder resolution and no-action preview; classification not exercised", or rerun with the on-device backend and record the decisions.
<!-- sources: todo/spamsieve-a#9 -->

#### 3.20 Parent acceptance criteria with no tracking sub-item — Low

- **Where:** `TODO.md:293`, `TODO.md:376`, `TODO.md:385`, `SpamWise/LocalNotifications.swift:13`
- **Problem:** Open parents carry engineering requirements that no sub-item covers. SS-14's direct correction links are missing: notifications offer only "Review in SpamWise". SS-21's prompt-injection and contradictory-example testing is untracked; `ClassifierTests.swift:4` covers escaping and separation, but no adversarial injection evaluation exists. SS-22's correction-effect preview is untracked.
- **Scenario:** When SS-14.3's delivery check passes, someone checks the parent though correction links were never built; SS-21 could likewise close without injection tests.
- **Fix:** Add open sub-items for notification correction actions (or record a decision that count-only notifications omit them), an adversarial prompt-injection and contradictory-example evaluation, and an inspector preview of a correction's effect.
<!-- sources: todo/spamsieve-b#13 -->
## 4. Swift and SwiftUI conventions

The basic Swift 6 setup is right. `Package.swift` uses tools 6.4 and the `.v6` language mode. It defines the user's full upcoming-feature array, plus `.strictMemorySafety()`, once and applies it to every target. In production code there is no `@unchecked Sendable` and no `nonisolated(unsafe)` (the one exception is in core: `CompletionOnce`). `unsafe` is placed on the narrowest C-interop expression. Most error categories have their own `…Failure` protocol and adopt `LocalizedError`, and user strings use `String(localized:)` with curly quotes. Package tests use Swift Testing with raw-identifier names. Public API carries DocC, and none of the comments fail the comment test. The views avoid view-returning computed vars, use `Label` and `LabeledContent` correctly, and show latency through `Measurement`.

Below that layer, the user's conventions are applied unevenly. Four patterns recur in every module:

- **Bare `String`s where the rules ask for domain types.** These include the decision path, model IDs, mailbox roles, help anchors, URL routes, manifest fields and probe operations. Consumers in other modules compare them against literals, so a typo compiles.
- **Limits written out several times.** The same values appear in Swift constants, in generated AppleScript, in view copy and in backup validation. Several pairs can already drift apart in ways that silently drop or overlap messages.
- **Error cases reused across unrelated categories.** Users see "Mail service unavailable", "More than one message matches", or a frozen-run comparison message for problems such as a non-empty folder, a bad selection count or a duplicate threat sample.
- **Duplicated logic that has already diverged.** Examples are the two MIME walkers, the Claude and Apple guided-output paths, IMAP move and verify, the CLI cost and threshold formulas, and the IMAP endpoint hashes.

The documented "strict SwiftLint passes" baseline is weaker than it looks. `.swiftlint.yml` drops the shared `parent_config` that SubTrack and Zephyr use. Against the user's real rule set, SwiftLint reports 429 findings, two of them errors. The local comment also mislabels a correctness rule (`optional_data_string_conversion`) as a layout rule. Those violations, together with the semicolon-joined statements, long single-closure functions, `.map { $0 }` and swift-format-mangled switches, show code that was written to pass a lenient linter rather than to follow the user's idiom.

On the SwiftUI side, the problems are thin previews, testing concerns leaking into production views, and sheet structure:

- **Previews.** `PreviewHelper` cannot seed accounts, health, labels, audit events or content rules. Most complex views preview only an empty state, and the "No accounts" preview actually shows an account.
- **Test hooks in views.** Three views replace VoiceOver's `accessibilityValue` with raw enum tokens so the UI tests have something to match. The UI tests themselves locate elements by English copy and by coordinates, and every launch is forced to English.
- **Sheets.** Each sheet builds its own title and Done chrome, and most Done buttons respond to neither Return nor Escape.

A few reported deviations need calibrating:

- **`…Sec`/`…Min` suffixes** follow the user's swiftui-conventions rule ("suffix dimensional primitives with abbreviated units", e.g. `timeMin`). The real time-naming problems are unit-less `timeout`/`latency` parameters, `Min` colliding with "minimum", and mixed `Duration`, `TimeInterval` and wall-clock `Date`.
- **`…ID` capitalization** matches the sister repositories, so it is a project-wide style question rather than a defect.
- **Signed `Int` for never-negative values** is recorded as a compatibility decision in the repository CLAUDE.md. The agent wrote that ledger entry, so it does not override the user's `UInt` rule. Several of the affected types are new internal types with no persistence constraint.

| Rule | Status | Main locations |
|---|---|---|
| Swift 6 mode, upcoming features, strict memory safety on every target | Pass for package; fail for Tools harness | `SpamWiseCore/Package.swift`; `Tools/DocumentWorker/check.sh:10`, `Tools/Corpus/README.md:157` |
| Concurrency hygiene (no unchecked Sendable, narrow `unsafe`, structured tasks) | Mostly pass | Redundant `nonisolated` in `SpamWise/AppModelIMAP.swift:43`, `AutomationIntents.swift:7`; avoidable `unsafe` in `Store/Store.swift:92`, `Tools/DocumentWorker/ProbeHost.swift:43`; untracked tasks in `IMAPConnectionModel.swift:34` |
| Shared lint baseline | Fail | `.swiftlint.yml:8` (no `parent_config`; 429 findings under the shared config) |
| Error design (category protocols, general errorDescription, contextual failureReason, actionable recoverySuggestion) | Fail | `TrustExclusions.swift:13`, `AppModelFolders.swift:23`, `AppleMailAdapter.swift:83`, `AutomationIntents.swift:130`, `AppModelErrors.swift:14`, `ThreatMetrics.swift:91`, `SpamhausHTTPS.swift:18`, `Classifier/Types.swift:206` |
| Domain-restricted types; strict throwing parsing | Fail | `SpamWiseCore/State.swift:80` (path), `ModelTokenPricing.swift:26` (model ID), `MailScripts.swift:213` (role), `HelpButton.swift:10`, `ComparisonReport.swift:164`, `StatisticalLearning.swift:22`, `Signals/Evidence.swift:10` |
| `UInt` for never-negative values | Fail (deviation recorded by the agent) | `MailPreferences.swift:52`, `Gates.swift:34`, `Classifier/Types.swift:18`, `Metrics.swift:41`, `IMAPSweepCursor.swift:2` |
| No magic numbers | Fail | `MailScripts.swift:39`, `StateBackup.swift:24`, `RspamdLookup.swift:46`, `FolderSettingsView.swift:36`, `MailReviewView.swift:47`, `SpamWiseEval/main.swift:31`, `Tools/DocumentWorker/Worker.swift:70` |
| Naming: acronyms, abbreviations, unit suffixes | Partial | Acronyms mostly right; `IMAPTLSTransport`, `AuthResult`, `resp`, `operation: ContentRuleOperator`; unit-less `timeout`, `latency`, `monthCost`, pricing rates |
| Orchestrator functions, extension clusters | Fail | `Pipeline.swift:81`, `MIMEParser.swift:258`, `AppleMailAdapter.swift:285`, `GeminiClassifier.swift:22`, `AppModelFolders.swift:54`, `SpamWiseEval/main.swift:132` |
| Don't reinvent the wheel / reuse project code | Fail | `EmbeddedImages.swift:98`, `ClaudeClassifier.swift:5`, `RunReport.swift:36`, `SpamWiseDaemon/main.swift:39` (no swift-argument-parser), `BackupSettingsView.swift:75`, `HelpButton.swift:9` |
| Idiomatic form (one statement per line, `Array(_:)`, `if let x`) | Fail | `ResourceDeadline.swift:26`, `ClaudeClassifier.swift:61`, `AppModel.swift:219`, `LearningState.swift:299`, `BackupSettingsView.swift:71` |
| Non-trivial subviews in own files | Fail | `ContentView.swift:21`, `MailReviewView.swift:69`, `ContentRuleEditorView.swift:88`, `DecisionDetailView.swift:92` |
| `#Preview` for major modes via `PreviewHelper` | Fail | `PreviewHelper.swift:89`, `MailHealthView.swift:53`, `ContentRuleEditorView.swift:184`, `StartupSettingsView.swift:5` |
| Default spacing; fixed sizes only when needed | Partial | `ContentView.swift:155`, `ActivityStatisticsView.swift:63`, sheet minimums across views |
| Accessibility labels and stable identifiers | Partial | `ContentView.swift:158`, `DecisionDetailView.swift:26` (raw tokens spoken), `ContentView.swift:10` (unlabeled spinners), `MailConnectionView.swift:13` |
| Swift Testing names and suites | Mostly pass | Raw-identifier test names throughout; suite naming inconsistent at `LearningTests.swift:9`, `UnitTests/DirectUpdateConfigurationTests.swift:5` |
| UI tests: identifier locators, screen objects return next screen and wait | Partial | `UITests/ActivityScreen.swift:35`, `UITests.swift:222`, `EvidenceScreen.swift:17`, `ReviewScreens.swift:36`, `UITests.swift:271` |
| DocC on public API; no history comments | Pass | Public declarations documented; no comment-test violations found in scope |

### Findings

| # | Severity | Location | Finding |
|---|---|---|---|
| 4.1 | Medium | `.swiftlint.yml:8` | Shared SwiftLint parent config dropped; 429 findings under the real baseline |
| 4.2 | Medium | `SpamWise/AppModelErrors.swift:14` | Error presenter adds remediation and developer-only signing advice |
| 4.3 | Medium | `SpamWise/AppModelFolders.swift:23` | App validation failures reported as "Mail action unavailable" |
| 4.4 | Medium | `SpamWise/AutomationIntents.swift:130` | AutomationIntentError inverts description and reason, collapses all failures |
| 4.5 | Medium | `SpamWise/BackupSettingsView.swift:75` | Security-scoped bounded import copied four times with copied core limits |
| 4.6 | Medium | `SpamWise/ContentView.swift:158` | VoiceOver values replaced with raw enum tokens for UI tests |
| 4.7 | Medium | `SpamWise/FolderSettingsView.swift:36` | App layer repeats page sizes, plan cap and core limits as literals |
| 4.8 | Medium | `SpamWise/IMAPConnectionModel.swift:42` | IMAP setup swallows errors and bypasses the busy gate |
| 4.9 | Medium | `SpamWise/ReviewDigestView.swift:12` | Hand-built sheet chrome; most Done buttons lack keyboard shortcuts |
| 4.10 | Medium | `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:5` | Claude and Apple classifiers duplicate guided types, verdict building and error mapping |
| 4.11 | Medium | `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:26` | Model and service identifiers are bare strings in several literal tables |
| 4.12 | Medium | `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:164` | Manifest and report fields with closed vocabularies are bare strings |
| 4.13 | Medium | `SpamWiseCore/Sources/Evaluation/ThreatMetrics.swift:91` | One context-free ComparisonError serves unrelated commands |
| 4.14 | Medium | `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:22` | Persisted learning features are an unversioned positional `[Double]` |
| 4.15 | Medium | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:83` | Overloaded AppleScript error numbers yield wrong user messages |
| 4.16 | Medium | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:285` | Long mail methods; move/verify, history and hashing logic duplicated and drifted |
| 4.17 | Medium | `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:39` | Generated AppleScript hard-codes bounds duplicated in Swift |
| 4.18 | Medium | `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:98` | MIME traversal reimplemented and drifted from MIMEParser |
| 4.19 | Medium | `SpamWiseCore/Sources/Signals/RspamdLookup.swift:46` | Signals endpoints, timeouts, byte values and DBL codes are inline and duplicated |
| 4.21 | Medium | `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:24` | Retention bounds and bounding code duplicated; backup validation can drift |
| 4.22 | Medium | `SpamWiseCore/Sources/SpamWiseCore/TrustExclusions.swift:13` | Core operations throw errors from unrelated categories |
| 4.23 | Medium | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:39` | Hand-rolled CLI parsers; daemon hides every error behind one sentence |
| 4.24 | Medium | `SpamWiseCore/Sources/SpamWiseEval/RunReport.swift:36` | Eval CLI reimplements threshold policy, cost formula and provider mapping |
| 4.25 | Medium | `UITests/ActivityScreen.swift:35` | UI tests locate by English text and coordinates |
| 4.26 | Low | `MailExtension/MailExtension.swift:1` | Unexplained AppIntents import exists only to force linkage |
| 4.27 | Low | `Scripts/export-store-match.py:280` | Scripts Python has no `.python-version`; hyphenated modules force runpy |
| 4.28 | Low | `Scripts/notarize-match.py:24` | Notarization helper runs credentialed commands with no timeout |
| 4.29 | Low | `SpamWise/ActivityStatisticsView.swift:15` | Statistics recomputed per access; date and account helpers duplicated |
| 4.30 | Low | `SpamWise/AppModel.swift:20` | Sheets modeled as independent Bools and Bool-plus-payload pairs |
| 4.31 | Low | `SpamWise/AppModelCredentials.swift:39` | Key verification hard-codes Haiku 5.5 and ignores the configured model |
| 4.32 | Low | `SpamWise/AppModelIMAP.swift:43` | Redundant `nonisolated`/`@MainActor` imply a default isolation that is not set |
| 4.33 | Low | `SpamWise/AutomationIntents.swift:122` | Pretty JSON encoder duplicated; shared helper hidden in RulesDocument.swift |
| 4.34 | Low | `SpamWise/BackupSettingsView.swift:71` | `guard let`/`if let` rename instead of shadowing |
| 4.35 | Low | `SpamWise/ContentView.swift:10` | Indeterminate progress indicators have no accessibility label |
| 4.36 | Low | `SpamWise/ContentView.swift:21` | Non-trivial subviews live in other views' files |
| 4.37 | Low | `SpamWise/ContentView.swift:155` | Unnamed frame sizes and non-default spacing |
| 4.38 | Low | `SpamWise/CorpusView.swift:65` | File import/export uses `.data` instead of `.emailMessage` |
| 4.39 | Low | `SpamWise/GeneralSettingsView.swift:29` | Hand-rolled `Binding(get:set:)` duplicates existing helpers |
| 4.40 | Low | `SpamWise/HelpButton.swift:9` | AppKit help button reimplements HelpLink; placement inconsistent |
| 4.41 | Low | `SpamWise/HelpButton.swift:10` | Help anchors, routes, categories and health keys are bare strings |
| 4.42 | Low | `SpamWise/IMAPConnectionModel.swift:113` | IMAP settings validated by a JSON round trip |
| 4.43 | Low | `SpamWise/IMAPSettingsView.swift:77` | IMAPConnectionModel constructed on every parent re-render |
| 4.44 | Low | `SpamWise/LearningSettingsView.swift:47` | Misnamed RulesDocument; label export re-encodes per render and swallows errors |
| 4.45 | Low | `SpamWise/MailHealthView.swift:19` | Persistence logic built inside view bodies |
| 4.46 | Low | `SpamWise/MailHealthView.swift:53` | Previews miss major modes; "No accounts" preview shows an account |
| 4.47 | Low | `SpamWise/SettingsView.swift:5` | `@Bindable` where no `$model` projection is used |
| 4.48 | Low | `SpamWise/StartupSettingsView.swift:44` | Views discard caught error detail or ignore failures |
| 4.49 | Low | `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:5` | Money values are unit-less Doubles; USD literal repeated |
| 4.50 | Low | `SpamWiseCore/Sources/Classifier/Types.swift:63` | Lenient truncation and clamping; providers validate differently |
| 4.51 | Low | `SpamWiseCore/Sources/Classifier/Types.swift:135` | Literal defaults shadow named limits; clamp idiom hand-written repeatedly |
| 4.52 | Low | `SpamWiseCore/Sources/Classifier/Types.swift:206` | ClassificationError reused outside its category, with no context |
| 4.53 | Low | `SpamWiseCore/Sources/Decision/Decision.swift:88` | ReviewTreatment mapped with a ternary instead of an exhaustive switch |
| 4.54 | Low | `SpamWiseCore/Sources/Learning/LearningState.swift:299` | `.map { $0 }` used for slice-to-array conversion |
| 4.55 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPConfiguration.swift:40` | ASCII byte literals in validators and the IMAP tokenizer |
| 4.56 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:7` | Credential reference uses optional fields for exclusive sources |
| 4.57 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:48` | IMAPError reused for CLI, model and provider-key failures |
| 4.58 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:110` | Decoder copies CodingKeys into hand-written allow-lists |
| 4.59 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPTransport.swift:75` | `deadlineExceeded` never thrown; timeouts surface as unavailable |
| 4.60 | Low | `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:213` | Mailbox roles and cursors are bare strings with a silent Inbox fallback |
| 4.61 | Low | `SpamWiseCore/Sources/MessageModel/DomainResolver.swift:8` | Missing bundled suffix list silently disables domain logic |
| 4.62 | Low | `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:5` | Some package declarations are needlessly public |
| 4.63 | Low | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:189` | NSRegularExpression with `try?`, force unwraps and recompilation |
| 4.64 | Low | `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:26` | Semicolon-joined statements and formatter-mangled one-liners |
| 4.65 | Low | `SpamWiseCore/Sources/Signals/Evidence.swift:6` | Abbreviated and mismatched names |
| 4.66 | Low | `SpamWiseCore/Sources/Signals/Evidence.swift:10` | Closed vocabularies and validated values stored as free Strings |
| 4.67 | Low | `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:108` | Helpers reimplemented where the project or SDK provides them |
| 4.68 | Low | `SpamWiseCore/Sources/Signals/SpamhausHTTPS.swift:18` | URLError reused for project errors; failure reasons lack context |
| 4.69 | Low | `SpamWiseCore/Sources/Signals/SpamhausHTTPS.swift:83` | Hardened URLSession setup and bounded reads duplicated |
| 4.70 | Low | `SpamWiseCore/Sources/SpamWiseCore/ActivityQuery.swift:27` | Force unwraps guarded only by distant logic |
| 4.71 | Low | `SpamWiseCore/Sources/SpamWiseCore/Exports.swift:1` | Core modules re-exported with underscored `@_exported` |
| 4.72 | Low | `SpamWiseCore/Sources/SpamWiseCore/MailPreferences.swift:52` | Never-negative counts, limits and offsets use signed Int |
| 4.73 | Low | `SpamWiseCore/Sources/SpamWiseCore/NotificationPlanning.swift:39` | Time values: unit-less parameters, ambiguous `Min`, mixed clocks and types |
| 4.74 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:81` | Long functions instead of orchestrators across modules |
| 4.75 | Low | `SpamWiseCore/Sources/SpamWiseCore/ReviewPriority.swift:21` | Priority rank encoded as magic Ints |
| 4.76 | Low | `SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift:68` | State invalidation open-coded at 13 sites |
| 4.77 | Low | `SpamWiseCore/Sources/SpamWiseEval/main.swift:31` | Eval limits duplicated as literals and hard-coded into prose |
| 4.78 | Low | `SpamWiseCore/Sources/Store/Keychain.swift:48` | Failure reasons lack context; Keychain decode failure reports status 0 |
| 4.79 | Low | `SpamWiseCore/Sources/Store/Store.swift:92` | Unsafe C/ObjC calls where checked APIs exist |
| 4.80 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift:43` | Tests hard-code copies of private production limits |
| 4.81 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/LearningTests.swift:9` | Suite naming inconsistent; per-site lint suppressions |
| 4.82 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/ParsingTests.swift:4` | Shared test helpers in unrelated files; history-named test file |
| 4.83 | Low | `Tools/Corpus/audit.py:134` | Corpus thresholds inline and restated in report prose |
| 4.84 | Low | `Tools/Corpus/audit.py:240` | Corpus tools duplicate union-find, verification and private writes |
| 4.85 | Low | `Tools/Corpus/spaphish.py:266` | Percentiles and hyperparameters reported inconsistently |
| 4.86 | Low | `Tools/DocumentWorker/Fixtures.swift:48` | Harness errors lack LocalizedError; encoding failure swallowed |
| 4.87 | Low | `Tools/DocumentWorker/ProbeHost.swift:43` | Pre-cancelled probe uses `withUnsafeCurrentTask` |
| 4.88 | Low | `Tools/DocumentWorker/Protocol.swift:42` | Probe operations stringly typed; 0-PID sentinels |
| 4.89 | Low | `Tools/DocumentWorker/Worker.swift:70` | Magic exit codes and probe sizes not derived from limits |
| 4.90 | Low | `Tools/DocumentWorker/check.sh:10` | Tools Swift harness omits the required upcoming features |
| 4.91 | Low | `UITests/ReviewScreens.swift:36` | Screen objects don't return the next screen or wait |
| 4.92 | Low | `UITests/UITests.swift:271` | XCTWaiter predicate boilerplate written 8 times |
| 4.93 | Info | `SpamWise/MailConnectionView.swift:13` | Mail status accessibility identifier changes with state |
| 4.94 | Info | `SpamWiseCore/Sources/Classifier/Types.swift:156` | Modules share names with their primary types |
| 4.95 | Info | `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:5` | Report types expose Decodable that bypasses validation |
| 4.96 | Info | `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:10` | `ID` capitalized against the "id is not an acronym" rule |

#### 4.1 Shared SwiftLint parent config dropped; 429 findings under the real baseline — Medium

- **Where:** `.swiftlint.yml:8`
- **Problem:** Unlike SubTrack and Zephyr, the config has no `parent_config:` pointing at the shared gist, so "strict SwiftLint passes" is measured against a much weaker rule set. The comment calls the disabled rules layout rules, but `optional_data_string_conversion` is a correctness rule that flags lossy `String(decoding:as:)`.
- **Scenario:** Under the shared config, SwiftLint reports 429 findings, including errors at `UnreadableMailView.swift:7` and `IMAPPaging.swift:23` (`count > 0`). Invalid UTF-8 from IMAP or the Store at 13 `String(decoding:as:)` sites is silently replaced with U+FFFD.
- **Fix:** Adopt the shared `parent_config`, keep only justified overrides with accurate comments, gitignore `.swiftlint/RemoteConfigCache`, and fix or explicitly except the findings.
<!-- sources: config/swift-xcode#8 -->

#### 4.2 Error presenter adds remediation and developer-only signing advice — Medium

- **Where:** `SpamWise/AppModelErrors.swift:14` (also `SpamWise/AppModel.swift:118`)
- **Problem:** `AppModel.describe` appends type-specific remediation after the LocalizedError fields instead of letting `recoverySuggestion` carry it. For `.permissionDenied`, the denial is stated twice. For KeychainError and store-initialization failures, end users are told to check signing entitlements and App Group access.
- **Scenario:** A user who denies Automation reads the denial twice in one status line. A non-developer whose Keychain fails is told to inspect "the signed app’s shared Keychain entitlement". Intents and the daemon never get the remediation at all.
- **Fix:** Move the Automation instructions into `IntegrationError.recoverySuggestion`, give KeychainError a user-actionable suggestion or none, send signing hints to a privacy-safe Logger, and make `describe` only join the three fields.
<!-- sources: conventions/app-logic#2 -->

#### 4.3 App validation failures reported as "Mail action unavailable" — Medium

- **Where:** `SpamWise/AppModelFolders.swift:23` (also `:17-19`, `:31`, `:14`, `:55`, `:118`; `AppModelScanning.swift:128`; `AppModelCredentials.swift:19`; `AppModelRules.swift:14,31,38`; `AppModelMailReview.swift:65`; `AutomationIntents.swift:98,108,112`)
- **Problem:** Several app-level conditions all throw `IntegrationError.unavailable`, whose text is "The Mail action is unavailable. The requested message or Mail service is unavailable.". These include a misnamed training folder, a non-empty folder, the 20-plan cap, an unpersisted record and a missing store.
- **Scenario:** A user saves a "Train as Junk" plan on a non-empty folder, or adds a 21st plan. The status blames Mail, so they go troubleshoot Automation permissions. The plan cap is not explained anywhere.
- **Fix:** Add an app-level `FolderPlanError` (`misnamed(expected:)`, `notEmpty(folder:count:)`, `limitReached(maximum:)`) and a storage-unavailable error. Give each its own interpolated `failureReason` and `recoverySuggestion`, and keep IntegrationError for real adapter failures.
<!-- sources: conventions/app-logic#1, comments/app-logic#6 -->

#### 4.4 AutomationIntentError inverts description and reason, collapses all failures — Medium

- **Where:** `SpamWise/AutomationIntents.swift:130` (also `:100`, `:124-126`)
- **Problem:** The error conforms to `MailIntegrationFailure`. Its `errorDescription` returns case-specific instructions, and it has no `failureReason`. `execute` and `diagnostics` map every underlying error to `.unavailable`: incomplete onboarding, non-Mail transport, selection count, permission denial and store failure.
- **Scenario:** "Correct Selected Mail" with three messages selected, or with IMAP as the transport, shows only "Check setup and Activity in SpamWise. Select one Mail message." Nothing says which condition failed.
- **Fix:** Add an `AutomationFailure` protocol with a shared description, per-case interpolated failure reasons and the UUID guidance in `recoverySuggestion`. Map known underlying errors to specific cases instead of collapsing them.
<!-- sources: conventions/app-logic#3 -->

#### 4.5 Security-scoped bounded import copied four times with copied core limits — Medium

- **Where:** `SpamWise/BackupSettingsView.swift:75` (also `:79`; `ContentRuleEditorView.swift:71-75`; `CorpusView.swift:86-90`; `AppModelRules.swift:39-43`)
- **Problem:** Four sites repeat the same start-access / FileHandle / read-up-to-limit+1 sequence. Three of them hard-code limits that mirror private core constants (`StateBackup.maximumBytes`, `ContentRuleManagement.maximumArchiveBytes`, MIME 2 MB), and the unexplained `+ 1` sentinel is copied each time.
- **Scenario:** Raising `ContentRuleManagement.maximumArchiveBytes` to 2 MB leaves the view reading 1,000,001 bytes. Valid larger archives are truncated and then rejected as invalid JSON.
- **Fix:** Add one `URL.readSecurityScoped(maximumBytes:)` helper that reads one byte past the limit and throws on oversize. Expose the core limits publicly, or let core import APIs take a URL. Call the helper from all four sites.
<!-- sources: conventions/app-views-settings#9, comments/app-views-settings#4 -->

#### 4.6 VoiceOver values replaced with raw enum tokens for UI tests — Medium

- **Where:** `SpamWise/ContentView.swift:158` (also `:150-151`; `DecisionDetailView.swift:24-26`, `:159`; consumers `UITests/ActivityScreen.swift:6-7,75`, `UITests.swift:290`)
- **Problem:** The mode footer, Outcome row and correction label set `accessibilityValue` to `"dryRun"`, `outcome.rawValue` and `correction.rawValue` so the UI tests can match them. VoiceOver speaks these untranslated code tokens, which breaks the rule that test hooks stay out of production and that identified controls keep real accessibility text.
- **Scenario:** A French VoiceOver user selects the Outcome row and hears the localized title followed by "failed" or "moveToJunk".
- **Fix:** Remove the raw-value overrides. Give tests per-state identifiers (for example `activity.mode.dryRun`) or match localized text. If a value is needed, use the localized title.
<!-- sources: conventions/tests#2 -->

#### 4.7 App layer repeats page sizes, plan cap and core limits as literals — Medium

- **Where:** `SpamWise/FolderSettingsView.swift:36` (also `:34`, `:39`; `AppModelFolders.swift:31,43,56`; `MailReviewView.swift:47,51,53`; `AppModelMailReview.swift:41`; `OnboardingView.swift:93,97`; `CorpusView.swift:82,90`; `AdvancedSettingsView.swift:14,20`; `NotificationSettingsView.swift:20`; `LearningSettingsView.swift:35`; `EvidenceSettingsView.swift:63`; `SpamhausSettingsView.swift:34`; `DirectUpdateConfiguration.swift:9,11,22`; `HelpButton.swift:5`; `IMAPConnectionModel.swift:10`)
- **Problem:** Each of these values is written in two or more places, and nothing ties the copies together:
  - The folder preview and Junk review page size (20) appears in both the view offset math and the model's `limit:`.
  - The folder-plan cap (20) appears at both save and scan.
  - The dry-run size ignores `AppModel.defaultScanLimit`.
  - Steppers, Settings copy and the Rspamd endpoint restate core constants: `correctionLimitRange`, `bodyTokenBudgetRange`, the notification interval range, `maximumReviewedLabels`, and the MIME byte cap.
- **Scenario:** Raising the cap at `AppModelFolders.swift:31` to 30 leaves `.prefix(20)` at `:56`, so plans 21–30 save but are never swept. Changing the Junk `limit:` to 50 leaves the view paging by 20, which shows overlapping pages and disables Next too early.
- **Fix:** Expose named constants from AppModel and core, for example `maximumFolderPlans`, `previewPageSize`, `correctionLimitRange`, `maximumReviewedLabels` and `RspamdLoopbackHTTP.endpoint`. Pass a page index rather than a computed offset. Interpolate the limits into copy with FormatStyle, and read the help book name from Info.plist.
<!-- sources: conventions/app-logic#8, comments/app-logic#7, conventions/app-views-main#6, conventions/app-views-settings#10, comments/app-views-settings#5 -->

#### 4.8 IMAP setup swallows errors and bypasses the busy gate — Medium

- **Where:** `SpamWise/IMAPConnectionModel.swift:42` (also `:21`, `:66-70`, `:75`, `:89-94`, unstructured Tasks at `:34`, `:51`, `:77`; `AppModel.swift:356`)
- **Problem:**
  - Every IMAP failure becomes fixed text, so `failureReason` is lost.
  - `load()` uses `try?`, so a decode error looks the same as having no saved connection.
  - An invalid probe UID returns silently.
  - The three Tasks skip `model.run`/`model.busy`, so a mail-moving probe can overlap a scan.
  - `AppModel.correct` discards the IMAP adapter error with `try?` and corrects with a nil adapter.
- **Scenario:** A host with an underscore fails validation, but the status still says "Check the endpoint and Keychain access". The user enters UID "abc" and nothing happens. A correction made while the Keychain item is missing reports "Integration unavailable" and gives no cause.
- **Fix:** Route these operations through `model.run` or a tracked helper that sets `busy`, show `AppModel.describe(error)` or a typed IMAPSetupError, give feedback for invalid input, let `load()` surface decode failures, and stop discarding the adapter error in `correct`.
<!-- sources: conventions/app-logic#4 -->

#### 4.9 Hand-built sheet chrome; most Done buttons lack keyboard shortcuts — Medium

- **Where:** `SpamWise/ReviewDigestView.swift:12` (also `PolicyView.swift:22`; `CorpusView.swift:20,59`; `MailReviewView.swift:16,59,75,88,103`; `ActivityStatisticsView.swift:78`; `AuditTrailView.swift:17,24`; `ReviewDigestView.swift:42`)
- **Problem:** Each sheet builds its own title `Text` and `HStack { Spacer; Done }` instead of using `navigationTitle` and toolbar placements. Titles use `.headline` in two places and `.title2` in three. Only `ReviewDigestView.swift:34` gives Done a keyboard shortcut. The Audit sheet uses its own search field, while Activity uses `.searchable`.
- **Scenario:** With Statistics, Configuration history, Reviewed corpus, Review Junk, Corrections or Message preview open, neither Escape nor Return closes the sheet, so keyboard users must click Done.
- **Fix:** Give sheets `.navigationTitle` with Done in `ToolbarItem(placement: .confirmationAction)` or `.cancellationAction`, use `.searchable` in AuditTrailView, and keep one heading style if inline titles stay.
<!-- sources: conventions/app-views-main#9 -->

#### 4.10 Claude and Apple classifiers duplicate guided types, verdict building and error mapping — Medium

- **Where:** `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:5` (also `:65-78`, `:80-95`; `AppleClassifier.swift:61-74`, `:93-109`, `:114-121`; `RemoteVerdict.swift:79-89`)
- **Problem:** Each FoundationModels classifier declares its own `@Generable` label and verdict pair, with different guide text, and builds `Verdict` and `TokenUsage` from `session.usage` the same way. The cancellation / ClassificationError / LanguageModelError catch chain is written three times. The copies have already drifted: only Apple validates reason length, and Claude maps labels with a switch while Apple uses `rawValue`.
- **Scenario:** A new label, a new confidence guide, or a new LanguageModelError mapping lands in one classifier only. Claude and Apple then validate and retry differently.
- **Fix:** Define one internal `@Generable` verdict with a String-backed label that matches `MailLabel`, a shared `Verdict(guided:session:modelID:)` factory, and one `ClassificationError(mapping:)` initializer used at all three catch sites.
<!-- sources: conventions/core-classifier-learning#6 -->

#### 4.11 Model and service identifiers are bare strings in several literal tables — Medium

- **Where:** `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:26` (also `ClaudeClassifier.swift:21-27`; `GeminiClassifier.swift:6,13,17`; `OpenAIClassifier.swift:6,13,17`; `AppleClassifier.swift:12-17`; `AdvancedSettings.swift:18-22`; `SpamWiseDaemon/main.swift:129-137`; `SpamWiseEval/main.swift:106-107,129`; `ConfiguredClassifier.swift:22,59`; `IMAPDaemonConfiguration.swift:106,123`; `Store.swift:52`; `Keychain.swift:35,40`)
- **Problem:** The supported model set is closed and known at compile time. Even so, it is a `String` checked by separate literal switches in pricing, Claude initialization, the OpenAI and Gemini single-value guards, AdvancedSettings, the daemon, the eval CLI and the budget reservation. The Keychain service, the account name and the App Group are also inline duplicates.
- **Scenario:** Adding a Claude model to `ClaudeClassifier` without updating the pricing table makes `.rates(for:)` throw after the paid call has returned. The verdict is discarded and the spend is still incurred. The daemon still rejects `--model <new>`. Changing `ModelBackend.claude.defaultModelID` silently moves every call to the $1.00 reservation.
- **Fix:** Add a String-backed `ModelIdentifier` enum with `backend`, `pricing(at:)` and `claudeModel` properties. Make `rates(for:)` non-throwing over it, and parse strings only at the persistence and CLI boundary. Key provider credentials by `ModelBackend`, and hoist the service and App Group identifiers into named constants.
<!-- sources: conventions/core-classifier-learning#1, conventions/mail-integration#7, conventions/core-pipeline-store#15 -->

#### 4.12 Manifest and report fields with closed vocabularies are bare strings — Medium

- **Where:** `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:164` (also `:37`, `:51`, `:98`, `:101`, `:147`, `:169`; `Metrics.swift:20,92,122`; `ThreatMetrics.swift:8,10,89`; `SpamWiseEval/main.swift:67-72,111-123`)
- **Problem:** The fields `priorExposure`, `costBasis`, `frozenAt`, decision `path`, threat `truth` keys, export role and the provider choice are strings checked by hand against literal arrays or prefixes. The calibration filter `$0.path == "model"` depends on the literal at `PipelineClassification.swift:38`.
- **Scenario:** Renaming the pipeline's `"model"` path still compiles but silently empties every CalibrationBucket. Writing `"priorExposure": "None"` gives the generic invalidManifest error instead of a decoding error at the key.
- **Fix:** Add Codable enums (PriorExposure, CostBasis, a shared DecisionPath, MailboxRole). Decode `frozenAt` as Date, key `truth` by `ThreatKind`, and map `--model` through ModelBackend.
<!-- sources: conventions/eval-scripts#2 -->

#### 4.13 One context-free ComparisonError serves unrelated commands — Medium

- **Where:** `SpamWiseCore/Sources/Evaluation/ThreatMetrics.swift:91` (also `SpamWiseEval/main.swift:31,47`; `ComparisonReport.swift:48-61,186-192`; `ReviewedCorpus.swift:81-85`; `SpamWiseEval/Options.swift:94-111`)
- **Problem:** `ComparisonError.invalidManifest` has a single fixed reason about frozen-run comparison. It is used for about 12 manifest checks, threat-report validation and two oversized-file checks. ReviewedCorpus reports a non-regular path as `.oversized`. EvaluationError reasons name no flag, file, hash or variable.
- **Scenario:** `--threat-report` with a duplicate sampleID prints advice about human-reviewed, campaign-disjoint comparison runs. `--reviewed somedir/` reports that the export is too large.
- **Fix:** Split the errors into ComparisonManifestError, ThreatReportError and ReviewedCorpusError, with cases that carry context (`.duplicateSample(id)`, `.fileTooLarge(path, limit)`, `.notRegularFile(url)`). Break `validate` into named checks, and move actionable text to `recoverySuggestion`.
<!-- sources: conventions/eval-scripts#1 -->

#### 4.14 Persisted learning features are an unversioned positional `[Double]` — Medium

- **Where:** `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:22` (also `:7`; `LearningState.swift:40`, `:139`)
- **Problem:** Each feature's meaning is defined only by its array position, `featureCount = 8` must match the literal by hand, and `LearningSample` has no schema version. The decoder silently drops any sample whose feature count differs.
- **Scenario:** A developer adds a ninth feature and bumps `featureCount`. On the next launch every persisted sample is filtered out, which erases the user's correction training set without an error.
- **Fix:** Model the features as a `LearningFeatures` struct with named properties, a schema version and a `vector` accessor. Migrate or zero-fill older versions in `init(from:)`. At minimum, add a test that the feature count matches.
<!-- sources: conventions/core-classifier-learning#7 -->

#### 4.15 Overloaded AppleScript error numbers yield wrong user messages — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:83` (also `:224`, `:342`; `MailScripts.swift:57-58,69-70,113-120,172,201,249`; `MailFolderScripts.swift:10,17,27`; `MailDestinations.swift:38`)
- **Problem:** The executor maps every -1701 to `.ambiguous` and every -1702 to `.staleMessage`. The scripts reuse those real OSStatus values for selection count, account and mailbox resolution, existing annotations and folder limits, so Mail's own errors with those numbers get the same mapping. A non-probe subject throws `.unavailable`.
- **Scenario:** Correct Selection with 0 or 60 messages selected says "More than one message matches the requested identity." A message that already has a red flag fails with "no longer matches its recorded state."
- **Fix:** Use script-specific error numbers outside the OSStatus range, interpolated from a private enum. Map them to dedicated cases such as `selectionCount(expected:)`, `accountUnresolved`, `existingAnnotation` and `notProbeMessage`, each with an interpolated reason and an actionable suggestion.
<!-- sources: conventions/mail-integration#1 -->

#### 4.16 Long mail methods; move/verify, history and hashing logic duplicated and drifted — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:285` (also `:236`, `:314-319`, `:324-331`; `IMAPAdapter.swift:32,63-71,122-129,143-175,183,237-265`; `IMAPDaemonConfiguration.swift:166-175`; `MailScripts.swift:130,158,182-183,220-227,253-260`; `SpamWiseDaemon/main.swift:51-112`)
- **Problem:** `importHistory` and `SpamWiseDaemon.run` do their detailed work inline instead of delegating to helpers. Safety logic is copied rather than composed: IMAP `perform` versus `probeMove`, replied-address extraction, the MOVE capability check and the AppleScript source guard. The copies have already drifted: the sweep key hashes the host without lowercasing it, while the validation fingerprint lowercases it.
- **Scenario:** A move-verification fix lands in `perform` but not in `probeMove`, so the probe validates accounts under different rules from live actions. A host that changes only in case keeps its validation but restarts its sweep cursor.
- **Fix:** Extract `repliedAddresses(in:)`, `isLikelyReceipt(_:)`, a shared `moveAndVerify(_:to:session:)`, `MailScripts.sourceGuard(_:)`, `supportsMove(_:)`, one `endpointFingerprint`, and one script page-loop builder. Then split the daemon's `run` into named steps.
<!-- sources: conventions/mail-integration#6 -->

#### 4.17 Generated AppleScript hard-codes bounds duplicated in Swift — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:39` (also `:41`, `:6`, `:54`, `:66`, `:69`, `:81`, `:198`, `:215`, `:242`; `MailFolderScripts.swift:5,10,17,22,27,45,64`; `AppleMailAdapter.swift:111,113,223`; `AppleMailFolders.swift:7,11`; `MailDestinations.swift:35`; `IMAPAdapter.swift:6`; `IMAPPaging.swift:6`; `SpamWiseDaemon/main.swift:9`)
- **Problem:** Each bound is written as a literal in the script text and again as one or more Swift constants. That covers the 2,000,000-byte message size, folder depth 16, page size 1,000, the 50-message selection and the "8 seconds" timeout. `maximumPageSize` is defined in both MailScripts and AppleMailAdapter, and the IMAP size limit is defined twice on one type.
- **Scenario:** Raising `AppleMailAdapter.maximumMessageBytes` to 4 MB leaves `pageEnvelope` rejecting messages over 2 MB, so they are counted as unavailable on every sweep and never classified. If the two `maximumPageSize` constants diverge, every page throws.
- **Fix:** Interpolate the Swift constants into the script templates (`\(maximumMessageBytes)`, `\(scriptTimeoutSeconds)`, `\(maximumSelectionCount)`) and keep one owner per bound.
<!-- sources: conventions/mail-integration#5, comments/mail-integration#5 -->

#### 4.18 MIME traversal reimplemented and drifted from MIMEParser — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:98` (also `:6-13`, `:47`, `:65-79`, `:100`, `:125-142`; `MIMEParser.swift:6-12,71-79,202,228-257,280-291`)
- **Problem:** EmbeddedImages copies header splitting, boundary parsing, multipart iteration and the resource limits from MIMEParser, and the copies disagree:
  - Header limit: `<=` versus `<`.
  - Boundary matching: exactly one match versus first match.
  - Close delimiter: an exact match versus `hasSuffix("--")`.
  - Source decoding: lossy UTF-8 versus byte-preserving.

  Because MIMEParser closes on any `hasSuffix("--")`, a legal boundary such as `abc--` closes at its opening delimiter.
- **Scenario:** A message with a 65,536-byte header block, or with boundary `abc--`, is accepted by one parser and rejected by the other. OCR text and body text then describe different MIME trees.
- **Fix:** Extract one internal MIME walker in MessageModel that both parsers use, and detect the close delimiter as `trimmed == "--" + boundary + "--"`.
<!-- sources: conventions/core-parsing-signals#8 -->

#### 4.19 Signals endpoints, timeouts, byte values and DBL codes are inline and duplicated — Medium

- **Where:** `SpamWiseCore/Sources/Signals/RspamdLookup.swift:46` (also `:47`, `:55`, `:76`, `:36`; `RspamdLoopbackHTTP.swift:29`; `ExternalEvidence.swift:112,120,134-137,156,174`; `SpamhausHTTPS.swift:8-12,16-17,31-32,61`; `RDAP.swift:64`; `MIMEParser.swift:112-113`)
- **Problem:** The Rspamd 3-second cap is written three times next to an existing constant. The port, endpoint and `--timeout=2` are literals. Raw ASCII byte values hide their meaning. The DNS `validCodes` set copies `SpamhausHTTPS.codes`.
- **Scenario:** Someone changes the Rspamd port or time limit in one place and misses the CLI argument or the HTTP endpoint. A new DBL code added to `SpamhausHTTPS.codes` but not to `validCodes` causes HTTPS listings to be mapped and then discarded as unknown.
- **Fix:** Hoist endpoints (as `URL`), ports, timeouts (as `Duration`) and one shared DBL code table into `private static let` constants, and derive the DNS set from the table. Use `UInt8(ascii:)` for byte classes and an enum for evidence source names.
<!-- sources: conventions/core-parsing-signals#6 -->

#### 4.21 Retention bounds and bounding code duplicated; backup validation can drift — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:24` (also `:23`, `:25`, `:27`, `:116`; `PipelineCorrections.swift:4-8,116-121`; `CorpusManagement.swift:6-10,18-26`; `Pipeline.swift:6`; `RuleManagement.swift:33`; `ContentRuleManagement.swift:5`)
- **Problem:** The 200-correction, 500-label, 16,000-character, 40-URL and 10,000-rule limits are declared separately in three or four files, and backup validation uses a literal `<= 100` for content rules. The message-bounding code is copied. The limits are also applied inconsistently: corrections truncate labels with `suffix(500)`, while corpus import throws at 501.
- **Scenario:** Raising `PipelineCorrections.maximumCorrections` to 300 makes every later backup fail to restore with "backup could not be opened", because StateBackup still validates against 200.
- **Fix:** Define the limits once, for example `enum RetentionLimits` or static members on AppState. Add a single `ParsedMessage.boundedForRetention()` used by corrections, corpus import, retries and backup validation.
<!-- sources: conventions/core-pipeline-store#8, comments/core-pipeline-store#17 -->

#### 4.22 Core operations throw errors from unrelated categories — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/TrustExclusions.swift:13` (also `:9`; `PipelineCorrections.swift:27,30,41,44`; `CorpusManagement.swift:17,61,77,104`; `PipelineReadStatus.swift:45`; `Pipeline.swift:273`; `NotificationPlanning.swift:68`; `TrainingFolders.swift:33,35,49`; `AutomationRequest.swift:38,48,52,73`; `CorrectionUndo.swift:31`)
- **Problem:** Core code borrows the nearest existing error case, so the user sees a description of a different failure. Examples: `RuleManagementError.tooManyRules` for trust exclusions, `ClassificationError.invalidOutput` for Review with domain scope, `ParseError.tooLarge` for batch size, and `IntegrationError.unavailable` or `.staleMessage` for missing records, request replay and unavailable undo.
- **Scenario:** Pasting 101 trust-exclusion addresses reports that the 10,000 sender-rule maximum was reached. Importing 21 reviewed messages reports that the message exceeds content limits.
- **Fix:** Add focused error types, each with a category protocol and LocalizedError: `CorrectionError`, `TrustExclusionError(tooManyAddresses(limit:))`, `CorpusError`, `AutomationError` and `UndoError`.
<!-- sources: conventions/core-pipeline-store#4 -->

#### 4.23 Hand-rolled CLI parsers; daemon hides every error behind one sentence — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:39` (also `:136`, `:151-191`; `SpamWiseEval/Options.swift:28,47,54`; `SpamWiseEval/main.swift:10,13-20`)
- **Problem:** Both executables parse arguments by hand even though swift-argument-parser is the established choice and Zephyr already resolves it. The daemon reports usage errors as `IMAPError.invalidConfiguration`, and `main` then replaces every non-cancellation error with "Headless operation failed. Check settings and credentials." The eval parser accepts only `--flag value` pairs and does not reject conflicting modes.
- **Scenario:** A bad `--limit`, an unknown `--model`, a missing config file and a JSON typo all print the same sentence and exit 1. `spamwise-eval --export … --input c --model …` runs an export and ignores the other flags. `--input c --help` fails with "Invalid arguments".
- **Fix:** Adopt `AsyncParsableCommand` with typed `@Option`s, subcommands and `validate()`. Print `localizedDescription` and `failureReason`, which carry no secrets, and give usage errors their own type.
<!-- sources: conventions/mail-integration#2, conventions/eval-scripts#4 -->

#### 4.24 Eval CLI reimplements threshold policy, cost formula and provider mapping — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/RunReport.swift:36` (also `:66-69`; `Classifier/Types.swift:30-35`; `Decision.swift:82-84`; `SpamWiseEval/main.swift:111-114`; `Scripts/evaluate-with-keychain.swift:31-35,59-67`; `Scripts/store-provider-key.swift:35`)
- **Problem:** `thresholdCandidates` rebuilds Decision's Junk-to-Review demotion rule instead of calling `Decision.evaluate`. The cost estimate copies `TokenUsage.estimatedCost` and keeps its own per-million constant. Provider selection uses model-ID prefixes even though `ModelBackend` exists. The standalone `Scripts/*.swift` programs cannot import SpamWiseCore, so their copied constants are largely unavoidable.
- **Scenario:** A change to Decision policy, or adding a cache-write rate to `estimatedCost`, makes the report's threshold candidates and costs describe behavior the product does not have. Production thresholds are chosen from those numbers.
- **Fix:** Compute candidates with `Decision.evaluate(verdict, strength:)`. Build a `ModelTokenPricing` from the override flags, which requires making its initializer public, and report `estimatedCost`. Resolve providers through `ModelBackend` and generate the usage list from it.
<!-- sources: conventions/eval-scripts#3, correctness/eval-scripts#14 -->

#### 4.25 UI tests locate by English text and coordinates — Medium

- **Where:** `UITests/ActivityScreen.swift:35` (also `:12`, `:47`; `UITests.swift:40,60,68-69,75,80,84-85,91-92,100,139,222,234`; `EvidenceScreen.swift:17`; `RuleEditorView.swift:26`)
- **Problem:** The rule is to query by `.accessibilityIdentifier`, never by localized label or index. The suite violates it in four ways:
  - It finds Settings tabs by their English titles.
  - It asserts rule actions, threat status and correction status by comparing English copy.
  - It opens a disclosure by clicking a normalized coordinate.
  - It forces every launch into English.

  The Settings tabs are a real framework limit; the rest are not.
- **Scenario:** Rewording "Not assessed" or "Correction saved. Mail action: failed." fails the corrections test with no behavior change. Running the suite in Spanish or French fails at the tab lookup.
- **Fix:** Add state-specific identifiers such as `threats.status.unassessed` and assert that they exist. Look up native tab titles through the String Catalog, and click the disclosure element instead of a coordinate.
<!-- sources: conventions/tests#3 -->

#### 4.26 Unexplained AppIntents import exists only to force linkage — Low

- **Where:** `MailExtension/MailExtension.swift:1`
- **Problem:** The file uses no AppIntents symbol. Nothing else links the framework, and the repository ledger says the linkage silences a metadata warning.
- **Scenario:** A maintainer deletes the import because it looks unused, and the warning returns, failing the warnings-as-errors build.
- **Fix:** Link AppIntents through the target's frameworks phase and drop the import, or keep the import with a one-line comment explaining it.
<!-- sources: conventions/mail-integration#19 -->

#### 4.27 Scripts Python has no `.python-version`; hyphenated modules force runpy — Low

- **Where:** `Scripts/export-store-match.py:280` (also `Scripts/test_export_store_match.py:14,101`; `docs/app-store.md`)
- **Problem:** Tools/Corpus, Tools/Preferences and Tools/Site each pin an interpreter, but Scripts/ does not, and the docs borrow the `spamwise-corpus` env. `export-store-match.py` needs Python 3.11+ for `datetime.UTC`. Hyphenated filenames force `runpy` loading and patching of `__globals__`.
- **Scenario:** Running export-store-match with an older system python3 fails at import. Renaming a helper breaks the runpy-dict tests at runtime instead of at import.
- **Fix:** Add `Scripts/.python-version`, or move the scripts into a packaging project. Rename the modules to snake_case, import them normally, and patch with `unittest.mock.patch`.
<!-- sources: conventions/eval-scripts#14 -->

#### 4.28 Notarization helper runs credentialed commands with no timeout — Low

- **Where:** `Scripts/notarize-match.py:24` (also `:47`, `:75`; `export-store-match.py:72-90`)
- **Problem:** The export helper has bounded waits and process-tree cleanup. The notarization helper's own `run` does not, and it covers Match decryption, altool and `notarytool --wait`.
- **Scenario:** `notarytool --wait` hangs, and the decrypted AuthKey.p8 stays in the temporary directory until someone kills the process. A SIGKILL leaves it on disk.
- **Fix:** Share one `run` helper with a timeout and process-tree cleanup between both scripts, and give notarization a generous but finite timeout.
<!-- sources: conventions/eval-scripts#15 -->

#### 4.29 Statistics recomputed per access; date and account helpers duplicated — Low

- **Where:** `SpamWise/ActivityStatisticsView.swift:15` (also `:17-23`, `:37`, `:44-68`; `ActivityDateFilterView.swift:27-30`; `ContentView.swift:78,166`)
- **Problem:** The computed `statistics` property re-filters and re-sorts the whole log on every read, including once per bar inside the Chart closure. The end-of-day logic is copied in two views and the account-list expression in two others.
- **Scenario:** One render runs the query 9 + N times, where N is the number of bars. A DST fix to the end-of-day rule has to be made in two places.
- **Fix:** Bind `statistics` once in `body`. Add an `ActivityQuery.setDays(from:through:calendar:)` helper and a shared account-IDs helper on AppModel.
<!-- sources: conventions/app-views-main#18 -->

#### 4.30 Sheets modeled as independent Bools and Bool-plus-payload pairs — Low

- **Where:** `SpamWise/AppModel.swift:20` (also `ContentView.swift:129-136`; `RuleEditorView.swift:40-46,59`; `ContentRuleEditorView.swift:32-37,53-55`)
- **Problem:** Six mutually exclusive `show…` flags allow states that should be impossible. The rule editors keep a presentation Bool and the payload in separate variables, where nil means "new". Statuses are preformatted strings in the model.
- **Scenario:** Any path that sets `showingEditor = true` without resetting the payload opens the wrong form, which already happens after Remove in ContentRuleEditorView. When the digest flag and the corrections flag are both set, presentation order is unclear.
- **Fix:** Use `enum ActivitySheet: Identifiable` with one `.sheet(item:)`, use an identifiable editor-mode enum (`.new`, `.edit(rule)`), and model statuses as enums localized in the view.
<!-- sources: conventions/app-logic#6, conventions/app-views-settings#21 -->

#### 4.31 Key verification hard-codes Haiku 5.5 and ignores the configured model — Low

- **Where:** `SpamWise/AppModelCredentials.swift:39` (also `:17`, `:25`, `:58`, `:61`; `ModelSettingsView.swift:57`)
- **Problem:** Verification uses `ClaudeClassifier(key:)`, which always uses `.haiku5_5`, while classification uses the configured model ID. Status strings hard-code "Haiku 5.5", and localized text is persisted in the verification record.
- **Scenario:** A user with a custom Claude model passes verification against Haiku, and then classification fails because the key lacks access to the configured model.
- **Fix:** Verify against the configured model, interpolate its display name, and persist a non-localized marker that is localized at display time.
<!-- sources: conventions/app-logic#20 -->

#### 4.32 Redundant `nonisolated`/`@MainActor` imply a default isolation that is not set — Low

- **Where:** `SpamWise/AppModelIMAP.swift:43` (also `AutomationIntents.swift:7,95,130`; `PreviewHelper.swift:4`; `UITestFixture.swift:63`)
- **Problem:** The app target does not set `SWIFT_DEFAULT_ACTOR_ISOLATION`, so type-level `nonisolated` has no effect and suggests a MainActor default that does not exist. `PreviewHelper` is `@MainActor` as a whole, which forces fixture seeding onto the main actor.
- **Scenario:** A maintainer assumes the target defaults to MainActor, adds an unannotated helper that touches AppKit, and gets nonisolated code.
- **Fix:** Remove the redundant modifiers, or adopt the MainActor default deliberately. Mark only `PreviewHelper.model(...)` `@MainActor`.
<!-- sources: concurrency#15, conventions/app-logic#14 -->

#### 4.33 Pretty JSON encoder duplicated; shared helper hidden in RulesDocument.swift — Low

- **Where:** `SpamWise/AutomationIntents.swift:122` (also `:99`; `RulesDocument.swift:21-27`)
- **Problem:** `JSONEncoder.pretty` sits at the bottom of the FileDocument file, so the intent rebuilds the same encoder inline, and the diagnostics path uses a plain encoder.
- **Scenario:** Someone adds `.withoutEscapingSlashes` to `pretty`, and intent output stops matching UI exports.
- **Fix:** Move the extension to its own file and use `JSONEncoder.pretty` everywhere.
<!-- sources: conventions/app-logic#16 -->

#### 4.34 `guard let`/`if let` rename instead of shadowing — Low

- **Where:** `SpamWise/BackupSettingsView.swift:71` (also `TrustExclusionsView.swift:10`)
- **Problem:** `guard let url = pendingURL` and `if let own = model.state.ownAddresses` bind new names where swift-conventions asks for shadowing.
- **Scenario:** A style inconsistency only. It has no runtime effect.
- **Fix:** Use `guard let pendingURL` and `if let ownAddresses = …`.
<!-- sources: conventions/app-views-settings#20 -->

#### 4.35 Indeterminate progress indicators have no accessibility label — Low

- **Where:** `SpamWise/ContentView.swift:10` (also `:160`; `OnboardingView.swift:36`)
- **Problem:** The bare `ProgressView()` spinners do not say what is in progress.
- **Scenario:** At launch and during scans, VoiceOver announces only "progress indicator".
- **Fix:** Use `ProgressView("Loading…")` with `.labelsHidden()`, or add an `.accessibilityLabel`.
<!-- sources: conventions/app-views-main#22 -->

#### 4.36 Non-trivial subviews live in other views' files — Low

- **Where:** `SpamWise/ContentView.swift:21` (also `MailReviewView.swift:69,94`; `DecisionDetailView.swift:92,132,144,175,221`; `ContentRuleEditorView.swift:88-158,160-182`)
- **Problem:** Several sizable views are not in files of their own:
  - ActivityView, the main window at about 118 lines, is a private struct in ContentView.swift.
  - CorrectionResultsView and MessagePreviewView live in MailReviewView.swift.
  - The shared VerdictBadge lives in DecisionDetailView.swift.
  - ContentRuleFormView, a 70-line sheet with persistence logic, lives in ContentRuleEditorView.swift.

  Some `localizedTitle` extensions also sit outside LocalizedLabels.swift.
- **Scenario:** Searching for the Activity window, the correction-results sheet or the content-rule labels by file name finds nothing.
- **Fix:** Move these views into their own files and consolidate the `localizedTitle` extensions in LocalizedLabels.swift.
<!-- sources: design/onboarding-consistency#25, conventions/app-views-main#8, conventions/app-views-settings#13 -->

#### 4.37 Unnamed frame sizes and non-default spacing — Low

- **Where:** `SpamWise/ContentView.swift:155` (also `:11`, `:122`, `:128`, `:177`; `ActivityStatisticsView.swift:63,80`; `ActivityDateFilterView.swift:20`; `AuditTrailView.swift:26`; `CorpusView.swift:46,62`; `MailReviewView.swift:36,43,62,90,105`; `ReviewDigestView.swift:36,43`; `OnboardingView.swift:50`; `SettingsView.swift:37`; `RuleEditorView.swift:24,28`; `TrustExclusionsView.swift:19`)
- **Problem:** Every sheet chooses its own literal minimum size, and the main window minimum is written twice. The status footer uses custom spacing of 6 and padding of 8. The fixed TextEditor height ignores Dynamic Type.
- **Scenario:** Changing the Activity window minimum means editing two literals. Sheet proportions vary for no reason (600×600, 700×420, 760×450).
- **Fix:** Name the sizes as private static constants or in a shared `SheetMetrics`, use default spacing, and use `@ScaledMetric` for text heights.
<!-- sources: conventions/app-views-main#7 -->

#### 4.38 File import/export uses `.data` instead of `.emailMessage` — Low

- **Where:** `SpamWise/CorpusView.swift:65` (also `DecisionDetailView.swift:84`)
- **Problem:** "Import reviewed .eml files…" accepts any file, and raw-source exports are not typed as email, although `UTType.emailMessage` exists.
- **Scenario:** A user picks PDFs, and the batch fails with a generic parse error.
- **Fix:** Use `[.emailMessage]` for the importer and `.emailMessage` for the exporter.
<!-- sources: conventions/app-views-main#17 -->

#### 4.39 Hand-rolled `Binding(get:set:)` duplicates existing helpers — Low

- **Where:** `SpamWise/GeneralSettingsView.swift:29` (also `EvidenceSettingsView.swift:14-20,31-35`; `FolderSettingsView.swift:24`; `IMAPSettingsView.swift:8-21`; `ModelSettingsView.swift:10-23`)
- **Problem:** Because the target fields are `Bool?`, each view writes its own closures next to `mailBinding` and `advancedBinding`. FolderSettingsView builds an optional binding by hand, where `Binding($plan)` would do.
- **Scenario:** The next `Bool?` setting adds another copy, and the copies can disagree about what nil means.
- **Fix:** Add `advancedBinding(_:default:)` and `mailBinding` overloads for `Bool?`, and use `if let plan = Binding($plan)`.
<!-- sources: conventions/app-views-settings#17 -->

#### 4.40 AppKit help button reimplements HelpLink; placement inconsistent — Low

- **Where:** `SpamWise/HelpButton.swift:9` (also `GeneralSettingsView.swift:47-53`; `AdvancedSettingsView.swift:45`; `ModelSettingsView.swift:103`; `PolicyView.swift:34`; `MailConnectionView.swift:72`)
- **Problem:** A 30-line NSViewRepresentable wraps `.helpButton`, although SwiftUI has `HelpLink` (macOS 14+, deployment target macOS 27). In General, the filtering-strength help button sits beside "Show setup". On Advanced, it is hidden inside a collapsed disclosure.
- **Scenario:** A user clicks ? next to "Show setup" and gets the Filtering strength page.
- **Fix:** Replace the wrapper with `HelpLink { Help.open(page) }` and put one help link per pane, in the section it documents or at the trailing bottom.
<!-- sources: design/settings#17, design/onboarding-consistency#21 -->

#### 4.41 Help anchors, routes, categories and health keys are bare strings — Low

- **Where:** `SpamWise/HelpButton.swift:10` (also `:5`; `LocalizedLabels.swift:105-114`; `MyApp.swift:9,18`; `ToolsCommands.swift:11,16`; `AppModelNavigation.swift:7-11`; `LocalNotifications.swift:11,14,51,61,63`; `AppModelFolders.swift:61,95,107`; `FolderSettingsView.swift:26`; `SpamhausSettingsView.swift:32-35,51`; `IMAPSettingsView.swift:42,67`; `MailReviewView.swift:7,23`; `UnreadableMailView.swift:4`)
- **Problem:** The following are all free strings:
  - help anchors, a closed set of six, which fall back silently through `default:`
  - URL hosts
  - notification categories, where "activity" is used but never registered
  - window IDs
  - the `"folder:" + id` health key, stored under an `accountID:` parameter
  - Spamhaus URLs, which are force-unwrapped
  - the IMAP port and UID, kept as text
  - an empty string standing in for "no account"
- **Scenario:** `HelpButton(page: "correcting-mistake")` compiles, VoiceOver says "Help for SpamWise Help", and clicking it opens nothing. Renaming a URL host breaks notification taps silently.
- **Fix:** Add `HelpPage`, `AppRoute`/`NotificationCategory`, `AppWindow` and `ScanCursor` enums. Use typed `URL` constants, `TextField(value:format:)` bound to `UInt16`/`UInt32`, and an optional account selection.
<!-- sources: conventions/app-logic#7, conventions/app-views-main#10, comments/app-views-main#9, conventions/app-views-settings#16, comments/app-logic#13 -->

#### 4.42 IMAP settings validated by a JSON round trip — Low

- **Where:** `SpamWise/IMAPConnectionModel.swift:113` (also `:10`; `MailIntegration/IMAPConfiguration.swift:16-25`)
- **Problem:** The public initializer does not validate, and `validate()` is internal, so the app encodes and re-decodes the configuration just to trigger validation. The default port `"993"` copies the core default. The transport does validate before connecting, so the cost is readability and API strictness.
- **Scenario:** A future caller builds an invalid configuration directly, and nothing fails until connection time.
- **Fix:** Make the initializer throwing, or add a public `validated(...)`, and expose `IMAPConfiguration.defaultPort`.
<!-- sources: conventions/app-logic#5 -->

#### 4.43 IMAPConnectionModel constructed on every parent re-render — Low

- **Where:** `SpamWise/IMAPSettingsView.swift:77` (also `IMAPConnectionModel.swift:14`)
- **Problem:** `State(initialValue:)` keeps only the first instance, but the init allocates a new model with a fresh UUID on every parent `body` evaluation.
- **Scenario:** There is no visible failure today. Any side effect later added to the init would repeat on every re-render.
- **Fix:** Have AppModel own the model and pass it in, or create it once in `.task`.
<!-- sources: conventions/app-views-settings#25 -->

#### 4.44 Misnamed RulesDocument; label export re-encodes per render and swallows errors — Low

- **Where:** `SpamWise/LearningSettingsView.swift:47` (also `BackupSettingsView.swift:13`; `RulesDocument.swift:6`)
- **Problem:** A generic data FileDocument named for rules is used for backups, labels, sources and statistics. The label exporter encodes up to 500 labels on every `body` pass, and `try?` turns an encoding failure into a 0-byte file.
- **Scenario:** Toggling any switch in the pane re-encodes the retained corpus on the main actor. An encoding failure exports an empty file and still reports success.
- **Fix:** Rename the type to something neutral such as `DataFileDocument`, build the export lazily in the button action, and report encoding errors.
<!-- sources: comments/app-views-settings#10 -->

#### 4.45 Persistence logic built inside view bodies — Low

- **Where:** `SpamWise/MailHealthView.swift:19` (also `ProviderConsentView.swift:20-31`; `DecisionDetailView.swift:50-58,70-76`; `CorpusView.swift:79-113`; `MailDestinationView.swift:12-18`; `ContentView.swift:102-104`)
- **Problem:** These views reach into `model.store`, `model.adapter` and settings closures directly, rather than calling intention-revealing AppModel methods. They also reimplement nil-store handling, which is where the wrong error types in 4.3 came from.
- **Scenario:** Account scope, consent and corpus operations can only be exercised through the UI.
- **Fix:** Move these into AppModel methods such as `setAccount(_:included:)`, `setMailSharingConsent(_:for:)`, `undoLatestCorrection()`, `importReviewed(_:label:)` and `readDestinations(accountID:)`.
<!-- sources: conventions/app-views-main#15 -->

#### 4.46 Previews miss major modes; "No accounts" preview shows an account — Low

- **Where:** `SpamWise/MailHealthView.swift:53` (also `PreviewHelper.swift:89-105`; `AppModel.swift:63,72-77`; `MailReviewView.swift:109-110`; `AuditTrailView.swift:30`; `CorpusView.swift:116`; `ActivityDateFilterView.swift:35`; `SettingsView.swift:63`; `GeneralSettingsView.swift:61`; `EvidenceSettingsView.swift:106`; `ContentRuleEditorView.swift:184`; `FolderSettingsView.swift:92-108`; `TrustExclusionsView.swift:36`; `MailDestinationView.swift:38-40`; `KeyEntryView.swift:30`; `NotificationSettingsView.swift:66-73`; `StartupSettingsView.swift:5`; `ModelSettingsView.swift:114-127`; `MailConnectionView.swift:81-84`; `ProviderConsentView.swift:65-70`; `BackupSettingsView.swift:89`; `DecisionDetailView.swift:236-242`)
- **Problem:** `PreviewHelper` cannot seed accounts, scan health, junk envelopes, correction results, audit events, reviewed labels, content rules, folders, validated accounts, local-only mode or status. As a result:
  - Most complex views preview only an empty shell.
  - `AppModel(preview:)` inherits the DEBUG UI-test account, so "No accounts" shows one.
  - Some previews build fixtures inline.
  - Several previews use the default form style instead of `.grouped`.
  - StartupSettingsView reads `SMAppService` directly, so its modes cannot be previewed.
- **Scenario:** Misaligned disclosure content, populated content-rule tables and multi-account health rows never appear in Xcode previews.
- **Fix:** Add PreviewHelper fixtures and an explicit `accounts` parameter. Add populated, empty, error and busy previews, wrap component previews in `Form { }.formStyle(.grouped)`, and inject a login-item status provider.
<!-- sources: design/main-window#27, design/settings#21, design/onboarding-consistency#24, conventions/app-views-main#11, conventions/app-views-settings#12 -->

#### 4.47 `@Bindable` where no `$model` projection is used — Low

- **Where:** `SpamWise/SettingsView.swift:5` (also `GeneralSettingsView.swift:5`, `AccountSettingsView.swift:5`, `AdvancedSettingsView.swift:5`, `EvidenceSettingsView.swift:5`, `IMAPSettingsView.swift:5`, `LearningSettingsView.swift:6`, `ModelSettingsView.swift:5`, `RuleEditorView.swift:6`)
- **Problem:** None of these views project `$model`, yet sibling views use `let model: AppModel`, so the codebase mixes two styles for the same thing.
- **Scenario:** Readers look for bindings that don't exist, and the `var` allows reassignment.
- **Fix:** Use `let model: AppModel`, and add `@Bindable` only where `$model` is used.
<!-- sources: conventions/app-views-settings#19 -->

#### 4.48 Views discard caught error detail or ignore failures — Low

- **Where:** `SpamWise/StartupSettingsView.swift:44` (also `SpamhausSettingsView.swift:73-75`; `BackupSettingsView.swift:43,48`; `ContentRuleEditorView.swift:56-57,65`; `RuleEditorView.swift:64`; `LearningSettingsView.swift:52-53`)
- **Problem:** Catch blocks and `.failure` cases show fixed sentences, and two importers `break` silently. That discards the `failureReason` that `AppModel.describe` already knows how to show.
- **Scenario:** Login-item registration fails because the app was translocated, and the user sees only "Login registration failed."
- **Fix:** Show `AppModel.describe(error)` in every catch and failure branch, and handle importer failures.
<!-- sources: conventions/app-views-settings#14 -->

#### 4.49 Money values are unit-less Doubles; USD literal repeated — Low

- **Where:** `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:5` (also `:7`, `:12-57`; `Types.swift:30`; `SpamWise/AppModel.swift:45,9,28,43,374`; `ContentView.swift:168`; `DecisionDetailView.swift:204,210`; `ActivityStatisticsView.swift:52`)
- **Problem:**
  - The rates `input`, `output` and `cached` and the values `estimatedCost` and `monthCost` carry no unit, while siblings use `estimatedCostUSD`.
  - `verified` and `source` are strings.
  - The Gemini cut-over date is a raw epoch.
  - `"USD"` is repeated in several files.
- **Scenario:** A maintainer cannot see when the Gemini multiplier switches over, and can mistake a per-million rate for a per-token rate.
- **Fix:** Rename the values with a USD unit (`inputUSDPerMillionTokens`, `monthCostUSD`), store `URL` and `Date` values, build the cut-over date from components, and define one billing-currency constant.
<!-- sources: conventions/core-classifier-learning#2, conventions/app-logic#17, conventions/app-views-main#20 -->

#### 4.50 Lenient truncation and clamping; providers validate differently — Low

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:63` (also `:45-46`; `RemoteVerdict.swift:30`; `AppleClassifier.swift:57`; `ClaudeClassifier.swift:66-78`)
- **Problem:** `Verdict.init` truncates reasons and `TokenUsage.init` clamps counts, so `validated()` can never catch them. Apple and RemoteVerdict reject an over-long reason, while Claude silently truncates it.
- **Scenario:** The same over-long reason is discarded on Apple but acted on with a truncated explanation on Claude, so cross-provider evaluations measure different contracts.
- **Fix:** Store values as given and enforce all bounds in `validated()`. Clamp legacy persisted data only in `init(from:)`.
<!-- sources: conventions/core-classifier-learning#3 -->

#### 4.51 Literal defaults shadow named limits; clamp idiom hand-written repeatedly — Low

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:135` (also `:141-152`, `:278-281`, `:301-304`; `CorrectionLearning.swift:14,36,62,80`; `LearningState.swift:119-121`; `GeminiClassifier.swift:42,48`; `ClaudeClassifier.swift:8,10`; `AppleClassifier.swift:81-84,117,119`; `RemoteVerdict.swift:45-50`; `StatisticalLearning.swift:28`)
- **Problem:** The defaults 40, 1500, 15, 10, 10000 and 1000 repeat existing constants. Gemini finish reasons are inline arrays, and `@Guide` text restates "240 characters". The `min(upper, max(lower, x))` clamp is written out by hand at about eleven sites, and PromptBuilder, AppleClassifier and RemoteModelRequest re-clamp values that the initializer already bounded.
- **Scenario:** Raising `ClassificationLimits`' timeout ceiling leaves the `timeout: 15` default and the "within fifteen seconds" doc stale. Lowering `maximumReasonCharacters` keeps telling the model "240 characters", so provider responses start being rejected.
- **Fix:** Add named defaults and default the parameters to the existing static limits. Add a `Comparable.clamped(to:)` extension, make the bounded fields `private(set)`, and remove the re-clamps.
<!-- sources: conventions/core-classifier-learning#4, conventions/core-classifier-learning#8, comments/core-classifier-learning#16 -->

#### 4.52 ClassificationError reused outside its category, with no context — Low

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:206` (also `:210-213`; `ThreatAssessment.swift:175,180`; `ModelTokenPricing.swift:59`; `Deadline.swift:11`; `ModelHTTPClient.swift:47-54`)
- **Problem:** Threat validation, pricing lookup and the generic deadline helper all borrow classification errors. No case carries the HTTP status, the model ID or the provider. `consentRequired` puts a recovery instruction in `failureReason`, and `missingCredential` has no suggestion. In practice, threat errors are converted to `.unavailable` before they surface.
- **Scenario:** HTTP 500 and being offline both read "The provider could not be reached."
- **Fix:** Add `ThreatAssessmentError` and a pricing error, add context cases such as `.http(status:)` and `.unsupportedModel(_)`, and move instructions to `recoverySuggestion`.
<!-- sources: conventions/core-classifier-learning#5 -->

#### 4.53 ReviewTreatment mapped with a ternary instead of an exhaustive switch — Low

- **Where:** `SpamWiseCore/Sources/Decision/Decision.swift:88`
- **Problem:** `review == .orangeFlag ? .orangeFlag : .orangeBackground` maps any new case to orange background with no compiler error.
- **Scenario:** A future `ReviewTreatment` case gives every Review message an orange background.
- **Fix:** Add `ReviewTreatment.action` as an exhaustive switch.
<!-- sources: conventions/core-classifier-learning#17 -->

#### 4.54 `.map { $0 }` used for slice-to-array conversion — Low

- **Where:** `SpamWiseCore/Sources/Learning/LearningState.swift:299` (also `:302`, `:327`; `CampaignLearning.swift:37`; `CorrectionLearning.swift:80,102`)
- **Problem:** An identity `map` exists only to turn an ArraySlice into an Array.
- **Scenario:** There is no runtime effect. Readers have to stop and decode the closure.
- **Fix:** Use `Array(...)`.
<!-- sources: conventions/core-classifier-learning#13 -->

#### 4.55 ASCII byte literals in validators and the IMAP tokenizer — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPConfiguration.swift:40` (also `IMAPDaemonConfiguration.swift:76-78`; `IMAPProtocol.swift:49-56,73,79-85,134,178,200`; `MailFolderScripts.swift:82-89`)
- **Problem:** `[45, 46]`, `(48...57)`, `case 32/40/41/34` and `Data([13, 10])` hide the meaning of the bytes, and `dateBoundary` falls back to fabricated `?? 2000` values.
- **Scenario:** A reviewer can't tell that '-' and '.' are the only hostname punctuation allowed, so adding '_' is easy to get wrong.
- **Fix:** Use `UInt8(ascii:)` constants or named ASCII predicates. `isLetter` and `isNumber` would accept non-ASCII characters, so don't use them here. Use Calendar components without the fabricated fallbacks.
<!-- sources: conventions/mail-integration#13 -->

#### 4.56 Credential reference uses optional fields for exclusive sources — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:7` (also `:19-27`, `:56-57`, `:72-89`, `:106`)
- **Problem:** Three optional fields plus a runtime "exactly one source" check let the public init accept invalid combinations. The IMAP-specific name also covers provider API keys. Decoding does validate, and only tests use the public init.
- **Scenario:** A both-sources value is created successfully, but it fails at first connection rather than at construction.
- **Fix:** Model the reference as `enum SecretSource { case environment(…), keychain(service:account:) }`, renamed to a general SecretReference.
<!-- sources: conventions/mail-integration#8 -->

#### 4.57 IMAPError reused for CLI, model and provider-key failures — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:48` (also `:63-66`; `SpamWiseDaemon/main.swift:83,136,157-190`)
- **Problem:** Provider-key lookup throws `IMAPError.authenticationFailed`, and usage and model errors throw `IMAPError.invalidConfiguration`. Today the visible cost is a vague reason, because the pipeline and the daemon rewrite these errors.
- **Scenario:** An unexported provider-key variable is recorded internally as an IMAP authentication failure.
- **Fix:** Add a `SecretResolutionFailure`/`CredentialReferenceError` and a `DaemonArgumentError`, and keep IMAPError for wire and session failures.
<!-- sources: conventions/mail-integration#3 -->

#### 4.58 Decoder copies CodingKeys into hand-written allow-lists — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:110` (also `:90-92`, `:108-130`; `IMAPConfiguration.swift:47`)
- **Problem:** Unknown-key rejection depends on string sets that duplicate the CodingKeys, and the input is parsed twice.
- **Scenario:** Adding a field to the CodingKeys without updating the set rejects every configuration that uses the field, with the generic daemon error.
- **Fix:** Compare a dynamic key container's `allKeys` against `CaseIterable` CodingKeys inside each `init(from:)`, and drop the JSONSerialization pre-pass.
<!-- sources: conventions/mail-integration#9 -->

#### 4.59 `deadlineExceeded` never thrown; timeouts surface as unavailable — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPTransport.swift:75` (also `:12`, `:28`, `:93`, `:116`)
- **Problem:** The 30-second session cancel makes pending I/O resume with `.unavailable`, and the localized `.deadlineExceeded` case is never used.
- **Scenario:** A slow fetch reports "The IMAP connection is unavailable." instead of "timed out", so the user looks for a network problem.
- **Fix:** Record that the cancellation came from the deadline and throw `.deadlineExceeded`, or remove the case and its catalog entry.
<!-- sources: conventions/mail-integration#10 -->

#### 4.60 Mailbox roles and cursors are bare strings with a silent Inbox fallback — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:213` (also `:240`; `AppleMailAdapter.swift:116,174,181,184,210-211,294,299,354`; `SpamWise/AppModelMailReview.swift:42`; `SpamWiseEval/main.swift:67-70`)
- **Problem:** The role allow-list is repeated four times, and the public MailScripts builders silently replace an unknown role with "inbox". Production callers go through the adapter, which rejects unknown roles with an unrelated error.
- **Scenario:** Calling `MailScripts.accountPage(..., role: "junk")` directly reads the Inbox without error.
- **Fix:** Add `enum MailboxRole { case inbox, junk, sent }` with a script reference and `enum PageCursor`, and remove the fallback.
<!-- sources: conventions/mail-integration#4 -->

#### 4.61 Missing bundled suffix list silently disables domain logic — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/DomainResolver.swift:8` (also `:29`)
- **Problem:** The resource is a build-time invariant, yet a load failure yields an empty rule set, so `registrableDomain` returns nil everywhere without any diagnostic. SwiftPM and the tests make this unlikely in practice.
- **Scenario:** A packaging change drops the file, and domain allow/block rules stop matching silently.
- **Fix:** Use `preconditionFailure`, or `assertionFailure` with a logged health status. Keep nil results for invalid hosts only.
<!-- sources: conventions/core-parsing-signals#22 -->

#### 4.62 Some package declarations are needlessly public — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:5` (also `:19-45`; Periphery lists 46 candidates in `IMAPTransport.swift`, `CachedThreatDetector.swift`, `ReviewedCorpus.swift`, `Metrics.swift`, `Store.swift`, `EvidenceProcess.swift`)
- **Problem:** Some public types are used only inside their own module, which widens the cross-module surface even though InternalImportsByDefault is on. Periphery overstates the count: `IMAPTLSTransport` must stay public because a public default argument uses it, and the category error protocols are public on purpose.
- **Scenario:** The app starts depending on `EmbeddedImages` internals, and later refactors become breaking changes.
- **Fix:** Lower the confirmed single-module declarations to internal or package. Add Periphery with an exclusion list for the deliberate cases.
<!-- sources: tooling#7 -->

#### 4.63 NSRegularExpression with `try?`, force unwraps and recompilation — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:189` (also `:42-46`, `:133`, `:142`, `:172`, `:176`; `Evidence.swift:87-104`; `ContentRules.swift:69,115`)
- **Problem:** The patterns are static, yet they are compiled at runtime with `try?`, which turns a pattern error into "no matches". The code also force-unwraps NSRange conversions and rebuilds the address regex on every call. Content-rule regexes compile twice per rule per message.
- **Scenario:** A typo in the address pattern makes every message parse as malformed, with no diagnostic.
- **Fix:** Use `Regex` literals stored as `private static let`, with typed captures. Lowercase headers once, and compile each user regex once.
<!-- sources: conventions/core-parsing-signals#11 -->

#### 4.64 Semicolon-joined statements and formatter-mangled one-liners — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:26` (also `:20,34,35,56`; `RDAP.swift:17,38,74,83,84,101,105`; `MIMEParser.swift:113,120,122`; `Gates.swift:23,60,61,72`; `ClaudeClassifier.swift:33,61-64,80-82`; `AppleClassifier.swift:30,93-95`; `RemoteVerdict.swift:79-83`; `Decision.swift:14,73`; `Classifier/Types.swift:45-47,62,107-109,139`; `SpamWise/AppModel.swift:95,203,219,264,338,345`; `IMAPConnectionModel.swift:23-24,35`; `AutomationIntents.swift:14,122`; `AppModelSettings.swift:33`; `MailReviewView.swift:47,51,64,88,103`; `ContentView.swift:103`; `Evaluation/CachedThreatDetector.swift:15`; `ComparisonReport.swift:107,127,128`; `SpamWiseEval/main.swift:37,49,154-158,172,181`; test files including `DecisionTests.swift:298,309,315,379`, `RoadmapStateTests.swift:204`, `IMAPFixtureTransport.swift:9,14`)
- **Problem:** Statements, control flow and early returns are packed onto single lines. Lines combining a guard with a mutation, such as `guard !busy else { return }; busy = true`, hide the order of side effects, and some sit inside lock closures. swift-format reflow has split `switch` cases and `catch let … as` clauses across lines in misleading ways, and `advancedBinding` copies through an unneeded temporary.
- **Scenario:** A reviewer misreads the DeadlineRace lock body or the Claude label switch, whose `case .review:` begins on the `.inbox` line, and edits the wrong arm.
- **Fix:** Write one statement and one case per line. Enable swift-format's `DoNotUseSemicolons` and `OneVariableDeclarationPerLine` in a shared `.swift-format`, as the sister repositories do.
<!-- sources: conventions/core-parsing-signals#18, conventions/core-classifier-learning#11, conventions/app-logic#13, conventions/app-views-main#19, conventions/eval-scripts#11, conventions/tests#13 -->

#### 4.65 Abbreviated and mismatched names — Low

- **Where:** `SpamWiseCore/Sources/Signals/Evidence.swift:6` (also `:57`; `SpamhausHTTPS.swift:26,44,80`; `ContentRules.swift:19,25`; `MIMEParser.swift:338`)
- **Problem:** Some names are abbreviated or don't match what they describe:
  - `AuthResult` and `trustedAuthServers` abbreviate "Authentication".
  - `resp` mirrors a wire key without a CodingKey.
  - `operation` holds a `ContentRuleOperator`.
  - The HTTPS path returns a `DNSAnswer`.
  - The `plain` and `enabled` booleans don't read as assertions.
- **Scenario:** Readers have to translate between operation and Operator, and between DNS and HTTPS, when tracing evidence.
- **Fix:** Rename to `AuthenticationResult`, `matchOperator`, `BlocklistAnswer` and `isEnabled`, and use CodingKeys where the values are persisted.
<!-- sources: conventions/core-parsing-signals#19 -->

#### 4.66 Closed vocabularies and validated values stored as free Strings — Low

- **Where:** `SpamWiseCore/Sources/Signals/Evidence.swift:10` (also `:12`, `:74`, `:93`; `ExternalEvidence.swift:16,57,61,192`; `Message.swift:16,29`; `RspamdLookup.swift:18,71-73`; `MIMEParser.swift:271,302`; `DocumentInspection.swift:34`)
- **Problem:** Authentication mechanism and result, evidence source, and text media types come from closed sets, yet consumers in other modules compare them as strings. The resolver address, URLs and executable path are re-validated at every use. Migrating them has a Codable cost.
- **Scenario:** A comparison typo such as `"softFail"` compiles and never matches. An invalid resolver address persists in settings and only shows up as unknown evidence.
- **Fix:** Add enums for mechanism, outcome, source and media type, and parsed `IPv4Address` and `URL` values, with Codable that keeps the wire format.
<!-- sources: conventions/core-parsing-signals#7 -->

#### 4.67 Helpers reimplemented where the project or SDK provides them — Low

- **Where:** `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:108` (also `DomainResolver.swift:21`; `EvidenceProcess.swift:59`; `EmbeddedImages.swift:14-17`)
- **Problem:**
  - `validIPv4` reimplements `inet_pton`, which the package already calls.
  - Process exit is polled every 10 ms instead of using `terminationHandler`.
  - UTI identifiers are typed out as strings instead of using `UTType` constants.

  The Calendar day-arithmetic and hex-padding suggestions were judged weak, and `public.heic` is correct.
- **Scenario:** The hand-written validator needs its own tests and can drift from platform semantics.
- **Fix:** Reuse `inet_pton` or `IPv4Address`, bridge `terminationHandler` with a continuation, and use `UTType.png.identifier` and the other constants.
<!-- sources: conventions/core-parsing-signals#13 -->

#### 4.68 URLError reused for project errors; failure reasons lack context — Low

- **Where:** `SpamWiseCore/Sources/Signals/SpamhausHTTPS.swift:18` (also `:64`; `RspamdLookup.swift:73`; `ExternalEvidence.swift:97`; `RDAP.swift:21`; `RspamdLoopbackHTTP.swift:53`; `ContentRules.swift:50`; `Message.swift:43`; `ResourceDeadline.swift:8-12`; `EmbeddedImages.swift:40`)
- **Problem:** Validation failures are thrown as Foundation URLError codes with the wrong meaning. `ParseError` cases carry no context. `ContentRuleError.invalid`'s `failureReason` is really an instruction, and it merges four causes. An image type mismatch throws `.tooLarge`. The Signals URLErrors are converted to unknown findings before they surface.
- **Scenario:** A user who saves an empty content-rule pattern is told to "Check the rule expression and size limits." A parse failure never names the charset or limit.
- **Fix:** Add an `ExternalEvidenceError` that conforms to the local protocols. Give `ParseError` and `ContentRuleError` associated values with interpolated reasons, move advice to `recoverySuggestion`, and throw `.invalidEncoding` for type mismatches.
<!-- sources: conventions/core-parsing-signals#5, comments/core-parsing-signals#23 -->

#### 4.69 Hardened URLSession setup and bounded reads duplicated — Low

- **Where:** `SpamWiseCore/Sources/Signals/SpamhausHTTPS.swift:83` (also `:42-54`, `:65-70`; `RspamdLoopbackHTTP.swift:9-22,47,54-59,67-85`; `EvidenceProcess.swift:55-58`)
- **Problem:** The code has two redirect-refusing delegates, two hardened configurations and three bounded byte loops. Their differences (server trust, proxies) are justified, but nothing names them. SpamhausHTTPS mutates a caller-supplied configuration.
- **Scenario:** A future hardening fix lands in one transport only.
- **Fix:** Use one internal `BoundedHTTPClient` with explicit parameters and a shared `readBounded(_:limit:)`. Copy the configuration before mutating it.
<!-- sources: conventions/core-parsing-signals#12 -->

#### 4.70 Force unwraps guarded only by distant logic — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/ActivityQuery.swift:27` (also `:28`; `PipelineCorrections.swift:47`; `StateBackup.swift:58`)
- **Problem:** `start!`, `end!`, `domain!` and `.combined!` rely on checks made elsewhere instead of on the type system.
- **Scenario:** Reordering the guard at `PipelineCorrections.swift:44` turns `domain!` into a crash inside a Store transaction.
- **Fix:** Use `start.map { … } ?? true`, a `switch scope` that binds the domain, and `guard let combined`.
<!-- sources: conventions/core-pipeline-store#21 -->

#### 4.71 Core modules re-exported with underscored `@_exported` — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Exports.swift:1` (lines 1-6)
- **Problem:** Six modules are re-exported through an unofficial attribute. This bypasses MemberImportVisibility and hides module boundaries at use sites.
- **Scenario:** A toolchain change to `@_exported` breaks every app import.
- **Fix:** Expose the modules as library products and import them explicitly, or adopt the sisters' shared-framework layout.
<!-- sources: config/swift-xcode#22 -->

#### 4.72 Never-negative counts, limits and offsets use signed Int — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/MailPreferences.swift:52` (also `:28-36`; `State.swift:27,29,84,123,125,138-142,165`; `NotificationPlanning.swift:10-14,19`; `Gates.swift:34-38`; `Evidence.swift:36`; `StatisticalLearning.swift:26`; `Identity.swift:9`; `RDAP.swift:101`; `Classifier/Types.swift:18,45,55,124,126`; `LearningState.swift:82,84,108,120`; `CorrectionLearning.swift:14,36,62,80`; `Decision.swift:13`; `IMAPSweepCursor.swift:2`; `MailPage.swift:8,10,25`; `MailScripts.swift:220,253`; `MailFolderScripts.swift:63`; `IMAPPaging.swift:14,17,70-72`; `IMAPAdapter.swift:189,290`; `SpamWiseDaemon/main.swift:149`; `Metrics.swift:41-51,80-84,100`; `ThreatMetrics.swift:29-42`; `ComparisonReport.swift:14,75`; `CachedClassifier.swift:10-12`)
- **Problem:** Counts, revisions, offsets, UIDs, ages and confidence are signed and clamped with `max(0, …)` or range checks, which goes against the `UInt` rule. The repository ledger records a compatibility decision, but private types such as `IMAPMetadata` and the selection tuples have no persistence constraint. `ComparisonRun.Result.corrections` is already `UInt`, so the code is inconsistent.
- **Scenario:** A persisted `quietStartHour` of 24 makes `isQuiet` always true, so notifications are suppressed forever. A negative offset is silently clamped and the first page is re-read.
- **Fix:** Use `UInt`/`UInt32` in internal types first; JSON stays compatible for non-negative values. Model quiet hours and confidence as validated types, and remove the clamps.
<!-- sources: conventions/core-parsing-signals#16, conventions/core-classifier-learning#9, conventions/core-pipeline-store#11, conventions/mail-integration#12, conventions/eval-scripts#9 -->

#### 4.73 Time values: unit-less parameters, ambiguous `Min`, mixed clocks and types — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/NotificationPlanning.swift:39` (also `:10,40,51-52`; `Pipeline.swift:8,10,31,86`; `PipelineClassification.swift:4-8,13,153`; `State.swift:37,82`; `RDAP.swift:11,28-29`; `ExternalEvidence.swift:81,87,174`; `RspamdLookup.swift:36`; `RspamdLoopbackHTTP.swift:6,25`; `SpamhausHTTPS.swift:41`; `ContentRules.swift:62`; `EvidenceProcess.swift:28-29`; `MailExtension/MessageActionHandler.swift:6`; `IMAPTransport.swift:46,48`; `SpamWiseDaemon/main.swift:148`; `ComparisonReport.swift:77-91,165-175`; `Scripts/swiftdata-probe.swift:16`; `Tools/DocumentWorker/Protocol.swift:8-10`; `Tools/DocumentWorker/Client.swift:36,46,94,112`; `Tools/DocumentWorker/Worker.swift:67`; `UITests/UITests.swift:126-128`; `IMAPFixtureTransport.swift:6-8`)
- **Problem:** `…Sec` suffixes follow the user's abbreviated-unit rule. These do not:
  - `timeout`, `latency`, `callbackDeadline`, `poll`, `UITestTiming.launch` and `fragment` carry no unit at all.
  - `minimumIntervalMin` reads as "minimum minimum".
  - The code mixes `Duration` with `TimeInterval`, and `* 60` appears inline.
  - The extension's 9-second watchdog is written independently of its 8-second limit.
  - The document harness measures elapsed time with a non-monotonic `Date`.
  - `IMAPTLSTransport` lacks the acronym separator (`IMAP_TLSTransport`).
- **Scenario:** Raising the extension's classification limit above 9 seconds lets the watchdog always fire first and cancel the work. An NTP adjustment skews harness timings that are cited as evidence.
- **Fix:** Use `Duration` with `ContinuousClock` for deadlines, and derive the watchdog as limit plus grace. Spell out units on remaining unit-less values (`intervalMinutes` with a CodingKey), and rename the transport.
<!-- sources: conventions/core-parsing-signals#9, comments/core-parsing-signals#17, conventions/core-pipeline-store#10, conventions/mail-integration#11, conventions/eval-scripts#7, conventions/tests#16, conventions/tools#7 -->

#### 4.74 Long functions instead of orchestrators across modules — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:81` (also `:27-79`, `:140-151`, `:265-331`; `PipelineClassification.swift:9-94,210-214`; `PipelineCorrections.swift:20-104`; `MIMEParser.swift:258-333`; `EvidenceProcess.swift:31-66`; `RDAP.swift:53-85`; `RspamdLookup.swift:51-59`; `GeminiClassifier.swift:22-71`; `OpenAIClassifier.swift:22-67`; `RemoteVerdict.swift:66`; `AppleClassifier.swift:23-24`; `LearningState.swift:193-247`; `ThreatAssessment.swift:163-182`; `SpamWise/AppModelFolders.swift:54-114`; `AppModelScanning.swift:37-75,41,94`; `AppModel.swift:61-121,291-299,312-316`; `SpamWiseEval/main.swift:28-55,149-160,181-186,202-212,245-255`; `ComparisonReport.swift:95-137`; `Tools/DocumentWorker/Client.swift:48-101`)
- **Problem:** Several functions mix many concerns inline instead of delegating to named helpers:
  - The pipeline's `process`, `dispatch`, `classify` and `correct`.
  - MIMEParser's `part`.
  - The provider `classify` methods.
  - AppModel scanning and `init`.
  - The eval commands.

  Some of these copy predicates and output code between themselves: the account-scope check three times, the report encoder three times, and the harness rejection four times. Others pick behavior through literal comparisons (`header == "Authorization"`, a four-way `!=` chain).
- **Scenario:** An account-scoping change lands in `scanMailAccounts` but not in `scanConfiguredFolders`, so folder sweeps still touch excluded accounts. A new terminal worker status defaults to sending `terminate()`.
- **Fix:** Extract named steps and predicates: `unclassifiedReason(for:)`, `isInScope(accountID:)`, `recordingScanHealth`, `emit(_:options:)`, `ProviderAuthentication`, `Status.leavesLiveWorker` (as an exhaustive switch). Group MIMEParser helpers into extensions.
<!-- sources: conventions/core-parsing-signals#10, conventions/core-classifier-learning#10, conventions/core-pipeline-store#7, conventions/app-logic#11, conventions/eval-scripts#10, conventions/tools#12 -->

#### 4.75 Priority rank encoded as magic Ints — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/ReviewPriority.swift:21`
- **Problem:** `rank` returns 0, 1 or 2, and `reason(_:)` reconstructs the meaning with `case 0`, `case 1` and `default`.
- **Scenario:** A new tier that misses one of the two edits gives the wrong digest reason, with no compiler help.
- **Fix:** Use a `private enum Rank: Int, Comparable` with a localized `reason`.
<!-- sources: conventions/core-pipeline-store#16 -->

#### 4.76 State invalidation open-coded at 13 sites — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift:68` (also `:79,109`; `CorpusManagement.swift:63,66,92,93,110,111`; `ContentRuleManagement.swift:25,49,60`; `CorrectionUndo.swift:44`; `StateBackup.swift:75,90-91`; `State.swift:255,270-271`; `PipelineCorrections.swift:67-68`)
- **Problem:** The revision bump and retry clearing are written two different ways, and only some sites also clear `correctionUndo`.
- **Scenario:** A new mutation forgets `retries.removeAll()`, and reviewers can't tell which sites are meant to clear undo.
- **Fix:** Add `AppState.invalidatePendingWork(clearingUndo:)` and call it at every site.
<!-- sources: conventions/core-pipeline-store#9 -->

#### 4.77 Eval limits duplicated as literals and hard-coded into prose — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/main.swift:31` (also `:7`, `:47`, `:74`, `:129`; `ComparisonReport.swift:8,26,133,136`; `RunReport.swift:6,52`; `Metrics.swift:119-120`; `Options.swift:110`; `Scripts/store-provider-key.swift:30`; `Scripts/rspamd-http-fixture.swift:74`; `Scripts/document-probe.swift:130,148,158`)
- **Problem:** The 20 MB manifest cap appears three times. The report prose hard-codes "1,500" and "0.2%" next to the constants, the reservation ceiling special-cases a model-ID string, and the bucket strides are literals.
- **Scenario:** Raising ComparisonReport's limit still leaves the CLI rejecting large manifests with invalidManifest. Changing `minimumGoodExamples` leaves the report saying 1,500.
- **Fix:** Expose `ComparisonReport.maximumManifestBytes`, interpolate the constants with FormatStyle, and name the export defaults and the reservation bound.
<!-- sources: conventions/eval-scripts#6, comments/eval-scripts#7 -->

#### 4.78 Failure reasons lack context; Keychain decode failure reports status 0 — Low

- **Where:** `SpamWiseCore/Sources/Store/Keychain.swift:48` (also `:50`; `StateBackup.swift:14-16,72`; `RuleManagement.swift:22,25`; `MailClientAdapter.swift:70-71`; `Store.swift:26-28`; `EvaluationBudget.swift:19-20`)
- **Problem:** Non-UTF-8 Keychain data throws `KeychainError.status(errSecSuccess)`. BackupError collapses a wrong key, corruption, oversize and an unsupported version into one case whose reason is really advice. Limits are hard-coded in the messages.
- **Scenario:** A corrupt Keychain item reports "Keychain returned status 0." A user can't tell a wrong recovery key from a backup made by a newer version.
- **Fix:** Add `KeychainError.invalidData`, split BackupError while keeping the no-content-leak property, move advice to `recoverySuggestion`, and interpolate limits with FormatStyle.
<!-- sources: conventions/core-pipeline-store#5 -->

#### 4.79 Unsafe C/ObjC calls where checked APIs exist — Low

- **Where:** `SpamWiseCore/Sources/Store/Store.swift:92` (also `:97`)
- **Problem:** `fileExists(atPath:isDirectory:)` and C `open` have checked alternatives, `resourceValues(.isDirectoryKey)` and System's `FileDescriptor.open`. Only `flock` lacks one, and `fd` is an abbreviation.
- **Scenario:** The audited unsafe surface on the persistence path is wider than it needs to be.
- **Fix:** Switch to the checked APIs, rename `fd` to `lockDescriptor`, and keep `flock` as the only C boundary.
<!-- sources: conventions/core-pipeline-store#14 -->

#### 4.80 Tests hard-code copies of private production limits — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift:43` (also `:185,251`; `ProviderTests.swift:230`; `EmbeddedImageTests.swift:52,62,65`; `ParsingTests.swift:45,52,61,91`; `MailIntegrationTests.swift:217`; `IMAPTests.swift:35`; `DecisionTests.swift:270,291`; `SignalsTests.swift:155`; `ClassifierTests.swift:26,29`)
- **Problem:** Boundary-plus-one values such as `16_385`, `65_537`, `524_289` and `addingTimeInterval(35)` are unexplained copies of private constants.
- **Scenario:** Lowering `maximumResponseBytes` to 8 KiB leaves the tests passing while the new boundary goes untested.
- **Fix:** Make the limits `internal static` (tests already use `@testable`) and derive the fixtures from them, as in `limit + 1`.
<!-- sources: conventions/tests#10 -->

#### 4.81 Suite naming inconsistent; per-site lint suppressions — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/LearningTests.swift:9` (also `IMAPTests.swift:6-8`; `UnitTests/DirectUpdateConfigurationTests.swift:5`)
- **Problem:** The two raw-identifier suites are verb phrases, each with a bare `@Suite` and an inline `swiftlint:disable:next type_name`. The app suite uses XCTest-style `DirectUpdateConfigurationTests`. Most package tests are ungrouped top-level functions. `type_name` flags any raw identifier, not only verb phrases.
- **Scenario:** Every new raw-identifier suite needs another suppression, so contributors drift back to type-style names.
- **Fix:** Disable `type_name` in a nested Tests `.swiftlint.yml`. Group the tests into noun-phrase suites, for example `` `Direct update configuration` ``, and drop the bare `@Suite`.
<!-- sources: correctness/tests#19, conventions/tests#15, comments/tests#13 -->

#### 4.82 Shared test helpers in unrelated files; history-named test file — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/ParsingTests.swift:4` (also `MailIntegrationTests.swift:93`; `SignalsTests.swift:97`; `RoadmapStateTests.swift:1`)
- **Problem:** `fixture()`, `Counter` and `StubRDAP` live in whichever suite first needed them. `RoadmapStateTests` takes its name from a project milestone rather than what it tests: migration, backups, rule import, budget, notifications and replay. `Counter` wraps `Mutex(0)` where `Atomic<Int>` would do.
- **Scenario:** Deleting ParsingTests.swift breaks nine unrelated files. Nobody looks for backup tests in "RoadmapStateTests".
- **Fix:** Move the shared helpers into `TestSupport/` files, split RoadmapStateTests by subject, and consider `Atomic<Int>`.
<!-- sources: conventions/tests#14, comments/tests#11 -->

#### 4.83 Corpus thresholds inline and restated in report prose — Low

- **Where:** `Tools/Corpus/audit.py:134` (also `:126-128,148,246,303,326,381`; `prepare.py:72,124,135,268-270`; `screen.py:80-113,163,243,273`; `spaphish.py:29-48,95,102,157,251,263`)
- **Problem:** Thresholds such as Jaccard 0.8, 0.95, train fraction 0.7 and report cutoffs are inline. Committed report "method" strings restate them by hand, and spaphish hard-codes audit's 0.8.
- **Scenario:** Lowering the campaign threshold to 0.7 leaves the reports claiming 0.8, so reports that are not comparable look comparable.
- **Fix:** Promote the values to module constants, build method strings with f-strings, and import shared values across modules.
<!-- sources: conventions/tools#5 -->

#### 4.84 Corpus tools duplicate union-find, verification and private writes — Low

- **Where:** `Tools/Corpus/audit.py:240` (also `:19-35,116-118,190,196-198,234-236,294-296,371-390`; `prepare.py:244-254,265,382-398`; `spaphish.py:31,83-91,94,282-296`; `screen.py:48-67,254-263`; `Preferences/run.py:225-233`)
- **Problem:** The path-halving union-find is copied three times, with only prepare's copy using `setdefault`. Manifest-and-hash verification is copied twice and reads the file differently each time, and the private umask/write block appears five times. The modules already import from prepare.
- **Scenario:** Corpus verification is tightened in audit, while screen keeps the old check and silently accepts a corpus the audit would reject.
- **Fix:** Move `DisjointSet`, `read_verified_corpus`, `verify_file_sha256`, `real_development`, `split_fraction` and a `private_output` context manager into prepare.py or a `corpus_io.py`.
<!-- sources: conventions/tools#4, comments/tools#5 -->

#### 4.85 Percentiles and hyperparameters reported inconsistently — Low

- **Where:** `Tools/Corpus/spaphish.py:266` (also `:148-155,232-242`; `screen.py:124`)
- **Problem:** The two tools compute p95 with different index formulas. spaphish restates the model's constructor arguments by hand.
- **Scenario:** For 20 timings, spaphish reports the maximum as p95 and screen reports the 19th value. Changing `min_df` leaves the report claiming the old value.
- **Fix:** Use one `statistics.quantiles` helper, and report `get_params()`.
<!-- sources: conventions/tools#15 -->

#### 4.86 Harness errors lack LocalizedError; encoding failure swallowed — Low

- **Where:** `Tools/DocumentWorker/Fixtures.swift:48` (also `Protocol.swift:30-32`; `ProbeHost.swift:9`)
- **Problem:** `ProbeError` conforms only to `Error`. `encoded()` turns an encoding failure, which should never happen, into empty `Data`. That is the same "invalid reply" the harness asserts for deliberately malformed output. `verify()` already prints the observed context before throwing.
- **Scenario:** A field that cannot be encoded empties every reply, and the invalid-reply probe still passes.
- **Fix:** Add `LocalizedError` with a shared description and an interpolated reason, and make encoding failure a `preconditionFailure`.
<!-- sources: conventions/tools#10 -->

#### 4.87 Pre-cancelled probe uses `withUnsafeCurrentTask` — Low

- **Where:** `Tools/DocumentWorker/ProbeHost.swift:43`
- **Problem:** Two `unsafe` markers are used for non-interop self-cancellation, even though a child added after `group.cancelAll()` starts cancelled.
- **Scenario:** Code the README suggests copying normalizes `unsafe` outside C interop.
- **Fix:** Use a cancelled task group instead.
<!-- sources: conventions/tools#11 -->

#### 4.88 Probe operations stringly typed; 0-PID sentinels — Low

- **Where:** `Tools/DocumentWorker/Protocol.swift:42` (also `WorkerProbes.swift:9-34`; `ProbeHost.swift:53,56,118,179,189,193`; `Client.swift:34,50,59,67,92,134-157`; `Corpus/language-audit.swift:11,24,31,39`)
- **Problem:** Operation literals are repeated in two files, and `default:` maps typos to `.malformed`. Process identity is `Int32` with 0 meaning none. The language helper writes "unknown".
- **Scenario:** `ProbeCommand(operation: "crsh")` returns `.malformed`, so checks fail with a confusing mismatch instead of a compile error.
- **Fix:** Add `enum ProbeOperation: String, Codable` with an exhaustive switch, use `pid_t?`, and encode an optional `NLLanguage`.
<!-- sources: conventions/tools#8 -->

#### 4.89 Magic exit codes and probe sizes not derived from limits — Low

- **Where:** `Tools/DocumentWorker/Worker.swift:70` (also `:18,43,63,68,73,77,83,124`; `WorkerProbes.swift:11-32`; `ProbeHost.swift:55,159,164-166,198`; `Client.swift:124`)
- **Problem:** Exit codes 71–76 are bare literals that the README does not map. The CPU limit and sampling interval are inline. The probe sizes (3001, 13 pages, 13 seconds, `errno=22`) are not derived from `DocumentWorkerLimits`.
- **Scenario:** Raising `textCharacters` to 4000 makes the oversized-text probe a valid reply, and launchd's "exited with code 74" can't be decoded without the source.
- **Fix:** Add a `WorkerExitCode` enum, move the limits into `DocumentWorkerLimits`, derive the probe sizes from them, and use `EINVAL`.
<!-- sources: conventions/tools#6 -->

#### 4.90 Tools Swift harness omits the required upcoming features — Low

- **Where:** `Tools/DocumentWorker/check.sh:10` (also `Tools/Corpus/README.md:157-161`)
- **Problem:** The harness, which the README presents as the basis for a shipping XPC target, compiles with none of the six upcoming features. The language-audit command uses the old experimental `StrictMemorySafety` flag. The behavioral drift claim is speculative, because the client is an actor and the latch uses `Mutex`.
- **Scenario:** Moved into an Xcode target with the app's settings, the code compiles or behaves differently from what the 28 signed checks observed.
- **Fix:** Add the six `-enable-upcoming-feature` flags to `common`, and use `-strict-memory-safety` in the README command.
<!-- sources: conventions/tools#2 -->

#### 4.91 Screen objects don't return the next screen or wait — Low

- **Where:** `UITests/ReviewScreens.swift:36` (also `:6`; `UITests.swift:59-63,94-99,339-340`; `EvidenceScreen.swift:32-34,47-49`)
- **Problem:** The screen objects break the rule that each transition returns the next screen object after waiting for it:
  - `CorpusScreen.close` neither returns nor waits.
  - `StatisticsScreen.close` returns Void.
  - `RulesScreen.close` is `@discardableResult`, and the tests reuse stale `activity`/`detail` objects.
  - `acceptTerms` and `save` don't wait for the change to land.
- **Scenario:** On a slow runner, Cmd-, reaches the closing corpus sheet and the Rules button never appears. Cmd-W can close Settings before a save commits.
- **Fix:** Return the destination screen after waiting for its landing element, chain the returned objects in the tests, and wait for saved state.
<!-- sources: conventions/tests#6 -->

#### 4.92 XCTWaiter predicate boilerplate written 8 times — Low

- **Where:** `UITests/UITests.swift:271` (also `:167,229,286,313,377`; `ActivityScreen.swift:71-82`; `ReviewScreens.swift:23-34`)
- **Problem:** `waitForNonExistence(timeout:)` and `wait(for:toEqual:timeout:)` cover most of these cases. Screen-object assertions don't forward `file:`/`line:`.
- **Scenario:** A timeout is reported at the helper line, not at the test step that triggered it, which slows triage.
- **Fix:** Use the XCUIElement wait APIs, add one `waitForValue` helper, and thread `#filePath`/`#line` through.
<!-- sources: conventions/tests#7 -->

#### 4.93 Mail status accessibility identifier changes with state — Info

- **Where:** `SpamWise/MailConnectionView.swift:13` (also `UITests.swift:191,196`)
- **Problem:** The identifier switches between `mail.status` and `mail.permissionDenied`, while ContentView uses a fixed identifier plus a value. Current tests rely on this deliberately.
- **Scenario:** A test waiting for `mail.status` after a denial times out instead of failing on the value.
- **Fix:** Use a fixed identifier and expose the state through a value or a state-specific child, then update the tests.
<!-- sources: conventions/app-views-main#14 -->

#### 4.94 Modules share names with their primary types — Info

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:156` (also `Decision.swift:64`; `Package.swift:30-37`)
- **Problem:** Module `Classifier` contains protocol `Classifier`, and module `Decision` contains struct `Decision`, which breaks `Module.Type` qualification. This extends the user's suite-shadowing rule by analogy, and no current collision exists.
- **Scenario:** A future name collision on `MailLabel` or `Verdict` can't be disambiguated as `Classifier.MailLabel`.
- **Fix:** Rename the modules (`Classification`, `DecisionPolicy`) while they are still internal to the package.
<!-- sources: conventions/core-classifier-learning#14 -->

#### 4.95 Report types expose Decodable that bypasses validation — Info

- **Where:** `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:5` (also `:65`; `Metrics.swift:39,90`; `ThreatMetrics.swift:28,74`)
- **Problem:** The synthesized `init(from:)` skips the validating initializers. No code decodes these types today.
- **Scenario:** A future tool decodes a hand-edited report and trusts `eligibleForBoundedComparison`.
- **Fix:** Declare the types `Encodable` only, or re-validate in `init(from:)`.
<!-- sources: conventions/eval-scripts#19 -->

#### 4.96 `ID` capitalized against the "id is not an acronym" rule — Info

- **Where:** `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:10` (also `:68,146,162`; `ThreatMetrics.swift:7`)
- **Problem:** Read literally, the swift-conventions rule argues against `…ID`. SpamWise, SubTrack and Zephyr all use `…ID` consistently, so a local rename would be inconsistent.
- **Scenario:** No defect. The style question spreads with new code.
- **Fix:** Decide project-wide, and if renaming, preserve JSON keys with CodingKeys.
<!-- sources: conventions/eval-scripts#8 -->
## 5. Comments and documentation

Public API in SpamWiseCore has full DocC coverage. Scripted scans across the Classifier, Decision, Learning, pipeline and Store modules found no `public` type or member without a `///` comment. The few undocumented public symbols are enum cases written on compound `case` lines. The codebase is also clean of the usual debris: no commented-out code, no untracked TODO/FIXME/HACK markers, and almost no inline `//` comments. The handful that exist (for example `Pipeline.swift:135` and `Store.swift:100`) explain a reason and pass the comment test in the global CLAUDE.md. Relative Markdown links all resolve, and spot checks of documented constants (thresholds 99/95/90, the 30-second settling window, the 8 s/9 s MailKit watchdog, Haiku pricing, the 90 `@Test` functions) match the code.

The problem is substance and accuracy, not coverage. Much of the DocC looks written to satisfy a "document every public symbol" rule. The same template, "Creates a X with the supplied configuration.", appears 28 times across the repository, including on parameterless initializers. It hides the clamping and truncation that callers actually need to know about. Copy-pasted summaries are wrong for the symbol they sit on: `Store.read` claims to read credentials, and `CorrectionExample.reason` repeats `Verdict`'s doc. Several docs describe one consumer or one transport rather than the contract: `MessageIdentity` is described as Apple Mail only, `DNSAnswer` as DNS only, and `ContentRules.matches` as "for previews". Others are phrased as defenses against a reviewer ("without claiming…", "never trusts itself") or narrate schema history ("Phase 1 stores", "legacy"). Nothing enforces doc quality: SwiftLint's `missing_docs` is off and no CI job runs `docbuild` with warnings as errors.

Internal app, view, test and tooling code has almost no comments. That suits the user's self-documenting-first standard only if the code really documents itself, and here it often does not. The app's most safety-relevant rules are written as anonymous compound booleans, discarded results and inline `Binding` setters that look deletable: which records count as already processed, the post-process persistence check, claim release, optimistic settings ordering, and dry-run reset on transport change. The same goes for an encode/decode round trip used as a validator and an empty Keychain read used as an existence check. Magic numbers are duplicated between the UI copy and the core constants. Tests rely on positional Apple Event and IMAP transcripts and on literals one past a limit, and one test's name promises the persist-before-act invariant without checking it. In almost every case the fix is to extract a named helper or constant, not to write more prose.

Repository documentation is the weakest area. It reads as a running agent diary rather than a reference. CLAUDE.md is 68 KB, and more than 90% of it is dated milestone narrative: submission IDs, worker UUIDs, test counts, and superseded rulings nobody marked as superseded. Its few standing instructions are themselves stale: the module list is incomplete, the branch is wrong, and one scope ruling forbids work that is already implemented. The same diary style runs through automation.md, evaluation.md, the progress ledgers, the probe docs and the DocumentWorker README. Statements that later work superseded were never updated, so the docs now contradict each other on automation acceptance, the updater, the git remote and RDAP defaults. About 70 citations point at gitignored `.build/<uuid>` artifacts. The README lacks the architecture, editions, testing and license sections that SubTrack's and Zephyr's READMEs have.

The diary style also reaches user-facing text. Help pages opened from setup and Settings tell users about notarization, acceptance tests, offline protocol tests and the agent's $150 evaluation ceiling. These pages go stale the moment any gate passes, and App Review will read them as unfinished-product disclaimers.

### Findings

| # | Severity | Location | Finding |
|---|---|---|---|
| 5.1 | Medium | `CLAUDE.md:5` | Standing instructions in CLAUDE.md are stale or contradict the code |
| 5.2 | Medium | `CLAUDE.md:27` | CLAUDE.md is a 68 KB session ledger, not agent instructions |
| 5.3 | Medium | `README.md:3` | README lacks architecture, editions, testing and license sections |
| 5.4 | Medium | `SpamWise/AppModelScanning.swift:113` | Seen-record predicate and persistence check are opaque |
| 5.5 | Medium | `SpamWise/IMAPConnectionModel.swift:113` | JSON round trip used as an undocumented validator |
| 5.6 | Medium | `SpamWise/OnboardingView.swift:97` | Magic numbers in UI copy and logic duplicate core constants |
| 5.7 | Medium | `SpamWise/SpamWise.help/Contents/Resources/en.lproj/troubleshooting-mail-integration.html:5` | Help pages narrate development status and the $150 budget |
| 5.8 | Medium | `SpamWiseCore/Sources/Classifier/Types.swift:90` | `CorrectionExample.gist`/`.reason` docs do not match what is stored |
| 5.9 | Medium | `SpamWiseCore/Sources/Classifier/Types.swift:129` | Templated "with the supplied configuration" init docs hide clamping |
| 5.10 | Medium | `SpamWiseCore/Sources/Learning/LearningState.swift:124` | Decoder doc says "clamps" but discards invalid records |
| 5.11 | Medium | `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:22` | Persisted feature vector uses unnamed positional indices |
| 5.12 | Medium | `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:144` | `IMAPAccountValidation.record` silently switches the shared route to IMAP |
| 5.13 | Medium | `SpamWiseCore/Sources/MessageModel/Identity.swift:12` | `MessageIdentity` docs are Apple Mail-only and call `mailbox` display-only |
| 5.14 | Medium | `SpamWiseCore/Sources/MessageModel/Message.swift:5` | `ParsedMessage.headers` doesn't say values are undecoded bytes |
| 5.15 | Medium | `SpamWiseCore/Sources/Store/Store.swift:57` | Doc comments that are wrong for the symbol they describe |
| 5.16 | Medium | `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:39` | Persist-before-acting test never checks the ordering |
| 5.17 | Medium | `SpamWiseCore/Tests/SpamWiseCoreTests/MailIntegrationTests.swift:75` | Positional Apple Event and IMAP transcript stubs are opaque |
| 5.18 | Medium | `docs/automation.md:86` | Reference docs narrate dated session events |
| 5.19 | Medium | `docs/evidence.md:8` | evidence.md omits the keyed Spamhaus HTTPS transport |
| 5.20 | Medium | `docs/spamsieve-parity-progress.md:150` | Docs contradict each other and the code on current status |
| 5.21 | Low | `MailExtension/MailExtension.swift:1` | Unused `import AppIntents` has no explanation |
| 5.22 | Low | `Scripts/app-store-check.sh:25` | Script output hard-codes project status |
| 5.23 | Low | `Scripts/notarize-match.py:2` | Python helpers' docstrings and `--help` omit modes and arguments |
| 5.24 | Low | `Scripts/rspamd-runtime-check.sh:1` | Scripts have no purpose/usage header |
| 5.25 | Low | `Scripts/rspamd-runtime-check.sh:73` | Unexplained values in runtime harnesses |
| 5.26 | Low | `SpamWise.xcodeproj/project.pbxproj:446` | No DocC strictness or documentation build |
| 5.27 | Low | `SpamWise/ActivityDateFilterView.swift:30` | Duplicated end-of-day math with unexplained `-0.001` |
| 5.29 | Low | `SpamWise/AppModel.swift:130` | Optimistic settings queue and refresh override are unexplained |
| 5.30 | Low | `SpamWise/AppModel.swift:285` | History-eligible set encodes a receipt-gate rule without a name |
| 5.31 | Low | `SpamWise/AppModel.swift:355` | IMAP-record discriminator and swallowed adapter error are implicit |
| 5.32 | Low | `SpamWise/AppModelFolders.swift:87` | Sweep-completion and claim-release expressions need names |
| 5.33 | Low | `SpamWise/AppModelRules.swift:43` | Rule-import byte limit duplicated with an unexplained `+1` |
| 5.34 | Low | `SpamWise/AutomationIntents.swift:8` | `AutomationLabel` raw values are persisted Shortcuts identities |
| 5.35 | Low | `SpamWise/DecisionDetailView.swift:156` | Stringly-typed `"verification"` path check |
| 5.36 | Low | `SpamWise/DirectUpdateConfiguration.swift:9` | Guards encode unstated GitHub naming rules and MAS detection |
| 5.37 | Low | `SpamWise/IMAPConnectionModel.swift:132` | Credential-existence check via discarded Keychain read |
| 5.38 | Low | `SpamWise/IMAPSettingsView.swift:11` | Safety side effects buried in inline `Binding` setters |
| 5.39 | Low | `SpamWise/IMAPSettingsView.swift:67` | Opaque inline expressions in Settings view bodies |
| 5.40 | Low | `SpamWise/MailHealthView.swift:22` | Account-inclusion binding hides the snapshot-on-first-toggle rule |
| 5.41 | Low | `SpamWise/SpamWise.help/Contents/Resources/en.lproj/correcting-mistakes.html:5` | Help names controls and tabs that differ from the UI |
| 5.42 | Low | `SpamWiseCore/Sources/Classifier/AppleClassifier.swift:22` | `Generate` signature has unlabeled, swappable parameters |
| 5.43 | Low | `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:20` | Init doc says "for evaluation" but production uses it |
| 5.44 | Low | `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:5` | Gemini 2x pricing epoch is unexplained |
| 5.45 | Low | `SpamWiseCore/Sources/Classifier/ThreatAssessment.swift:90` | `ThreatInput.init` silently strips learned scores |
| 5.46 | Low | `SpamWiseCore/Sources/Classifier/Types.swift:29` | `TokenUsage` fallback condition misstated |
| 5.47 | Low | `SpamWiseCore/Sources/Decision/Decision.swift:4` | `FilteringStrength` case docs duplicate the thresholds |
| 5.48 | Low | `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:76` | `latencyP50Sec` doc describes the 95th percentile |
| 5.49 | Low | `SpamWiseCore/Sources/Evaluation/Metrics.swift:19` | `EvaluationObservation.file`/`.path` docs are narrower than stored values |
| 5.50 | Low | `SpamWiseCore/Sources/Learning/CampaignLearning.swift:68` | Candidate fingerprints use placeholder label and date |
| 5.51 | Low | `SpamWiseCore/Sources/Learning/LearningState.swift:67` | `CampaignMatch` doc denies the Junk gate it drives |
| 5.52 | Low | `SpamWiseCore/Sources/Learning/LearningState.swift:253` | Partial or inaccurate member docs in LearningState |
| 5.53 | Low | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:285` | `importHistory` is a long block that needs named helpers |
| 5.54 | Low | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:290` | Docs phrased as reviewer-directed disclaimers |
| 5.55 | Low | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:337` | `testDisposableMessage` docs omit that it moves and flags mail |
| 5.56 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:134` | Multi-line doc comments use `///` instead of `/** */` |
| 5.57 | Low | `SpamWiseCore/Sources/MailIntegration/IMAPProtocol.swift:49` | Wire parsing uses raw ASCII byte values |
| 5.58 | Low | `SpamWiseCore/Sources/MailIntegration/MailPage.swift:25` | Paging and sentinel contracts lack names |
| 5.59 | Low | `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:100` | `MailScripts.lookup` documented as a read but builds mutating scripts |
| 5.60 | Low | `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:233` | `accountPage` docs omit the role parameter and Inbox fallback |
| 5.61 | Low | `SpamWiseCore/Sources/MessageModel/DocumentInspection.swift:16` | Status is all-or-nothing but documented per attachment |
| 5.62 | Low | `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:44` | `extract` says unsupported MIME fails; it is skipped |
| 5.63 | Low | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:4` | Docs describe downstream policy instead of their own contract |
| 5.64 | Low | `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:146` | Stale "byte-preserved above" comment |
| 5.65 | Low | `SpamWiseCore/Sources/MessageModel/Message.swift:32` | `AttachmentMetadata.init` doc names one consumer, not its behavior |
| 5.66 | Low | `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:14` | Non-obvious mechanisms have no explanation |
| 5.67 | Low | `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:46` | Deadline helpers say "returns" but throw |
| 5.68 | Low | `SpamWiseCore/Sources/Signals/ContentRules.swift:74` | `ContentRules.matches` documented "for previews" but gates live mail |
| 5.69 | Low | `SpamWiseCore/Sources/Signals/Evidence.swift:33` | `tldIsAbuseHeavy` doc says weak; brief and prompt say strong |
| 5.70 | Low | `SpamWiseCore/Sources/Signals/Evidence.swift:111` | `ContactsLookup` doc omits the permission prompt and throws |
| 5.71 | Low | `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:6` | Public enum cases lack DocC across modules |
| 5.72 | Low | `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:78` | `Query` typealias says "absolute" name; callers pass relative |
| 5.73 | Low | `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:213` | `DNSAnswer` documented as DNS-only; HTTPS returns it too |
| 5.74 | Low | `SpamWiseCore/Sources/Signals/RspamdLookup.swift:35` | Docs and literals restate named constants |
| 5.75 | Low | `SpamWiseCore/Sources/Signals/SpamhausHTTPS.swift:8` | DBL listing-code tables duplicated with no source |
| 5.76 | Low | `SpamWiseCore/Sources/SpamWiseCore/ConfiguredClassifier.swift:55` | Discarded `PromptBuilder.prompt` result is unexplained |
| 5.77 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:26` | Public API DocC is summary-only; overloads indistinguishable |
| 5.78 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:276` | Dense inline decision logic needs named helpers |
| 5.79 | Low | `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:100` | Gate precedence encoded by calling `Gates.evaluate` twice |
| 5.80 | Low | `SpamWiseCore/Sources/SpamWiseCore/State.swift:38` | Doc comments narrate store history and phases |
| 5.81 | Low | `SpamWiseCore/Sources/SpamWiseCore/State.swift:248` | DocC omits side effects of settings edits, restore and corrections |
| 5.82 | Low | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:16` | Daemon help text is ragged and incomplete |
| 5.83 | Low | `SpamWiseCore/Sources/SpamWiseEval/Options.swift:26` | `spamwise-eval` usage incomplete and states unenforced policy |
| 5.84 | Low | `SpamWiseCore/Sources/SpamWiseEval/main.swift:149` | Seed-state isolation inlined instead of a named helper |
| 5.85 | Low | `SpamWiseCore/Sources/Store/Store.swift:32` | Store actor DocC lacks a summary and the lock behavior |
| 5.86 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:176` | Test names cover a fraction of multi-behavior tests |
| 5.87 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:390` | Persistence failure forced by an unexplained directory-as-store trick |
| 5.88 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/EmbeddedImageTests.swift:65` | Boundary tests hard-code production limits |
| 5.89 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/ProviderTests.swift:162` | Unnamed literal fixtures in tests |
| 5.90 | Low | `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:1` | Test file named after a project phase |
| 5.91 | Low | `TODO.md:120` | Docs cite evidence that does not exist in the repository |
| 5.92 | Low | `Tools/Corpus/README.md:88` | Corpus README omits the OpenTextShield candidate and `--synthetic` |
| 5.93 | Low | `Tools/Corpus/README.md:159` | Corpus README uses the obsolete strict-memory-safety flag |
| 5.94 | Low | `Tools/Corpus/README.md:183` | "Separate pyenv environment" is never named |
| 5.95 | Low | `Tools/Corpus/audit.py:126` | Report method strings duplicate unnamed code literals |
| 5.96 | Low | `Tools/Corpus/screen.py:152` | Order-dependent imports and split reset are unexplained |
| 5.97 | Low | `Tools/DocumentWorker/ProbeHost.swift:55` | Harness uses unnamed limits and errno literals |
| 5.98 | Low | `Tools/DocumentWorker/Worker.swift:70` | Worker exit codes 71–76 are undocumented |
| 5.99 | Low | `Tools/Preferences/run.py:34` | Unexplained reference-date timestamp |
| 5.100 | Low | `UITests/ActivityScreen.swift:34` | Duplicated UI lookup workarounds with one comment |
| 5.101 | Low | `UITests/EvidenceScreen.swift:17` | Disclosure expanded by an unexplained coordinate click |
| 5.102 | Low | `docs/automation.md:5` | automation.md omits the Apple Mail transport requirement |
| 5.103 | Low | `docs/conventions-and-design-review.md:96` | Conventions ledger claims an exhaustive review it no longer covers |
| 5.104 | Low | `docs/packaging.md:11` | packaging.md misdescribes the Help index and notarization input |
| 5.105 | Low | `docs/privacy-audit.md:19` | Privacy docs and onboarding copy are stale about data flows |
| 5.106 | Low | `eval/mock-responses.json:2` | Mock-response keys are undocumented SHA-256 hashes |
| 5.107 | Info | `SpamWise/` (18 Settings view files) | No comments or DocC in Settings views; none required |
| 5.108 | Info | `SpamWiseCore/Sources/MailIntegration/IMAPProtocol.swift:4` | Protocol parsing lacks RFC references |
| 5.109 | Info | `SpamWiseCore/Sources/SpamWiseCore/State.swift:36` | Calibration notes embedded in DocC |

#### 5.1 Standing instructions in CLAUDE.md are stale or contradict the code — Medium

- **Where:** `CLAUDE.md:5`, `CLAUDE.md:7`, `CLAUDE.md:12`, `CLAUDE.md:77`, `CLAUDE.md:153-155`
- **Problem:** The few lines meant as standing instructions are stale. L5 points to a session-only implementation plan and says "work proceeds on `codex/phase-one`". L7's module list omits Learning, MailIntegration, Evaluation and the daemon (Package.swift:38,44,45,50). L77 says fingerprints and URI/DNS blocklists "remain deferred", though TODO.md:51-53 marks them implemented. L12 still says "pending integration".
- **Scenario:** An agent declines to extend `SpamhausHTTPS.swift` or the campaign fingerprints because L77 calls them deferred. Another puts Apple Events code outside MailIntegration because the module isn't in the documented DAG.
- **Fix:** Rewrite the Contract and architecture section from the current Package.swift, with each target and its dependency edges. State the current branch policy, replace the session-plan reference with explicit precedence rules, and delete superseded rulings (L12, L59, L77).
<!-- sources: comments/repo-docs#2 -->

#### 5.2 CLAUDE.md is a 68 KB session ledger, not agent instructions — Medium

- **Where:** `CLAUDE.md:27` (whole file, 654 lines / 68,501 bytes), `CLAUDE.md:57`
- **Problem:** Only L1–25 work as durable instructions. Everything after the "Milestone ledger" heading is dated narrative: submission IDs, worker tokens, test durations, test counts at nine points, and 25 `.build/<uuid>` paths. The file is loaded into every session at about 17k tokens. Superseded rulings sit unmarked next to their replacements: L59 says the UI runner is blocked, and L81–89 resolve it. At least one load-bearing claim is false: L57 says strict memory safety is enabled, but it is not on for the Xcode targets. Neither SubTrack nor Zephyr tracks a file like this; both keep history in CHANGELOG.md.
- **Scenario:** An agent reads L59 or L75 ("Full onboarding/corrections interaction remains unverified") and stops trying to run UI tests, or trusts "strict memory safety is enabled" and skips that work.
- **Fix:** Cut it to about 60–100 lines of durable content. Keep the invariants, the module DAG, identifiers, commands and locks, signing and tool-sandbox caveats, probe-mail hygiene, the $150 ceiling and the opt-in live-test rule. Move design decisions to docs/architecture.md or ADRs and release evidence to CHANGELOG.md or PR descriptions. Fix the false claims.
<!-- sources: config/swift-xcode#12, comments/repo-docs#1 -->

#### 5.3 README lacks architecture, editions, testing and license sections — Medium

- **Where:** `README.md:3`, `README.md:41`
- **Problem:** The README is 41 lines. It has no architecture or layout map, no target/scheme or editions table (SpamWise vs SpamWiseDirect), no testing section and no license statement. L3 describes only "guided Claude classification", though OpenAI, Gemini, Apple on-device and PCC providers exist. For implementation decisions it sends readers to CLAUDE.md.
- **Scenario:** A new developer can't tell which scheme ships to the App Store, what SpamWiseDirect is for, or that installing both channels breaks the shared bundle identity (stated only in distribution-differences.md:36-39).
- **Fix:** Restructure after SubTrack's and Zephyr's READMEs: description, editions, architecture and layout, prerequisites, building, testing (check.sh, ui-check.sh, store-check.sh, opt-in live and intent tests), running, releasing, privacy, license (or "none selected"). Link a docs index instead of CLAUDE.md.
<!-- sources: comments/repo-docs#4 -->

#### 5.4 Seen-record predicate and persistence check are opaque — Medium

- **Where:** `SpamWise/AppModelScanning.swift:113` (predicate at 115-117, guard at 125-130)
- **Problem:** Which existing records stop an automatic scan from reprocessing a message is decided by an unnamed four-clause predicate. Paused and superseded records don't count, dry-run records count only during dry runs, and unclassified records count only within the current revision. The reload-and-guard that follows also catches the duplicate and failed-save paths of `Pipeline.process`, but nothing explains it, so it looks like redundant work.
- **Scenario:** A new `ActionOutcome` case is added without knowing whether it should count as seen. Sweeps then re-act on mail or permanently skip unclassified mail. Or someone deletes the guard as redundant.
- **Fix:** Extract `alreadyProcessedKeys(dryRun:)` with one named predicate per clause, and `requirePersisted(_:)`, each with a one-line `///`.
<!-- sources: comments/app-logic#2 -->

#### 5.5 JSON round trip used as an undocumented validator — Medium

- **Where:** `SpamWise/IMAPConnectionModel.swift:113-116`, `SpamWiseCore/Sources/MailIntegration/IMAPConfiguration.swift:34-36`
- **Problem:** `_ = try JSONDecoder().decode(IMAPConfiguration.self, from: JSONEncoder().encode(connection.account))` exists only to trigger the internal `validate()`, which runs from `init(from:)`. It looks like dead code and is a roundabout way to call an existing function.
- **Scenario:** Someone removes the apparent no-op. An invalid host or identifier is then saved to the store and Keychain and fails only at connection or scan time.
- **Fix:** Make `IMAPConfiguration.validate()` public with DocC and call `try connection.account.validate()`, or give the type a validating public initializer.
<!-- sources: comments/app-logic#4 -->

#### 5.6 Magic numbers in UI copy and logic duplicate core constants — Medium

- **Where:** `SpamWise/OnboardingView.swift:93,97`, `SpamWise/MailReviewView.swift:47,51,53`, `SpamWise/MailConnectionView.swift:57`, `SpamWise/ReviewDigestView.swift:17`, `SpamWise/KeyEntryView.swift:22`, `SpamWise/PolicyView.swift:5`
- **Problem:** Views hard-code 20, 30 seconds, seven days, 4000 and "Haiku 5.5", both in logic and in user-facing strings. Each value is defined authoritatively elsewhere: `AppModel.defaultScanLimit`, `limit: 20` in AppModelMailReview, `moveSettlingTime`, `lookbackDays`, `maximumPolicyCharacters`. The Junk review pager has three bare `20`s that must match a fourth.
- **Scenario:** The Junk page size changes to 50, and the pager skips or repeats messages because it still advances by 20. Or the settling time changes and the UI keeps promising 30 seconds.
- **Fix:** Use `AppModel.defaultScanLimit` and add `AppModel.junkPageSize`. Expose the other values as package constants and interpolate them into localized strings with FormatStyle.
<!-- sources: comments/app-views-main#3 -->

#### 5.7 Help pages narrate development status and the $150 budget — Medium

- **Where:** `SpamWise/SpamWise.help/Contents/Resources/en.lproj/troubleshooting-mail-integration.html:5` (also :7, :9, :11), `en.lproj/getting-started.html:5`, `en.lproj/filtering-strength.html:9`, `en.lproj/what-data-is-sent.html:11`, the es.lproj and fr.lproj equivalents. Reached from `SpamWise/MailConnectionView.swift:72`, `SpamWise/GeneralSettingsView.swift:51`, `SpamWise/ModelSettingsView.swift:103` and `SpamWise/AdvancedSettingsView.swift:45`.
- **Problem:** End-user Help contains the implementing agent's status notes: "A successful build or notarization does not prove live Mail callbacks…", "Keep pending runtime checks visible", "No live IMAP acceptance is implied by offline protocol tests", "MailKit remains dry-run-only until…", synthetic-fixture caveats, and "The configured paid-call ceiling starts at $150." This fails the comment test applied to documentation, and the text goes stale as soon as any gate passes.
- **Scenario:** A user opens Help next to "Usage and spending" and learns about a $150 ceiling they can't change. App Review reads the troubleshooting page as unfinished-product disclaimers.
- **Fix:** Rewrite these pages, in all three languages, as user tasks only: Automation denied, why no action happened, how to restore a message. Move build, notarization, test and calibration caveats to TODO.md or docs/, and rebuild the Help indexes.
<!-- sources: comments/app-views-main#1, comments/app-views-settings#3 -->

#### 5.8 `CorrectionExample.gist`/`.reason` docs do not match what is stored — Medium

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:90`, `Types.swift:94`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:59`, `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:54`, `SpamWiseCore/Sources/Learning/CorrectionLearning.swift:18`
- **Problem:** The doc calls `gist` a "bounded message summary". The main correction path stores the previous decision's model-written reason in it, and corpus import stores a body prefix. Retrieval scores similarity on subject + gist, so one field holds two kinds of data and nothing says so. `reason` copies `Verdict.reason`'s doc and no production call site sets it.
- **Scenario:** A maintainer tunes lexical retrieval on the assumption that gist is message content. For every UI correction, it is actually matching the model's earlier explanation.
- **Fix:** Decide what `gist` holds: store a bounded text excerpt everywhere, or rename and redocument it as the prior explanation. Document `reason` for its real meaning, or delete it.
<!-- sources: comments/core-classifier-learning#1 -->

#### 5.9 Templated "with the supplied configuration" init docs hide clamping — Medium

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:129` (also Types.swift:36, :60, :98, :163, :165; `Classifier/ClaudeClassifier.swift:31`; `Decision/Decision.swift:71`; `MessageModel/DomainResolver.swift:15`; `MessageModel/Identity.swift:34`; `Signals/RDAP.swift:13`, :36; `Signals/Evidence.swift:51`, :113; `Signals/Gates.swift:20,53,70`; `SpamWiseCore/Pipeline.swift:16`; `SpamWiseCore/State.swift:52,93,147,210`; `SpamWiseCore/MailClientAdapter.swift:8,17`; `SpamWiseCore/CompletionOnce.swift:9`; `Store/Store.swift:39`; `Store/Keychain.swift:39`; `MailIntegration/AppleMailAdapter.swift:117`; `MailIntegration/IMAPDaemonConfiguration.swift:18`). All paths are under `SpamWiseCore/Sources/`.
- **Problem:** The template appears 28 times repo-wide, including on parameterless inits that take no configuration, and it hides the behavior callers need. `Verdict` truncates `reason` to 240 characters, `TokenUsage` clamps its counts, `ClassificationInput` clamps timeout to 0.01–15 s, correctionLimit to 0–100 and bodyTokenBudget to 100–4000, `RDAPLookup` reads its cache file synchronously, `SenderRule` lowercases `value`, `Store.init` creates a 0700 parent directory, and `AppleMailAdapter` waits 30 s per move by default. The two `MockClassifier` inits share one doc. A related case: `IMAPCredentialReference.init` claims "exactly one source" but never validates.
- **Scenario:** A caller passes `timeout: 30` and silently gets 15 s, with nothing in Quick Help to warn them. Readers also see "Creates a DomainResolver with the supplied configuration" on `init()`.
- **Fix:** Replace each with a sentence about what the initializer establishes ("Clamps limits to the supported ranges…", "Normalizes `value` to lowercase", "Waits `moveSettlingTime` after each move"). Give the two `MockClassifier` inits distinct docs. Make `IMAPCredentialReference.init` validate, or reword its doc.
<!-- sources: conventions/core-parsing-signals#17, conventions/core-classifier-learning#12, comments/core-parsing-signals#7, comments/core-classifier-learning#3, comments/core-pipeline-store#8, comments/mail-integration#13 -->

#### 5.10 Decoder doc says "clamps" but discards invalid records — Medium

- **Where:** `SpamWiseCore/Sources/Learning/LearningState.swift:124` (filter at 136-150)
- **Problem:** "Decodes older empty state and clamps persisted retention and feature bounds" is inaccurate. Only the retention limits are clamped. Samples and fingerprints that fail hash-length, token, feature-count, range, partition or date checks are dropped whole.
- **Scenario:** A change to `featureCount` or the partition function makes every persisted sample fail validation. All the user's training corrections vanish on the next load, and the doc led the maintainer to expect clamping.
- **Fix:** Document it as "Decodes persisted state, defaulting missing collections to empty, clamping retention limits and discarding samples or fingerprints that violate current bounds." Extract `isValid` predicates on `LearningSample` and `CampaignFingerprint`.
<!-- sources: comments/core-classifier-learning#6 -->

#### 5.11 Persisted feature vector uses unnamed positional indices — Medium

- **Where:** `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:22` (7, 23-34, 85), `SpamWiseCore/Sources/Learning/LearningState.swift:39`
- **Problem:** The order of `LearningSample.features` is a persisted contract defined only by an eight-element array literal. Index 0 is a bias term, implied only by `index == 0 ? 0` in regularization. `featureCount = 8` is kept in step by hand. The public doc refers to a "version-one" order, but no version field exists.
- **Scenario:** Someone inserts a feature mid-array. Persisted samples fail the decoder's count check and are dropped, or, if the count is unchanged, they are silently misaligned against the new weights.
- **Fix:** Add a `LearningFeature: Int, CaseIterable` enum (bias, abuseHeavyTLD, …), derive `featureCount` from `allCases.count`, name the bias check, and document the persistence contract. Add a version field if versioning is intended.
<!-- sources: comments/core-classifier-learning#7 -->

#### 5.12 `IMAPAccountValidation.record` silently switches the shared route to IMAP — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:144` (148-153), `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:20-21,57-74`, `MailExtension/MessageActionHandler.swift:26-31`
- **Problem:** The doc states a caller precondition, but the function also sets `settings.route = .imap` and `advanced.transport = .imap`. Without `statePath`, the daemon writes to the shared App Group store and prints only "endpoint validation recorded. Dry run remains unchanged." The switch is consistent with how the Apple Mail probe sets its route, but it is undocumented.
- **Scenario:** A user who runs the AppleScript/MailKit route tries `spamwise-daemon --probe`. The GUI app's route silently becomes IMAP, and the extension keeps recording callbacks but stops classifying.
- **Fix:** Document the side effect in DocC and in the daemon's help and success output, or split this into `recordProbe` and an explicit `activateIMAPRoute`.
<!-- sources: comments/mail-integration#1, conventions/mail-integration#16 -->

#### 5.13 `MessageIdentity` docs are Apple Mail-only and call `mailbox` display-only — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/Identity.swift:12` (4-13), `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:194-212`, `SpamWiseCore/Sources/MailIntegration/IMAPPaging.swift:39-45`
- **Problem:** For IMAP identities, `localID` holds the UID and `accountID` the configuration ID. `mailbox`, documented as "for display and diagnostics", is required by `validateIdentity` and folded into `key`. The `key` getter switches between two hashing schemes, only one of which includes `localID`, with no explanation.
- **Scenario:** A maintainer localizes or drops `mailbox`. IMAP actions then fail validation and storage keys change, so existing records and claims stop deduplicating.
- **Fix:** Document both identity forms and that `mailboxValidity` is UIDVALIDITY. Split `key` into `imapKey` and `mailKey`, with one sentence on why the Mail key omits the local ID (it changes when a message moves).
<!-- sources: comments/core-parsing-signals#1 -->

#### 5.14 `ParsedMessage.headers` doesn't say values are undecoded bytes — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/Message.swift:5`, `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:202,248-250`
- **Problem:** Every header value except Subject and the From display name is a Latin-1 view of the raw bytes, so RFC 2047 words stay encoded and raw UTF-8 becomes mojibake. ContentRules (`.recipients`, `.replyTo`, `.listID`, `.contentType`) and the authentication checks match against these strings. Neither `headers` nor `header(_:)` says so.
- **Scenario:** A rule "recipients contains José" never matches, because the stored value is `=?utf-8?q?Jos=C3=A9?=` or `JosÃ©`.
- **Fix:** State in both docs that values are undecoded, byte-preserved strings, or decode the headers ContentRules consumes and document that instead.
<!-- sources: comments/core-parsing-signals#2 -->

#### 5.15 Doc comments that are wrong for the symbol they describe — Medium

- **Where:** `SpamWiseCore/Sources/Store/Store.swift:57`, `SpamWiseCore/Sources/Store/Keychain.swift:24,41`, `SpamWiseCore/Sources/SpamWiseCore/ConfiguredClassifier.swift:9`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:116,120,130,149,242`, `SpamWiseCore/Sources/SpamWiseCore/MailPreferences.swift:19`
- **Problem:** Copied or intent-based docs mislead. `Store.read` and `APIKeychain.read` share "Reads durable state or credentials", and Store holds no credentials. `APIKeychain` says "the user's API key", though it stores the Spamhaus, IMAP and other provider keys. `HistoryIndex.summary` returns counts, not "human-readable history". `RetryJob`'s property docs are copied from `DecisionRecord`. An initializer "without changing existing account scope". `isQuiet` returns true for out-of-range hours without saying so.
- **Scenario:** A reader trusts `Store.read` as a credential accessor, or expects `isQuiet` to be false for a corrupt hour of 24, when it actually suppresses every notification.
- **Fix:** Rewrite each to state actual behavior. For example, `Store.read`: "Decodes the value stored under `key`, or returns `fallback`". `isQuiet`: "invalid hours are treated as always quiet".
<!-- sources: comments/core-pipeline-store#5, conventions/core-pipeline-store#19 -->

#### 5.16 Persist-before-acting test never checks the ordering — Medium

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:39`, `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionFixtures.swift:25-28`, `DecisionTests.swift:389`
- **Problem:** The test is named `persists before acting and prevents duplicate actions`, but it checks dedupe, cost, read status and previews. `RecordingAdapter.perform` never reads the store. The nearby `prevents actions after persistence fails` test most likely fails at load, before dispatch is reached. Nothing pins the order of save and dispatch, yet the name tells readers the invariant is covered (and docs/conventions-and-design-review.md:227 repeats the claim).
- **Scenario:** Pipeline is reordered to dispatch before `StateRepository.update`, and every test still passes.
- **Fix:** Give `RecordingAdapter` the Store and assert inside `perform` that the record and claim already exist. Or rename the test for what it checks and add a separate ordering test.
<!-- sources: comments/tests#1 -->

#### 5.17 Positional Apple Event and IMAP transcript stubs are opaque — Medium

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/MailIntegrationTests.swift:75-78` (also :48, :61-63), `SpamWiseCore/Tests/SpamWiseCoreTests/IMAPTests.swift:143-147,359-366`
- **Problem:** `StubAppleEvents` hands out responses in order, whichever script asks. The IMAP fixtures use hand-numbered tags. On the safety-critical move and probe paths, nothing says which lookup, move, verify or settle step each `.boolean(true)` or `S14` answers.
- **Scenario:** The adapter gains one verification script, and every later response shifts by one. The test fails with a confusing decode error, or still passes for the wrong reason.
- **Fix:** Add named builders (`.lookup(selected)`, `.move(succeeded:)`, `.verify(in:)`) and an IMAP transcript builder that assigns tags automatically. Better still, match stub responses to the script kind.
<!-- sources: comments/tests#4 -->

#### 5.18 Reference docs narrate dated session events — Medium

- **Where:** `docs/automation.md:86` (also :131), `docs/evaluation.md:43-64,99-100`, `docs/repository-approval.md:13`, `docs/roadmap-progress.md:6`, `docs/updating.md:121`, `docs/probes/local-model-screening.md:15`, `docs/probes/unreadable-mail-pages.md:3,42`, `Tools/DocumentWorker/README.md:110-160,210-230`, `Tools/Corpus/README.md:171`
- **Problem:** Reference docs mix behavior with diary entries: "At 22:10 PDT…", "On 2026-10-16, this path admitted one synthetic OpenAI request… HTTP 429", "The user's iCloud and Google accounts… over the coming weeks", first-person "I independently checked", "before the change" narratives, and worker-specific `.build/<uuid>` evidence paths. The DocumentWorker README's dated check counts (24, then 28) were each accurate for their own run but read as a contradiction. roadmap-progress.md and spamsieve-parity-progress.md duplicate TODO.md. This fails the comment test applied to documentation.
- **Scenario:** A reader works through 70 lines of a troubleshooting narrative to find the one durable fact (a saved shortcut needs Stop and Output), and can't tell whether the 429 paragraph describes current behavior.
- **Fix:** Rewrite in the present tense: behavior, limits, commands and platform quirks. Move dated results to CHANGELOG.md, PRs or probe logs without PIDs or local times. Fold the progress ledgers into TODO.md and delete them.
<!-- sources: comments/repo-docs#5, comments/eval-scripts#9, comments/tools#1 -->

#### 5.19 evidence.md omits the keyed Spamhaus HTTPS transport — Medium

- **Where:** `docs/evidence.md:8` (11-12, 22-25), `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:63`, `docs/spamhaus.md:46-49`
- **Problem:** The optional-evidence reference describes Spamhaus as public-DNS only and says no key is configured. Its description of `SpamhausConfiguration` omits the `transport` field. The HTTPS transport sends domains directly to `apibl.spamhaus.net` with a Keychain-stored key, which is a different data flow.
- **Scenario:** A reviewer concludes that domains reach only the user's resolver and that no credential is stored.
- **Fix:** Cover both transports, their data flows and the stored key, or keep transport details only in spamhaus.md and link to it.
<!-- sources: comments/repo-docs#7 -->

#### 5.20 Docs contradict each other and the code on current status — Medium

- **Where:** `docs/spamsieve-parity-progress.md:150-151` (also :123, :190, :237-238), `docs/automation.md:49-50`, `docs/app-store-feasibility.md:23,72`, `docs/repository-approval.md:13-14`, `docs/distribution-differences.md:13`, `docs/detection-design.md:52-53`, `docs/probes/runtime-checklist.md:3`, `TODO.md:171`
- **Problem:** Rolling progress notes were never updated when later work superseded them. The docs give opposite answers on whether native automation passed, whether an external updater exists (SpamWiseDirect links one), whether a git remote exists, the branch baseline (7cf6c55 vs d1284e5), trusted-path threat coverage, MailKit callback status, and the RDAP default. The code makes RDAP opt-in (`PipelineClassification.swift:159`).
- **Scenario:** Someone drafting App Review notes from app-store-feasibility.md claims there is no updater and no native automation, or a privacy reviewer believes RDAP runs by default.
- **Fix:** Make TODO.md the single status source and keep feature docs to behavior only. Correct each listed statement against the code, and replace runtime-checklist.md:3 with a pointer to TODO.md.
<!-- sources: comments/repo-docs#6 -->

#### 5.21 Unused `import AppIntents` has no explanation — Low

- **Where:** `MailExtension/MailExtension.swift:1`
- **Problem:** No AppIntents symbol is used in MailExtension. According to the ledger, the import silences an Xcode metadata-extraction warning, but neither the code nor the build settings say so.
- **Scenario:** A cleanup pass removes the dead-looking import, and the warnings-as-errors build may fail for no visible reason.
- **Fix:** Express the dependency in build settings (link AppIntents.framework or disable metadata extraction), or add a one-line comment.
<!-- sources: comments/mail-integration#14 -->

#### 5.22 Script output hard-codes project status — Low

- **Where:** `Scripts/app-store-check.sh:25` (also :32, :49)
- **Problem:** The script prints "App Review justification and approval remain pending" whenever the temporary-exception key is present. It can't know App Review status.
- **Scenario:** After approval, every run still reports the exception as pending.
- **Fix:** Report only what was checked ("Temporary Apple Events exception present; requires App Review justification") and track status in TODO.md.
<!-- sources: comments/eval-scripts#15 -->

#### 5.23 Python helpers' docstrings and `--help` omit modes and arguments — Low

- **Where:** `Scripts/notarize-match.py:2` (40, 96-97), `Scripts/export-store-match.py:120,271-276`
- **Problem:** With no action flag, notarize-match.py runs `notarytool history`, and the docstring doesn't mention this mode. `--archive` actually needs a ZIP, pkg or dmg. No argparse option in either script has `help=`. "reviewed" in the certificate error has no meaning in that context.
- **Scenario:** A user passes an .xcarchive to `--archive` and notarization fails.
- **Fix:** Describe all three modes in the docstring. Rename `--archive` to `--submit` or document the accepted types, add `help=` to every argument, and drop "reviewed".
<!-- sources: comments/eval-scripts#13 -->

#### 5.24 Scripts have no purpose/usage header — Low

- **Where:** `Scripts/rspamd-runtime-check.sh:1` (and every other `Scripts/*.sh`, plus the Swift probes such as `Scripts/swiftdata-probe.swift:1`), `Tools/DocumentWorker/check.sh:1`, `Tools/DocumentWorker/Client.swift:100-106`
- **Problem:** Fifteen scripts go straight from the shebang or `import` to code. None says what it checks, which arguments it takes (rspamd-runtime-check.sh takes five positional paths) or what counts as success. DocumentWorker's check.sh runs four acceptance phases in one flat block. Client.swift's compound condition implements the README's "terminate only after a live response" rule but doesn't name it. These are internal scripts, and the `${N:?…}` messages give partial help.
- **Scenario:** A maintainer learns about missing arguments one error at a time and has to read docs/probes to discover the prerequisite builds.
- **Fix:** Add a 1–3 line header to each script (purpose, arguments, where the procedure is documented). Split check.sh into named functions per phase, and extract `workerIsLive(after:)` in Client.swift.
<!-- sources: comments/eval-scripts#5, comments/tools#15 -->

#### 5.25 Unexplained values in runtime harnesses — Low

- **Where:** `Scripts/rspamd-runtime-check.sh:73` (also :29), `Scripts/rspamd-http-fixture.swift:6,74`, `Scripts/evidence-runtime-probe.swift:26`, `Scripts/export-store-match.py:20`
- **Problem:** Some intent-bearing values have no name. The strongest cases are the 65_537-byte body, which is one byte over the 64 KiB response cap, and `DECRYPT`, which reaches into fastlane's internal Match library. Others, such as `observerDelay`, the redirect-trap port and the discard-port DNS, are partly self-describing, and the sandbox already blocks external DNS.
- **Scenario:** The transport's response limit is raised, and the "overflow" check silently stops overflowing.
- **Fix:** Name the values (`responseLimitPlusOne = 64 * 1024 + 1`), add a short reason comment where a name isn't enough, and rename `DECRYPT` to `MATCH_DECRYPT_RUBY` with a note.
<!-- sources: comments/eval-scripts#6 -->

#### 5.26 No DocC strictness or documentation build — Low

- **Where:** `SpamWise.xcodeproj/project.pbxproj:446`
- **Problem:** SpamWise sets no `OTHER_DOCC_FLAGS`, and no CI job runs `docbuild`. SubTrack sets `--warnings-as-errors` on 8 configurations, and both SubTrack (ci.yml:141) and Zephyr (ci.yml:267) run `xcodebuild docbuild`.
- **Scenario:** A renamed parameter or broken symbol link in SpamWiseCore DocC goes unnoticed.
- **Fix:** Add `OTHER_DOCC_FLAGS = --warnings-as-errors` (or equivalent package strictness) and port Zephyr's `docs` CI job.
<!-- sources: config/ci-automation#26 -->

#### 5.27 Duplicated end-of-day math with unexplained `-0.001` — Low

- **Where:** `SpamWise/ActivityDateFilterView.swift:29-30`, `SpamWise/ActivityStatisticsView.swift:17-23`
- **Problem:** Two views compute an inclusive "through" date as next midnight minus one millisecond, inline and unnamed.
- **Scenario:** One copy moves to a half-open range and the other doesn't, so Statistics and the Activity filter disagree.
- **Fix:** Add one tested helper on `ActivityQuery` that takes start and through days, and use a half-open comparison.
<!-- sources: comments/app-views-main#7 -->

#### 5.29 Optimistic settings queue and refresh override are unexplained — Low

- **Where:** `SpamWise/AppModel.swift:130`, `AppModel.swift:175-191`
- **Problem:** Edits apply locally, persist through a serial `await previous?.value` chain, and `refresh()` ignores stored settings while `pendingSettings > 0`. Nothing names or documents this.
- **Scenario:** Someone deletes line 130 or the chaining, and the Pause/dry-run toggle flicker comes back, the same bug the ledger says was fixed before.
- **Fix:** Extract `preservingPendingEdits(_:)` and `hasPendingSettingEdits`, and add a short `///` on `editSettings`.
<!-- sources: comments/app-logic#1 -->

#### 5.30 History-eligible set encodes a receipt-gate rule without a name — Low

- **Where:** `SpamWise/AppModel.swift:285-289`
- **Problem:** The anonymous set excludes pending retries so a message can't vouch for itself, but nothing says that is why.
- **Scenario:** `.subtracting(retries)` is removed as redundant, and a pending spam message gates itself toward Inbox.
- **Fix:** Extract `historyEligibleInboxKeys(in:)` with a one-line `///`.
<!-- sources: comments/app-logic#8 -->

#### 5.31 IMAP-record discriminator and swallowed adapter error are implicit — Low

- **Where:** `SpamWise/AppModel.swift:355-359`, `SpamWise/AppModelIMAP.swift:33-38`
- **Problem:** IMAP origin is inferred from `mailboxValidity != nil`, and `try?` silently turns an adapter setup failure into "no action". Fail-open is intended, but nothing says so. A missing Keychain item actually surfaces later, as an action error.
- **Scenario:** A maintainer turns `try?` into `try`, and corrections can no longer be saved when the IMAP store fails to load.
- **Fix:** Add `MessageIdentity.isIMAPRecord` or `correctionAdapter(for:)`, document the fail-open choice, and consider surfacing the configuration error in `status`.
<!-- sources: comments/app-logic#10 -->

#### 5.32 Sweep-completion and claim-release expressions need names — Low

- **Where:** `SpamWise/AppModelFolders.swift:87-88`
- **Problem:** Two inline booleans decide when a training sweep ends and when claims are released. The `|| page.visitedCount == 0` clause has no stated reason.
- **Scenario:** The clause is "fixed" as an apparent off-by-one, and sweeps never finish on emptied folders, or claims are released while unreadable messages remain.
- **Fix:** Extract `isSweepComplete(offset:page:)` and `canReleaseClaims(page:health:)`, each with a one-line reason.
<!-- sources: comments/app-logic#3 -->

#### 5.33 Rule-import byte limit duplicated with an unexplained `+1` — Low

- **Where:** `SpamWise/AppModelRules.swift:5,43`, `SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift:34,91`
- **Problem:** The app copies core's private 2,000,000-byte limit and reads one extra byte, so that core's `<=` check rejects oversized files. Neither the copy nor the sentinel is explained.
- **Scenario:** Core lowers the limit and the app's copy stays at the old value.
- **Fix:** Expose the limit from core and wrap the read in `readBounded(_:limit:)`, with a doc explaining the extra byte.
<!-- sources: comments/app-logic#12 -->

#### 5.34 `AutomationLabel` raw values are persisted Shortcuts identities — Low

- **Where:** `SpamWise/AutomationIntents.swift:8`
- **Problem:** `"inbox"`, `"spam"` and `"needs-review"` match neither the case names nor `MailLabel`, and saved Shortcuts persist them, yet nothing marks them as a stable contract.
- **Scenario:** Someone makes them "consistent", and every saved Junk shortcut breaks.
- **Fix:** Add a one-line `///`: the raw values are persisted by Shortcuts and must not change.
<!-- sources: comments/app-logic#14 -->

#### 5.35 Stringly-typed `"verification"` path check — Low

- **Where:** `SpamWise/DecisionDetailView.swift:156,168`, `SpamWise/AppModelCredentials.swift:61`, `SpamWiseCore/Sources/SpamWiseCore/NotificationPlanning.swift:57`
- **Problem:** The view's `.disabled` check is the only thing stopping corrections to the synthetic API-key verification record, and it compares a magic string used in four places across two modules.
- **Scenario:** The path is renamed in one place, and correcting the fake record creates a sender rule.
- **Fix:** Add `DecisionRecord.isSyntheticVerification`, or make `path` an enum, and use it everywhere.
<!-- sources: comments/app-views-main#6 -->

#### 5.36 Guards encode unstated GitHub naming rules and MAS detection — Low

- **Where:** `SpamWise/DirectUpdateConfiguration.swift:9-11,26-27`
- **Problem:** The regexes hard-code GitHub's limits (39-character owners, no `--`, 100-character repositories), and a `_MASReceipt` check disables updates for App Store installs. Neither is named or explained.
- **Scenario:** Someone deletes the receipt check, and a store-installed copy of the direct variant offers GitHub updates.
- **Fix:** Extract `isValidGitHubOwner`, `isValidGitHubRepository` and `isMacAppStoreInstall`, with a `///` citing GitHub's rules.
<!-- sources: comments/app-logic#11 -->

#### 5.37 Credential-existence check via discarded Keychain read — Low

- **Where:** `SpamWise/IMAPConnectionModel.swift:132-136`
- **Problem:** `_ = try keychain.read()` exists only to make the save fail when no credential exists, and nothing says so.
- **Scenario:** A refactor changes it to `try?`, and connections are saved without credentials.
- **Fix:** Use a named `requireSavedCredential(in:)` or `APIKeychain.requireExisting()`.
<!-- sources: comments/app-logic#9 -->

#### 5.38 Safety side effects buried in inline `Binding` setters — Low

- **Where:** `SpamWise/IMAPSettingsView.swift:11-18`, `SpamWise/ModelSettingsView.swift:13-20`, `SpamWise/SpamhausSettingsView.swift:12-15`, `SpamWise/EvidenceSettingsView.swift:82-87`
- **Problem:** These anonymous view closures are the only place several rules live: a transport change forces dry run and resets the route, a backend change clears the model, a Spamhaus service change revokes consent, and onAppear coerces settings for App Store builds. Pipeline independently refuses to act on unvalidated accounts, so this is a maintainability gap, not a safety hole.
- **Scenario:** The transport picker is switched to the generic `advancedBinding`, and the dry-run reset quietly disappears.
- **Fix:** Move each rule into a named, tested model or core operation (`switchMailTransport(to:)`, `selectingSpamhausTransport(_:)`, `restrictedToDistribution()`).
<!-- sources: comments/app-views-settings#6 -->

#### 5.39 Opaque inline expressions in Settings view bodies — Low

- **Where:** `SpamWise/IMAPSettingsView.swift:67`, `SpamWise/FolderSettingsView.swift:24`, `SpamWise/ModelSettingsView.swift:37-39,61,106`
- **Problem:** Several expressions need a name: `UInt32(...).map { $0 > 0 } != true`, a Binding that mixes the local `plan` with `self.plan`, inline PCC and key-provider lists, and a `.task(id: model.busy)` budget reload.
- **Scenario:** A new key-based provider falls into the else-branch and shows PCC text with no key field.
- **Fix:** Add `hasValidProbeUID`, `ModelBackend.requiresAPIKey` and `availableCases`, plus a `planBinding` property and a named reload.
<!-- sources: comments/app-views-settings#7 -->

#### 5.40 Account-inclusion binding hides the snapshot-on-first-toggle rule — Low

- **Where:** `SpamWise/MailHealthView.swift:22-28` (the predicate is repeated in `SpamWise/AppModelScanning.swift` and `SpamWise/AppModelFolders.swift`)
- **Problem:** That nil means "all accounts" is documented in MailPreferences.swift:7. The undocumented part is that the first toggle snapshots the accounts known at that moment, so accounts added later are excluded.
- **Scenario:** The user unchecks account A and later adds account C, and C is silently never filtered.
- **Fix:** Add `MailOptions.includes(_:)` and `setIncluded(_:_:knownAccounts:)` with DocC on new-account treatment and a core unit test.
<!-- sources: comments/app-views-main#8 -->

#### 5.41 Help names controls and tabs that differ from the UI — Low

- **Where:** `SpamWise/SpamWise.help/Contents/Resources/en.lproj/correcting-mistakes.html:5`, `en.lproj/what-data-is-sent.html`, `SpamWise/DecisionDetailView.swift:150,152`, `SpamWise/SettingsView.swift:14`
- **Problem:** The Help says "Mark as Good / Mark as Junk", but the inspector buttons read "Good" and "Junk" (the longer titles appear only in the menu bar and accessibility labels). It says "Account settings" for the "Accounts" tab and doesn't mention Undo.
- **Scenario:** A user looks for a "Mark as Good" button in the inspector.
- **Fix:** Match the visible UI, mention Undo latest correction, and update es/fr.
<!-- sources: comments/app-views-main#10 -->

#### 5.42 `Generate` signature has unlabeled, swappable parameters — Low

- **Where:** `SpamWiseCore/Sources/Classifier/AppleClassifier.swift:22-24` (also :76)
- **Problem:** The public typealias takes `(AppleModelBackend, String, String, Int)`, and the doc doesn't say which String is the instructions and which is the prompt. Swapping them compiles. (The "fifteen seconds" in the classify doc is an accurate upper bound.)
- **Scenario:** An alternative backend swaps the two Strings, and untrusted message text becomes the system instructions.
- **Fix:** Document each parameter in a `/** */` block, or pass a small labeled struct.
<!-- sources: comments/core-classifier-learning#12 -->

#### 5.43 Init doc says "for evaluation" but production uses it — Low

- **Where:** `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift:20` (also :31), `SpamWiseCore/Sources/SpamWiseCore/ConfiguredClassifier.swift:50`
- **Problem:** `init(modelID:key:)` is documented for evaluation, but ConfiguredClassifier builds the live classifier with it. `init(key:)` never says it selects Haiku 5.5. Neither doc mentions the `.configuration` throw.
- **Scenario:** Someone treats `init(modelID:)` as evaluation-only, changes its validation, and breaks Settings model selection.
- **Fix:** Document `init(modelID:key:)` as selecting a supported model and throwing otherwise, and `init(key:)` as "Uses Claude Haiku 5.5".
<!-- sources: comments/core-classifier-learning#2 -->

#### 5.44 Gemini 2x pricing epoch is unexplained — Low

- **Where:** `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:5-7,43`
- **Problem:** Rates double from `1_798_761_600` (2027-01-01 UTC) with no source or meaning given. The `rates(for:at:)` doc doesn't explain `at:`. `legacyHaiku` holds the current Haiku 5.5 rate and doubles as the fallback.
- **Scenario:** After 2027-01-01, Gemini estimates double, and nothing tells a maintainer whether that is intended.
- **Fix:** Write the date as a readable ISO 8601 constant with a sourced doc, document `at:`, and rename `legacyHaiku` with a note on its fallback role.
<!-- sources: comments/core-classifier-learning#8 -->

#### 5.45 `ThreatInput.init` silently strips learned scores — Low

- **Where:** `SpamWiseCore/Sources/Classifier/ThreatAssessment.swift:90-97`
- **Problem:** The init nils out `bayesLogOdds` and `learnedMargin`, and its doc doesn't say so. The type doc only partly states the invariant. The fingerprint doc's "enriched text beyond the raw hash" is unclear.
- **Scenario:** Someone deletes the "redundant" assignments, and preference scores leak into threat assessments and cache keys.
- **Fix:** Extract `evidence.excludingLearnedScores()`, document the exclusion on the init, and reword the fingerprint doc.
<!-- sources: comments/core-classifier-learning#5 -->

#### 5.46 `TokenUsage` fallback condition misstated — Low

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:29` (also :25, :31)
- **Problem:** The doc ties the Haiku fallback to records without a model identity, but the code falls back whenever `pricing` is nil.
- **Scenario:** `TokenUsage(…, modelID: "gpt-5.4-mini")` without pricing is silently priced at Haiku rates.
- **Fix:** "Uses captured `pricing`, or Claude Haiku 5.5 rates when none was captured", and drop "historical".
<!-- sources: comments/core-classifier-learning#13 -->

#### 5.47 `FilteringStrength` case docs duplicate the thresholds — Low

- **Where:** `SpamWiseCore/Sources/Decision/Decision.swift:4-14`
- **Problem:** Each case doc hard-codes the 99/95/90 values that are already in `threshold`. The type doc carries the roadmap note "pending held-out calibration".
- **Scenario:** Calibration changes balanced to 97, and the published docs still say 95.
- **Fix:** Describe the cases relatively (strictest, default, most permissive), point to `threshold`, and track calibration in TODO.md.
<!-- sources: comments/core-classifier-learning#9 -->

#### 5.48 `latencyP50Sec` doc describes the 95th percentile — Low

- **Where:** `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:75-76,122-123`
- **Problem:** The median property's doc describes both percentiles, and it omits the rule that the value is nil when any measurement is missing (which `latencyP95Sec` does state).
- **Scenario:** A report consumer reads nil as a bug.
- **Fix:** "Nearest-rank median per-message latency, absent if any measurement is missing."
<!-- sources: comments/eval-scripts#2 -->

#### 5.49 `EvaluationObservation.file`/`.path` docs are narrower than stored values — Low

- **Where:** `SpamWiseCore/Sources/Evaluation/Metrics.swift:19` (also :9, :122), `SpamWiseCore/Sources/Evaluation/ComparisonReport.swift:111,115`, `SpamWiseCore/Sources/SpamWiseEval/main.swift:204`
- **Problem:** `file` is documented as a "Relative corpus path" but also holds manifest IDs and `reviewed/<content-id>`. `path` is documented as "Gate, model, or error" but the code also emits fingerprint, correction, selection and comparison. Calibration filters on the literal `"model"`.
- **Scenario:** The pipeline's `"model"` path is renamed, and every calibration bucket silently reports zero.
- **Fix:** Document `file` as an opaque sample identifier, and replace `path` with a shared enum.
<!-- sources: comments/eval-scripts#11 -->

#### 5.50 Candidate fingerprints use placeholder label and date — Low

- **Where:** `SpamWiseCore/Sources/Learning/CampaignLearning.swift:68,77`
- **Problem:** The matchers build full fingerprints with arbitrary `.inbox`/`.junk` labels and `.distantPast` dates only to get shingles and anchors. The differing labels look meaningful but are ignored.
- **Scenario:** Label-dependent logic is later added to `fingerprint()`, and matching changes without anyone noticing.
- **Fix:** Extract a `candidateSignature(for:)` helper that returns anchors and shingles.
<!-- sources: comments/core-classifier-learning#15 -->

#### 5.51 `CampaignMatch` doc denies the Junk gate it drives — Low

- **Where:** `SpamWiseCore/Sources/Learning/LearningState.swift:67`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:27-36`
- **Problem:** The doc says a match is "never a standalone action instruction", yet with fingerprints enabled a match skips the model and produces Junk at confidence 100, which is the decisive gate in the brief.
- **Scenario:** A maintainer changes the anchor logic believing matches are advisory, and that directly changes Junk moves.
- **Fix:** Document the gate behavior, and note in TODO.md (L51) that the match is decisive.
<!-- sources: todo/roadmap#9 -->

#### 5.52 Partial or inaccurate member docs in LearningState — Low

- **Where:** `SpamWiseCore/Sources/Learning/LearningState.swift:253` (also :59, :154, :172-186)
- **Problem:** `forget` removes any sample with the ID, not only "explicit" ones. `CampaignFingerprint.label` documents only the Inbox value. `recordCorrection` doesn't mention that it withdraws overlapping Junk fingerprints and predictions.
- **Scenario:** A Good correction unexpectedly deletes other admitted predictions.
- **Fix:** Fix both docs and extract `withdrawJunkEvidence(overlapping:)`.
<!-- sources: comments/core-classifier-learning#11 -->

#### 5.53 `importHistory` is a long block that needs named helpers — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:285-336`, `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:125-129`
- **Problem:** One function pages, filters, dedupes, counts replies and applies an English-only receipt heuristic. `eligibleInbox` and `incremental` are undocumented, and IMAPAdapter duplicates the reply counter.
- **Scenario:** The two reply-counting copies drift apart.
- **Fix:** Extract `looksLikeReceipt(_:)` and a shared reply counter, and document both parameters.
<!-- sources: comments/mail-integration#8 -->

#### 5.54 Docs phrased as reviewer-directed disclaimers — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:290` (also :323), `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:106`, `SpamWiseCore/Sources/SpamWiseCore/MailPreferences.swift:37,49`, `SpamWiseCore/Sources/SpamWiseCore/ReviewPriority.swift:3`, `SpamWiseCore/Sources/SpamWiseCore/ActivityQuery.swift:39,57`, `SpamWiseCore/Sources/SpamWiseCore/SelectedCorrections.swift:45`, `SpamWiseCore/Sources/Decision/Decision.swift:75`, plus similar "without X" docs in Classifier/Types.swift:157,169, ClaudeClassifier.swift:35, ThreatAssessment.swift:125,142 and Learning/CorrectionLearning.swift:56
- **Problem:** Many docs answer review objections ("without claiming…", "never trusts itself") instead of stating behavior. AppleMailAdapter.swift:290 is also inaccurate: a nil `eligibleInbox` accepts all Inbox mail. `ReviewPriority` never states its ordering. `Decision.evaluate` omits the Junk-below-threshold demotion and its throw. Some "without X" clauses do accurately describe pure functions, but they replace the positive contract.
- **Scenario:** A caller passes nil `eligibleInbox` because the comment says only classified mail is imported.
- **Fix:** State the behavior positively. For example, ReviewPriority: "action failures first, then evidence disagreements, then lower confidence, then newest". `Decision.evaluate`: demotion and throw. Document `eligibleInbox`.
<!-- sources: comments/mail-integration#7, comments/core-pipeline-store#11, comments/core-classifier-learning#4 -->

#### 5.55 `testDisposableMessage` docs omit that it moves and flags mail — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:337` (347-349), `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:177-178`
- **Problem:** Both docs describe eligibility only. They leave out the Junk-and-back moves, the 30 s settling waits, the orange flag the AppleScript version leaves, the return values and the errors.
- **Scenario:** A caller expects a read-only check and gets a minute-long run that leaves the message flagged orange.
- **Fix:** Write `/** */` DocC listing the mutation sequence, waits, final state, return value and failures. Consider renaming to `runDisposableMoveProbe`.
<!-- sources: comments/mail-integration#3 -->

#### 5.56 Multi-line doc comments use `///` instead of `/** */` — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:134-135,177-178`; related `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:117`, `SpamWiseCore/Sources/MailIntegration/IMAPTransport.swift:11-12`, `SpamWiseCore/Sources/MailIntegration/IMAPConfiguration.swift:52-53`
- **Problem:** swift-conventions requires `/** */` for multi-line docs. The same convention review also flagged undocumented IMAPError, IMAPCredential and ScriptValue cases (see 5.71) and the boilerplate AppleMailAdapter init (see 5.9).
- **Scenario:** The documentation style is inconsistent across the package.
- **Fix:** Convert both blocks to `/** */`.
<!-- sources: comments/mail-integration#11, conventions/mail-integration#15 -->

#### 5.57 Wire parsing uses raw ASCII byte values — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPProtocol.swift:49-55,79,134`, `SpamWiseCore/Sources/MailIntegration/IMAPConfiguration.swift:40`, `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift:77`
- **Problem:** The tokenizer and allowlists compare against 32, 40, 41, 34, 92, `[13, 10]` and numeric ranges, so every value must be translated by hand.
- **Scenario:** A transcription error in the host allowlist passes review unnoticed.
- **Fix:** Use `UInt8(ascii:)` or named constants, and a named `CharacterSet` for allowlists.
<!-- sources: comments/mail-integration#10 -->

#### 5.58 Paging and sentinel contracts lack names — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailPage.swift:25,37`, `SpamWiseCore/Sources/MailIntegration/IMAPPaging.swift:24-33`, `SpamWiseCore/Sources/MailIntegration/IMAPSweepCursor.swift:1-8`, `MailExtension/MessageActionHandler.swift:6-7`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:16`
- **Problem:** Several contracts are hidden in arithmetic. The row-count check is one dense expression. `.boolean(false)` is an "unreadable" sentinel. IMAP offsets count from the newest message. The 9 s watchdog must exceed the 8 s classification cap. `1...max(1, n)` relies on `atIndex` returning nil.
- **Scenario:** The range trick is "simplified" and empty lists crash, or the watchdog is set to 8 s.
- **Fix:** Extract `expectedRowCount`, name the sentinel, document `IMAPSweepCursor.offset`, derive the watchdog from the deadline plus a margin, and guard empty lists explicitly.
<!-- sources: comments/mail-integration#9 -->

#### 5.59 `MailScripts.lookup` documented as a read but builds mutating scripts — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:100` (111-127), `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:250`
- **Problem:** With a non-`.none` action, the script flags, colors or moves mail. The doc mentions neither `action` nor that `expectedSource` is then required.
- **Scenario:** The function is reused for a preview with an action argument, and the message moves to Junk.
- **Fix:** Split it into `lookup(_:)` and `action(_:for:expectedSource:)`, or document both parameters and the mutation.
<!-- sources: comments/mail-integration#2 -->

#### 5.60 `accountPage` docs omit the role parameter and Inbox fallback — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:233` (211-213, 249), `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:180`
- **Problem:** The doc says "Inbox", but the function accepts the Junk and Sent roles, silently falls back to Inbox for unknown strings, and always reports "Account Inbox unresolved". `recent` has the same fallback.
- **Scenario:** A direct call with `"junk"` reads the Inbox, and the results are labeled as Junk data.
- **Fix:** Replace the role string with an enum, or document the accepted values and the fallback and put the role in the error text.
<!-- sources: comments/mail-integration#6 -->

#### 5.61 Status is all-or-nothing but documented per attachment — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/DocumentInspection.swift:16` (28, 31, 37), `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:274`
- **Problem:** One oversized text attachment makes the whole re-parse throw, so every text attachment is marked unavailable. "Its content" implies a per-attachment status, and "existing parser" is change-relative wording.
- **Scenario:** A 10 KB attachment beside a 100 KB one is discarded too.
- **Fix:** Document the whole-message status or skip oversized parts one at a time, and drop "existing".
<!-- sources: comments/core-parsing-signals#21 -->

#### 5.62 `extract` says unsupported MIME fails; it is skipped — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:44` (82)
- **Problem:** Unsupported image types such as WebP are skipped silently. Only malformed or over-limit parts throw.
- **Scenario:** A caller reads an empty result as "no images".
- **Fix:** "Returns validated PNG/JPEG/GIF/TIFF/HEIC parts; other types are skipped; malformed or over-limit parts throw."
<!-- sources: comments/core-parsing-signals#11 -->

#### 5.63 Docs describe downstream policy instead of their own contract — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:4`, `SpamWiseCore/Sources/MessageModel/DocumentInspection.swift:25`, `SpamWiseCore/Sources/Signals/ContentRules.swift:51`
- **Problem:** "Deliberately bounded… mail is unclassified" describes what the pipeline does with the result. The parser itself throws `ParseError`. Similar claims about other modules go stale whenever those modules change.
- **Scenario:** The pipeline stops failing open on a rule timeout, and "Mail remains unchanged" becomes false.
- **Fix:** Describe this code's own contract, and put the fail-open guarantee where it is enforced.
<!-- sources: comments/core-parsing-signals#22 -->

#### 5.64 Stale "byte-preserved above" comment — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:146` (conversion now at 201-202)
- **Problem:** Declaration reordering moved `parse` below `decodeWords`, so "above" now points the wrong way. The original placement in cce7b3a was correct.
- **Scenario:** A reader looks above for the byte preservation and misreads the branch.
- **Fix:** Extract `utf8Reinterpreted(_:)` and delete the comment.
<!-- sources: comments/core-parsing-signals#3 -->

#### 5.65 `AttachmentMetadata.init` doc names one consumer, not its behavior — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/Message.swift:32`, `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:106`
- **Problem:** The doc says "for explicit user rules", though the parser is the main caller. It doesn't mention the 256-character truncation, and that 256 duplicates `maximumAttachmentLabelCharacters`.
- **Scenario:** A reader misses that this initializer is where truncation is enforced.
- **Fix:** "Creates attachment labels, truncating the media type and filename to 256 characters", using the named constant.
<!-- sources: comments/core-parsing-signals#18 -->

#### 5.66 Non-obvious mechanisms have no explanation — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:14-45`, `SpamWiseCore/Sources/Signals/ContentRules.swift:117-119`, `SpamWiseCore/Sources/Signals/Evidence.swift:71`
- **Problem:** The private `DeadlineRace` first-wins latch uses tuple slots and has no explanation. Nothing says the regex deadline depends on `.reportProgress`. The abuse-heavy TLD list is inline and unsourced.
- **Scenario:** `.reportProgress` is removed as unnecessary, and pathological regexes ignore the 100 ms budget.
- **Fix:** Add a short doc and a named struct for `DeadlineRace`, one comment on `.reportProgress`, and a named, sourced TLD constant.
<!-- sources: comments/core-parsing-signals#27 -->

#### 5.67 Deadline helpers say "returns" but throw — Low

- **Where:** `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift:46` (63), `SpamWiseCore/Sources/Classifier/Deadline.swift:4` (11)
- **Problem:** Both carry the same doc, "Returns at the deadline…". They actually throw (`ResourceDeadlineError.timeout` or `CancellationError`, and `ClassificationError.timeout`). `withResourceDeadline` also clamps non-finite seconds to 1 ms, and its doc uses the Classifier term "provider".
- **Scenario:** A caller passes `.infinity` to mean "no deadline" and everything times out after 1 ms.
- **Fix:** Use `/** */` DocC with `- Parameter seconds:` (or reject non-finite values) and `- Throws:`, and say "operation" instead of "provider".
<!-- sources: comments/core-parsing-signals#15, comments/core-classifier-learning#14 -->

#### 5.68 `ContentRules.matches` documented "for previews" but gates live mail — Low

- **Where:** `SpamWiseCore/Sources/Signals/ContentRules.swift:74`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:109`
- **Problem:** Live classification uses `.first` of this function's result.
- **Scenario:** Someone relaxes the timeout or ordering as "preview-only" and changes live gating.
- **Fix:** "Enabled matching rules, newest first; the first element wins during classification."
<!-- sources: comments/core-parsing-signals#14 -->

#### 5.69 `tldIsAbuseHeavy` doc says weak; brief and prompt say strong — Low

- **Where:** `SpamWiseCore/Sources/Signals/Evidence.swift:33`, `SpamWiseCore/Sources/Classifier/Types.swift:244`
- **Problem:** The DocC contradicts brief §3.2 and the fixed instructions, which both treat this as strong evidence.
- **Scenario:** A maintainer demotes the signal while tuning weights.
- **Fix:** "Strong but non-decisive evidence: the sender TLD is on the static abuse-heavy list."
<!-- sources: gap/brief-conformance#10 -->

#### 5.70 `ContactsLookup` doc omits the permission prompt and throws — Low

- **Where:** `SpamWiseCore/Sources/Signals/Evidence.swift:111-119`, `SpamWise/AppModel.swift:255`
- **Problem:** The method doc doesn't mention that `requestAccess: true` can trigger a TCC prompt, or the errors it throws. The type doc itself is accurate.
- **Scenario:** A background caller passes `true` and an unexpected permission prompt appears.
- **Fix:** Use a `/** */` doc with `- Parameter requestAccess:` and `- Throws:`.
<!-- sources: comments/core-parsing-signals#19 -->

#### 5.71 Public enum cases lack DocC across modules — Low

- **Where:** `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:6` (also :19, :224), `Signals/ContentRules.swift:6,10`, `Signals/Gates.swift:5,7,28`, `Signals/RspamdLookup.swift:6`, `Signals/EvidenceProcess.swift:10`, `MessageModel/Message.swift:43`, `MessageModel/ResourceDeadline.swift:9`, `SpamWiseCore/AuditEvent.swift:17-18`, `SpamWiseCore/MailFolder.swift:19`, `SpamWiseCore/AutomationRequest.swift:5-6`, `SpamWiseCore/AdvancedSettings.swift:135`, `MailIntegration/IMAPTransport.swift:11-12`, `MailIntegration/AppleMailAdapter.swift:9`, `MailIntegration/IMAPConfiguration.swift:52-53`, `Evaluation/Metrics.swift:5`, `Evaluation/ReviewedCorpus.swift:6-7,15` (all under `SpamWiseCore/Sources/`)
- **Problem:** Compound `case` lines leave public cases undocumented, while sibling enums (`SpamhausTransport`, `AttachmentTextCoverage.Status`, `IncomingRoute`) document every case. Some meanings aren't obvious: `.observed` vs `.listed`, partial vs complete history, `recipients` covering To and Cc but not Bcc, `ReviewedCorpusPartition.all` being exploratory only, and retryable vs fatal `IMAPError`s. The `ExternalEvidenceFinding.status` doc names three states for four cases, and relabels are audited as `.corpusImport`. SwiftLint `missing_docs` is off, so nothing catches this.
- **Scenario:** Quick Help shows bare case names, and a reader filtering the audit log misreads relabels as imports.
- **Fix:** Put each case on its own line with a `///` summary, fix the `status` doc, consider a `corpusRelabel` kind, and enable `missing_docs`.
<!-- sources: comments/core-parsing-signals#6, comments/core-pipeline-store#14, comments/mail-integration#12, comments/eval-scripts#3, conventions/eval-scripts#12 -->

#### 5.72 `Query` typealias says "absolute" name; callers pass relative — Low

- **Where:** `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:78` (156, 195-196)
- **Problem:** Callers pass `domain + ".dbl.spamhaus.org"` without the root dot, and the default implementation appends it.
- **Scenario:** An injected resolver trusts the doc and search domains get appended to the query.
- **Fix:** "a validated DBL query name without the trailing root label", or pass the absolute name.
<!-- sources: comments/core-parsing-signals#9 -->

#### 5.73 `DNSAnswer` documented as DNS-only; HTTPS returns it too — Low

- **Where:** `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:213-224`, `SpamWiseCore/Sources/Signals/SpamhausHTTPS.swift:3-35`
- **Problem:** The HTTPS transport converts API codes into fake `127.0.1.x` strings to fit the DNS shape. Nothing documents that.
- **Scenario:** DNS-specific validation is added and misbehaves on HTTPS answers.
- **Fix:** Rename to `BlocklistAnswer` with a typed listing code, or at least redocument it and comment the normalization.
<!-- sources: comments/core-parsing-signals#8 -->

#### 5.74 Docs and literals restate named constants — Low

- **Where:** `SpamWiseCore/Sources/Signals/RspamdLookup.swift:35-47`, `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:173-174`, `SpamWiseCore/Sources/Signals/EvidenceProcess.swift:30`
- **Problem:** The default timeout `3` and "five domains" are repeated in docs and literals beside `queryTimeoutSec` and `maximumQueries`. RspamdLookup has no constant at all.
- **Scenario:** A constant changes, and the defaults and docs keep advertising the old value.
- **Fix:** Add `maximumTimeout` and use the constants as defaults. Describe bounds conceptually in docs.
<!-- sources: comments/core-parsing-signals#16 -->

#### 5.75 DBL listing-code tables duplicated with no source — Low

- **Where:** `SpamWiseCore/Sources/Signals/SpamhausHTTPS.swift:8-12`, `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:134-137`
- **Problem:** The same nine codes are hard-coded twice. Neither copy cites Spamhaus or explains why 2003 / 127.0.1.3 is excluded.
- **Scenario:** One table is updated and the two transports disagree on what counts as listed.
- **Fix:** A single `DBLListing` enum with both representations and a doc that links Spamhaus's return-code page.
<!-- sources: comments/core-parsing-signals#10 -->

#### 5.76 Discarded `PromptBuilder.prompt` result is unexplained — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/ConfiguredClassifier.swift:55`
- **Problem:** The prompt is built and thrown away, evidently to validate the input before a non-refundable budget reservation.
- **Scenario:** The line is removed as dead code, and invalid inputs consume reservations.
- **Fix:** `try PromptBuilder.validate(input)`, or a named helper.
<!-- sources: comments/core-pipeline-store#13 -->

#### 5.77 Public API DocC is summary-only; overloads indistinguishable — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:26,80`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:20`, `SpamWiseCore/Sources/SpamWiseCore/TrainingFolders.swift:39-43`, `SpamWiseCore/Sources/Store/Store.swift:68`, `SpamWiseCore/Sources/SpamWiseCore/EvaluationBudget.swift:48`
- **Problem:** The two `process` overloads share one summary, though one also parses MIME and runs OCR and Rspamd. `attempt` is public and unexplained, and the unit of `timeout` is undocumented.
- **Scenario:** An integrator passes a nonzero `attempt` or a timeout in milliseconds.
- **Fix:** Give the overloads distinct summaries, add `- Parameters` and `- Throws` on non-trivial functions, and consider making `attempt` internal.
<!-- sources: comments/core-pipeline-store#7 -->

#### 5.78 Dense inline decision logic needs named helpers — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:276-294` (also :56, :141-151), `SpamWiseCore/Sources/SpamWiseCore/TrainingFolders.swift:57-62`, `SpamWiseCore/Sources/SpamWiseCore/ReviewPriority.swift:8-31`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:170,210-214`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:221-227`
- **Problem:** The dispatch outcome chain, the error-reason mapping, claim retention, the magic review ranks 0/1/2, contact freshness, transport availability and the cost backfill are all inline and unnamed.
- **Scenario:** Reordering dispatch's else-if chain silently changes recorded outcomes.
- **Fix:** Extract `claimOutcome(for:in:isCorrection:)`, `isClaimRetained(_:)`, a private `Rank` enum, `isTransportAvailable` and `backfillMonthlyCostsIfNeeded()`, and document `correction`.
<!-- sources: comments/core-pipeline-store#12 -->

#### 5.79 Gate precedence encoded by calling `Gates.evaluate` twice — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:95-124`, `SpamWiseCore/Sources/Signals/Gates.swift:75`
- **Problem:** Sender rules, then content rules, then Contacts/history: the product's precedence is expressed by blanking different arguments on two calls, with no doc on the function.
- **Scenario:** The two calls are collapsed into one, and content rules lose precedence over relationship trust.
- **Fix:** Use named steps (`explicitSenderRuleGate`, `contentRuleGate`, `relationshipGate`), or give Gates dedicated entry points.
<!-- sources: comments/core-pipeline-store#6 -->

#### 5.80 Doc comments narrate store history and phases — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:38,40,47`, `SpamWiseCore/Sources/SpamWiseCore/AdvancedSettings.swift:76,82,92`
- **Problem:** "Absent in Phase 1 stores", "existing configurations" and "legacy" fail the comment test. A reader can't tell what nil means today.
- **Scenario:** A new reader can't tell whether a nil `origin` is valid input.
- **Fix:** Describe current nil semantics ("nil means public DNS"), and move the migration rationale to commits.
<!-- sources: comments/core-pipeline-store#9 -->

#### 5.81 DocC omits side effects of settings edits, restore and corrections — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:248`, `SpamWiseCore/Sources/SpamWiseCore/StateBackup.swift:60`, `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:19`
- **Problem:** The summaries leave out the side effects. Editing settings can force dry run back on and clear the undo. Restore pauses filtering and revokes validations. A Review correction deletes the address rule and throws `invalidOutput` at domain scope.
- **Scenario:** A UI developer can't tell why dry run turned itself back on.
- **Fix:** Add a Discussion and `- Throws:`, or extract named invariant helpers, and throw a dedicated error for Review at domain scope.
<!-- sources: comments/core-pipeline-store#4 -->

#### 5.82 Daemon help text is ragged and incomplete — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:16-25`
- **Problem:** Mixed continuations produce uneven help lines. The config keys, `statePath` and the route switch on `--probe` are not documented.
- **Scenario:** A user can't write a config file without reading the source.
- **Fix:** Reflow the help into an OPTIONS list and add a CONFIG section and the route-switch note.
<!-- sources: comments/mail-integration#17 -->

#### 5.83 `spamwise-eval` usage incomplete and states unenforced policy — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/Options.swift:26` (12-14, 25), `SpamWiseCore/Sources/SpamWiseEval/main.swift:74`
- **Problem:** The reviewed-mode synopsis omits `--mock-responses`, `--budget-store`, the price overrides and `--state`. "Requires separate spending authorization" is operator policy the code doesn't enforce. The 1–1000 `--limit` range isn't stated.
- **Scenario:** A user never learns that mock responses work in reviewed mode.
- **Fix:** List the common options once, describe `--budget-store` by its behavior, and state the limit range.
<!-- sources: comments/eval-scripts#8 -->

#### 5.84 Seed-state isolation inlined instead of a named helper — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/main.swift:149-160`
- **Problem:** The offline-isolation invariant documented in docs/evaluation.md:66 is eight unexplained assignments inside an orchestrator of about 55 lines.
- **Scenario:** A new network evidence option isn't disabled, and evaluation starts making lookups.
- **Fix:** Extract `isolatedState(_:strength:)` with a one-line doc.
<!-- sources: comments/eval-scripts#17 -->

#### 5.85 Store actor DocC lacks a summary and the lock behavior — Low

- **Where:** `SpamWiseCore/Sources/Store/Store.swift:32-35` (100)
- **Problem:** The DocC abstract is an implementation detail. The non-blocking `lockUnavailable` behavior appears only in a private comment.
- **Scenario:** Callers don't learn that concurrent writers fail immediately instead of waiting.
- **Fix:** Lead with a type summary and move the transaction and lock details into a Discussion.
<!-- sources: comments/core-pipeline-store#16 -->

#### 5.86 Test names cover a fraction of multi-behavior tests — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:176` (also :83), `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:5,89`, `SpamWiseCore/Tests/SpamWiseCoreTests/ClassifierTests.swift:4`, `SpamWiseCore/Tests/SpamWiseCoreTests/SignalsTests.swift:159`
- **Problem:** Tests chain five to ten behaviors behind narrow names, and names are their only documentation. The user's "extend the existing test" rule partly explains the chaining.
- **Scenario:** An undo assertion fails under a "pending retries" name, and someone writes a duplicate undo test.
- **Fix:** Split them into focused tests with shared fixtures, or rename the combined ones to describe the whole flow.
<!-- sources: comments/tests#2 -->

#### 5.87 Persistence failure forced by an unexplained directory-as-store trick — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift:390-392`
- **Problem:** The test passes a directory as the store URL, which looks like a setup mistake.
- **Scenario:** Someone "fixes" the path, and the fail-open coverage is lost.
- **Fix:** A named `unwritableStore()` fixture in DecisionFixtures.swift.
<!-- sources: comments/tests#6 -->

#### 5.88 Boundary tests hard-code production limits — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/EmbeddedImageTests.swift:65` (also :46, :52, :62), `ProviderTests.swift:230`, `MailIntegrationTests.swift:217`, `ExternalEvidenceTests.swift:43,185,251`, `ParsingTests.swift:45,52,61,91`, `ClassifierTests.swift:29`, `SignalsTests.swift:155,176`, `IMAPTests.swift:35` (all under `SpamWiseCore/Tests/SpamWiseCoreTests/`)
- **Problem:** Values such as 524_289 and 65_537 are one past a limit, yet they don't reference `EmbeddedImages.maximumImageBytes` or `ModelHTTPClient.maximumResponseBytes`, which are public. Some bounds are private, so a literal is the only option there.
- **Scenario:** A reader can't tell which limit a literal tracks once that limit changes.
- **Fix:** Use `constant + 1` where reachable, and a named private test constant otherwise.
<!-- sources: comments/tests#3 -->

#### 5.89 Unnamed literal fixtures in tests — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/ProviderTests.swift:162,166`, `RoadmapStateTests.swift:203`, `EmbeddedImageTests.swift:69`, `DecisionTests.swift:270,291`, `MailIntegrationTests.swift:180-182` (all under `SpamWiseCore/Tests/SpamWiseCoreTests/`)
- **Problem:** Several fixture values are unnamed: the epoch values are the Gemini cutoff, bytes 16..<24 are the PNG IHDR dimensions, 35 s is just past the first retry, and 21 is the stub Inbox size.
- **Scenario:** The pricing cutoff moves, and nobody can tell the test meant "one second before".
- **Fix:** `introductoryRateEnd` from ISO 8601, `png(width:height:)`, `pastFirstRetry` and `inboxCount`.
<!-- sources: comments/tests#5 -->

#### 5.90 Test file named after a project phase — Low

- **Where:** `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift:1`
- **Problem:** "Roadmap" names a milestone. The file's seven tests cover migration, backup, rule import, corpus, budget, notifications and automation.
- **Scenario:** Someone looking for backup tests misses this file and adds parallel ones.
- **Fix:** Split the file by behavior, or rename it.
<!-- sources: comments/tests#12 -->

#### 5.91 Docs cite evidence that does not exist in the repository — Low

- **Where:** `TODO.md:120`, `docs/roadmap-progress.md:4`, `docs/conventions-and-design-review.md:3`, `docs/privacy-audit.md:49`, `CLAUDE.md:69`, and about 58 `.build/<uuid>` references across docs
- **Problem:** The `.build` paths point at gitignored local artifacts. The cited hashes are not on squashed `main`; they are reachable only through `origin/codex/phase-one`.
- **Scenario:** A reviewer cloning `main` can verify none of the evidence.
- **Fix:** Remove `.build` paths and branch-only hashes. Keep reproducible commands and conclusions, and attach evidence to PRs or releases if needed.
<!-- sources: comments/repo-docs#12 -->

#### 5.92 Corpus README omits the OpenTextShield candidate and `--synthetic` — Low

- **Where:** `Tools/Corpus/README.md:88-106`, `Tools/Corpus/screen.py:28-34,148,273-275`
- **Problem:** The README documents only Horizon-Labs with budgets 384 and 1024. The script also supports `opentextshield` (96 and 384; it rejects 1024) and `--synthetic`.
- **Scenario:** `--candidate opentextshield --max-tokens 1024` raises `ValueError`.
- **Fix:** Document `--candidate`, each candidate's budgets and revision, and `--synthetic`.
<!-- sources: comments/tools#7 -->

#### 5.93 Corpus README uses the obsolete strict-memory-safety flag — Low

- **Where:** `Tools/Corpus/README.md:159`
- **Problem:** It is the only recipe that uses `-enable-experimental-feature StrictMemorySafety`. Every other recipe uses `-strict-memory-safety`.
- **Scenario:** The recipe may warn on Swift 6.4, and `-warnings-as-errors` would turn that into a failure. Unverified.
- **Fix:** Use `-strict-memory-safety`.
<!-- sources: comments/tools#8 -->

#### 5.94 "Separate pyenv environment" is never named — Low

- **Where:** `Tools/Corpus/README.md:183`, `Tools/Corpus/.python-version`, `docs/probes/spaphish-baseline.md:106`
- **Problem:** `.python-version` pins `spamwise-corpus`. The only working recipe uses a worker-specific environment name found in a probe doc.
- **Scenario:** Packages installed in an arbitrary environment no longer match the hashed baseline requirements.
- **Fix:** Give the environment a stable name (`spamwise-spaphish`) and show the `pyenv virtualenv` and run commands.
<!-- sources: comments/tools#9 -->

#### 5.95 Report method strings duplicate unnamed code literals — Low

- **Where:** `Tools/Corpus/audit.py:126-148` (also :246, :326, :381), `Tools/Corpus/spaphish.py:102,148-157,232-263`, `Tools/Corpus/screen.py:163,243`, `Tools/Corpus/prepare.py:72,124,135,268-270`
- **Problem:** Provenance prose and parameter blocks are hand-typed copies of thresholds and hyperparameters that are themselves unnamed literals.
- **Scenario:** The Jaccard threshold changes, and every committed report still claims 0.8.
- **Fix:** Hoist them into named module constants and build the method strings and parameter dicts from those constants.
<!-- sources: comments/tools#4 -->

#### 5.96 Order-dependent imports and split reset are unexplained — Low

- **Where:** `Tools/Corpus/screen.py:152-161`, `Tools/Corpus/spaphish.py:77-78`, `Tools/Corpus/audit.py:116-118`
- **Problem:** The Hugging Face offline variables must be set before the deferred imports. The split reset exists because `development_campaigns` skips holdout rows. Neither ordering is explained. `local_files_only=True` already limits the network risk.
- **Scenario:** The reset is deleted as redundant, and some rows are never compared for leakage.
- **Fix:** Add `force_offline_huggingface()` and `make_all_rows_campaign_eligible(rows)`, or one-line comments.
<!-- sources: comments/tools#10 -->

#### 5.97 Harness uses unnamed limits and errno literals — Low

- **Where:** `Tools/DocumentWorker/ProbeHost.swift:55` (76, 124, 159, 164, 198), `Tools/DocumentWorker/Client.swift:124`, `Tools/DocumentWorker/Worker.swift:18,68`, `Tools/DocumentWorker/WorkerProbes.swift:26,32`, `Tools/DocumentWorker/Fixtures.swift:5,18`
- **Problem:** Boundary fixtures hard-code limit + 1 (13 pages, 3001 characters) next to `DocumentWorkerLimits`, and errnos appear as bare 1 and 22. The 0.1-point font and the `active:` flag are unexplained.
- **Scenario:** `pages` is raised to 20, and the page-limit probe no longer tests the boundary.
- **Fix:** Add the limits to `DocumentWorkerLimits`, derive fixtures from them, use `EPERM` and `EINVAL`, and rename `active:` to `withJavaScriptAction:`.
<!-- sources: comments/tools#11 -->

#### 5.98 Worker exit codes 71–76 are undocumented — Low

- **Where:** `Tools/DocumentWorker/Worker.swift:70` (43, 63, 73, 77, 83, 124), `Tools/DocumentWorker/WorkerProbes.swift:13`
- **Problem:** Launchd logs only the code, and neither the source nor the README maps codes to reasons.
- **Scenario:** "Exited with code 75" requires searching the source, and a reused number makes two failures indistinguishable.
- **Fix:** Add a `WorkerExit: Int32` enum with a `terminate(_:)` helper, and list the codes in the README.
<!-- sources: comments/tools#2 -->

#### 5.99 Unexplained reference-date timestamp — Low

- **Where:** `Tools/Preferences/run.py:34`
- **Problem:** `813456000 + index` is seconds since 2001-01-01, matching Foundation's default `Date` decoding, and nothing says so.
- **Scenario:** Someone reads it as Unix time, "fixes" it, and dates jump about 31 years.
- **Fix:** Name it (`REFERENCE_DATE_SECONDS`) and derive it from datetimes, or add a one-line comment.
<!-- sources: comments/tools#12 -->

#### 5.100 Duplicated UI lookup workarounds with one comment — Low

- **Where:** `UITests/ActivityScreen.swift:34` (also :47), `UITests/UITests.swift:222,228-236,346-349`
- **Problem:** The toolbar-title lookup and the nested-static-text fallback are duplicated, and only one copy is explained. `threatsAreUnassessed` compares English text, which contradicts the ledger's claim that localized queries were replaced.
- **Scenario:** A new screen copies the uncommented copy and swaps in an identifier, and the test times out.
- **Fix:** Add `openSettingsPane(_:)` and `displayedText(of:)` helpers with a single comment each, and use semantic values.
<!-- sources: comments/tests#7 -->

#### 5.101 Disclosure expanded by an unexplained coordinate click — Low

- **Where:** `UITests/EvidenceScreen.swift:17`
- **Problem:** The test clicks at 20% across the disclosure, presumably because the identifier sits on the label (CLAUDE.md), but the code doesn't say so.
- **Scenario:** A wider localized label moves the hit point, and the Spamhaus test times out.
- **Fix:** An `expandDisclosure(_:)` helper with a one-line reason, or click the disclosure triangle if it is exposed.
<!-- sources: comments/tests#8 -->

#### 5.102 automation.md omits the Apple Mail transport requirement — Low

- **Where:** `docs/automation.md:5-7` (also :46-59, :86-120), `SpamWise/AutomationIntents.swift:111-113`
- **Problem:** The Preview and Correct intents require `transport == .appleMail`, and the documented prerequisites leave that out. The verification sections are a dated session log (see 5.18).
- **Scenario:** An IMAP user gets "Select one Mail message" with no explanation.
- **Fix:** Add the prerequisite, and reduce the verification sections to current reproduction steps.
<!-- sources: comments/app-logic#18 -->

#### 5.103 Conventions ledger claims an exhaustive review it no longer covers — Low

- **Where:** `docs/conventions-and-design-review.md:96` (also :3, :8, :58, :115-121, :226-239), `CLAUDE.md:153-155`
- **Problem:** The ledger is dated against baseline 6d813c1 and "140 files". Some 74–76 later Swift files are absent, including nine app-logic files, seven test files, the Spamhaus HTTPS code and the automation code. Rows narrate session edits ("Added…", "Removed generated file header"). Two rows (DecisionTests "aligned with asserted behavior" and UITests "localized status queries replaced") are inaccurate. CLAUDE.md repeats the "every file" claim without caveat.
- **Scenario:** A reviewer treats AutomationIntents.swift or the UI screen objects as already reviewed.
- **Fix:** Delete the per-file ledger, keeping the durable compatibility decisions (L41–54) in an architecture doc, and remove the "exhaustive" claim from CLAUDE.md.
<!-- sources: comments/app-logic#17, comments/tests#14, comments/repo-docs#10 -->

#### 5.104 packaging.md misdescribes the Help index and notarization input — Low

- **Where:** `docs/packaging.md:11` (also :5, :32), `Scripts/help-index.sh:3-6`, `Scripts/archive.sh:39-40`
- **Problem:** The doc says "six English pages" and a single `-s en` index, but there are three localized books, each indexed. It says the script uploads the "archive", but the script submits a ZIP of the exported app.
- **Scenario:** Someone rebuilds only the English index, and Spanish and French search goes stale.
- **Fix:** Describe three localized books indexed by help-index.sh, and the ZIP submission.
<!-- sources: comments/eval-scripts#10 -->

#### 5.105 Privacy docs and onboarding copy are stale about data flows — Low

- **Where:** `docs/privacy-audit.md:19`, `docs/privacy.md`, `SpamWise/OnboardingView.swift:72,93`, `SpamWise/AppModelScanning.swift:93-98`
- **Problem:** The audit's Spamhaus row predates the HTTPS transport and its Keychain key. "Preview up to 20 recent Inbox messages" actually reads 20 per account. Examples are not relevance-selected. The storage list omits the contact snapshot and the RDAP cache.
- **Scenario:** A four-account user sends up to 80 messages, and an App Privacy questionnaire drafted from these docs misses the Spamhaus key flow.
- **Fix:** Regenerate the inventory from the code, fix the copy ("per account" or cap the total), and complete the storage list.
<!-- sources: privacy-dataflow#14 -->

#### 5.106 Mock-response keys are undocumented SHA-256 hashes — Low

- **Where:** `eval/mock-responses.json:2`, `SpamWiseCore/Sources/SpamWiseEval/main.swift:93`, `docs/evaluation.md`
- **Problem:** The keys are SHA-256 hashes of the raw fixture bytes. Nothing says so, and nothing says how to regenerate them.
- **Scenario:** A typo fix in a fixture causes `missingMock`, and there is no documented way to recover.
- **Fix:** Document the key scheme and the `shasum -a 256 eval/fixtures/*/*.eml` command. Optionally add a fixture-path field to each entry.
<!-- sources: comments/tools#13 -->

#### 5.107 No comments or DocC in Settings views; none required — Info

- **Where:** `SpamWise/` (the 18 Settings view files)
- **Problem:** Not a defect. All types are internal, so swift-conventions requires no DocC, and nothing fails the comment test. The real gaps are the non-self-documenting expressions in 5.38 and 5.39.
- **Scenario:** None.
- **Fix:** None beyond 5.38 and 5.39.
<!-- sources: comments/app-views-settings#11 -->

#### 5.108 Protocol parsing lacks RFC references — Info

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPProtocol.swift:4` (also :204-207), `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:275-276`
- **Problem:** COPYUID (RFC 4315), OAUTHBEARER (RFC 7628) and LIST layouts are parsed positionally with no grammar reference.
- **Scenario:** A reviewer can't verify `index + 3` or the deliberate rejection of UID sets without opening the RFC.
- **Fix:** Add one-line doc comments citing each grammar.
<!-- sources: comments/mail-integration#19 -->

#### 5.109 Calibration notes embedded in DocC — Info

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:36` (also :16)
- **Problem:** "Provisional… requires runtime calibration" records outstanding project work in an API doc and doesn't link to TODO.md. It is accurate today.
- **Scenario:** After calibration, nothing forces the comment to change.
- **Fix:** Describe the value ("Maximum seconds the Mail callback waits for a decision") and track calibration in TODO.md.
<!-- sources: comments/core-pipeline-store#10 -->
## 6. Project configuration compared with SubTrack and Zephyr

SpamWise's Swift package is configured correctly. It uses tools-version 6.4 and Swift 6 language mode, and a single hoisted `swiftSettings` array applies every upcoming feature plus `.strictMemorySafety()` to every target. Most Xcode project-level Swift settings also match the conventions: complete strict concurrency, approachable concurrency, ExistentialAny, InternalImportsByDefault, MemberImportVisibility and ImmutableWeakCaptures. On the machine the reviewers used, the package tests (89 passed, 1 opt-in skip), both app builds and every Python suite pass with zero warnings. The one existing workflow is better hardened than the sisters' workflows: actions are pinned to SHAs, `permissions` are least-privilege and checkout sets `persist-credentials: false`. Keep those practices when porting the sister workflows.

The repository scaffolding around that code falls well short of SubTrack and Zephyr. The most serious problem is that the Xcode project references `../../Libraries/GitHubUpdateChecker` through a local path, and the product it needs exists only as an unpushed commit on a local branch. A fresh clone fails package resolution for every scheme, which reviewers reproduced. Until this is fixed, no CI can be adopted and no second machine can build the project. The other gaps follow from it:

- The only workflow validates the static site.
- Nothing builds, tests, lints or scans for dead code on push or PR.
- The main `SpamWise` scheme is generated by Xcode on each machine, not committed.
- The UnitTests target is never run by any script.

The build variants are defined ad hoc. The App Store build exists only when `Scripts/app-store-check.sh` passes `SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE` on the command line. The notarized Developer ID artifact comes from the `SpamWise` target, which has no update checks. The target that does have update checks is named `SpamWiseDirect`, and that name appears in the menu bar and in Finder. The sisters instead use explicit `-MAS` and `-download` targets with their own App structs, entitlements and Info.plists, and release through fastlane. SpamWise instead has about 466 lines of custom Python that decrypts Match material, run inside the corpus ML virtualenv.

There is also a pattern of configuration drift and hand editing:

- The project file was written by hand and contains null build files.
- iOS template keys end up in the shipped macOS Info.plist.
- Build settings and the entitlements file disagree about file access, so the signed app carries both the read-only and the read-write entitlement.
- Generated Help indexes and a compiled AppleScript are committed as binaries, with no build step to regenerate them.
- Strict memory safety is missing from every Xcode target, although CLAUDE.md claims it is on.

The SwiftLint config does not use the house parent config, which hides about 428 violations under the shared standard. The scripts that serve as the documented developer interface require agent-only tooling (`agent-lock`, `rg`). The tracked CLAUDE.md is a 68 KB work log rather than a set of durable instructions.

None of this affects runtime correctness today on the author's Mac. It does mean the project cannot be reproduced, reviewed or released by anyone or anything else. Most fixes are mechanical: copy the matching sister file or setting.

| Aspect | SubTrack | Zephyr | SpamWise | Gap |
| --- | --- | --- | --- | --- |
| Build/test CI | `ci.yml`: unit, CLI, UI (download and MAS), DocC on `xcode-27`; SPM and DerivedData caches; xcresult upload; concurrency cancel | `ci.yml`: unit, build both editions, UI, DocC; same caching and signing env | None. `site.yml` only, and it runs only on docs/site PRs or manual dispatch | No package, app, extension or UI test automation |
| Lint CI and config | `lint.yml`; `.swiftlint.yml` with gist `parent_config`; tracked `.swift-format` symlink | Same | No lint workflow; standalone `.swiftlint.yml` with no parent, which disables a house rule; no `.swift-format`; Tools/ and Scripts/ outside scope | About 428 violations (2 errors) hidden under the house standard |
| Periphery | `periphery.yml` + `.periphery.yml` | Same | None | No dead-code scan; a manual scan found 11 unused and 43 redundant-public symbols |
| actionlint config | `.github/actionlint.yaml` (xcode-27 label) | Same | None | Needed once xcode-27 jobs exist |
| Package references | Remote `GitHubUpdateChecker` with a version requirement (2.1.1) | Remote, with a version requirement (2.2.0) | Local `../../Libraries/GitHubUpdateChecker`; product only on unpushed `codex/release-discovery` | Fresh clones cannot resolve packages |
| Swift settings | Includes `SWIFT_STRICT_MEMORY_SAFETY = YES` | Same | Everything except strict memory safety on Xcode targets (package has it) | Missing on all five Xcode targets |
| SDK and platforms | `SDKROOT = macosx` | Same | `SDKROOT = auto`; iOS, tvOS, watchOS, visionOS and DriverKit deployment targets; `INFOPLIST_KEY_UI*` keys reach the shipped plist | Template residue |
| Project file | Generated by Xcode | Generated by Xcode | Hand-written IDs; two `(null) in Frameworks` entries; `MyApp.swift` | Fragile to edit |
| Schemes and test plans | 7 shared schemes, test plan | 10 shared schemes, 2 test plans | Only `SpamWiseDirect` is shared, with no TestAction; main scheme autocreated; stale `xcuserdata` plist tracked; no test plans; UnitTests never run | Test and archive configuration not versioned |
| Variants | `SubTrack (MAS)` / `SubTrack (download)` targets, each with its own App struct, entitlements and Info.plist; shared framework | `Zephyr (MAS)` / `Zephyr (download)`; `libZephyr` | `SpamWise` and `SpamWiseDirect` share one folder, entitlements and Info.plist; `APP_STORE` exists only as a CLI override; Developer ID ships the target with no updater | Store identity not in the project; direct product named `SpamWiseDirect` |
| Entitlements | Per variant, consistent with build settings | Per variant | Shared; build setting says read-only, file says read-write, so both are signed; extension gets unneeded file access | Contradictory and over-broad |
| Generated resources | `Help/` at root; "Build Help Book" phase with anchor validation; `*.cshelpindex` gitignored | Same | Committed `.cshelpindex` regenerated only by `archive.sh`; compiled `.scpt` committed beside its source; no run-script phases | Stale-output risk |
| Scripts | Plain `xcodebuild`/fastlane; documented headers (e.g. `make-dmg.sh`) | Plain; `make-pkg.sh` | Every script needs an `agent-lock` worker token and `rg`; assumes cwd is the repo root; no headers; token validated in only one script | Agent tooling baked into the human build path |
| Release / fastlane | Gemfile, `.ruby-version`, Appfile, Matchfile, Fastfile, `.env.example`, metadata; tag-driven `release.yml`; build number stamped | Same; `.pkg` | No fastlane; custom Python Match decryption run in the corpus venv; manual zip; hard-coded 1.0 (1) | Reinvents an existing tool; no versioning or release automation |
| Repository files | LICENSE (GPL-2.0), CREDITS.md, CHANGELOG, full `.gitignore` | LICENSE (MIT), CREDITS.md, CHANGELOG, full `.gitignore` | No LICENSE, CREDITS or CHANGELOG; minimal `.gitignore`; no app icon; public site links into a private repo | Attribution and hygiene gaps |
| Bootstrap and diagnostics | Per-variant App; preview guard; Sentry after guards; dSYM upload | Similar | Single App struct; no preview guard; one `Logger` in the codebase; no crash reporting or recorded policy | No field diagnostics |
| Agent configuration | `.claude/settings.local.json` skillOverrides; excluded `.codex/config.toml`; no tracked CLAUDE.md | Same | `.codex/config.toml` only; no `.claude/`; 68 KB tracked CLAUDE.md work ledger | Missing Claude skill overrides; ledger used in place of instructions |

### Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| 6.2 | Medium | `.github/workflows/site.yml:3` | No CI builds or tests the package, app, extension or UI |
| 6.3 | Medium | `.swiftlint.yml:1` | SwiftLint config drops the house parent config; no lint CI |
| 6.4 | Medium | `CLAUDE.md:195` | Tracked CLAUDE.md is a 68 KB work ledger with operational details and a standing Trash-cleanup instruction |
| 6.5 | Medium | `Scripts/app-store-check.sh:44` | App Store variant exists only as a command-line flag; Developer ID ships the target without an updater |
| 6.6 | Medium | `Scripts/ui-check.sh:7` | Build, test and release entry points require agent-only tooling |
| 6.7 | Medium | `SpamWise.xcodeproj/project.pbxproj:513` | No Xcode target enables strict memory safety, contrary to CLAUDE.md |
| 6.8 | Medium | `SpamWise.xcodeproj/project.pbxproj:872` | Direct build's product name is SpamWiseDirect |
| 6.9 | Medium | `SpamWise.xcodeproj/xcshareddata/xcschemes/SpamWiseDirect.xcscheme:1` | Main SpamWise scheme is unshared; stale xcuserdata plist tracked; no test plans |
| 6.10 | Low | `.claude/settings.local.json` (absent) | Claude configuration lacks the Apple skill overrides the sisters enable |
| 6.11 | Low | `.gitignore:1` | `.gitignore` lacks the house entries for credentials and release outputs |
| 6.12 | Low | `.swiftlint.yml:1` | No Periphery; `.swift-format` not tracked; lint scope omits Tools/ and Scripts/ |
| 6.13 | Low | `Resources/SpamWiseRule.applescript:1` | Mail rule script is kept as both source and committed compiled binary |
| 6.14 | Low | `Scripts/app-store-check.sh:17` | Scripts abort under `set -e` before printing their diagnostics |
| 6.15 | Low | `Scripts/archive.sh:6` | Scripts lack headers, assume the repo root as cwd, and validate the worker token inconsistently |
| 6.16 | Low | `Scripts/help-index.sh:6` | Help index is committed and rebuilt by hand; no build phase or anchor validation |
| 6.17 | Low | `Scripts/notarize-match.py:38` | Release tooling reimplements fastlane match in Python |
| 6.18 | Low | `SpamWise.xcodeproj/project.pbxproj:11` | Hand-written pbxproj contains dangling `(null) in Frameworks` build files |
| 6.19 | Low | `SpamWise.xcodeproj/project.pbxproj:611` | Build settings and entitlements disagree; both read-only and read-write file access are signed |
| 6.20 | Low | `SpamWise.xcodeproj/project.pbxproj:617` | iOS template settings leak into the macOS bundle; metadata inconsistent |
| 6.21 | Low | `SpamWiseCore/Sources/SpamWiseEval/main.swift:6` | `@main` in `main.swift` breaks SwiftPM's native build system |
| 6.22 | Low | `Tools/DocumentWorker/check.sh:88` | Production-symbol gate passes silently when ripgrep is missing |
| 6.23 | Low | `Tools/Site/build.py:16` | Public site pages link into the private repository; site deps not hash-checked |
| 6.24 | Low | `docs/app-store.md:83` | Release Python helpers run in the corpus ML virtualenv |
| 6.25 | Info | `SpamWise/MyApp.swift:27` | No crash reporting, structured logging or preview guard in the bootstrap |

#### 6.2 No CI builds or tests the package, app, extension or UI — Medium

- **Where:** `.github/workflows/site.yml:3` (`.github/workflows/` contains only this file)
- **Problem:** The only workflow runs Python site checks, on PRs that touch `docs/**` or `Tools/Site/**` and on manual dispatch. Nothing runs `swift test` for SpamWiseCore, builds the app and extension targets or the `APP_STORE` configuration, runs UnitTests or UITests, or checks DocC. Every "tests pass" claim in CLAUDE.md is a local, unautomated run. The sisters each have `ci.yml`, `lint.yml`, `periphery.yml` and `release.yml`.
- **Scenario:** A PR that breaks package tests, the Mail extension build or the strict-concurrency build merges green, because no check runs on it. PR #1 has been validated only for the static site.
- **Fix:** After fixing 6.1, adapt `Zephyr/.github/workflows/ci.yml`: setup-xcode 27, `IDESkipMacroFingerprintValidation`, SPM and DerivedData caches, xcbeautify, xcresult upload, concurrency cancel. Add jobs for `swift test --package-path SpamWiseCore -Xswiftc -warnings-as-errors`, unsigned builds of both editions and of `APP_STORE`, and DocC. Add a UI job using the `SIGNING` env, overriding `PROVISIONING_PROFILE_REQUIRED=NO` (the UITests target sets YES at `project.pbxproj:804/823`). Add `.github/actionlint.yaml` with the `xcode-27` label. Keep SpamWise's SHA pinning rather than the sisters' floating tags.
<!-- sources: config/ci-automation#2, config/swift-xcode#9 -->

#### 6.3 SwiftLint config drops the house parent config; no lint CI — Medium

- **Where:** `.swiftlint.yml:1` (also `:13`)
- **Problem:** The sister configs start with `parent_config:` pointing at the RISCfuture gist and add only excludes and `prefer_nimble`. SpamWise's config is standalone. It omits the house opt-in rules (attributes, missing_docs, async_without_await, unused_parameter, raw_value_for_camel_cased_codable_enum, and the analyzer rules), and it disables `optional_data_string_conversion`. The project's "0 violations" baseline therefore measures a weaker standard. There is also no `lint.yml`.
- **Scenario:** Run against the house parent config, the code reports about 428 violations. That includes 43 Codable enums without explicit raw values, which can silently break persisted data when a case is renamed. Two violations are errors: `empty_count` at `SpamWise/UnreadableMailView.swift:7` and at `SpamWiseCore/Sources/MailIntegration/IMAPPaging.swift:23`.
- **Fix:** Replace the file with the sister form: the gist `parent_config`, `excluded: [.build, .superpowers, Tools/Corpus]` and `disabled_rules: [prefer_nimble]`. Keep only the local overrides that are genuinely needed, each with a comment. Copy `Zephyr/.github/workflows/lint.yml` with SpamWise's source roots, then fix or justify each finding.
<!-- sources: config/ci-automation#9 -->

#### 6.4 Tracked CLAUDE.md is a 68 KB work ledger with operational details and a standing Trash-cleanup instruction — Medium

- **Where:** `CLAUDE.md:195` (also `:67`, `:94`, and roughly 600 lines of dated milestone and probe narrative)
- **Problem:** Neither sister tracks a CLAUDE.md or AGENTS.md. SpamWise's is mostly a chronological record of what an agent did and claimed passed. The user's comment rules put that kind of history in commit messages, and loading it costs context in every session. The file includes a durable instruction to move generated probe mail to Trash. It also records operational details: reuse of SubTrack's `MATCH_PASSWORD`, Keychain service names, personal addresses and notarization IDs. All of that becomes public if the repo is published as planned.
- **Scenario:** Future sessions load the whole ledger as project instructions, including the Trash-cleanup directive. That directive is narrowly scoped (documented generated probes only, never emptying Trash) but sits uneasily beside the product's no-Trash invariant. Making the repo public exposes the credential-reuse and account details.
- **Fix:** Cut CLAUDE.md down to a few dozen lines of durable instructions: architecture invariants, commands and conventions. Move the ledger to commit history or a dated `docs/history` file if it must be kept. Keep the probe-cleanup rule only if the user wants it standing. Review the file for personal and operational details before any visibility change.
<!-- sources: config/ci-automation#16 -->

#### 6.5 App Store variant exists only as a command-line flag; Developer ID ships the target without an updater — Medium

- **Where:** `Scripts/app-store-check.sh:44` (also `SpamWiseCore/Sources/SpamWiseCore/DistributionCapabilities.swift:5`, `:13`; `Scripts/archive.sh:17`; `project.pbxproj:595`, `:613`, `:835`, `:853`; `docs/app-store.md`)
- **Problem:** `APP_STORE` is supplied only by `SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE` on one script's xcodebuild line. That override replaces the configured conditions, and no target, configuration or scheme encodes the store build. `DistributionCapabilities` enables external programs (dig, rspamc) and PCC whenever `APP_STORE` is absent. Meanwhile `archive.sh` notarizes the plain `SpamWise` target, whose update settings say "Update checks are unavailable in this build". `SpamWiseDirect` is never archived. The sisters use explicit `-MAS` and `-download` targets, each with its own App struct, entitlements, Info.plist and injected `FeatureFlags(isAppStoreBuild:)`.
- **Scenario:** An archive made from Xcode's Product > Archive, or from a future CI or fastlane lane that omits the flag, is a store-signed build with the executable-evidence paths compiled in. The project's own App Review notes say those paths must be excluded. Separately, users of the notarized download can never learn about updates.
- **Fix:** Adopt the sister layout: `SpamWise-MAS` and `SpamWise-download` targets, each with its own App struct, entitlements and Info.plist, and shared code in a common framework. Archive and notarize the download target for Developer ID. The `#if APP_STORE` checks live in the SPM package, and target-level settings do not reach package targets. So either inject the capability from the per-variant App struct (as the sisters do) or set the condition through a configuration or xcconfig that also covers the package. Then remove the command-line override from scripts and docs.
<!-- sources: config/swift-xcode#4, conventions/eval-scripts#16, architecture#23 -->

#### 6.6 Build, test and release entry points require agent-only tooling — Medium

- **Where:** `Scripts/ui-check.sh:7` (also `Scripts/check.sh:3`, `:10`; `Scripts/archive.sh:21`; `Scripts/app-store-check.sh:46`; `README.md:17`)
- **Problem:** README's "Build and verify" section and every script start from an `agent-lock worker` token. That is an agent-coordination tool from the user's Codex setup. `ui-check.sh` hard-requires `agent-lock run ui`, and the warning gates depend on `rg`. No sister script, Fastfile or workflow references agent-lock. The `.build/<token>/` layout exists to serve parallel agent sessions.
- **Scenario:** A developer following README on a clean Mac fails at `agent-lock: command not found` or has to invent a token. A GitHub runner without ripgrep makes the `rg` warning gates misbehave (see 6.22).
- **Fix:** Make the plain path the default, as the sisters do: xcodebuild or fastlane lanes and CI jobs with no tokens. Keep worker isolation as an optional wrapper documented in the user's ios-dev-isolation skill rather than in README. Replace `rg` with `grep -E` in shipped scripts.
<!-- sources: config/ci-automation#14 -->

#### 6.7 No Xcode target enables strict memory safety, contrary to CLAUDE.md — Medium

- **Where:** `SpamWise.xcodeproj/project.pbxproj:513` (also `:507`, `:577-585`; `CLAUDE.md:57`; `SpamWiseCore/Package.swift:10`)
- **Problem:** swift-conventions requires strict memory safety on every target, and the sisters set `SWIFT_STRICT_MEMORY_SAFETY = YES`. SpamWise sets it only in the package. The SpamWise, SpamWiseDirect, MailExtension, UnitTests and UITests targets compile without it. `git log -S` shows the setting was never added, so the CLAUDE.md claim has never been true for the Xcode targets. The unsafe-heavy code is in the package, which is checked, so this is a convention gap and a false claim, not demonstrated unchecked unsafe code.
- **Scenario:** Unsafe pointer or C interop added to the app or extension (NSAppleScript bridges, Security framework, MailKit callbacks) compiles with no `unsafe` marker or diagnostic.
- **Fix:** Add `SWIFT_STRICT_MEMORY_SAFETY = YES;` to both project-level configurations. Build with warnings as errors and clear any diagnostics with checked APIs or narrow `unsafe` expressions. Correct CLAUDE.md.
<!-- sources: config/swift-xcode#2, conventions/app-logic#15 -->

#### 6.8 Direct build's product name is SpamWiseDirect — Medium

- **Where:** `SpamWise.xcodeproj/project.pbxproj:872` (also `:926`; `docs/distribution-differences.md:60`)
- **Problem:** `PRODUCT_NAME = SpamWiseDirect`, with no `CFBundleDisplayName` or `PRODUCT_MODULE_NAME` override. So the bundle, the executable and `CFBundleName` all read "SpamWiseDirect". The docs say this keeps build products distinct, but the name is visible to users. The sisters set `PRODUCT_NAME` to the product name and use a distinct module name (for example `SubTrackDownload`).
- **Scenario:** A direct-build user sees "About SpamWiseDirect", "Quit SpamWiseDirect" and `SpamWiseDirect.app` in the menu bar, Dock, Finder, Force Quit and Mail Automation prompts. That does not match the Help book or the extension's display name.
- **Fix:** Set `PRODUCT_NAME = SpamWise` and `INFOPLIST_KEY_CFBundleDisplayName = SpamWise`, plus a distinct `PRODUCT_MODULE_NAME` such as `SpamWiseDownload`. Keep outputs apart with separate schemes or build directories.
<!-- sources: config/swift-xcode#5 -->

#### 6.9 Main SpamWise scheme is unshared; stale xcuserdata plist tracked; no test plans — Medium

- **Where:** `SpamWise.xcodeproj/xcshareddata/xcschemes/SpamWiseDirect.xcscheme:1` (also `SpamWise.xcodeproj/xcuserdata/tmorgan.xcuserdatad/xcschemes/xcschememanagement.plist:7`, `:13`; `Scripts/check.sh:9`; `Scripts/ui-check.sh:7`; `Scripts/archive.sh:17`; `Scripts/app-store-check.sh:40`)
- **Problems:**
  - Every script drives `-scheme SpamWise`, which exists only because Xcode autocreates it. Its test membership, launch arguments and Archive configuration are not versioned.
  - The one shared scheme, `SpamWiseDirect`, has no TestAction, so the `#if SPAMWISE_DIRECT_UPDATES` code never builds under test.
  - None of the documented commands runs UnitTests, and `UnitTests/UnitTests.swift` is an import-only stub.
  - A per-user `xcschememanagement.plist` is committed despite `xcuserdata/` in `.gitignore`. It names scaffold schemes that no longer exist (MyApp, SpamWiseKit).
  - Empty untracked `SpamWiseKit/` and `SpamWiseKitTests/` directories remain in the checkout.
  - The sisters share every scheme (7 and 10) and use `.xctestplan` files.
- **Scenario:** On a runner or Mac with "Autocreate schemes" off, the scripts fail with "scheme SpamWise not found". Elsewhere the generated scheme may omit UITests or use a different archive configuration. Every scheme reorder dirties a tracked file.
- **Fix:** Share explicit schemes for each app variant, the extension and the tests. Add a test plan covering UnitTests and UITests, with Archive set to Release. Run `git rm --cached -r SpamWise.xcodeproj/xcuserdata` and delete the empty SpamWiseKit directories.
<!-- sources: tooling#3, config/ci-automation#13, config/swift-xcode#7, distribution/packaging#11, tooling#9 -->

#### 6.10 Claude configuration lacks the Apple skill overrides the sisters enable — Low

- **Where:** `.claude/settings.local.json` (absent; compare `.codex/config.toml` and `SubTrack/.claude/settings.local.json`)
- **Problem:** The local `.codex/config.toml` enables swiftui-specialist, app-intents-specialist and related Apple skills, but there is no `.claude/` directory. Both sisters have matching `skillOverrides`. This is per-user, local configuration.
- **Scenario:** Claude Code sessions working on SpamWise's SwiftUI and App Intents code run without the specialist skills the user enabled for the sister apps.
- **Fix:** Run `agent-config audit --backend claude` and apply its preview, which should produce `skillOverrides` matching SubTrack's.
<!-- sources: config/ci-automation#19 -->

#### 6.11 `.gitignore` lacks the house entries for credentials and release outputs — Low

- **Where:** `.gitignore:1`
- **Problem:** The file has seven entries. It is missing Zephyr's patterns for `*.xcresult`, `fastlane/.env`, `asc_api_key.json`, `*.p8`, `*.dmg`, `*.pkg`, Help indexes and the SwiftLint remote cache. Release helpers decrypt App Store Connect keys and produce packages, and `.codex`, `__pycache__` and `.ruff_cache` are ignored only through global or `.git/info/exclude` rules.
- **Scenario:** On a machine without the user's global ignores, `git add -A` commits a key written into the tree or a `fastlane/.env`.
- **Fix:** Merge the relevant blocks from `Zephyr/.gitignore`, and add `__pycache__/`, `.ruff_cache/` and `.codex/`.
<!-- sources: config/ci-automation#24 -->

#### 6.12 No Periphery; `.swift-format` not tracked; lint scope omits Tools/ and Scripts/ — Low

- **Where:** `.swiftlint.yml:1` (also missing `.periphery.yml`, `.github/workflows/periphery.yml`, `.swift-format`; `.github/workflows/site.yml:42`)
- **Problems:**
  - The sisters run `periphery scan --strict` across both editions. SpamWise has no config and no workflow; a manual scan during this review found 11 unused and 43 redundant-public symbols.
  - SwiftLint's `included` list omits `Tools/DocumentWorker` (741 lines) and `Scripts/*.swift` (834 lines).
  - Only the `Tools/Site` Python suite runs in CI; the Corpus and Preferences suites do not.
  - Local swift-format finds `~/.swift-format` by ancestor lookup, but the config is not tracked, so CI and other machines use defaults.
  - These files currently report zero findings, so this is a coverage gap.
- **Scenario:** Dead code from the many probe iterations stays in the binary and in review scope. A later edit to the XPC worker, or a broken Corpus test, goes unflagged.
- **Fix:** Add a `.periphery.yml` modeled on Zephyr's (both editions plus the test schemes, `retain_swift_ui_previews: true`) and copy its workflow. Track a `.swift-format` symlink as the sisters do. Add `Tools` and `Scripts` to SwiftLint's scope, and add a light CI job running ruff and `unittest` for Tools/Corpus and Tools/Preferences.
<!-- sources: config/ci-automation#10, config/swift-xcode#19, conventions/tools#18 -->

#### 6.13 Mail rule script is kept as both source and committed compiled binary — Low

- **Where:** `Resources/SpamWiseRule.applescript:1` (also `SpamWise/SpamWiseRule.scpt`; `SpamWise/AppModelNavigation.swift:15`)
- **Problem:** The app bundles the hand-compiled `SpamWise/SpamWiseRule.scpt`. The readable source sits in `Resources/`, which is outside every target. No `osacompile` step or regeneration note exists. The two decompile identically today, differing only in indentation.
- **Scenario:** A reviewed edit to the `.applescript`, such as a new URL parameter, has no effect. Mail users keep running the old compiled rule with no build error.
- **Fix:** Compile in a run-script phase with `osacompile -o "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/SpamWiseRule.scpt" Resources/SpamWiseRule.applescript` and stop tracking the `.scpt`, or keep only one form.
<!-- sources: config/ci-automation#25, correctness/mail-integration#17, comments/mail-integration#16 -->

#### 6.14 Scripts abort under `set -e` before printing their diagnostics — Low

- **Where:** `Scripts/app-store-check.sh:17` (also `:20`; `Scripts/evidence-runtime-check.sh:10-11`)
- **Problem:** If the sandbox key is missing, `PlistBuddy` fails inside a command substitution and `set -e` exits before the "App Sandbox missing" message, so that message prints only when the key exists but is false. `evidence-runtime-check.sh` sends all build output to a log and exits silently on failure. The scripts still fail closed; only the explanation is lost.
- **Scenario:** Removing `com.apple.security.app-sandbox` from MailExtension.entitlements makes the check exit 1 after "Does Not Exist", with no explicit diagnostic.
- **Fix:** Use `sandbox=$(PlistBuddy ... 2>/dev/null || echo missing)`, and wrap the evidence build in `|| { tail -65 "$build_root/evidence-build.log"; exit 1; }`, as `check.sh` does.
<!-- sources: correctness/eval-scripts#12 -->

#### 6.15 Scripts lack headers, assume the repo root as cwd, and validate the worker token inconsistently — Low

- **Where:** `Scripts/archive.sh:6` (also `Scripts/check.sh:3-7`, `Scripts/store-check.sh:3-8`, `Scripts/ui-check.sh:3-7`, `Scripts/help-index.sh:3`, `Scripts/evidence-runtime-check.sh:3-6`, `Scripts/rspamd-runtime-check.sh:3-9`; compare `Scripts/app-store-check.sh:5-7`)
- **Problem:** Only `app-store-check.sh` restricts the token to `[a-zA-Z0-9-]`. The others put any value into `.build/$worker`. None `cd`s to the repo root, and none has a usage header, unlike `SubTrack/Scripts/make-dmg.sh:1-13`. `archive.sh` also generates its Developer ID ExportOptions inline, while the App Store options are a checked-in plist. The token comes from the operator, so no trust boundary is crossed.
- **Scenario:** `bash Scripts/archive.sh ../../tmp` writes archives outside `.build/`. A token like `../Shared` makes `evidence-runtime-check.sh` write and Developer-ID-sign a probe app next to the repo. Running `check.sh` from another directory fails with "SpamWiseCore not found".
- **Fix:** Factor the existing `case` validation into a sourced helper, and start each script with `cd "$(dirname "$0")/.."` and a short usage header. Check in a `DeveloperIDExportOptions.plist`.
<!-- sources: conventions/eval-scripts#18, security/eval-scripts#6 -->

#### 6.16 Help index is committed and rebuilt by hand; no build phase or anchor validation — Low

- **Where:** `Scripts/help-index.sh:6` (also `SpamWise/SpamWise.help/Contents/Resources/{en,es,fr}.lproj/search.cshelpindex`; `Scripts/archive.sh:16`)
- **Problem:** The project has no `PBXShellScriptBuildPhase`. The search index is a tracked binary that only `archive.sh` regenerates, so release archives are current but Xcode and development builds are not. Nothing validates that `HelpButton` anchors exist; all seven exist today. SubTrack's `build-help-book.sh` runs as a build phase that fingerprints the book, checks anchors and indexes each locale, and the index is gitignored. (The parallel `.scpt` problem is 6.13.)
- **Scenario:** After a Help page edit or an anchor rename, Xcode builds ship a stale index or a broken anchor, and Help Viewer silently opens the first page. Each release archive leaves regenerated binaries dirty in the working tree.
- **Fix:** Copy `SubTrack/Scripts/build-help-book.sh` and `purge-help-cache.sh` (prefix `codes.tim.SpamWise`), add a "Build Help Book" phase to each app target, move the book to a root `Help/`, gitignore `**/*.cshelpindex` and delete `help-index.sh`.
<!-- sources: config/ci-automation#11, config/swift-xcode#18 -->

#### 6.17 Release tooling reimplements fastlane match in Python — Low

- **Where:** `Scripts/notarize-match.py:38` (also `:45`; `Scripts/export-store-match.py`; `docs/packaging.md:45-46`; `CLAUDE.md:94`)
- **Problem:** About 466 lines of Python decrypt the shared Match repository into a temporary keychain and drive notarization and store export, reading `MATCH_PASSWORD` from a fastlane `.env`. In practice that has been SubTrack's `.env`. The sisters do this through fastlane (Appfile, Matchfile, Fastfile, `.env.example`, metadata). The env file is an argument rather than a hard-coded path, and the script is an optional alternative to a notarytool profile, so the coupling is softer than it first appears.
- **Scenario:** Maintaining SpamWise signing requires understanding bespoke keychain and search-list handling that fastlane match already handles in the user's other apps. Releases depend on another project's `.env` being present.
- **Fix:** Add a fastlane setup mirroring Zephyr's, with SpamWise's own `.env`, notarize lanes and App Store lanes, then delete the Python Match helpers.
<!-- sources: config/swift-xcode#10 -->

#### 6.18 Hand-written pbxproj contains dangling `(null) in Frameworks` build files — Low

- **Where:** `SpamWise.xcodeproj/project.pbxproj:11` (also `:12`, `:134`, `:136`)
- **Problem:** Two `PBXBuildFile` entries have neither a `fileRef` nor a `productRef`. Sequential object IDs (`AA00…`, `CC00…`) show the file was written by hand rather than by Xcode. Two targets share one product dependency, and the two Embed phases reference MailExtension through different build files.
- **Scenario:** The next Xcode save or merge rewrites these entries unpredictably and produces noisy diffs. "Missing package product" or duplicate-product warnings are possible.
- **Fix:** Remove the null entries and their phase references. Re-add package products through Xcode so each target has its own dependency, and normalize the Embed phases.
<!-- sources: config/swift-xcode#15 -->

#### 6.19 Build settings and entitlements disagree; both read-only and read-write file access are signed — Low

- **Where:** `SpamWise.xcodeproj/project.pbxproj:611` (also `:661`, `:702`, `:734`, `:851`, `:905`; `SpamWise/SpamWise.entitlements:15`; `MailExtension/MailExtension.entitlements:11`)
- **Problem:** Every app and extension configuration sets `ENABLE_USER_SELECTED_FILES = readonly`, while `SpamWise.entitlements` grants `files.user-selected.read-write`. codesign merges both, so the signed app carries both keys. The Mail extension, which never presents a panel, gets `read-only` it does not need. It also declares `network.client` in its file without a matching build setting. Read-write is in effect, so exports work today.
- **Scenario:** A reviewer or a least-privilege check questions the contradictory entitlements. A later edit to one source silently has no effect because the other still grants access.
- **Fix:** Use one source of truth: set `ENABLE_USER_SELECTED_FILES = readwrite` on the app targets and drop the duplicate key from the file, or the reverse. Remove file access from both MailExtension configurations and declare its network access consistently.
<!-- sources: config/ci-automation#15, config/swift-xcode#14, distribution/product#14, correctness/app-logic#20, temp/app#16 -->

#### 6.20 iOS template settings leak into the macOS bundle; metadata inconsistent — Low

- **Where:** `SpamWise.xcodeproj/project.pbxproj:617` (also `:625-626`, `:667-676`, `:857-866`, `:911-920`, `:482`, `:501`, `:517-519`, `:559`, `:572`, `:586-588`, `:614`, `:633`, `:635`, `:706`, `:738`; `SpamWise/MyApp.swift`; `docs/app-store.md:181`)
- **Problems:**
  - Unconditional `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` and `_iPhone` keys reach the shipped Info.plist, along with `UIStatusBarStyle = ""` and `UIApplicationSupportsIndirectInputEvents`.
  - The project sets iOS, tvOS, watchOS, visionOS and DriverKit deployment targets and `SDKROOT = auto`, although `SUPPORTED_PLATFORMS = macosx`.
  - The app has no copyright string; the extension's is empty. The docs say "Use copyright Tim Morgan".
  - The binary's category is `utilities`, while the planned store category is Productivity.
  - The main source file keeps the template name `MyApp.swift`.
- **Scenario:** Store validation output is cluttered with irrelevant UIKit keys. About and Get Info show no copyright, and the binary's category disagrees with the store listing.
- **Fix:** Delete the `INFOPLIST_KEY_UI*` settings and the non-macOS deployment targets. Set `SDKROOT = macosx` and `LD_RUNPATH_SEARCH_PATHS = @executable_path/../Frameworks`. Set `NSHumanReadableCopyright` for the app and extension, choose one category for both the plist and the metadata, and rename `MyApp.swift` to `SpamWiseApp.swift`.
<!-- sources: config/swift-xcode#13, distribution/packaging#14, temp/app#13 -->

#### 6.21 `@main` in `main.swift` breaks SwiftPM's native build system — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseEval/main.swift:6` (also `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:7`)
- **Problem:** A file named `main.swift` is compiled as top-level code, which conflicts with `@main` unless `-parse-as-library` is passed. The default swiftbuild system tolerates this, but the native build system rejects it. Periphery's SwiftPM indexing needed a workaround because of it.
- **Scenario:** `swift build --build-tests --build-system native`, and tools that use that path, fail with "'main' attribute cannot be used in a module that contains top-level code", which blocks analysis of the whole package.
- **Fix:** Rename the files to `SpamWiseEval.swift` and `SpamWiseDaemon.swift`.
<!-- sources: tooling#8 -->

#### 6.22 Production-symbol gate passes silently when ripgrep is missing — Low

- **Where:** `Tools/DocumentWorker/check.sh:88` (same pattern at `Scripts/check.sh:10`, `Scripts/archive.sh:21`, `Scripts/app-store-check.sh:46`)
- **Problem:** `if nm … | rg 'WorkerProbes|exercise'` treats `rg: command not found` (status 127) as "no match", and `set -e` does not fire inside an `if` condition. The script then exits 0. The Scripts/ warning gates share the shape but are backed by `SWIFT_TREAT_WARNINGS_AS_ERRORS` and a loud `xcbeautify` dependency. The worker harness runs only on the owner's provisioned machine.
- **Scenario:** On a Mac without Homebrew ripgrep, a production worker accidentally built with the probe sources still passes, and the harness reports success.
- **Fix:** Use `grep -Eq` (ships with macOS) everywhere, or capture the output and fail explicitly on a search-tool status other than 0 or 1.
<!-- sources: conventions/tools#1, comments/tools#3 -->

#### 6.23 Public site pages link into the private repository; site deps not hash-checked — Low

- **Where:** `Tools/Site/build.py:16` (also `docs/lifecycle.html:43`, `:45`; `docs/mail-compatibility.html:34`; `.github/workflows/site.yml:34`, `:36`)
- **Problem:** `SOURCE_URL` points at `blob/main/docs/` in the private RISCfuture/SpamWise. `docs/` mixes the five site pages with about 30 internal engineering documents, whereas the sisters' `docs/` contains only the site. The workflow installs pinned requirements without `--require-hashes` and duplicates the Python version instead of reading the project's.
- **Scenario:** After Pages publication, the "details" links on the lifecycle and compatibility pages return 404 for every visitor while the repo stays private.
- **Fix:** Link only to published pages, or inline the content, until the repo is public. Consider moving internal docs out of `docs/`, installing with `--require-hashes`, and pinning `python-version` to 3.14.8.
<!-- sources: config/ci-automation#23 -->

#### 6.24 Release Python helpers run in the corpus ML virtualenv — Low

- **Where:** `docs/app-store.md:83` (also `Scripts/notarize-match.py`, `Scripts/export-store-match.py`, `Scripts/test_export_store_match.py`)
- **Problem:** python-conventions requires a per-project `.python-version`. `Scripts/` has none, and the signing helpers are documented to run with `PYENV_VERSION=spamwise-corpus`, the scikit-learn and torch environment. The helpers' unittest runs in no CI job.
- **Scenario:** Rebuilding or deleting the corpus environment breaks the release procedure, and signing code runs with an unrelated, heavy dependency set on its import path.
- **Fix:** Retire the helpers in favor of fastlane (6.17). Until then, give `Scripts/` its own virtualenv (for example `spamwise-release`) and run its tests in CI.
<!-- sources: config/ci-automation#21 -->

#### 6.25 No crash reporting, structured logging or preview guard in the bootstrap — Info

- **Where:** `SpamWise/MyApp.swift:27` (also `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:55`)
- **Problem:** `App.init` calls `model.startMonitoring()` unconditionally, with no Xcode-preview guard like SubTrack's `isRunningInXcodePreview`. The only `Logger` in the app, extension and core is in AppleMailAdapter. The sisters bootstrap Sentry after their guards and upload dSYMs. Omitting Sentry may be deliberate given the no-message-content logging rule, but the decision is not recorded.
- **Scenario:** A crash in `MessageActionHandler` or the monitor loop on a user's Mac leaves no trace. A preview host launching the app starts monitoring against the shared store.
- **Fix:** Record a diagnostics policy. Add privacy-redacted `os.Logger` categories for the pipeline, scanner and extension, and a preview guard before `startMonitoring()`. If Sentry is adopted, follow the sisters' guarded bootstrap with content scrubbing.
<!-- sources: config/swift-xcode#23 -->
## 7. Distribution readiness

SpamWise is not ready to ship through either channel. The signing work is real and largely solid. The app and extension are sandboxed, the hardened runtime is inherited at project level, and the Developer ID export has been notarized, stapled and Gatekeeper-assessed several times. The store package also excludes the updater and the `/usr/bin/dig` path. Provider consent, the privacy-policy drafts and the default safety posture (dry run on, no delete or Trash path, fail open) are thorough. What is missing is everything around the binary: an app icon, a reproducible package graph, version stamping, a stapled distributable container, an update path, license notices, and a CI or release pipeline.

The four High findings are product defects that would affect nearly every real user, independent of the open runtime gates. The production classifier is wired to the agent's lifetime $150 evaluation ledger, which never resets. Filtering therefore stops for good after about 1,500 Haiku calls, or about 150 calls with any other model. The automatic sweep walks the entire existing Inbox, 20 messages a minute, with no start date, and the Mail-rule trigger advances that same cursor instead of handling the new message. No automatic filtering runs at all, not even in dry run, until the user builds a `[SpamWise Probe]` message and passes a developer acceptance test. Meanwhile the menu bar says "SpamWise is running". The fourth High finding is the missing icon, which blocks App Store validation outright.

The most repeated root cause, reported by five reviewers, is that the store/direct edition split exists only as a `SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE` override in one script. An ordinary Xcode Organizer archive builds a store submission that offers the executable Rspamd transport and the PCC selector. Verifiers note that the sandbox makes executable transport fail safely and that PCC still needs an ungranted entitlement, so this is a structural footgun rather than an exploit. Even so, it departs from the sister repos, which give each edition its own target and shared scheme.

Compared with SubTrack and Zephyr, the release toolchain has been reinvented and is undeclared. The sisters use fastlane match, gym and notarize lanes, a tag-driven `release.yml`, tag-stamped versions, `CHANGELOG.md` with `release-notes.sh`, DMG or pkg packaging, a remote, versioned `GitHubUpdateChecker`, CI, lint and periphery workflows, and LICENSE plus CREDITS. SpamWise instead has about 470 lines of Python that load fastlane's private match internals, read another project's `MATCH_PASSWORD`, and depend on one machine's state. That includes a sibling library commit (`eab9c1d`) that exists on no remote. Its only workflow is `site.yml`.

The Mac App Store path also carries a strategic risk the docs already acknowledge. Every real action depends on a discretionary Apple Events temporary exception for `com.apple.mail`, and the MailKit extension is dry-run only. The App Store Connect app record does not exist (altool error 19), and the privacy and support URLs are unpublished. A realistic plan treats Developer ID as the primary channel and the store edition as contingent on an early App Review answer.

### Readiness checklist

| Requirement | Developer ID | Mac App Store | Evidence | Blocker? |
|---|---|---|---|---|
| App icon | Missing; generic icon in Dock, Finder, TCC prompt, Mail Extensions | Missing; validation fails | No AppIcon or `.icon`; no `Assets.car` or `CFBundleIconName` in export (§7.3) | **Yes (MAS); serious for Developer ID** |
| Product works for a new user | Filtering stops after the $150 lifetime ledger; no sweeps until probe passes; full-Inbox traversal | Same | §7.1, §7.2, §7.4 | **Yes (both)** |
| Sandbox and hardened runtime | Pass | Pass | Signed entitlements on final export; project `ENABLE_HARDENED_RUNTIME = YES` | No |
| Entitlements minimal and consistent | App signed with both read-only and read-write; extension has unused file access | Same; reviewers ask for justification | `codesign -d --entitlements` on export (§7.21) | No (fix advised) |
| Apple Events to Mail | Fine (TCC consent) | Discretionary temporary exception; core feature | `SpamWise.entitlements:19` (§7.13) | **Risk; possible blocker (MAS)** |
| Usage strings accurate | Automation string omits automatic Junk moves and flags | Same (5.1.1) | `project.pbxproj:615` (§7.9) | No (fix advised) |
| Edition gating (`APP_STORE`) | n/a | CLI-only; Organizer archive includes rspamc, dig and PCC | `app-store-check.sh:44` (§7.5) | **Yes (MAS, process)** |
| Distribution signing | Export, notarize and staple verified (saved artifacts) | Match-signed pkg passes signature checks; no app record (error 19) | `.build/cb38d7c0…/store/validation-final-retry.json` | **Yes (MAS: app record)** |
| Distributable container | Script leaves an unstapled ZIP; no DMG or pkg | pkg via helper script | `archive.sh:39-41` (§7.7, §7.18) | Yes (Developer ID) |
| Update mechanism | Shipped target has none; direct target unconfigured and unpackaged; repo private | Store updates | `UpdateSettingsView.swift:32`; `project.pbxproj:876-877` (§7.6) | **Yes (Developer ID)** |
| Versioning and release notes | 1.0 (1) hard-coded; no CHANGELOG | Second upload would reuse build 1 | `project.pbxproj:597/629` (§7.10) | Yes (any second release) |
| Reproducible build and CI | Sibling package path on an unpushed branch; no CI | Same | `project.pbxproj:1000` (§7.11, §7.10) | Yes (process) |
| Release tooling | Custom Python around private fastlane internals | Same | `export-store-match.py:20` (§7.8) | No (maintainability) |
| Privacy policy and support URLs | Drafts, unpublished | Required for submission | `docs/privacy.md`, `docs/repository-approval.md` | **Yes (MAS)** |
| Privacy manifest and App Privacy label | Optional on macOS | Questionnaire pending; manifest declares no collected data | `PrivacyInfo.xcprivacy` (§7.26) | Yes (MAS questionnaire) |
| Third-party AI consent (5.1.2) | Implemented per provider (per docs) | Same | `docs/app-store-feasibility.md:35-39` | No (not runtime-verified here) |
| Reviewer access and demo flow | n/a | Plan drafted; depends on the probe step; no review keys | `docs/app-review-notes.md` | **Yes (MAS)** |
| Licensing and attribution | No LICENSE; no Apache-2.0 notice for bundled code | Same | No LICENSE, NOTICE or CREDITS (§7.14, §7.24) | Yes (legal) |
| State migration and recovery | `schemaVersion` never read; one bad value locks all state | Same | `State.swift:163` (§7.16) | Yes (before any upgrade) |
| Supportability | No crash-reporting decision; dSYMs not managed per release; thin diagnostics | `uploadSymbols` false | §7.20, §7.22 | No |
| Metadata hygiene | No copyright string | Category mismatch (Utilities vs Productivity) | `project.pbxproj:614` (§7.19) | No |
| Edition naming | Direct target would show "SpamWiseDirect" | n/a | `project.pbxproj:872` (§7.17) | No (before direct release) |

### Open runtime gates

| Gate | Status | Blocks shipping? | Evidence |
|---|---|---|---|
| Production spend control (lifetime $150 ledger) | Open defect | **Yes** | `EvaluationBudget.swift:27`, `ConfiguredClassifier.swift:5-6,56-61` |
| Sweep scope, start date and new-mail latency; Mail-rule trigger | Open defect | **Yes** | `AppModelScanning.swift:48-49`, `AppModelNavigation.swift:8` |
| Deduplication for Inboxes over 5,000 messages (reviewer assessment) | Open defect | **Yes** | `State.swift:161,235`; `AppModelScanning.swift:113-121` |
| Fresh-user onboarding under five minutes; probe required before any automatic filtering | Not run; probe UX blocks it | **Yes** | runtime checklist step 1; `TODO.md:83`; `AppModel.swift:57-60` |
| Threshold calibration (99/95/90) on representative held-out mail | Open; no corpus | Yes for automatic Junk; not for dry run or Review | `TODO.md:86` |
| Provider acceptance | Claude: one synthetic call; OpenAI: HTTP 429; Gemini: untested; on-device: Review for all five fixtures | Yes for non-Claude providers | `TODO.md:75` |
| App Store Connect record and store validation | Fails with error 19 | Yes (MAS) | `docs/app-store.md:109` |
| Apple Events temporary-exception approval | Apple's decision; not filed | Yes (MAS) | `docs/app-review-notes.md` |
| Hosted privacy and support URLs; App Privacy answers; manifest data types | Not done | Yes (MAS) | `docs/privacy-audit.md`; `PrivacyInfo.xcprivacy` |
| MailKit incoming callbacks, account identity, deadline | One callback observed; no account bridge; dry run only | No (Apple Events is the action route) | `docs/mail-compatibility.md`; `MessageActionHandler.swift:21` |
| Move settling on slow or offline servers (window longer than 30 s) | Open | Partly | `TODO.md:84` |
| Account types beyond iCloud and Google | Untested | Yes for broad compatibility claims | `docs/mail-compatibility.md` |
| Large or changing mailboxes; 8-second AppleScript timeouts | Not measured | Yes | `TODO.md:85`; `MailScripts.swift` |
| Sleep/wake, restart, offline recovery, screen lock | Open | Yes for unattended use | `TODO.md:156,216` |
| Concurrent signed App Group access (app and extension) | Unverified | Medium risk | runtime checklist step 9 |
| Extension reading the shared Keychain item | Unverified | No while MailKit is dry run only | runtime checklist step 2 |
| Notification delivery and deep links | Unverified | No (opt-in) | `TODO.md:300` |
| Second-device training folders | Unverified | No (opt-in) | `TODO.md:242` |
| PDF extraction and malware coverage | Not shipped | No (correctly excluded) | `TODO.md:329` |
| Direct update channel | No host configured | Yes for direct-release maintenance | `docs/updating.md`; `UpdateSettingsView` |
| Private Cloud Compute entitlement | Not granted | No, but the selector should be hidden | `ModelSettingsView.swift:36-40` |
| Spamhaus HTTPS live access | Unverified | No (opt-in) | `docs/spamhaus.md` |

### Findings

| # | Severity | Location | Finding |
|---|---|---|---|
| 7.5 | Medium | `Scripts/app-store-check.sh:44` | App Store edition exists only as a command-line override |
| 7.6 | Medium | `Scripts/archive.sh:17` | Developer ID artifact has no update path; direct edition never packaged or configured |
| 7.7 | Medium | `Scripts/archive.sh:39` | Script zips before stapling and leaves no stapled distributable |
| 7.8 | Medium | `Scripts/export-store-match.py:20` | Release tooling re-implements fastlane match and borrows another repo's password |
| 7.9 | Medium | `SpamWise.xcodeproj/project.pbxproj:615` | Automation usage string understates what SpamWise does to Mail |
| 7.10 | Medium | `SpamWise.xcodeproj/project.pbxproj:629` | Version 1.0 (1) hard-coded; no CI, release workflow or changelog |
| 7.12 | Medium | `SpamWise/AppModel.swift:159` | Whole-state JSON reloaded every 3 seconds; state grows without bound |
| 7.13 | Medium | `SpamWise/SpamWise.entitlements:19` | Store build depends on a discretionary Apple Events temporary exception |
| 7.14 | Medium | `SpamWiseCore/Package.swift:23` | No third-party notices for bundled Apache-2.0 and MPL-2.0 code |
| 7.15 | Medium | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:139` | Missing API key reported as a storage or entitlement failure |
| 7.16 | Medium | `SpamWiseCore/Sources/SpamWiseCore/State.swift:163` | No migration framework; one undecodable value locks all state |
| 7.17 | Low | `SpamWise.xcodeproj/project.pbxproj:872` | Direct edition would show as "SpamWiseDirect" and shares the store identity |
| 7.18 | Low | `Scripts/archive.sh:39` | Bare ZIP instead of a notarized DMG or pkg |
| 7.19 | Low | `SpamWise.xcodeproj/project.pbxproj:614` | No copyright string; category disagrees with store metadata |
| 7.20 | Low | `Scripts/archive.sh:32` | No crash-reporting decision; dSYMs not retained per release |
| 7.21 | Low | `SpamWise/SpamWise.entitlements:15` | Contradictory file entitlements; extension gets unused file access |
| 7.22 | Low | `SpamWiseCore/Sources/SpamWiseCore/ActivityQuery.swift:94` | Diagnostics export omits version, OS, provider and scan health |
| 7.23 | Low | `docs/mail-compatibility.md:12` | Public compatibility page shows internal ledger references |
| 7.24 | Low | `docs/repository-approval.md:11` | No project LICENSE (acknowledged as pending) |
| 7.25 | Info | `SpamWiseCore/Sources/SpamWiseCore/AdvancedSettings.swift:16` | Provider model IDs and prices hard-coded with no update channel |
| 7.26 | Info | `SpamWise/PrivacyInfo.xcprivacy:5` | Privacy manifest declares no collected data types |

#### 7.5 App Store edition exists only as a command-line override — Medium

- **Where:** `Scripts/app-store-check.sh:44`, `SpamWiseCore/Sources/SpamWiseCore/DistributionCapabilities.swift:5`, `docs/app-store.md:57`, `Scripts/export-store-match.py:220-246`, `SpamWise.xcodeproj/project.pbxproj:510`
- **Problem:** Hiding PCC and the rspamc executable transport, and showing the store update text, depend on `#if APP_STORE`. No target, configuration, scheme, xcconfig or `Package.swift` defines it. The only definition is a `SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE` override in one script, which also replaces `$(inherited)` for every target, package targets included. `export-store-match.py` signs whatever archive it is given. The `TODO.md:363` item claiming store-specific restrictions is checked anyway. The sisters use dedicated `(MAS)` and `(download)` targets and shared schemes. Verifiers note that the sandbox makes the executable transport fail safely and that PCC still needs an ungranted entitlement, so the consequence is review risk, not code execution.
- **Scenario:** The owner uses Product ▸ Archive ▸ Distribute App ▸ App Store Connect, or Xcode Cloud or a future fastlane lane names the SpamWise scheme. The uploaded build offers "Command-line client" under Rspamd and "Private Cloud Compute" under Provider, contrary to `docs/distribution-differences.md` and the reviewer notes.
- **Fix:** Create explicit editions, as the sisters do. Add a `SpamWise (MAS)` target or configuration with `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) APP_STORE`, and a download edition (today's SpamWiseDirect), each with a shared scheme. Carry the condition into SpamWiseCore through a package trait or a separate product, or move `DistributionCapabilities` into the app target. Then drop the CLI override, and make the export step reject an archive that still contains executable-transport symbols or the dig path.
<!-- sources: todo/spamsieve-b#4, config/ci-automation#3, distribution/packaging#2, distribution/product#5, security/core-pipeline-store#7 -->

#### 7.6 Developer ID artifact has no update path; direct edition never packaged or configured — Medium

- **Where:** `Scripts/archive.sh:17`, `SpamWise/UpdateSettingsView.swift:31-32`, `SpamWise.xcodeproj/project.pbxproj:876-877`, `SpamWise.xcodeproj/project.pbxproj:930-931`, `SpamWise/Info.plist:8-10`, `SpamWise/DirectUpdateConfiguration.swift:11`
- **Problem:** The only notarization pipeline archives `-scheme SpamWise`, which defines neither `APP_STORE` nor `SPAMWISE_DIRECT_UPDATES`. Every notarized ZIP so far is a third edition: direct-only features, but "Update checks are unavailable in this build." No script builds SpamWiseDirect. Its `SPAMWISE_UPDATE_OWNER` and `SPAMWISE_UPDATE_REPOSITORY` are empty raw pbxproj settings, so `DirectUpdateConfiguration(bundle:)` returns nil. The repository is private, so the GitHub releases API would return 404 anyway, and discovery is manual click-to-check only. The empty values are a documented placeholder and no direct release has shipped, so this is a readiness gap rather than a user-facing defect today.
- **Scenario:** A user installs today's Developer ID build. When 1.0.1 fixes a mis-filing bug, nothing in the app tells them, and they keep running a build with known mail-handling defects.
- **Fix:** Have `archive.sh` sign and notarize the download edition, following Zephyr's EDITIONS map. Move `SPAMWISE_DISTRIBUTION`, the update owner and repository, and the version into a tracked `Config/SpamWise.xcconfig`, and set them to `RISCfuture/SpamWise` once releases are public. Fail release automation if they are empty. Use GitHubUpdateChecker's scheduled checks as SubTrack does, or at least check on launch with a cadence preference.
<!-- sources: distribution/packaging#3, config/swift-xcode#6, config/ci-automation#5 -->

#### 7.7 Script zips before stapling and leaves no stapled distributable — Medium

- **Where:** `Scripts/archive.sh:39`, `Scripts/archive.sh:40-42`
- **Problem:** `archive.sh` creates `SpamWise.zip`, submits it, staples only the exported `.app`, and never rebuilds the ZIP. The `SpamWise-notarized.zip` files cited in `CLAUDE.md` were therefore made by hand, so the release artifact cannot be reproduced from the repository. The script does not parse the notarytool status; a rejected submission is caught only indirectly, because `stapler` fails under `set -e`. Unlike `app-store-check.sh`, it also does not validate the worker token, so a `../x` token writes outside `.build`.
- **Scenario:** The obvious artifact, `.build/<token>/SpamWise.zip`, gets published. A recipient who opens it offline is blocked by Gatekeeper, because the ticket is not stapled inside the archive.
- **Fix:** After `stapler staple` and `stapler validate`, rebuild the distributable from the stapled app and remove or rename the pre-staple ZIP. Better, build a container as described in §7.18. Parse the notarytool JSON and fail unless the status is Accepted. Validate the worker token with the same `case` pattern as `app-store-check.sh`.
<!-- sources: distribution/packaging#10, correctness/eval-scripts#11 -->

#### 7.8 Release tooling re-implements fastlane match and borrows another repo's password — Medium

- **Where:** `Scripts/export-store-match.py:20`, `Scripts/notarize-match.py:45`, `docs/packaging.md:46`
- **Problem:** About 470 lines of Python stand in for fastlane match, gym, notarize and deliver. The code loads fastlane's private `match/encryption` internals through `ruby -e`, hand-builds a keychain, re-signs with `codesign`, runs `productbuild`, and takes profile paths as arguments. There is no Gemfile, `.ruby-version`, Appfile, Matchfile or `fastlane/.env.example`, so the fastlane dependency is undeclared, and `MATCH_PASSWORD` is read from another project's `fastlane/.env` (SubTrack's). The shared password is probably common to the single Match repository, so the borrowing matters less than the reinvented, undeclared tooling. It runs against the user's "don't reinvent the wheel" rule.
- **Scenario:** A fastlane update that moves `match/encryption`, a Ruby or gemset change, or SubTrack rotating its `.env` breaks SpamWise packaging. A new App ID capability needs edits to `validate_profile`. None of this can run in CI, where secrets arrive for fastlane lanes.
- **Fix:** Copy Zephyr's `fastlane/{Appfile,Matchfile,Fastfile,.env.example,.gitignore}`, `Gemfile`/`Gemfile.lock`, `.ruby-version` and `.ruby-gemset` (gemset `spamwise`). List `codes.tim.SpamWise` and `codes.tim.SpamWise.MailExtension` in the Matchfile and model mas/download editions in the Fastfile. Then delete `notarize-match.py`, `export-store-match.py` with its test, and `AppStoreExportOptions.plist`.
<!-- sources: config/ci-automation#4 -->

#### 7.9 Automation usage string understates what SpamWise does to Mail — Medium

- **Where:** `SpamWise.xcodeproj/project.pbxproj:615` (also `:665`, `:855`, `:909`; es/fr `InfoPlist.strings`)
- **Problem:** `NSAppleEventsUsageDescription` reads "SpamWise reads mail history and applies your corrections in Apple Mail." The TCC prompt is the user's main consent point. The string leaves out automatic Junk moves, Review flags, read-status changes and mailbox sweeps, all of which the adapter performs once dry run is off. Guideline 5.1.1 expects complete purpose strings.
- **Scenario:** A user grants Automation believing SpamWise only applies their own corrections, then finds unread mail moved to Junk automatically. App Review may also flag the string as incomplete.
- **Fix:** Rewrite it, for example: "SpamWise reads messages in Apple Mail to classify them and, when you allow it, moves unwanted mail to Junk, marks messages for review, and restores mail you correct." Update the Spanish and French strings to match.
<!-- sources: distribution/packaging#7 -->

#### 7.10 Version 1.0 (1) hard-coded; no CI, release workflow or changelog — Medium

- **Where:** `SpamWise.xcodeproj/project.pbxproj:629` (also `:597`, `:647`, `:679`, `:698`, `:712`, `:837`, `:869`, `:891`, `:923`), `Scripts/AppStoreExportOptions.plist:13-16`, `.github/workflows/site.yml`
- **Problem:** Every configuration hard-codes `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 1`. All notarized submissions so far (for example 4dca30b7, fb685339 and 3c687cd4) are 1.0 (1). There is no `CHANGELOG.md` or `release-notes.sh`. `manageAppVersionAndBuildNumber` and `uploadSymbols` are false, and the only workflow is `site.yml`, so every build and test claim rests on one local machine. The sisters stamp versions from the tag and build numbers from `commit_count` (Zephyr `Fastfile:367`), and they have ci, lint, periphery and tag-driven release workflows.
- **Scenario:** A second App Store upload is rejected for reusing build 1. The direct updater compares `CFBundleShortVersionString` and never sees a newer release unless someone edits ten configuration entries by hand. GitHub release notes and "What's New" have no source.
- **Fix:** Move the version to a single xcconfig or project-level setting and stamp it from the tag and commit count in the archive lane (Zephyr `Fastfile:986-997`). Copy SubTrack's `release-notes.sh` (revision 5) and a `CHANGELOG.md` with the Zephyr header. Add `ci.yml` running package tests and an unsigned app build, plus a tag-driven `release.yml`.
<!-- sources: config/ci-automation#8, distribution/packaging#8 -->

#### 7.12 Whole-state JSON reloaded every 3 seconds; state grows without bound — Medium

- **Where:** `SpamWise/AppModel.swift:159`, `SpamWise/AppModel.swift:6`, `SpamWiseCore/Sources/SpamWiseCore/Store.swift:101-108`, `SpamWise/AppModelScanning.swift:126,136`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:144,191`, `SpamWise/AppleMailAdapter.swift:312`
- **Problem:** All state is one JSON blob: up to 5,000 decision records, retries holding up to 16 KB each, learning data, and the never-pruned `claimedActions` and `importedIDs`. The idle app decodes it every 3 seconds and several times per processed message, re-encodes it on every update, and builds a new `ModelContainer` on each access. Reassigning the observed model re-renders the Activity table. The cross-process `flock(... LOCK_NB)` makes a competing process fail immediately. Verifiers confirmed the design facts; the performance magnitudes are estimates.
- **Scenario:** After months of use the blob reaches several megabytes. The menu-bar app keeps using CPU and energy while idle, scans take seconds per message, and the MailKit extension's 8-second callback loses `lockUnavailable` races and drops dry-run records.
- **Fix:** Split state into separately keyed records (settings, rules, paginated activity, claims, histories) or real SwiftData models, and load Activity on demand. Replace the 3-second poll with a cheap change token. Age-prune claims and imported IDs. Retry the lock with a short bounded wait.
<!-- sources: distribution/product#11 -->

#### 7.13 Store build depends on a discretionary Apple Events temporary exception — Medium

- **Where:** `SpamWise/SpamWise.entitlements:19`, `MailExtension/MessageActionHandler.swift:39-45`, `docs/app-store-feasibility.md:25-28`
- **Problem:** History import, lookup, Junk and Inbox moves, flags and read status all go through Apple Events to Mail under `com.apple.security.temporary-exception.apple-events`, which every SpamWise configuration uses. Guideline 2.4.5(i) limits modifying other apps' data, temporary exceptions are granted case by case, and Mail offers no scripting-targets group that would replace this one. The MailKit extension always passes `forceDryRun: true` and calls `finish(nil)`, so a store build without the exception has no action path. The docs and `TODO.md:89` already track this as an open risk, yet the plan still says "pursue the Mac App Store first", and no App Store Connect record exists (error 19).
- **Scenario:** App Review refuses or limits the exception. The store build then cannot move any mail, and the extension alone does nothing visible, which also invites a 4.2 minimum-functionality rejection.
- **Fix:** Make Developer ID the primary channel, as SpamSieve does. Get an early exception decision from App Review using the drafted justification before investing further in store polish. Plan for an IMAP-only store build or no store edition if the exception is refused.
<!-- sources: distribution/packaging#5, security/app-logic#2 -->

#### 7.14 No third-party notices for bundled Apache-2.0 and MPL-2.0 code — Medium

- **Where:** `SpamWiseCore/Package.swift:23` (also `:22`), `MessageModel/Resources/public_suffix_list.dat`
- **Problem:** The app and extension statically link ClaudeForFoundationModels (Apache-2.0, pinned `0262e1a`). The unshipped direct edition also links swift-log (Apache-2.0, with `NOTICE.txt`). Apache-2.0 §4(a) and (d) require binary redistributions to include the license text and any NOTICE. The repository has no CREDITS, NOTICE or acknowledgements, and neither do the app, its About panel or the Help pages. The bundled Public Suffix List keeps its MPL-2.0 header in both bundles, which verifiers judged sufficient for MPL notice retention. GitHubReleaseDiscovery uses only swift-log, not markdown-ui or cmark. Nothing has been publicly distributed yet. Zephyr's `CREDITS.md` has an "Apache-2.0 notices" section for exactly this.
- **Scenario:** A notarized ZIP or App Store build distributed as-is redistributes ClaudeForFoundationModels without its required license text, a compliance defect from the first public release.
- **Fix:** Add a `CREDITS.md` modeled on Zephyr's, with Apache-2.0 notices for ClaudeForFoundationModels at `0262e1a` and for swift-log including its NOTICE, the MPL-2.0 Public Suffix List with source URL and version, and an Anthropic trademark/non-affiliation disclaimer. Surface the same text in the app, through About panel credits or a Help page, as SubTrack does.
<!-- sources: config/ci-automation#6, config/swift-xcode#11, distribution/packaging#9 -->

#### 7.15 Missing API key reported as a storage or entitlement failure — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:139` (through `:150`), `SpamWiseCore/Sources/SpamWiseCore/ConfiguredClassifier.swift:46`, `SpamWise/AppModelErrors.swift:21-26`
- **Problem:** `credential(settings.backend)` throws `KeychainError.missing` without mapping it. `Pipeline.process` turns every error that is not a classification, content-rule, budget or cancellation error into "persistence or integration unavailable". `AppModel.describe` adds "Check the signed app's shared Keychain entitlement" for every `KeychainError`, including `.missing`. Onboarding's "Continue offline" path saves no key while Claude stays the default backend. `support.md` promises that a missing key is reported, but the app never names it.
- **Scenario:** A user switches to Gemini, grants consent, and forgets "Save provider key". Activity fills with "persistence or integration unavailable", and the user troubleshoots signing and storage instead of entering the key.
- **Fix:** Map `KeychainError.missing` to `ClassificationError.missingCredential` in `ConfiguredClassifier`, and keep the entitlement wording for real `KeychainError.status` failures. Show a persistent "No API key for <provider>" banner while the selected provider has no stored key.
<!-- sources: distribution/product#8 -->

#### 7.16 No migration framework; one undecodable value locks all state — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:163`, `SpamWiseCore/Sources/SpamWiseCore/Store.swift:64`, `SpamWise/AppModel.swift:140-142`
- **Problem:** `schemaVersion = 1` is declared and never read. `Store.read` and `Store.update` decode the whole payload with synthesized `Codable`, so a new enum case, renamed key or non-optional field breaks decoding. When decoding fails, the app shows a generic storage-unavailable status and keeps the default `AppState()`, so onboarding reappears and every write fails. There is no quarantine, export or recovery screen. Mixed-version windows are realistic: the ledger records Mail running a stale extension generation, and a direct-to-store downgrade would hit the same failure.
- **Scenario:** Version 1.1 writes an `ActionOutcome.deferred` record. The still-running 1.0 extension, or a reinstalled 1.0 app, cannot decode the state. The user sees onboarding again, "Finish setup" fails to save, and filtering stops until the container is deleted by hand.
- **Fix:** Check `schemaVersion` on load and run explicit migrations. Decode collections leniently, skipping unknown elements and mapping unknown enum values to a fallback. Before any reset, quarantine the undecodable payload, and offer a recovery screen with restore from backup or reset.
<!-- sources: distribution/product#10 -->

#### 7.17 Direct edition would show as "SpamWiseDirect" and shares the store identity — Low

- **Where:** `SpamWise.xcodeproj/project.pbxproj:872` (also `:871`, `:925-926`)
- **Problem:** SpamWiseDirect sets `PRODUCT_NAME = SpamWiseDirect` with a generated Info.plist and no `CFBundleName` or `CFBundleDisplayName` override, so the menu bar, Finder, Login Items and TCC prompts would read "SpamWiseDirect". Both editions share `codes.tim.SpamWise`, the App Group, the Keychain group and the extension ID. That sharing is a deliberate, documented contract decision ("install one at a time"), unlike SubTrack's per-edition IDs. Because no script packages this target, only the naming is a defect.
- **Scenario:** A user moves from the store build to a GitHub build. The app shows the odd name "SpamWiseDirect", and both copies register the same extension and share one store, so whichever copy LaunchServices picks is the one that runs.
- **Fix:** Set `PRODUCT_NAME = SpamWise` and separate editions by scheme and build directory, or at least set `CFBundleName` and `CFBundleDisplayName` to SpamWise. Record a deliberate decision between per-edition bundle IDs and the shared identity, with a migration plan for the latter.
<!-- sources: distribution/packaging#12 -->

#### 7.18 Bare ZIP instead of a notarized DMG or pkg — Low

- **Where:** `Scripts/archive.sh:39`
- **Problem:** The Developer ID output is a ZIP of the app. SubTrack ships a notarized DMG (`make-dmg.sh`), and Zephyr ships a signed, notarized pkg because a quarantined, translocated app cannot host its system extension. A notarized ZIP is an accepted format, and the effect of translocation on Mail extension registration is unverified inference, so this is packaging polish.
- **Scenario:** A user unzips SpamWise in `~/Downloads` and launches it there. The Mail extension may register from a translocated path or fail to appear or update in Mail Settings, and the Mail-rule script points at a location that moves.
- **Fix:** Adopt Zephyr's `make-pkg.sh` with productsign and notarization, which installs to `/Applications` without translocation. At minimum, use SubTrack's `make-dmg.sh` with an `/Applications` symlink, notarized and stapled, and publish it through a `release.yml` like Zephyr's `publish` job.
<!-- sources: config/ci-automation#12 -->

#### 7.19 No copyright string; category disagrees with store metadata — Low

- **Where:** `SpamWise.xcodeproj/project.pbxproj:614`, `SpamWise.xcodeproj/project.pbxproj:706,738`, `docs/app-store.md:181`
- **Problem:** The app sets no `NSHumanReadableCopyright`, and the extension sets an explicit empty string. `LSApplicationCategoryType` is `public.app-category.utilities`, while the product-page draft lists Productivity. The sisters set "Copyright ©2026 Tim Morgan" and keep the category in `fastlane/metadata/primary_category.txt`.
- **Scenario:** The About window has no copyright line, and the bundle category and the App Store listing category disagree at submission.
- **Fix:** Set `INFOPLIST_KEY_NSHumanReadableCopyright = "Copyright ©2026 Tim Morgan"` on the app and extension targets. Choose one category and record it in both `LSApplicationCategoryType` and the store metadata.
<!-- sources: config/ci-automation#18 -->

#### 7.20 No crash-reporting decision; dSYMs not retained per release — Low

- **Where:** `Scripts/archive.sh:32`, `Scripts/AppStoreExportOptions.plist` (`uploadSymbols` false)
- **Problem:** Both sister apps use Sentry with redaction and keep each release's dSYMs as artifacts. SpamWise has no crash reporting, which may be a deliberate privacy choice for a mail filter, but the choice is undocumented. The dSYMs survive only inside per-worker `.build/<token>/SpamWise.xcarchive` directories and are not managed per release. App Store exports disable symbol upload.
- **Scenario:** A user reports a crash from a shipped build, and nobody can tell which of the many local archives (about 27 GB of `.build` worker directories) matches it, so the report cannot be reliably symbolicated. App Store Connect crash reports arrive unsymbolicated.
- **Fix:** Decide explicitly: adopt Zephyr's release-only, redacted Sentry setup, or document "no crash reporting" in the README and privacy policy. Either way, zip and retain each release's dSYMs (Zephyr `Fastfile:1113-1126`) and set `uploadSymbols` to true for App Store exports.
<!-- sources: config/ci-automation#20 -->

#### 7.21 Contradictory file entitlements; extension gets unused file access — Low

- **Where:** `SpamWise/SpamWise.entitlements:15`, `SpamWise.xcodeproj/project.pbxproj:611,661,851,905` (app), `:702,734` (MailExtension)
- **Problem:** The entitlements file grants `files.user-selected.read-write`, while `ENABLE_USER_SELECTED_FILES = readonly` adds `read-only`, so the signed app carries both. The extension has no file UI, but the same build setting signs it with `files.user-selected.read-only`. Verified with `codesign` on the final export. This breaks least privilege. Rejection on this basis would be unusual.
- **Scenario:** A reviewer sees contradictory file entitlements on the app and file access on a Mail extension with no open or save panels, and asks for clarification.
- **Fix:** Set `ENABLE_USER_SELECTED_FILES = readwrite` on the app targets, since backups and exports need write access, and remove the key from the entitlements file. Delete the setting from both MailExtension configurations.
<!-- sources: distribution/packaging#6 -->

#### 7.22 Diagnostics export omits version, OS, provider and scan health — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/ActivityQuery.swift:94` (through `:99`)
- **Problem:** `DiagnosticSummary` carries only paused, dry run, route, validated-account count, outcomes and retry count. It omits content-free facts support needs: app build, macOS version, backend and model, consent and local-only state, per-account scan health, the last extension heartbeat, and budget committed versus limit. `support.md` asks users to report these by hand. The export is already offered in Activity (`ActivityStatisticsView.swift:73`) as well as through Shortcuts.
- **Scenario:** A user reports "nothing is filtered". The diagnostics cannot show whether the cause is an unverified route (§7.1), an exhausted ledger (§7.4), missing consent or lost Mail permission, so support needs several round trips.
- **Fix:** Add those fields, plus a histogram of unclassified reasons, to `DiagnosticSummary`.
<!-- sources: distribution/product#17 -->

#### 7.23 Public compatibility page shows internal ledger references — Low

- **Where:** `docs/mail-compatibility.md:12` (also `:18`, `:44-47`), generated `docs/mail-compatibility.html`
- **Problem:** This file is a source for the public site (`Tools/Site/README.md:21`). It cites "probes recorded in `CLAUDE.md`", single-session clock times (08:42 PDT, 23:21:45 PDT) and PlugInKit "other version in use" diagnostics. The privacy, support and lifecycle pages are written for users; this page is not.
- **Scenario:** Once the site is published, prospective users see agent-ledger references and session timestamps, which reads as unfinished and points them to a file that is not user documentation.
- **Fix:** Rewrite the page as a user-facing matrix of supported, tested and untested account types, with known limits such as 30-second settling and same-account duplicate Message-IDs. Keep probe evidence in engineering docs outside the site sources.
<!-- sources: comments/repo-docs#11 -->

#### 7.24 No project LICENSE (acknowledged as pending) — Low

- **Where:** `docs/repository-approval.md:11`, `README.md`
- **Problem:** No source license has been chosen. There is no LICENSE file and the README has no License section, while Zephyr (MIT) and SubTrack (GPL-2.0+) both have them. The repository is private and the choice belongs to the owner, so this is a known pending item.
- **Scenario:** If the repository goes public as planned, the code is all-rights-reserved by default, which may not be the owner's intent, and contributors have no terms.
- **Fix:** Have the owner choose a license, add LICENSE (copy Zephyr's if MIT), and add a README "License" section that points to LICENSE and the new CREDITS.md (§7.14), matching `Zephyr/README.md:800`.
<!-- sources: config/ci-automation#7 -->

#### 7.25 Provider model IDs and prices hard-coded with no update channel — Info

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/AdvancedSettings.swift:16` (through `:22`), `SpamWiseCore/Sources/SpamWiseCore/OpenAIClassifier.swift:17`, `SpamWiseCore/Sources/SpamWiseCore/ModelTokenPricing.swift:59`
- **Problem:** OpenAI and Gemini each accept exactly one model ID (`gpt-5.4-mini`, `gemini-3.8-flash`), and pricing throws `.configuration` for any unknown model. Claude accepts several IDs. No fallback is intended. The real gap is that no update channel exists yet to ship a replacement (see §7.6).
- **Scenario:** OpenAI retires `gpt-5.4-mini`, and every OpenAI user's mail becomes "unclassified" until a new build is distributed by hand.
- **Fix:** Establish the update channel and a model-lifecycle check before release, and show a specific "model retired" error rather than a generic configuration failure.
<!-- sources: distribution/product#18 -->

#### 7.26 Privacy manifest declares no collected data types — Info

- **Where:** `SpamWise/PrivacyInfo.xcprivacy:5`
- **Problem:** The manifest declares only `NSPrivacyTracking` false and a UserDefaults `CA92.1` reason. Message content and email addresses go to Anthropic, OpenAI or Gemini, which retain them for up to 30 days. `docs/app-store.md:246` and `app-store-feasibility.md:43` already say "data not collected" would be wrong. The extension, which also sends content, has no manifest of its own.
- **Scenario:** Xcode's privacy report for the archive shows no collected data, which conflicts with the App Store Connect answers and can draw App Review questions.
- **Fix:** Once the App Store Connect answers are settled, add matching `NSPrivacyCollectedDataTypes` entries (emails or text messages, email address, other user content; purpose App Functionality; not linked; not tracking).
<!-- sources: privacy-dataflow#15 -->
## 8. Front-end design

The app is built from native macOS parts. It has a single `Window` with a `Table`, `.inspector` and `.searchable`; a real `Settings` scene with a toolbar `TabView` and `.formStyle(.grouped)`; a `MenuBarExtra`; `CommandMenu`; and `ContentUnavailableView` for the main empty states. It also uses `LabeledContent`, `ControlGroup`, `confirmationDialog` with destructive roles, `fileImporter`/`fileExporter`, Swift Charts, `SMAppService` login items and the native AppKit help bezel. Color is restrained: only `.secondary` appears, and no status depends on color alone. Symbols are used sparingly, as the swiftui-conventions skill asks. All 12 symbol uses resolve to current macOS 27 names, and none implies deletion (there is no `trash`). Every view has a preview. Expert controls are mostly collapsed inside Advanced. The weaknesses are not in the components. They are in structure, flow, feedback and copy.

The balance between approachable and powerful is wrong in two directions. The two things every user needs are choosing between on-device and cloud classification, and turning on real filtering. Onboarding does not offer the first; it is hard-coded to Anthropic (§8.30). The second sits behind a developer-style disposable-message probe that many users cannot complete (§8.1). Meanwhile, typical-user controls such as account inclusion are buried among paging diagnostics (§8.25). Engineering-ledger copy reaches the default path: calibration caveats, page offsets, MailKit status, "Haiku 5.5", token budgets, and an always-empty Threat assessment section (§8.6, §8.51). The most visible explanation in the app, the decision reason, is an unlocalized English debug string such as "gate: user domain block rule" (§8.2).

Modality and feedback are the main systemic defects. One global `busy` flag is shared with the 60-second background sweep, so foreground controls grey out every minute, clicks are dropped, and one sheet's Done button cannot be clicked (§8.7). One global, gray, never-cleared `status` string carries every error and success. It appears in the Activity footer, under every Settings tab and inside sheets, so sheet failures go unseen and stale messages follow the user between windows (§8.18). Eight independent sheets hang off one view, and requests are dropped or appear late (§8.16). The correction-results sheet can trap the user for minutes with no progress or cancel (§8.28). Most sheets cannot be closed with Escape or Return, and title and button conventions vary (§8.10).

Settings mixes apply-on-change controls with explicit Save buttons, sometimes in the same group, and silently discards drafts (§8.20). Collapsed and nested `DisclosureGroup`s act as the main hierarchy, which centers buttons, links and captions inside grouped forms; screenshots confirm this in English, Spanish and French (§8.5). Fields without prompts render as bare labels (§8.22). The Accounts tab is mostly classifier settings, and a tab named "Preferences" sits inside Settings (§8.4). The Activity window has a text-only toolbar that overflows in Spanish and French at the minimum width (§8.14). It has no menu-bar equivalents or keyboard shortcuts for its actions (§8.37). Its Time column shows no date (§8.13). It is missing the confidence and reason columns the brief requires (§8.12), and its filters list raw account IDs and pipeline codes (§8.15).

Mechanically, the localization is complete: every active key has es and fr values, placeholders match, and the catalog has no straight quotes or ASCII ellipses. The content is weaker. No string has plural variants (§8.8). SpamWiseCore strings survive only as hand-copied stale entries in the app catalog (§8.38). Labels are inconsistent, for example Good vs Inbox (§8.23). The Help book repeats QA notes and leaves major features undocumented (§8.35, §8.36). Two issues surfaced through this lens but are reported in their own sections: the missing app icon, and the fixed $150 lifetime evaluation budget, which Settings shows as "Authorized ceiling".

Limits of this review: reviewers did not run the app. Runtime behaviors are inferred from SwiftUI and AppKit semantics. These include dropped sheet presentations, MenuBarExtra key equivalents, Escape handling and Return in the key field. Several screenshots predate later view edits and were used only where the layout structure is unchanged.

### SF Symbols inventory

| Symbol | Where | Fit | Suggestion |
|---|---|---|---|
| `envelope.badge.shield.half.filled` | `MyApp.swift:23` (MenuBarExtra), `SpamWiseShortcuts.swift:9` (App Shortcut) | Good: mail plus protection; valid current name; template-rendered. Never changes, whatever the state | Vary by state: `.fill` when filtering is live, outline in dry run, `shield.slash` when paused, `exclamationmark.shield` when attention is needed (§8.61). Keep for the Shortcut |
| `tray` | `ContentView.swift:50` (Activity empty state) | Good: an empty mail log | Keep; use `ContentUnavailableView.search` when filters match nothing (§8.45) |
| `tray` | `ReviewDigestView.swift:16` (digest empty state) | Weak: `tray` means Inbox, and Review is a flag | `flag`, or `checkmark.circle` for "Nothing to review" |
| `sidebar.right` | `ContentView.swift:114` (inspector toggle) | Acceptable glyph; title is fixed at "Show details" and there is no tooltip | `sidebar.trailing`, a Show/Hide title, `.help` (§8.47) |
| `exclamationmark.triangle` | `DecisionDetailView.swift:28` (action error) | Correct | Reuse for the read-status error, scan failures and Mail connection status (§8.50) |
| `line.3.horizontal.decrease` | `RuleEditorView.swift:34` (no-rules empty state) | Filter glyph; does not say "sender rules" | `person.crop.circle.badge.checkmark` or `envelope.badge.person.crop` |
| `gearshape` | `SettingsView.swift:12` (General tab) | Standard | Keep |
| `person.crop.circle` | `SettingsView.swift:14` (Accounts tab) | Reads as a user profile; the tab mostly holds classifier settings | `at`, as Mail uses, after splitting out a Classifier tab with `sparkles` or `cpu` (§8.4) |
| `line.3.horizontal.decrease` | `SettingsView.swift:18` (Rules tab) | Acceptable filter metaphor; nearly identical to the Preferences glyph | `checklist` or `list.bullet.rectangle` |
| `text.alignleft` | `SettingsView.swift:22` (Preferences tab) | Poor: a text-formatting glyph | `text.bubble` or `text.quote`, with the tab renamed Policy (§8.4) |
| `slider.horizontal.3` | `SettingsView.swift:26` (Advanced tab) | Fair, conventional | `gearshape.2` (Apple's Advanced convention), or keep |
| Native help bezel | `HelpButton` (e.g. `DecisionDetailView.swift:170`) | Correct; has an accessibility label | Keep |
| (missing) toolbar items | `ContentView.swift:60-117` | Text-only, so it overflows | `pause.circle`/`play.circle`, `play.rectangle` or `eye`, `tray.full` or `list.bullet.clipboard`, `xmark.bin`, `line.3.horizontal.decrease.circle` (`.fill` when a filter is active), `chart.bar` (§8.14) |
| (missing) verdict and correction cues | `DecisionDetailView.swift:150-155`, `:225`; `MailMenuView.swift:12-23`; `AutomationIntents.swift:10-12` | Text-only, although Mail's own Junk and flag glyphs exist | `MailLabel.symbolName`: `tray` / `xmark.bin` / `flag`; `arrow.uturn.backward` on corrected rows (§8.52, §8.46) |
| (missing) status rows | `DecisionDetailView.swift:33`, `MailHealthView.swift:43`, `MailConnectionView.swift:12`, `KeyEntryView.swift:25`, `IMAPSettingsView.swift:53` | No visual state; failures read like help copy | `exclamationmark.triangle` for failure, `checkmark.circle` for success or Validated (§8.50) |

### Audience classification of user-visible controls

| Control | Where | Audience | Recommendation |
|---|---|---|---|
| Open at login, Filtering strength, Review treatment, Weekly digest | General | Typical | Keep; drop the "provisional until calibrated" note |
| Dry run toggle | General | Typical (locked until the probe passes) | Plain-language label and a guided enable flow (§8.1) |
| Check for updates | General (direct build only) | Typical | Hide the empty section in other builds |
| Notifications (enable, interval, quiet hours, Save) | General › disclosure | Typical/Power | Apply on change; use presets (§8.20, §8.62, §8.63) |
| Show setup | General | Typical | Add Cancel; don't reset dry run (§8.32) |
| Keep filtering on this Mac, Provider picker, consent | Accounts | Typical (privacy) | Move to a Classifier tab and to onboarding (§8.4, §8.30) |
| Model (read-only), Usage and spending | Accounts | Power | Move under Advanced; show monthly actuals |
| Provider keys / Claude Verify | Accounts, onboarding | Typical | Add prompts; one credential view for all providers (§8.22, §8.59) |
| Connection (Apple Mail/IMAP), IMAP credentials | Accounts | Power | Keep; confirm before switching transport (§8.21) |
| TLS port, bearer token, Inbox UID probe | Accounts | Developer | Number field; automate the probe (§8.67, §8.1) |
| Check Mail connection | Accounts, onboarding | Typical | Add an Open Automation Settings button (§8.24) |
| Account include toggles | Accounts › Accounts and scan health | Typical | Move out of the diagnostics disclosure (§8.25) |
| Page/offset/observed counts, mailbox destinations | Accounts › scan health | Developer | Move to a Diagnostics section |
| Test selected disposable message | Accounts › Enable mail actions | Developer, but required of typical users | Replace with a guided assistant (§8.1) |
| Configure folders…, trust exclusions, own-address exclusion | Accounts | Power | Keep |
| Sender rules (add/edit/remove/import/export) | Rules | Typical / Power | Add double-click, a context menu and Undo (§8.34) |
| Content rules (regex, fields, test) | Rules › sheet | Power | Keep; show errors inline (§8.18) |
| Policy editor | Preferences | Typical | Keep the draft; rename the tab (§8.4, §8.20) |
| Context limits (recent corrections, body token budget) | Advanced | Developer | Hide |
| Learning (similar corrections, campaigns, Bayes, learned weights) | Advanced | Power/Developer | Use plain-language labels; surface domain suggestions in Rules |
| Evaluation data (retain text, export labels) | Advanced | Developer | Hide |
| Domain age, OCR, attachments, Spamhaus DBL | Advanced › Optional evidence | Power | Apply on change; disable in local-only mode (§8.20, §8.29) |
| Rspamd transport / rspamc path | Advanced › Optional evidence | Developer | Keep under Advanced |
| Backup (key, export, restore) | Advanced | Power | Show the generated key (§8.11) |
| Integration details | Advanced | Developer | Hide |
| Pause/Resume, Dry run recent mail, Review digest, Review Junk, search, inspector | Activity toolbar | Typical | Symbol toolbar items plus menu commands (§8.14, §8.37) |
| Filter menu (account, path, outcome, dates) | Activity | Power | Show account names; drop or localize the path filter (§8.15) |
| Statistics and diagnostics export | Activity › sheet | Power/Developer | Keep |
| Good/Junk/Review, undo, preview, Open in Mail | Inspector | Typical | Keep; add shortcuts and a context menu (§8.37, §8.45) |
| Export raw source, Decision details | Inspector | Power/Developer | Keep behind the disclosure |
| Threat assessment | Inspector | Developer (no detector ships) | Hide until a detector ships (§8.51) |
| Mark Good/Junk/Review, Pause, Settings, Quit | Menu bar | Typical | Title case; state icon; remove the dead shortcuts (§8.26, §8.56, §8.61) |
| Reviewed corpus; Configuration history | Tools menu | Developer / Power | Put the corpus behind a developer flag |
| Preview/Correct Selected Mail intents | Shortcuts | Developer (UUID) | Make the UUID optional (§8.44) |
| Status / Export diagnostics intents | Shortcuts | Power | Keep |

### Findings

| # | Severity | Location | Finding |
|---|---|---|---|
| 8.3 | Medium | `SpamWise.xcodeproj/project.pbxproj:615` | Apple Events purpose string understates Automation use |
| 8.4 | Medium | `SpamWise/AccountSettingsView.swift:9` | Accounts tab holds the classifier; "Preferences" tab inside Settings; weak tab symbols |
| 8.5 | Medium | `SpamWise/AdvancedSettingsView.swift:10` | Collapsed and nested disclosures used as hierarchy; centered and misaligned rows |
| 8.6 | Medium | `SpamWise/AdvancedSettingsView.swift:41` | Developer jargon and evaluator caveats in primary copy |
| 8.7 | Medium | `SpamWise/AppModel.swift:219` | Background sweeps share the global busy flag and disable foreground actions |
| 8.8 | Medium | `SpamWise/AppModel.swift:240` | No plural variations anywhere ("1 accounts", "1 rules") |
| 8.9 | Medium | `SpamWise/AppModelErrors.swift:21` | Error messages duplicate or misstate the cause |
| 8.10 | Medium | `SpamWise/AuditTrailView.swift:24` | Sheets differ in titles and buttons; most ignore Escape and Return |
| 8.11 | Medium | `SpamWise/BackupSettingsView.swift:21` | Generated recovery key is hidden, overwritten without warning; any file accepted |
| 8.12 | Medium | `SpamWise/ContentView.swift:35` | Activity table lacks confidence/reason columns; verdict text only; counts in a tooltip |
| 8.13 | Medium | `SpamWise/ContentView.swift:37` | Time column shows no date across 5,000 retained records; no sorting |
| 8.14 | Medium | `SpamWise/ContentView.swift:58` | Text-only toolbar overflows at minimum width in Spanish and French |
| 8.15 | Medium | `SpamWise/ContentView.swift:75` | Filters, statistics and inspector show raw account IDs and internal path codes |
| 8.16 | Medium | `SpamWise/ContentView.swift:129` | Eight independent sheets; requests dropped, late or stacked |
| 8.17 | Medium | `SpamWise/ContentView.swift:158` | `accessibilityValue` carries UI-test tokens that VoiceOver speaks |
| 8.18 | Medium | `SpamWise/ContentView.swift:171` | All feedback goes through one gray, never-cleared global status string |
| 8.19 | Medium | `SpamWise/CorpusView.swift:49` | Corpus Forget deletes permanently with no confirmation |
| 8.20 | Medium | `SpamWise/EvidenceSettingsView.swift:41` | Settings mix apply-on-change and Save buttons; drafts silently discarded |
| 8.21 | Medium | `SpamWise/IMAPSettingsView.swift:16` | Touching the Connection picker silently unverifies the route and stops filtering |
| 8.22 | Medium | `SpamWise/KeyEntryView.swift:9` | Text and secure fields without prompts render as label-only rows |
| 8.23 | Medium | `SpamWise/LocalizedLabels.swift:38` | Good vs Inbox, and three names for the Review action |
| 8.24 | Medium | `SpamWise/MailConnectionView.swift:12` | Permission-denied state has no Open Automation Settings button |
| 8.25 | Medium | `SpamWise/MailHealthView.swift:18` | Account inclusion toggles buried in a flat diagnostics list |
| 8.26 | Medium | `SpamWise/MailMenuView.swift:15` | Menu-bar ⌥⌘G/J/R shortcuts only fire while the menu is open |
| 8.27 | Medium | `SpamWise/MailMenuView.swift:24` | Menu-bar corrections enabled during onboarding; results never shown |
| 8.28 | Medium | `SpamWise/MailReviewView.swift:88` | Correction results sheet has no progress or cancel through 30-second settles |
| 8.29 | Medium | `SpamWise/ModelSettingsView.swift:48` | Local-only mode leaves blocked providers and network evidence enabled |
| 8.30 | Medium | `SpamWise/OnboardingView.swift:21` | Setup is Anthropic-only and always says "Continue offline" |
| 8.31 | Medium | `SpamWise/OnboardingView.swift:39` | Return in the API-key field advances setup and loses the key |
| 8.32 | Medium | `SpamWise/OnboardingView.swift:42` | Reopened setup cannot be cancelled; Finish silently turns dry run on |
| 8.33 | Medium | `SpamWise/OnboardingView.swift:90` | Onboarding dry-run step never shows the decisions it previews |
| 8.34 | Medium | `SpamWise/RuleEditorView.swift:48` | Rule tables lack standard table affordances; removal has no confirmation or undo |
| 8.35 | Medium | `SpamWise/SpamWise.help/.../how-decisions-are-made.html:6` | Help out of step with the UI; major features undocumented |
| 8.36 | Medium | `SpamWise/SpamWise.help/.../troubleshooting-mail-integration.html:11` | Help pages carry developer QA notes and an unshipped CLI |
| 8.37 | Medium | `SpamWise/ToolsCommands.swift:9` | Toolbar actions have no menu commands or keyboard shortcuts |
| 8.38 | Medium | `SpamWiseCore/Package.swift:12` | Package strings depend on hand-copied stale entries in the app catalog |
| 8.39 | Medium | `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:69` | Configuration history shows raw rule IDs, UUIDs and rawValues |
| 8.40 | Low | `SpamWise/ActivityStatisticsView.swift:32` | Statistics accepts an inverted date range without feedback |
| 8.41 | Low | `SpamWise/AppModelCredentials.swift:50` | Key verification adds a fake "SpamWise setup" row to Activity |
| 8.42 | Low | `SpamWise/AppShortcuts.xcstrings:4` | App Shortcut phrase translations still `needs_review` |
| 8.43 | Low | `SpamWise/AuditTrailView.swift:17` | Configuration history: plain TextField search, no title, no empty state |
| 8.44 | Low | `SpamWise/AutomationIntents.swift:29` | Shortcuts intents require a typed Request UUID |
| 8.45 | Low | `SpamWise/ContentView.swift:35` | Activity table: no context menu, double-click, sorting or filtered empty state |
| 8.46 | Low | `SpamWise/ContentView.swift:43` | A correction adds a second row; the original keeps its old verdict |
| 8.47 | Low | `SpamWise/ContentView.swift:114` | Inspector toggle has a fixed "Show details" title and no tooltip |
| 8.48 | Low | `SpamWise/ContentView.swift:119` | Status footer spans beneath the inspector column |
| 8.49 | Low | `SpamWise/CorpusView.swift:65` | Corpus import accepts any file; more than 20 files reported as oversize |
| 8.50 | Low | `SpamWise/DecisionDetailView.swift:33` | Error and status rows use the warning glyph inconsistently |
| 8.51 | Low | `SpamWise/DecisionDetailView.swift:35` | Every inspector shows "Threat assessment: Not assessed" |
| 8.52 | Low | `SpamWise/DecisionDetailView.swift:225` | Good/Junk/Review have no shared symbol; verdict has no visual weight |
| 8.53 | Low | `SpamWise/Localizable.xcstrings:174` | French uses breakable spaces before `:` and `;` |
| 8.54 | Low | `SpamWise/Localizable.xcstrings:3391` | Spanish/French glossary inconsistencies and mixed register |
| 8.55 | Low | `SpamWise/MailMenuView.swift:9` | Menu-bar extra cannot be hidden; its status ignores dry run |
| 8.56 | Low | `SpamWise/MailMenuView.swift:25` | Mixed title/sentence case in menus and buttons; jargon in typical-path labels |
| 8.57 | Low | `SpamWise/MailReviewView.swift:30` | Review Junk list shows only subjects, with no page position |
| 8.58 | Low | `SpamWise/ModelSettingsView.swift:49` | Setting, provider and app names are inconsistent |
| 8.59 | Low | `SpamWise/ModelSettingsView.swift:62` | Credential entry implemented three ways with different feedback |
| 8.60 | Low | `SpamWise/MyApp.swift:17` | Help menu replacement drops ⌘?; Tools items in sentence case; ⌥⌘C conflict |
| 8.61 | Low | `SpamWise/MyApp.swift:23` | Menu-bar icon never reflects paused, dry-run or broken state |
| 8.62 | Low | `SpamWise/NotificationSettingsView.swift:17` | Steppers used for very large ranges |
| 8.63 | Low | `SpamWise/NotificationSettingsView.swift:25` | Quiet-hours labels concatenated as 24-hour "13:00" |
| 8.64 | Low | `SpamWiseCore/Sources/Classifier/Types.swift:314` | Quoted-reply stripping recognizes only English reply headers |
| 8.65 | Low | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:106` | Daemon and evaluation CLI output unlocalized and unpluralized |
| 8.66 | Info | `SpamWise/FolderSettingsView.swift:78` | Required training-folder name rendered without quotes |
| 8.67 | Info | `SpamWise/IMAPSettingsView.swift:42` | IMAP TLS port is a free-text String field |

#### 8.3 Apple Events purpose string understates Automation use — Medium

- **Where:** `SpamWise.xcodeproj/project.pbxproj:615` (:665, :855, :909; es/fr InfoPlist.strings)
- **Problem:** The purpose string reads "SpamWise reads mail history and applies your corrections in Apple Mail." Automation is actually used to read incoming messages for classification, move mail to Junk and back, set flags and colors, and read account and folder lists. Guideline 5.1.1 requires a purpose string to describe the actual use.
- **Scenario:** A reviewer grants Automation and then watches SpamWise move incoming mail to Junk, which the prompt never mentioned. That risks rejection, and users likewise approve without knowing what they are allowing.
- **Fix:** Use wording like "SpamWise reads messages in Mail to classify them and, when you allow it, moves junk to the Junk mailbox or flags messages for review.", and update the es/fr strings.
<!-- sources: content#18 -->

#### 8.4 Accounts tab holds the classifier; "Preferences" tab inside Settings; weak tab symbols — Medium

- **Where:** `SpamWise/AccountSettingsView.swift:9` (SettingsView.swift:12-26, ModelSettingsView.swift:26 and :81)
- **Problem:** The Accounts tab (`person.crop.circle`) opens with provider, local-only, model, consent, API key and spending. The mail accounts sit below the fold under collapsed disclosures, which makes this the tallest pane. A tab named "Preferences" inside a window macOS calls Settings holds only the natural-language policy, under the text-formatting glyph `text.alignleft`. Advanced uses `slider.horizontal.3`, while Apple uses `gearshape.2`.
- **Scenario:** A user looking for the account toggles must scroll and expand disclosures. A user looking to change the AI provider tries General and Advanced first. "Preferencias" and "Préférences" carry the same ambiguity.
- **Fix:** Split out a Classifier tab (`sparkles` or `cpu`) for provider, local-only, consent, key and usage. Keep Accounts for Mail and IMAP, with the `at` symbol. Rename Preferences to "Policy" (`text.bubble` or `text.quote`), and use `gearshape.2` for Advanced.
<!-- sources: design/settings#6, design/onboarding-consistency#15, design/settings#16 -->

#### 8.5 Collapsed and nested disclosures used as hierarchy; centered and misaligned rows — Medium

- **Where:** `SpamWise/AdvancedSettingsView.swift:10` (AdvancedSettingsView.swift:36, ProviderConsentView.swift:35-60, SpamhausSettingsView.swift:30-47, BackupSettingsView.swift:16-36, IMAPSettingsView.swift:56-72, MailConnectionView.swift:21 → TrustExclusionsView.swift:9, MailHealthView.swift:33 → MailDestinationView.swift:11, LearningSettingsView.swift:10-24 and :68, EvidenceSettingsView.swift:11, :29, :70, :74, ModelSettingsView.swift:80, MailConnectionView.swift:24 and :36, RuleEditorView.swift:58, PolicyView.swift:43)
- **Problem:** Advanced opens as six identical, headerless collapsed bars, and nesting reaches three levels. In a grouped Form, bare Text, Link and Button children of a DisclosureGroup lose leading alignment. The screenshots show centered links, buttons and captions in Backup, Spamhaus, provider consent and IMAP (backup-en.png, spamhaus-es/fr.jpg, disclosure-fr.png, en-imap-actions.jpg). Only some rows were fixed, with ad hoc `.frame(maxWidth: .infinity, alignment: .leading)`. Explanations are standalone secondary rows rather than Section footers, and Rules and Preferences are padded VStacks instead of Forms.
- **Scenario:** In French, the Spamhaus block shows its terms link, explanation and Save button centered under left-aligned toggles. No Advanced setting is visible until its bar is expanded, and trust exclusions need three expansions.
- **Fix:** Use `Section("Title") { … } footer: { Text(…) }` for primary grouping. Keep a disclosure only for rare diagnostics, and never nest one. Remove the frame workarounds, use grouped Forms for Rules and Preferences, and split Optional evidence into Local analysis and Network lookups sections.
<!-- sources: design/settings#7, design/onboarding-consistency#5, conventions/app-views-settings#27 -->

#### 8.6 Developer jargon and evaluator caveats in primary copy — Medium

- **Where:** `SpamWise/AdvancedSettingsView.swift:41` (AdvancedSettingsView.swift:37, MailHealthView.swift:36-38 and :47, MailDestinationView.swift:29, MailReviewView.swift:18, ActivityStatisticsView.swift:54, DecisionDetailView.swift:103 and :126, CorpusView.swift:20-37, LearningSettingsView.swift:14-15, EvidenceSettingsView.swift:42, :58, :63, ModelSettingsView.swift:31, :87, :91, ContentView.swift:146, MailConnectionView.swift:9, AppModel.swift:118)
- **Problem:** The copy restates the engineering ledger instead of telling users what happens or what to do. It covers page offsets, calibration, label provenance, MailKit dry-run status, signing advice, reservation ceilings, "sidecars", Bayes, and a SpamSieve mention. This appears in General, Accounts and Activity, not just Advanced, and setup asks users to enable a Mail extension that does nothing for them yet. Much of it is hard to translate.
- **Scenario:** In Accounts and scan health, a user reads "Next page offset 40" and "Mailbox changes can shift pages… counts do not guarantee delivery", with nothing to act on. Statistics and Review Junk open with notes on calibration and confirmed labels.
- **Fix:** Rewrite around outcomes and tasks, for example Review Junk: "Restore anything that isn't junk. Nothing moves unless you choose Mark Good." Move methodology caveats to Help or a Diagnostics disclosure. Remove the MailKit status and the extension instruction until that route works. Drop the third-party product name; verifiers judged the trademark risk overstated, but the copy is still unhelpful.
<!-- sources: content#8, design/main-window#15, comments/app-views-main#11 -->

#### 8.7 Background sweeps share the global busy flag and disable foreground actions — Medium

- **Where:** `SpamWise/AppModel.swift:219` (AppModel.swift:172-173, AppModelScanning.swift:11, DecisionDetailView.swift:68-77 and :156, MailMenuView.swift:24, ContentView.swift:64 and :71, CorpusView.swift:51, MailHealthView.swift:13, ContentRuleEditorView.swift:50-51, FolderSettingsView.swift:48, LearningSettingsView.swift:71)
- **Problem:** The 60-second automatic scan goes through the same exclusive `run`/`busy` gate as user actions, and runs longer when live moves add 30-second settles. While it runs, these controls are disabled: inspector corrections, Preview, Open in Mail, Export, Review Junk, menu-bar corrections, corpus edits and folder setup. Clicks that reach `run` are dropped silently. The Content rules sheet's Done button is inside the disabled HStack and has no Escape shortcut. The Folder sheet's "Cancel" cancels the global work task, including the sweep.
- **Scenario:** A user reaches for Good on a misfiled message, and it greys out for tens of seconds, every minute. Content rules can't be dismissed for at least 90 seconds during a three-move sweep. Clicking Folder "Cancel" to close the sheet aborts the Inbox sweep.
- **Fix:** Give background sweeps their own task and indicator. Queue or preempt them through the pipeline's own serialization. Never disable a sheet's dismiss button. Rename the folder button "Stop Preview" and scope it to that task. Show "Checking mail…" next to any temporarily disabled control.
<!-- sources: design/main-window#8, design/settings#4 -->

#### 8.8 No plural variations anywhere — Medium

- **Where:** `SpamWise/AppModel.swift:240` (AppModelScanning.swift:134, DecisionDetailView.swift:62, CorpusView.swift:27 and :30, LocalNotifications.swift:49, RuleManagement.swift:110, ContentRuleManagement.swift:28, AppModel.swift:366-368)
- **Problem:** None of the 705 catalog entries has plural variations or substitutions, although 23 keys carry counts. Interpolating with `format: .number` emits `%@` keys, which Xcode can't vary by plural. Some Ints have no FormatStyle at all. One status concatenates a localized sentence with a raw `actionError`.
- **Scenario:** Users see "Connected — 1 accounts readable", "Restores 1 rules and 1 examples" and "Classified 1 of 1 messages", with the same errors in Spanish and French.
- **Fix:** Interpolate the Int directly so the key carries `%lld`, or use a substitution. Then add one/other variations in en, es and fr, or use `^[\(count) rule](inflect: true)`, or rephrase as label–value pairs. Fold `actionError` into a single format string.
<!-- sources: design/onboarding-consistency#18, content#5, conventions/app-logic#12, conventions/app-views-main#12 -->

#### 8.9 Error messages duplicate or misstate the cause — Medium

- **Where:** `SpamWise/AppModelErrors.swift:21` (AppModelErrors.swift:14-19, AppModelFolders.swift:17-31, CorpusView.swift:82, SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift:25, TrustExclusions.swift:9 and :13)
- **Problem:** `describe()` joins description, reason and suggestion, then appends more text. A permission denial therefore reads as three overlapping sentences beginning "The Mail action is unavailable", even from Check Mail connection, where no action ran. Every KeychainError ends with entitlement advice the user can't follow. Validation also reuses unrelated cases:
  - `IntegrationError.unavailable` for a misnamed or non-empty training folder, and for the 20-plan limit.
  - `ParseError.tooLarge` for more than 20 files or a missing store.
  - `tooManyRules` ("maximum of 10,000 sender rules") for 101 trust-exclusion addresses or more than 30,000 characters.
- **Scenario:** A user who pastes 101 trust exclusions is told the 10,000 sender-rule maximum has been reached. A user who saves a plan for a non-empty folder reads "The Mail action is unavailable."
- **Fix:** Give `permissionDenied` a recoverySuggestion and drop the appended duplicate. Make IntegrationError's description general ("Couldn’t communicate with Mail."), and replace the entitlement advice with something the user can do. Add specific cases with accurate reasons: `folderNotEmpty`, `folderNameMismatch`, `tooManyFolderPlans`, `tooManyFiles`, and a trust-exclusion limit whose value is interpolated with `format: .number`.
<!-- sources: content#9, comments/core-pipeline-store#3 -->

#### 8.10 Sheets differ in titles and buttons; most ignore Escape and Return — Medium

- **Where:** `SpamWise/AuditTrailView.swift:24` (CorpusView.swift:20 and :59, MailReviewView.swift:16, :59, :75, :88, :103, ActivityStatisticsView.swift:31 and :78, ReviewDigestView.swift:12 and :42, FolderSettingsView.swift:50, ContentRuleEditorView.swift:21, :24-30, :50, :94-123, RuleFormView.swift:15 and :30-32, ActivityDateFilterView.swift:15-18)
- **Problem:** On macOS, Escape closes a sheet only through a cancel-action button, and Return only through a default button. Most sheets have a lone Done with neither; only the digest's own Done and the date filter have shortcuts. Titles use title2, headline, a Form section header or nothing. Form styles and button rows vary, and Cancel sits at the leading edge before a Spacer instead of beside the default button. One sheet says "Save" and another "Save rule". ContentRuleFormView has no title, and the content-rule table has no empty state, unlike the sender-rule table.
- **Scenario:** Escape does nothing in Statistics, Corpus, Review Junk, Configuration history, Folders, Content rules or Message preview. An empty Content rules sheet shows a blank grid.
- **Fix:** Use one pattern for all sheets: a NavigationStack with `.navigationTitle` plus `ToolbarItem(placement: .cancellationAction)` and `ToolbarItem(placement: .confirmationAction)`. Alternatively, use a shared `Spacer(); Cancel; Primary` footer. Map Done to `.defaultAction`, and to `.cancelAction` where it is the only button. Add a ContentUnavailableView for content rules and an "Add/Edit content rule" title.
<!-- sources: design/main-window#19, design/settings#15, design/onboarding-consistency#16, conventions/app-views-settings#22 -->

#### 8.11 Generated recovery key is hidden, overwritten without warning; any file accepted — Medium

- **Where:** `SpamWise/BackupSettingsView.swift:21` (:22-26, :40, :45, :51-56)
- **Problem:** The app generates an unrecoverable key and puts it straight into a SecureField. The key is never visible, and the empty field renders as a bare label. Generate replaces a typed key without confirmation, Copy gives no feedback, and Export is enabled with no "I saved this" step. Exporter and importer both use `.data`, so Restore offers every file. The destructive confirmation has no message.
- **Scenario:** A user clicks Generate, then Export, without copying the key, and is left with an unrecoverable backup. Or they type a restore key, click Generate by mistake, and lose it.
- **Fix:** Show the generated key in selectable monospaced text with Copy and Save to File. Require confirmation before Export, and before regenerating over a non-empty key. Keep a SecureField only for entering a key at restore. Declare an exported UTType for `.spamwisebackup`, add a `message:`, and consider File › Export/Import menu items.
<!-- sources: design/settings#13, design/onboarding-consistency#19 -->

#### 8.12 Activity table lacks confidence/reason columns; verdict text only; counts in a tooltip — Medium

- **Where:** `SpamWise/ContentView.swift:35` (ContentView.swift:36-45 and :164-166, DecisionDetailView.swift:225)
- **Problem:** Brief §6 asks for a table of time, sender, subject, verdict (icon plus label), confidence and reason, and a footer with today's counts. The table has only the first four columns, so every explanation is hidden until the inspector opens. VerdictBadge is plain text, and the Junk/Review breakdown exists only in `.help`.
- **Scenario:** Judging 200 dry-run decisions means opening each row's inspector one at a time. VoiceOver users never hear the day's Junk and Review counts.
- **Fix:** Add Confidence and Reason columns, with the reason on one line and the full text in `.help`. Give the verdict a symbol Label (§8.52), and show the Junk/Review counts as visible footer text.
<!-- sources: gap/brief-conformance#4 -->

#### 8.13 Time column shows no date across 5,000 retained records; no sorting — Medium

- **Where:** `SpamWise/ContentView.swift:37` (SpamWiseCore/Sources/SpamWiseCore/State.swift:161)
- **Problem:** The column uses `.dateTime.hour().minute()`, but the log keeps up to 5,000 records spanning days. The inspector shows no date either, and the Table has no `sortOrder`.
- **Scenario:** Two rows read "10:42" and "10:40". One is from today, one from five days ago, and nothing distinguishes them.
- **Fix:** Use a today-aware format like Mail's: the time for today, otherwise a short date plus time. Rename the column "Date", add a Date row to the inspector, and support `sortOrder` with `KeyPathComparator`.
<!-- sources: design/main-window#9, design/onboarding-consistency#10 -->

#### 8.14 Text-only toolbar overflows at minimum width in Spanish and French — Medium

- **Where:** `SpamWise/ContentView.swift:58` (:60-117, :128)
- **Problem:** Six long text-only buttons plus one icon button share a 720 pt minimum width. es-toolbar-overflow.jpg shows only two items before the » chevron. en-inspector-failed.jpg shows Review Junk, Filter and Statistics not fitting. Pause, a safety control, has no state glyph. The toolbar has no tooltips, no customization and no explicit placements.
- **Scenario:** A Spanish or French user can't see Filter, Statistics, Review Junk or the inspector toggle without discovering the overflow menu.
- **Fix:** Use `Label` items with symbols (see the inventory) and `.help`, which the "sparing icons" rule allows as label shorthand. Add `.toolbar(id:)` customization so low-priority items can be removed, and put the inspector toggle at `.primaryAction`.
<!-- sources: design/main-window#3, design/onboarding-consistency#9 -->

#### 8.15 Filters, statistics and inspector show raw account IDs and internal path codes — Medium

- **Where:** `SpamWise/ContentView.swift:75` (ContentView.swift:77-89, ActivityStatisticsView.swift:34-41, DecisionDetailView.swift:186-188)
- **Problem:** Filter → Account and the Statistics picker list `identity.accountID`, which is Mail's opaque scripting ID or `imap:<UUID>`. `model.accounts` already holds the names, and the expression is duplicated in both places. The Path filter and the detail row show untranslated tokens: gate, model, fingerprint, correction, selection, verification. The catalog translates "Path" as Ruta/Circuit but "All paths" as Todos los métodos/Toutes les méthodes. "Today" is a one-shot button, and nothing shows that a filter is active.
- **Scenario:** A Spanish user opens Filtrar → Cuenta, sees two UUIDs, then sees "fingerprint" and "gate" under Ruta.
- **Fix:**
  - Add an `accountName(for:)` helper with a localized "Unknown account" fallback, plus a shared `recordAccountIDs`.
  - Replace path strings with a typed "Decided by" enum with localized titles, or move the filter to diagnostics.
  - Use one translation for Path and All paths.
  - Show active filters with a `.fill` symbol, a search token or a Clear filters banner.
<!-- sources: design/main-window#10, design/onboarding-consistency#11, content#10, conventions/app-views-main#4 -->

#### 8.16 Eight independent sheets; requests dropped, late or stacked — Medium

- **Where:** `SpamWise/ContentView.swift:129` (:129-136; ReviewDigestView.swift:37; DecisionDetailView.swift:68; AppModelMailReview.swift:11 and :68; AppModel.swift:136)
- **Problem:** Sheets are triggered from the toolbar, the Tools menu, the menu bar, the 3-second refresh loop and other sheets, but all hang off ActivityView. SwiftUI presents one sheet per presenter, so a request made while another sheet is up is ignored and appears later. The digest stacks DecisionDetailView as a sheet on a sheet, against the HIG's one-sheet-at-a-time guidance.
- **Scenario:**
  - In the digest, Preview message shows nothing, then opens unexpectedly once the digest closes.
  - Menu-bar Mark as Junk shows no results while Statistics is open.
  - On a new week's first refresh, the digest pops up unprompted.
- **Fix:** Route every Activity modal through one `enum ActivitySheet: Identifiable` and `.sheet(item:)`. Show the digest's decision detail by pushing inside the digest or by selecting the row in the main inspector. Announce the weekly digest with a notification or a badge instead of a modal.
<!-- sources: design/main-window#2 -->

#### 8.17 `accessibilityValue` carries UI-test tokens that VoiceOver speaks — Medium

- **Where:** `SpamWise/ContentView.swift:158` (ContentView.swift:149-152, DecisionDetailView.swift:26 and :159, UITests/ActivityScreen.swift:6)
- **Problem:** Raw tokens exist for XCTest assertions: paused/dryRun/active, the outcome rawValue and the correction rawValue. VoiceOver speaks them in place of, or alongside, the localized value, in every locale. This contradicts the swiftui-conventions rule to locate elements by identifier and keep labels and values for VoiceOver.
- **Scenario:** VoiceOver reads "Outcome, dryRun", or "integrationUnavailable" in a French UI.
- **Fix:** Remove the overrides. Have tests assert on the identifier plus the localized value (locale is already pinned), or on a test-only identifier suffix such as `activity.mode.dryRun`.
<!-- sources: design/main-window#11, comments/app-views-main#2 -->

#### 8.18 All feedback goes through one gray, never-cleared global status string — Medium

- **Where:** `SpamWise/ContentView.swift:171` (AppModel.swift:218-225, SettingsView.swift:30-34 and :51-58, CorpusView.swift:61, MailReviewView.swift:61, FolderSettingsView.swift:31 and :45, ContentRuleEditorView.swift:125-157, StartupSettingsView.swift:28, SpamhausSettingsView.swift:45 and :75, RuleFormView.swift:28, MailHealthView.swift:43, MailDestinationView.swift:27, IMAPSettingsView.swift:53)
- **Problem:** `run` catches every error into `AppModel.status`. That string is rendered as `.callout .secondary` text limited to two lines, and it appears in the Activity footer, under every Settings tab and inside several sheets. It is overwritten by the next operation, including the automatic scan, and never cleared. Errors look the same as help captions. ContentRuleFormView shows no status, so a failed Save or Test leaves the sheet silent while the error lands behind the sheet's dimming. Settings tab titles are also written twice, in the Labels and in `SettingsPane.title`.
- **Scenario:** After Automation is revoked, every sweep fails. The only sign is a truncated gray line that looks like "Mail check finished". local-mode.png shows an Automation-denied error pinned under Accounts while the user edits the classifier.
- **Fix:** Separate neutral status from errors, and scope results to each operation. Show errors inline as `Label(…, systemImage: "exclamationmark.triangle.fill")` with a tint and a recovery button, or as an `.alert(isPresented:error:)`. Clear status on success, and drop the Settings footer. Build the tabs from a CaseIterable `SettingsPane` that has `title` and `systemImage`.
<!-- sources: design/main-window#7, design/settings#8, design/onboarding-consistency#13, conventions/app-views-settings#23 -->

#### 8.19 Corpus Forget deletes permanently with no confirmation — Medium

- **Where:** `SpamWise/CorpusView.swift:49` (:99-104)
- **Problem:** Forget immediately removes a reviewed label with its linked correction examples and learning. `CorpusManagement.forget` clears the undo state, so the action can't be reversed, and the destructive role alone is not a confirmation.
- **Scenario:** A user selects the wrong row, clicks Forget, and the example and its learning are gone.
- **Fix:** Wrap it in `.confirmationDialog("Forget this reviewed message?", …)` with a destructive confirm button and a message saying sender rules remain. Consider multi-select for bulk relabel and forget.
<!-- sources: design/main-window#20 -->

#### 8.20 Settings mix apply-on-change and Save buttons; drafts silently discarded — Medium

- **Where:** `SpamWise/EvidenceSettingsView.swift:41` (EvidenceSettingsView.swift:13-36, :71, :78, NotificationSettingsView.swift:13 and :36, TrustExclusionsView.swift:21, PolicyView.swift:39 and :44-48, IMAPSettingsView.swift:48, FolderSettingsView.swift:25, SpamhausSettingsView.swift:41 and :68-72, GeneralSettingsView.swift:41)
- **Problem:** macOS settings apply immediately. Inside Optional evidence, the domain-age, OCR and attachment toggles save through `editSettings`. The Spamhaus toggle and Rspamd picker beside them sit in local `@State` that only "Save evidence settings" persists, while the Spamhaus key goes to Keychain at once. Notifications, trust exclusions, policy, IMAP and folder plans each have their own Save button. Nothing marks unsaved edits, and `onAppear`/`.task` reloads stored values over the draft whenever the tab is shown again.
- **Scenario:** A user turns on Spamhaus DBL, saves the key, accepts the terms and closes Settings. The blocklist stays off. Another user edits the policy, glances at Rules, and returns to find the edits gone.
- **Fix:** Apply toggles and pickers on change through field-level `editSettings`, and gate Spamhaus on consent rather than a Save button. Commit text fields on submit or focus loss, or debounce them. Keep explicit commit only for credentials and destructive operations. Where a draft is unavoidable, keep it in the model, show its unsaved state and confirm before discarding, or move it into a sheet with Cancel/Save.
<!-- sources: design/settings#3, design/onboarding-consistency#12, conventions/app-views-settings#11 -->

#### 8.21 Touching the Connection picker silently unverifies the route and stops filtering — Medium

- **Where:** `SpamWise/IMAPSettingsView.swift:16` (IMAPSettingsView.swift:11-18, AppModel.swift:57 and :338, GeneralSettingsView.swift:25)
- **Problem:** The transport binding's setter sets `dryRun = true` and `route = .unverified` on any change, even a switch back to the already-validated transport. Only a new probe restores the route. `validatedAccounts` is kept, so the General Dry run toggle stays enabled, but `canScanAutomatically` requires a verified route. The only explanation is "Incoming route: Not verified" under Advanced › Integration details.
- **Scenario:** A user picks IMAP to look, then switches back to Apple Mail. Automatic filtering stops with no visible reason.
- **Fix:** Confirm before switching transports. Don't reset the route when the selection returns to the validated transport. Show "Filtering inactive: action test required" in General and the menu bar whenever the route is unverified.
<!-- sources: design/settings#2 -->

#### 8.22 Text and secure fields without prompts render as label-only rows — Medium

- **Where:** `SpamWise/KeyEntryView.swift:9` (ModelSettingsView.swift:62, SpamhausSettingsView.swift:39, BackupSettingsView.swift:21, IMAPSettingsView.swift:34-36 and :61, ContentRuleEditorView.swift:103 and :109)
- **Problem:** In `.grouped` forms the label sits on the left and the field is borderless on the right. With no `prompt:` and an empty value, nothing marks where to type. Screenshots in all three languages confirm rows that look like static labels.
- **Scenario:** In onboarding step 2, a user reads "Anthropic API key" but sees no input box, and Verify stays disabled.
- **Fix:** Add prompts, for example `SecureField("API key", text: $key, prompt: Text("sk-ant-…"))` or `prompt: Text("imap.example.com")`, or use `.roundedBorder` consistently. Alternatively, show a "Saved"/"Not set" state with LabeledContent. Recheck en, es and fr.
<!-- sources: design/settings#20, design/onboarding-consistency#4 -->

#### 8.23 Good vs Inbox, and three names for the Review action — Medium

- **Where:** `SpamWise/LocalizedLabels.swift:38` (DecisionDetailView.swift:150-158, MailMenuView.swift:12 and :20, MailReviewView.swift:55, CorpusView.swift:27, FolderSettingsView.swift:72, LocalNotifications.swift:49, AutomationIntents.swift:11)
- **Problem:** `MailLabel.inbox` displays as "Inbox" in the Verdict column, filters, statistics, corpus counts and "User corrected to %@". Every action calls the same label Good (Deseado/Légitime). Review is "Mark for Review" in the menu but "Mark as Review" in accessibility labels and Help.
- **Scenario:** A user clicks Good, and the inspector confirms "User corrected to Inbox", which makes it unclear what happened.
- **Fix:** Use one user-facing noun per label (Good/Review/Junk) everywhere, including `localizedTitle`. Reserve "Inbox" for the mailbox, write "You marked this Good", and pick one Review phrase.
<!-- sources: design/main-window#25, content#11 -->

#### 8.24 Permission-denied state has no Open Automation Settings button — Medium

- **Where:** `SpamWise/MailConnectionView.swift:12` (AppModelErrors.swift:15-19)
- **Problem:** When Automation is denied, the screen shows only a paragraph telling the user where to go in System Settings. The HIG recommends a direct link, and StartupSettingsView already uses `SMAppService.openSystemSettingsLoginItems()` for its pane.
- **Scenario:** A user who clicked Don't Allow must navigate System Settings by hand, in Accounts and in onboarding alike.
- **Fix:** When `mailPermissionDenied` is true, show `Button("Open Automation Settings")` opening `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`, beside an `exclamationmark.triangle` label.
<!-- sources: design/onboarding-consistency#14 -->

#### 8.25 Account inclusion toggles buried in a flat diagnostics list — Medium

- **Where:** `SpamWise/MailHealthView.swift:18` (MailHealthView.swift:10, :19-38, :43, :47, MailConnectionView.swift:18)
- **Problem:** Which accounts SpamWise filters is a core setting, yet it lives inside the collapsed "Accounts and scan health" disclosure. Each Toggle is labeled only with the account name, so neither the screen nor VoiceOver says what it controls. The rows are interleaved with a mailbox-destinations disclosure and the Last successful page, Observed Inbox messages and Next page offset rows, with no per-account grouping. Failures are plain text, and the only preview is "No accounts".
- **Scenario:** With iCloud and Gmail configured, identical rows run together, VoiceOver announces "iCloud, switch", and switching one off silently excludes that account.
- **Fix:** Promote accounts to a visible Section per account, headed by its name, with a "Filter this account" Toggle and one health summary such as "Last checked 2 min ago". Move paging diagnostics to an Advanced disclosure, style failures as warning Labels, and add previews with accounts and failures.
<!-- sources: design/main-window#26, design/settings#12 -->

#### 8.26 Menu-bar ⌥⌘G/J/R shortcuts only fire while the menu is open — Medium

- **Where:** `SpamWise/MailMenuView.swift:15` (:19, :23; MyApp.swift:23)
- **Problem:** These commands act on Mail's selection, so they are meant to be pressed while Mail is frontmost. MenuBarExtra key equivalents match only while that status-item menu is open, so the displayed shortcuts advertise something that doesn't exist.
- **Scenario:** A user selects spam in Mail and presses ⌥⌘J. Nothing happens in SpamWise; the keystroke goes to Mail.
- **Fix:** Remove the shortcuts, or document binding the existing Shortcuts intents to global keys in the Correcting mistakes Help page.
<!-- sources: design/main-window#5 -->

#### 8.27 Menu-bar corrections enabled during onboarding; results never shown — Medium

- **Where:** `SpamWise/MailMenuView.swift:24` (ContentView.swift:12-16 and :130)
- **Problem:** The Selected messages section is disabled only on `busy || !storageReady`. Corrections run during setup, writing rules and requesting moves, but the results sheet is attached to ActivityView, which doesn't exist until onboarding completes. ToolsCommands already gates on `onboardingComplete`.
- **Scenario:** During setup, a user chooses Mark as Junk. Rules are saved and moves are dispatched with no feedback, and a stale results sheet pops up after setup finishes.
- **Fix:** Disable the section and Pause until `onboardingComplete`, or present results from a scene-level Window.
<!-- sources: design/main-window#6 -->

#### 8.28 Correction results sheet has no progress or cancel through 30-second settles — Medium

- **Where:** `SpamWise/MailReviewView.swift:88` (AppModelMailReview.swift:10-11; SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:118; ContentView.swift:161)
- **Problem:** Menu-bar Mark as Good/Junk/Review opens CorrectionResultsView immediately, then corrects messages one at a time, each move followed by a 30-second verification. The sheet's only button, Done, is disabled while busy. There is no ProgressView or count, and the only Cancel sits in the window footer behind the modal sheet.
- **Scenario:** Marking six messages leaves a mostly empty sheet with a disabled Done for about three minutes, with rows appearing every 30 seconds or more. The app looks hung.
- **Fix:** Show determinate progress ("Correcting 2 of 6…" with `ProgressView(value:total:)`) and a Cancel bound to `model.cancel()` with `.cancelAction`. Keep Done available, or present results only when the work finishes or as a notification.
<!-- sources: design/main-window#1 -->

#### 8.29 Local-only mode leaves blocked providers and network evidence enabled — Medium

- **Where:** `SpamWise/ModelSettingsView.swift:48` (ModelSettingsView.swift:35-50, EvidenceSettingsView.swift:13-21 and :41-49)
- **Problem:** "Keep filtering on this Mac" only sets a flag. The Provider picker still lists every backend, and a conflicting selection produces only a plain-text notice. RDAP, Spamhaus and Rspamd controls stay interactive, with a caption that says they are disabled.
- **Scenario:** A user turns on local-only mode while Claude is selected. Every message fails classification until they notice the notice and change the picker. They can also enable Spamhaus lookups that will never run.
- **Fix:** On enabling local-only, switch to on-device or ask the user. Disable non-local picker options and the network evidence controls with an explanatory footer. Show any remaining conflict as a warning Label.
<!-- sources: design/settings#11 -->

#### 8.30 Setup is Anthropic-only and always says "Continue offline" — Medium

- **Where:** `SpamWise/OnboardingView.swift:21` (OnboardingView.swift:38, :66-93, KeyEntryView.swift:19-22)
- **Problem:** The account step hard-codes "Connect your Anthropic account", KeyEntryView and `ProviderConsentView(backend: .claude)`. There is no on-device, local-only, OpenAI or Gemini choice, which is exactly when privacy-minded users decide whether to trust the app. Because consent is fixed to `.claude`, reopening setup with Gemini selected grants consent to the wrong provider. The copy mentions "your selected provider" before any is chosen and names "Haiku 5.5". The button reads "Continue offline" even after a key is verified.
- **Scenario:** A user who doesn't want cloud processing clicks "Continue offline". The backend stays Claude without consent, so every message stays unclassified. A user who verified a key sees "Continue offline" and assumes it wasn't kept.
- **Fix:** Make step 2 "Choose how SpamWise classifies mail": a provider picker (on-device, Claude, OpenAI, Gemini) followed by that provider's key and consent view. Label the button "Continue" once a usable provider is configured and "Skip for now" otherwise. Interpolate the model's display name, and update the getting-started Help.
<!-- sources: design/onboarding-consistency#7, distribution/product#15, content#17, conventions/app-views-main#21 -->

#### 8.31 Return in the API-key field advances setup and loses the key — Medium

- **Where:** `SpamWise/OnboardingView.swift:39` (KeyEntryView.swift:6 and :9)
- **Problem:** Continue carries `.keyboardShortcut(.defaultAction)`, and the SecureField has no `.onSubmit`. On macOS, Return in a text field fires the default button. That advances the step and destroys KeyEntryView along with its unsaved `@State key`. This behavior is inferred and was not observed.
- **Scenario:** A user pastes a key and presses Return. Setup jumps to step 3, and going Back shows an empty field with nothing stored.
- **Fix:** Add `.onSubmit { model.verifyKey(key) }`. While an unsaved key is present, make "Verify and save key" the default button.
<!-- sources: design/onboarding-consistency#8 -->

#### 8.32 Reopened setup cannot be cancelled; Finish silently turns dry run on — Medium

- **Where:** `SpamWise/OnboardingView.swift:42` (AppModel.swift:201-205; GeneralSettingsView.swift:55-57)
- **Problem:** General → Show setup presents onboarding as a sheet with no Cancel, Close or Escape binding. The only exit is walking all four steps to Finish setup, and `finishSetup()` always writes `dryRun = true`.
- **Scenario:** A user with live filtering reopens setup to reread the privacy note, presses Escape (which does nothing), and clicks through to Finish. Junk moves stop with no explanation.
- **Fix:** In sheet mode, add Cancel with `.cancelAction` and a Done that only dismisses. Force dry run only on the first completion (`if !onboardingComplete`).
<!-- sources: design/onboarding-consistency#2 -->

#### 8.33 Onboarding dry-run step never shows the decisions it previews — Medium

- **Where:** `SpamWise/OnboardingView.swift:90` (:66, :90-99)
- **Problem:** Step 4 promises to "Preview decisions before changing your mail", but its only feedback is the global status string. The resulting records appear only in Activity, which doesn't show until onboarding ends.
- **Scenario:** A user runs "Dry run 20 recent messages", sees "Classified 20 of 20 messages", and has no idea what would have gone to Junk.
- **Fix:** Show a compact result list (subject, sender, verdict) with Junk and Review counts, or a summary with "Show in Activity". Include explicit empty and error states, for example when consent is off.
<!-- sources: design/onboarding-consistency#6 -->

#### 8.34 Rule tables lack standard table affordances; removal has no confirmation or undo — Medium

- **Where:** `SpamWise/RuleEditorView.swift:48` (RuleEditorView.swift:40-57, ContentRuleEditorView.swift:24-30, :28, :39)
- **Problem:** Neither table supports double-click editing, a context menu, the Delete key or +/− controls. Remove deletes immediately with no confirmation or UndoManager. The content-rule table shows Enabled/Disabled as text rather than as an inline Toggle. Content rules, a peer of sender rules, are reachable only through a loose button.
- **Scenario:** Delete and double-click do nothing, and a mis-clicked Remove loses a rule permanently.
- **Fix:** Add `.contextMenu(forSelectionType:menu:primaryAction:)` with Edit/Remove, `.onDeleteCommand`, and Undo or a confirmation. Use an inline Enabled Toggle, and present sender and content rules as two sections or a segmented control in the Rules tab.
<!-- sources: design/settings#14 -->

#### 8.35 Help out of step with the UI; major features undocumented — Medium

- **Where:** `SpamWise/SpamWise.help/Contents/Resources/en.lproj/how-decisions-are-made.html:6` (correcting-mistakes.html:6-7, what-data-is-sent.html:7, SpamWiseCore/Sources/Classifier/Types.swift:212, ContentRuleEditorView.swift:22, SettingsView.swift:14)
- **Problem:** The precedence page omits content rules, which rank between domain rules and trusted relationships. "Mark as Review" contradicts the menu's "Mark for Review". Help and the consent error say "Account settings", but the tab is "Accounts". No page covers content rules, folders, Review Junk, notifications, backup, the corpus, statistics or Shortcuts. The Help buttons are the only in-app documentation for these features.
- **Scenario:** A user wonders why a message from a Contact was blocked. Help says explicit rules beat Contacts, but describes only sender rules.
- **Fix:** Add content rules to the precedence list. Name controls exactly as the UI does, and change the consent error to "Settings > Accounts". Add short anchored pages for rules, folders, Review Junk, backup and notifications, and keep es/fr in step.
<!-- sources: content#4, comments/core-classifier-learning#18 -->

#### 8.36 Help pages carry developer QA notes and an unshipped CLI — Medium

- **Where:** `SpamWise/SpamWise.help/Contents/Resources/en.lproj/troubleshooting-mail-integration.html:11` (troubleshooting-mail-integration.html:7 and :9, filtering-strength.html:9, correcting-mistakes.html:11, getting-started.html:10; matching es.lproj and fr.lproj pages)
- **Problem:** End-user Help repeats the implementation ledger: notarization and acceptance-test caveats, "keep pending runtime checks visible", rule-of-three statistics, MailKit route status, and an evaluation CLI that no Xcode target ships.
- **Scenario:** A user opens Troubleshooting Mail integration and learns that notarization doesn't prove Mac App Store acceptance, but not what to do. An App Reviewer sees the product describe itself as unverified.
- **Fix:** Rewrite the six pages as task-oriented steps that use current UI labels. Move QA, calibration and CLI material to `docs/`, and regenerate the help indexes for all three languages.
<!-- sources: content#3 -->

#### 8.37 Toolbar actions have no menu commands or keyboard shortcuts — Medium

- **Where:** `SpamWise/ToolsCommands.swift:9` (ToolsCommands.swift:9-18, ContentView.swift:60-117, DecisionDetailView.swift:150-154)
- **Problem:** The HIG says every toolbar item should also be a menu command, because toolbars can be hidden, customized or overflowed. Pause/Resume, Dry run, Review digest, Review Junk, Statistics and the inspector toggle have neither a menu command nor a shortcut. View → Show Inspector is missing, and corrections can't be driven from the keyboard.
- **Scenario:** A user whose localized toolbar overflows has no menu path to Pause. A power user triaging 50 rows must mouse to the inspector for each one.
- **Fix:** Add a `CommandMenu("Filtering")` for Pause/Resume, Dry Run Recent Mail, Review Digest and Review Junk. Add `CommandGroup(after: .sidebar)` for Show/Hide Inspector (⌥⌘I) and Statistics. Bind the selected-row corrections through `.focusedSceneValue`, for example ⌘⇧G and ⌘⇧J.
<!-- sources: design/main-window#4 -->

#### 8.38 Package strings depend on hand-copied stale entries in the app catalog — Medium

- **Where:** `SpamWiseCore/Package.swift:12` (SpamWise/Localizable.xcstrings:6906, :8962, :8979; Signals/EvidenceProcess.swift:12; StateBackup.swift:12; RuleManagement.swift:22; ReviewPriority.swift:8; TODO.md:62)
- **Problem:** The package declares no `defaultLocalization` and has no catalog. Its roughly 82 `String(localized:)` calls lack `bundle:` and resolve against Bundle.main. Their translations exist only because they were hand-copied into the app catalog as `manual` or `stale` entries. The Mail extension has no catalog, so package text shown there is always English, and new package strings ship English-only. The catalog has 705 entries (491 auto, 107 manual, 107 stale). Roughly 60–67 stale entries are dead, such as "%lld/4,000 characters", "Step %lld of 4" and "Recent corrections: %lld". Another 33–40 stale entries are live Core strings, and one active key is unused. Xcode's Remove Stale Items would delete the Core es/fr translations without warning. TODO.md:62 marks es/fr verification complete despite this (see also §8.42). The one missing package key belongs to the Evaluation module, which the app does not import.
- **Scenario:** A maintainer prunes stale items, and a French user then sees an English rule-validation error. A translator fixes a dead `%lld` entry, and the fix never ships.
- **Fix:** Add `defaultLocalization: "en"` and per-target catalogs, and pass `bundle: .module` (or use `LocalizedStringResource`). Then prune the dead stale keys, rebuild so extraction states are accurate, and keep TODO.md:62 open until both are done.
<!-- sources: content#6, config/swift-xcode#21, conventions/core-pipeline-store#6, todo/roadmap#7, conventions/app-views-main#13, conventions/app-views-settings#26 -->

#### 8.39 Configuration history shows raw rule IDs, UUIDs and rawValues — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:69` (CorpusManagement.swift:96 and :114, RuleManagement.swift:71 and :80, ContentRuleManagement.swift:52 and :61, PipelineCorrections.swift:93-94, AuditTrailView.swift:12 and :21)
- **Problem:** Audit details are written at event time with internal identifiers: `address:`-prefixed rule IDs, content-rule UUIDs, and junk/allow/block rawValues. They are frozen in the language active when the event was recorded, and one import entry isn't localized at all. Search matches English `kind.rawValue`, a value the window never displays.
- **Scenario:** A Spanish user saves a block rule and sees "Saved domain:shop.example: block".
- **Fix:** Persist typed audit events (kind plus payload) and format them at display time with localized titles, such as "Blocked domain shop.example". Show a content rule's field and pattern instead of its UUID, and search the localized text.
<!-- sources: content#7 -->

#### 8.40 Statistics accepts an inverted date range without feedback — Low

- **Where:** `SpamWise/ActivityStatisticsView.swift:32` (:33; ActivityDateFilterView.swift:17)
- **Problem:** The Statistics From/Through pickers have no `in:` range, unlike the Activity filter's `.disabled(start > end)`, and the chart has no empty state.
- **Scenario:** With From after Through, the sheet shows "Decisions 0" and a blank chart, which reads as "no mail".
- **Fix:** Constrain the pickers, share one date-range control with the Activity filter, and add a ContentUnavailableView for an empty chart.
<!-- sources: design/main-window#30 -->

#### 8.41 Key verification adds a fake "SpamWise setup" row to Activity — Low

- **Where:** `SpamWise/AppModelCredentials.swift:50` (:50-63; DecisionDetailView.swift:156 and :168)
- **Problem:** Verification records a DecisionRecord with sender "SpamWise setup" and path "verification". It inflates Today and the statistics, and its correction controls are disabled.
- **Scenario:** A new user's first Activity row looks like a real email that was filtered.
- **Fix:** Record verification cost in the spending ledger and show the result in the key status. Otherwise, filter `verification` out of Activity, statistics and Today.
<!-- sources: design/onboarding-consistency#29 -->

#### 8.42 App Shortcut phrase translations still `needs_review` — Low

- **Where:** `SpamWise/AppShortcuts.xcstrings:4`
- **Problem:** The only phrase, "Check ${applicationName} status", is `new` in en and `needs_review` in es and fr, with a single phrasing per language.
- **Scenario:** French Siri users must say exactly "Vérifier l’état de SpamWise", and Xcode reports the phrase as not fully localized.
- **Fix:** Review the translations and mark them translated, then add one or two natural alternatives per language.
<!-- sources: content#19 -->

#### 8.43 Configuration history: plain TextField search, no title, no empty state — Low

- **Where:** `SpamWise/AuditTrailView.swift:17` (:12, :18-22)
- **Problem:** The sheet uses an unstyled TextField, unlike the main window's `.searchable`. It has no title or empty overlay and can't be sorted.
- **Scenario:** On a fresh install, Tools → Configuration history shows an untitled empty grid and a bare text box.
- **Fix:** Use a NavigationStack with `.navigationTitle("Configuration History")` and `.searchable`. Add ContentUnavailableView for no events and for no results, a localized Kind column, and `sortOrder`.
<!-- sources: design/main-window#22 -->

#### 8.44 Shortcuts intents require a typed Request UUID — Low

- **Where:** `SpamWise/AutomationIntents.swift:29` (:33, :56, :137)
- **Problem:** Replay protection is exposed as a required free-text "Request UUID" parameter with developer error copy. Ordinary users would need a separate Generate UUID step. Per verifiers, a reused UUID with a different selected message throws `staleMessage` rather than replaying the earlier reply.
- **Scenario:** A user adds Correct Selected Mail, enters "1" or nothing, and gets "Use a generated UUID for each new operation…".
- **Fix:** Make the parameter optional, generate a UUID when it's omitted, and leave it out of the ParameterSummary. Keep explicit IDs for scripted retries.
<!-- sources: distribution/product#16, design/onboarding-consistency#22 -->

#### 8.45 Activity table: no context menu, double-click, sorting or filtered empty state — Low

- **Where:** `SpamWise/ContentView.swift:35` (:48)
- **Problem:** The table has no `.contextMenu(forSelectionType:)`, `primaryAction` or `sortOrder`, and selection is single. The empty overlay tests unfiltered records, so a search with no matches shows a blank table.
- **Scenario:** A search for "invoice" with no matches shows empty stripes, and a power user can't right-click a row to mark it Junk.
- **Fix:** Add a context menu with corrections, Open in Mail and Preview, with double-click as the primary action. Show `ContentUnavailableView.search(text:)` for empty results, and consider multi-select.
<!-- sources: design/main-window#23 -->

#### 8.46 A correction adds a second row; the original keeps its old verdict — Low

- **Where:** `SpamWise/ContentView.swift:43` (SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift:68-89)
- **Problem:** `correct()` sets `correctedLabel` on the original row and appends a new "correction" record, while the Verdict column shows `decision.label`. Nothing links the two rows, and selection stays on the stale one. The duplicate does serve as an audit trail.
- **Scenario:** After marking a Review row as Junk, the same subject appears twice, once as Review and once as Junk.
- **Fix:** Show `correctedLabel ?? decision.label` with a Corrected indicator (`arrow.uturn.backward` plus `.help`). Group or hide standalone correction rows, and move selection to the updated record.
<!-- sources: design/main-window#13 -->

#### 8.47 Inspector toggle has a fixed "Show details" title and no tooltip — Low

- **Where:** `SpamWise/ContentView.swift:114` (:125)
- **Problem:** Selecting a row already opens the inspector, so the toggle usually hides details while VoiceOver still says "Show details". The icon-only item has no `.help`. `sidebar.trailing` is the semantic variant Apple uses, although none of the shipped languages is right-to-left.
- **Scenario:** With the inspector open, VoiceOver announces "Show details, button", and activating it hides them.
- **Fix:** Use `Button(showsInspector ? "Hide details" : "Show details", systemImage: "sidebar.trailing")` with a matching `.help`.
<!-- sources: gap/sf-symbols-visual-system#5 -->

#### 8.48 Status footer spans beneath the inspector column — Low

- **Where:** `SpamWise/ContentView.swift:119` (:34, :126)
- **Problem:** `.inspector` is applied to the Table inside a VStack, and the footer is a sibling below it. The full-height inspector column is crossed by the footer's divider and text, as en-inspector-failed.jpg shows; the screenshot is older, but the layout is unchanged.
- **Scenario:** With the inspector open, "Today: 2 Month: $0.00" sits on the inspector background.
- **Fix:** Attach `.inspector` to the outer container, or place the status in `.safeAreaInset(edge: .bottom)` on the Table. Verify at minimum width.
<!-- sources: design/main-window#24 -->

#### 8.49 Corpus import accepts any file; more than 20 files reported as oversize — Low

- **Where:** `SpamWise/CorpusView.swift:65` (:82; DecisionDetailView.swift:84)
- **Problem:** The importer uses `[.data]` although the button says ".eml files". Picking more than 20 files, or having no store, throws `ParseError.tooLarge` ("The message exceeds the supported content limits."). The .eml export also uses `.data`.
- **Scenario:** A user selects 25 messages and then hunts for one that is "too large".
- **Fix:** Use `[.emailMessage]` for both import and export, and validate the count up front ("Choose up to 20 messages at a time"), or batch the import.
<!-- sources: design/main-window#21 -->

#### 8.50 Error and status rows use the warning glyph inconsistently — Low

- **Where:** `SpamWise/DecisionDetailView.swift:33` (DecisionDetailView.swift:28, MailHealthView.swift:43, MailConnectionView.swift:12)
- **Problem:** The Junk action error is a `Label` with `exclamationmark.triangle`, but the mark-as-read error two rows below and per-account scan failures are bare Text. The Mail connection status looks the same whether access was granted or denied.
- **Scenario:** A failed mark-as-read reads like explanatory copy and is missed. "Not authorized to send Apple events to Mail" looks like a success message.
- **Fix:** Use the warning Label for `readStatusError` and `health.failure`. Render Mail status as `exclamationmark.triangle` or `checkmark.circle` depending on `mailPermissionDenied`. Consider a shared `StatusLabel` view.
<!-- sources: gap/sf-symbols-visual-system#4 -->

#### 8.51 Every inspector shows "Threat assessment: Not assessed" — Low

- **Where:** `SpamWise/DecisionDetailView.swift:35` (:101-103; SpamWiseCore/Sources/SpamWiseCore/PipelineThreatAssessment.swift:16)
- **Problem:** No detector ships, so every record shows a top-level "Not assessed" section and a safety caveat above the correction controls. The distinction is deliberate, but for typical users it is clutter.
- **Scenario:** Every inspected row pushes "Correct this decision" further down the narrow inspector.
- **Fix:** Render the section only when a finding is not unknown, and move the coverage note into Decision details. Show any real finding near the verdict with `exclamationmark.shield`.
<!-- sources: design/main-window#14 -->

#### 8.52 Good/Junk/Review have no shared symbol; verdict has no visual weight — Low

- **Where:** `SpamWise/DecisionDetailView.swift:225` (DecisionDetailView.swift:21-22 and :150-155, MailMenuView.swift:12-23, LocalizedLabels.swift:35-43, AutomationIntents.swift:10-12)
- **Problem:** VerdictBadge, the correction buttons, the menu items and the Shortcuts enum are all text-only, although these labels mirror Mail's own `xmark.bin` and flag glyphs. In the inspector the verdict has the same body style as the reason beneath it. Icons here would be label shorthand, which the "sparing icons" rule allows.
- **Scenario:** Scanning a long log for Junk means reading every Verdict cell.
- **Fix:** Add `MailLabel.symbolName` (`tray`, `xmark.bin`, `flag`). Use it in a `Label`-based VerdictBadge with `.font(.headline)` in the inspector, in `Button(title, systemImage:)` for the correction controls and menu items, and in `DisplayRepresentation(title:image:)`. Add no color.
<!-- sources: gap/sf-symbols-visual-system#3 -->

#### 8.53 French uses breakable spaces before `:` and `;` — Low

- **Where:** `SpamWise/Localizable.xcstrings:174` (French Help pages)
- **Problem:** Every space before `:`, `;`, `?` and `!` in French values is U+0020; the verifier counted 68, with no non-breaking spaces. `"%@: %lld"` has no space in French at all.
- **Scenario:** In a narrow form, a line wraps so that the next one begins with ": 15 minutes".
- **Fix:** Use U+202F or U+00A0 in the catalog and Help HTML, and give `"%@: %lld"` the French value `"%@ : %lld"`.
<!-- sources: content#14 -->

#### 8.54 Spanish/French glossary inconsistencies and mixed register — Low

- **Where:** `SpamWise/Localizable.xcstrings:3391` (:72, :89, :123, :826, :5127, :5287, :5466, :7763; es how-decisions-are-made.html)
- **Problem:**
  - Good is Deseado in some places and válido or bon in others; Review is Revisar/Por revisar and À vérifier/À examiner.
  - Spanish mixes formal usted ("Seleccione", "Confirme") with tú.
  - French "les comptes ne garantissent pas la livraison" is ambiguous; "décomptes" is clearer.
  - Verifiers judged "código fuente del mensaje" an acceptable email-client term.
- **Scenario:** The same label appears under different names on different screens.
- **Fix:** Settle a glossary (es: Deseado/Revisar/No deseado; fr: Légitime/À vérifier/Indésirables) and apply it to the catalog and Help. Use tú throughout Spanish.
<!-- sources: content#13 -->

#### 8.55 Menu-bar extra cannot be hidden; its status ignores dry run — Low

- **Where:** `SpamWise/MailMenuView.swift:9` (MyApp.swift:23)
- **Problem:** The HIG says people should decide whether a menu-bar extra appears, but `MenuBarExtra` has no `isInserted:` binding or setting. Its status line says "SpamWise is running" in the default dry-run state, while the main window says "Dry run — mail stays unchanged".
- **Scenario:** A new user assumes mail is being filtered when SpamWise is only simulating.
- **Fix:** Reuse the three-state mode text (Paused, Dry run, Filtering). Add `MenuBarExtra(isInserted:)` backed by a General setting.
<!-- sources: design/main-window#29 -->

#### 8.56 Mixed title/sentence case in menus and buttons; jargon in typical-path labels — Low

- **Where:** `SpamWise/MailMenuView.swift:25` (MailMenuView.swift:10-31, ToolsCommands.swift:10 and :15, ContentView.swift:63, :66, :105-106, GeneralSettingsView.swift:24, KeyEntryView.swift:22, AdvancedSettingsView.swift:18, LearningSettingsView.swift:14, MailDestinationView.swift:29, IMAPSettingsView.swift:36)
- **Problem:** "Mark for Review", "Show Activity" and "Quit SpamWise" sit beside "Pause filtering", "Reviewed corpus", "Dry run recent mail" and "Clear filters". macOS uses title case for menu items, push buttons and toolbar items. Typical-path labels also carry jargon such as "Haiku 5.5", "Body budget: ~%lld tokens" and "Bayes"; verifiers judged the "Dry run" wording a copy preference.
- **Scenario:** "Mark for Review" appears directly above "Pause filtering" in the same menu.
- **Fix:** Use title case for menu items, toolbar items and buttons, and sentence case for toggles and descriptive text. Consider "Preview only (don't move mail)" in place of "Dry run", and update the es/fr keys.
<!-- sources: content#16, design/onboarding-consistency#27 -->

#### 8.57 Review Junk list shows only subjects, with no page position — Low

- **Where:** `SpamWise/MailReviewView.swift:30` (:30-36, :46-53; AppModelMailReview.swift:16)
- **Problem:** Triage depends on the sender, but rows show only the subject. The subject-less fallback is "Unclassified message", which collides with the app's classification vocabulary. The paging buttons show no position, although `junkTotal` is available.
- **Scenario:** A user can't tell which "Re: invoice" is from their accountant without clicking each one.
- **Fix:** Use a Table or two-line rows with Sender, Subject and Date, a "(No subject)" fallback, and a "Messages 21–40 of 63" label.
<!-- sources: design/main-window#18 -->

#### 8.58 Setting, provider and app names are inconsistent — Low

- **Where:** `SpamWise/ModelSettingsView.swift:49` (LocalizedLabels.swift:8, SettingsView.swift:22, BackupSettingsView.swift:18 and :52, PolicyView.swift:28, DecisionDetailView.swift:187, FolderSettingsView.swift:15)
- **Problem:** The UI says "Select On-device", but the picker lists "Apple on-device". The policy is "Preferences" on its tab and "policy" in Backup, and "Policy revision" is actually a state counter. The Mail app is called "Mail.app", "Apple Mail" and "Mail".
- **Scenario:** In Backup, a user reads "policy" and can't match it to any tab.
- **Fix:** Quote exact picker titles in instructions, and use one term for the policy, with "Settings revision" for the counter. Call the app "Mail" throughout.
<!-- sources: content#12 -->

#### 8.59 Credential entry implemented three ways with different feedback — Low

- **Where:** `SpamWise/ModelSettingsView.swift:62` (:62-70; KeyEntryView.swift; SpamhausSettingsView.swift:39-47)
- **Problem:** Claude keys use KeyEntryView with verify, save and `keyStatus`. OpenAI and Gemini use an inline SecureField that reports only to the transient global status. Spamhaus has its own `keyStatus`. All three write through APIKeychain.
- **Scenario:** After switching providers, an OpenAI user can't tell whether their key is saved, so they re-enter it.
- **Fix:** Extract one `CredentialEntryView(title:status:save:)`, driven by an AppModel API that reports saved, not saved or error.
<!-- sources: conventions/app-views-settings#18 -->

#### 8.60 Help menu replacement drops ⌘?; Tools items in sentence case; ⌥⌘C conflict — Low

- **Where:** `SpamWise/MyApp.swift:17` (:17-19; ToolsCommands.swift:10 and :15)
- **Problem:** `CommandGroup(replacing: .help)` removes the system item bound to ⌘?, even though Info.plist registers the help book, and the replacement has no shortcut. ⇧⌘/ still opens the Help menu. The Tools items are sentence case without ellipses, and ⌥⌘C overlaps the conventional Copy Style shortcut.
- **Scenario:** Pressing ⌘? doesn't open SpamWise Help directly.
- **Fix:** Remove the override, or add `.keyboardShortcut("?", modifiers: .command)`. Title the items "Reviewed Corpus…" and "Configuration History…", and pick a non-conflicting shortcut.
<!-- sources: design/main-window#28, conventions/app-logic#18 -->

#### 8.61 Menu-bar icon never reflects paused, dry-run or broken state — Low

- **Where:** `SpamWise/MyApp.swift:23` (MailMenuView.swift:9, ContentView.swift:158)
- **Problem:** The only always-visible indicator is a fixed glyph. Paused, dry run and needs-attention (Automation denied, storage not ready) show only as text once a menu or window is open. The HIG doesn't require state glyphs, so this is an improvement rather than a violation.
- **Scenario:** A user pauses filtering, forgets, and spam piles up for days with no ambient cue.
- **Fix:** Use `MenuBarExtra { … } label: { Image(systemName: model.menuBarSymbol) }`, keeping every variant template-rendered (see the inventory). Give the label an accessibility label that names the state, and reuse the symbol in the menu status row and the Activity footer.
<!-- sources: gap/sf-symbols-visual-system#2 -->

#### 8.62 Steppers used for very large ranges — Low

- **Where:** `SpamWise/NotificationSettingsView.swift:17` (:17-21; AdvancedSettingsView.swift:17-22; FolderSettingsView.swift:34)
- **Problem:** The batch interval runs 5–1,440 in steps of 5 (287 steps), the body budget 100–4,000 in steps of 100, and the preview page 0–1,000 one at a time.
- **Scenario:** Changing the interval from 5 minutes to daily takes 287 clicks.
- **Fix:** Use presets for the interval (15 min, 1 h, 4 h, Daily), a labeled Slider for the budget, and a numeric field or paging buttons for the page.
<!-- sources: design/settings#19 -->

#### 8.63 Quiet-hours labels concatenated as 24-hour "13:00" — Low

- **Where:** `SpamWise/NotificationSettingsView.swift:25` (:23-30)
- **Problem:** `Text($0.formatted() + ":00")` is a verbatim concatenation. It ignores the locale and the 12/24-hour preference, which goes against the FormatStyle convention. The hour is a bare Int, and both pickers share one HStack row.
- **Scenario:** An en-US user on a 12-hour clock sees "13:00" instead of "1 PM", and the French labels are squeezed into one row.
- **Fix:** Use `DatePicker(displayedComponents: .hourAndMinute)`, or format a Date with `.dateTime.hour()`, with each picker on its own row. Consider a validated `Hour` type or `DateComponents`.
<!-- sources: design/settings#18, content#15, conventions/app-views-settings#15, design/onboarding-consistency#20 -->

#### 8.64 Quoted-reply stripping recognizes only English reply headers — Low

- **Where:** `SpamWiseCore/Sources/Classifier/Types.swift:314` (:315)
- **Problem:** `unquotedText` recognizes only "On … wrote:" and "-----Original Message-----", so Spanish ("escribió:") and French ("a écrit :") attributions are kept. Lines starting with ">" are still dropped. The patterns are bare literals.
- **Scenario:** A Spanish thread sends its full quoted history to the provider, using up the body budget and sending more third-party text off-device.
- **Fix:** Use a named static table of EN/ES/FR patterns (anchored `Regex`), with a fixture per language in the existing prompt test.
<!-- sources: conventions/core-classifier-learning#15 -->

#### 8.65 Daemon and evaluation CLI output unlocalized and unpluralized — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:106` (SpamWiseDaemon/main.swift:39, :67, :73; SpamWiseEval/main.swift:83; Options.swift:19; RunReport.swift:73; Scripts/evaluate-with-keychain.swift:9; Scripts/store-provider-key.swift:7)
- **Problem:** The output is plain English with no plural handling. Usage text and reports use straight apostrophes. The script errors say "Could not" where the project says "Couldn’t", and SetupKeyError has no category protocol. Standalone scripts have no bundle, so localization matters less there.
- **Scenario:** A one-message run prints "Processed 1 messages; dry run." or "Exported 1 messages".
- **Fix:** Use `String(localized:)` with `format: .number` and plural variants (or `inflect: true`), curly apostrophes, and the project's error pattern.
<!-- sources: conventions/mail-integration#18, conventions/eval-scripts#13 -->

#### 8.66 Required training-folder name rendered without quotes — Info

- **Where:** `SpamWise/FolderSettingsView.swift:78`
- **Problem:** The exact English folder name runs into the sentence ("…named SpamWise Train Good."), and nothing says it must not be translated.
- **Scenario:** A French user creates "SpamWise Entraîner Légitime", and the plan is rejected with a generic error (§8.9).
- **Fix:** Use curly quotes in en/es/fr, and note that the name must be typed exactly as shown.
<!-- sources: content#20 -->

#### 8.67 IMAP TLS port is a free-text String field — Info

- **Where:** `SpamWise/IMAPSettingsView.swift:42` (IMAPConnectionModel.swift:28)
- **Problem:** The port is bound to a String and validated only on Save or Check.
- **Scenario:** A user types "993 " or "imap" and learns it's invalid only after saving.
- **Fix:** Bind to an Int with `TextField(value:format: .number.grouping(.never))`, and show 993 as the prompt.
<!-- sources: design/settings#22 -->
## 9. Temporary code and configuration

Classic leftovers are rare in this codebase. The core has no stray `print` calls outside the two CLIs and no hard-coded test accounts. No keys or message content appear in logs. The UI-test fixtures, the denied and fixture Apple Events runners, `MockClassifier` wiring and fixture seeding are all inside `#if DEBUG`. `spamwise-eval`, `spamwise-daemon` and the Evaluation module are separate targets that the app does not link. No secrets were found in tracked files. Periphery found only 11 unused declarations in the repository, and all package, app and Python checks pass.

The main problem goes the other way. The agent built the project probe by probe, and much of its acceptance and evaluation scaffolding became product behavior instead of staying behind a flag. Two problems are serious:

- **Spending cap.** The owner's one-time $150 evaluation authorization is a lifetime, never-refunded spending ledger. It wraps every paid classification in the app, the Mail extension and the daemon. Filtering stops for good after about 1,500 Haiku calls or 150 calls to any other paid model (§9.2).
- **Probe gate.** The developer's disposable `[SpamWise Probe]` move test is the only way to validate an account. Until an account is validated, nothing scans automatically and dry run cannot be turned off (§9.1).

Smaller versions of the same pattern:

- The Mail extension still runs as a heartbeat probe that classifies but can never act.
- A threat-assessment pipeline runs on every message even though no detector exists.
- An evaluation hold-out silently withholds about 20% of the user's corrections from learning.
- An authentication-server trust feature has no production input.
- Shortcuts intents require a replay-test UUID.

The same history leaks into copy. Settings, the inspector and the Help book in all three languages carry the agent's ledger language: "pending signed timing validation", "provisional until calibrated", "notarization does not prove…", "Authorized ceiling". Diagnostics such as page offsets, raw path identifiers, account IDs and evidence JSON sit in default-visible places.

Build and distribution switches follow the same pattern:

- **`--ui-testing`.** This launch argument is the one test hook still read in Release. Nine reviewers flagged it independently.
- **`APP_STORE`.** It exists only as a command-line override in one script, so an ordinary Xcode archive builds the non-store feature set. That set includes a Private Cloud Compute provider and an `rspamc` transport, neither of which can work in the sandboxed Developer ID app.
- **Direct-update variant.** The update host is blank. The variant depends on a sibling-directory package that exists only on an unmerged local branch, and the tooling reviewer confirmed that a fresh clone fails `xcodebuild -list`.

Repository hygiene is the lowest-risk layer, but there is a lot of it:

- A 68 KB session ledger as `CLAUDE.md`.
- About 30 tracked probe reports that cite gitignored `.build/<uuid>` paths.
- About ten one-off probes mixed into `Scripts/`.
- Xcode multiplatform "MyApp" template residue, some of which ships in the macOS Info.plist.
- Tracked `xcuserdata`.
- About 65 dead string-catalog entries.
- Scripts written around the agent-only `agent-lock` tool.

None of this is dangerous, but together it makes it hard to tell what is product and what is history.

| Item | Location | Reachable in release? | Action |
|---|---|---|---|
| $150 lifetime evaluation ledger | `SpamWiseCore/Sources/SpamWiseCore/EvaluationBudget.swift:27`, `ConfiguredClassifier.swift:56` | Yes; enforced on every paid call | Separate target (spamwise-eval only); productize a user monthly cap if wanted |
| `[SpamWise Probe]` disposable-move validation | `AppleMailAdapter.swift:337`, `IMAPAdapter.swift:177`, `MailConnectionView.swift:51` | Yes; mandatory action gate | Productize (verify real moves; optional self-test) |
| `--ui-testing` launch switch | `SpamWise/AppModel.swift:63`, `NotificationSettingsView.swift:42,53` | Yes | `#if DEBUG` |
| UI-test fixtures and runners (`--ui-automation`, `--ui-corrections`, `--ui-visual-fixture`) | `SpamWise/UITestFixture.swift`, `AppModel.swift:73-112` | No | None (already `#if DEBUG`) |
| `PreviewHelper`, `AppModel(preview:)` | `SpamWise/PreviewHelper.swift:4` | Compiled in, never called | `#if DEBUG` |
| Extension dry-run classification and heartbeat fields; `.mailKit` route; `callbackDeadline` | `MailExtension/MessageActionHandler.swift:21`, `State.swift:8,36,198-201` | Yes | Productize or delete |
| Threat-assessment pipeline with no detector | `PipelineThreatAssessment.swift:15`, `Evaluation/CachedThreatDetector.swift` | Yes; runs per message | Separate target |
| 20% content-hash hold-out partition | `SpamWiseCore/Sources/Learning/LearningState.swift:333` | Yes | Productize as opt-in, or move to separate target |
| PCC provider, `rspamc` executable transport, `/usr/bin/dig` | `DistributionCapabilities.swift:11`, `RspamdLookup.swift:70`, `ExternalEvidence.swift:153` | Yes, in Developer ID builds | Gate on real capability, or `#if DEBUG` |
| `APP_STORE` compilation condition | `Scripts/app-store-check.sh:44` | Only through that script | Productize (build configuration and shared scheme) |
| SpamWiseDirect target and local GitHubUpdateChecker package | `project.pbxproj:876`, `:998` | Builds only on this machine | Productize or delete |
| Evaluation-corpus UI (partitions, label export, retained text) | `SpamWise/CorpusView.swift:21`, `LearningSettingsView.swift:24` | Yes | Separate target, or productize with plain language |
| Development-status copy in Settings and Help | `AdvancedSettingsView.swift:41`, `GeneralSettingsView.swift:18`, `SpamWise.help/` | Yes | Delete or rewrite |
| Required "Request UUID" intent parameter | `SpamWise/AutomationIntents.swift:29` | Yes | Productize (generate internally) |
| Synthetic verification `DecisionRecord` | `SpamWise/AppModelCredentials.swift:50` | Yes | Productize (record in key status) |
| Info-level AppleScript descriptor/permission logs | `AppleMailAdapter.swift:66,87` | Yes | Downgrade to `.debug` or delete |
| Trusted auth-server set with no production input | `SpamWiseCore/Sources/Signals/Evidence.swift:57` | Yes (inert) | Productize or delete |
| Dead API (`MailClientAdapter` requirements, `nextInboxMessages`, `lastReceipt`, `summary`, `Content.plain`, `messageID`, `localizedTitle`, `RetryJob.dryRun`) | various, see §9.30-§9.32 | Compiled in, unreachable | Delete |
| `AppleMailAdapter.export`, public `MockClassifier` | `AppleMailAdapter.swift:353`, `Types.swift:160` | Compiled in; eval/DEBUG callers only | Separate target |
| One-off probe scripts | `Scripts/*-probe.swift`, `Scripts/*-runtime-check.sh`, keychain helpers | No | Separate directory, or delete |
| Probe reports and session ledger | `CLAUDE.md`, `docs/probes/`, `Tools/*/reports`, `Tools/Preferences/*-2026-10-16.json` | No | Delete or archive |
| Xcode template residue (MyApp, `(null)` build files, iOS keys, SpamWiseKit dirs, AccentColor, xcuserdata) | `project.pbxproj:11`, `SpamWise/MyApp.swift`, `Assets.xcassets/AccentColor.colorset` | iOS Info.plist keys ship | Delete |
| Unexplained AppIntents linkage imports | `UnitTests/UnitTests.swift:1`, `MailExtension/MailExtension.swift:1` | Extension import ships | Productize (build setting) or document |
| Stale string-catalog entries | `SpamWise/Localizable.xcstrings` | Shipped in bundle | Delete |
| `agent-lock` worker tokens in scripts | `Scripts/check.sh:3`, `Scripts/ui-check.sh:7` | No | Productize (default token, optional lock) |
| Duplicate eval fixtures | `eval/fixtures/` | No | Delete duplicate copy |

### Findings

| # | Severity | Location | Finding |
|---|---|---|---|
| 9.3 | Medium | `CLAUDE.md:30` | Repo CLAUDE.md is a 68 KB probe ledger rather than project instructions |
| 9.4 | Medium | `MailExtension/MessageActionHandler.swift:21` | Mail extension is a dry-run heartbeat probe; `.mailKit` route is dead |
| 9.5 | Medium | `Scripts/app-store-check.sh:44` | App Store variant exists only as a command-line compilation override |
| 9.6 | Medium | `SpamWise/SpamWise.help/Contents/Resources/en.lproj/troubleshooting-mail-integration.html:11` | Help book ships development and acceptance notes |
| 9.7 | Medium | `SpamWise.xcodeproj/project.pbxproj:876` | Direct-update feature is inert scaffolding; standard build shows a dead "App updates" section |
| 9.9 | Medium | `SpamWise/AdvancedSettingsView.swift:41` | Development-status, probe and troubleshooting copy shown throughout the UI |
| 9.10 | Medium | `SpamWise/AutomationIntents.swift:29` | Shortcuts intents require a user-typed "Request UUID" |
| 9.11 | Medium | `SpamWiseCore/Sources/Learning/LearningState.swift:333` | Evaluation hold-out silently withholds about 20% of corrections from learning |
| 9.12 | Medium | `SpamWiseCore/Sources/Signals/Evidence.swift:57` | Trusted authentication-server set has no production input |
| 9.13 | Medium | `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:16` | Probe naming and evaluation tooling embedded in product modules |
| 9.14 | Medium | `SpamWiseCore/Sources/SpamWiseCore/DistributionCapabilities.swift:11` | Experimental options that cannot work are offered in Developer ID Settings |
| 9.15 | Medium | `SpamWiseCore/Sources/SpamWiseCore/PipelineThreatAssessment.swift:15` | Threat-assessment scaffold runs on every message with no detector |
| 9.16 | Low | `Resources/SpamWiseRule.applescript:1` | Compiled `.scpt` and help indexes are hand-synced build outputs |
| 9.17 | Low | `Scripts/check.sh:3` | Documented build scripts are written around agent-only `agent-lock` tooling |
| 9.18 | Low | `Scripts/swiftdata-probe.swift:1` | One-off probe harnesses mixed into `Scripts/` |
| 9.19 | Low | `SpamWise.xcodeproj/project.pbxproj:11` | Xcode multiplatform "MyApp" template residue, partly shipped in Info.plist |
| 9.20 | Low | `SpamWise.xcodeproj/xcuserdata/tmorgan.xcuserdatad/xcschemes/xcschememanagement.plist:12` | Tracked xcuserdata with phantom schemes; main scheme not shared |
| 9.21 | Low | `SpamWise/AppModel.swift:63` | `--ui-testing` launch argument is honored in Release builds |
| 9.22 | Low | `SpamWise/AppModelCredentials.swift:50` | Key verification writes a synthetic Activity record and hard-codes "Haiku 5.5" |
| 9.24 | Low | `SpamWise/ContentView.swift:84` | Raw path identifiers, account IDs and paging internals shown to users |
| 9.25 | Low | `SpamWise/CorpusView.swift:21` | Evaluation-corpus concepts exposed in Tools menu and Learning settings |
| 9.26 | Low | `SpamWise/Localizable.xcstrings:1` | About 65 stale catalog entries for removed copy |
| 9.27 | Low | `SpamWise/NotificationSettingsView.swift:53` | View branches on the UI-test flag instead of an injected service |
| 9.28 | Low | `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:5` | Undocumented scheduled Gemini price doubling in the compiled price table |
| 9.29 | Low | `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:87` | Probe-era info-level logging on every AppleScript run |
| 9.30 | Low | `SpamWiseCore/Sources/Signals/Gates.swift:40` | Production-dead members (`lastReceipt`, `summary`, `Content.plain`, `messageID`, `localizedTitle`) |
| 9.31 | Low | `SpamWiseCore/Sources/SpamWiseCore/MailClientAdapter.swift:27` | Dead and eval-only entry points in the Mail adapter layer |
| 9.32 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:213` | `RetryJob.dryRun` is always false |
| 9.33 | Low | `SpamWiseCore/Sources/Store/Keychain.swift:27` | Team ID hard-coded in the Keychain access group |
| 9.34 | Low | `Tools/Preferences/audit-2026-10-16.json:14` | Committed probe reports cite ignored local `.build` artifacts |
| 9.35 | Low | `UnitTests/UnitTests.swift:1` | Import-only AppIntents linkage workarounds with no explanation |
| 9.36 | Low | `eval/fixtures/junk/filler-spam.eml:1` | Eval fixtures duplicate the package test fixtures |
| 9.37 | Info | `.gitignore:1` | Untracked template leftovers; ignore rules rely on the global gitignore |
| 9.38 | Info | `SpamWise/PreviewHelper.swift:4` | Preview fixtures compiled into Release |

#### 9.3 Repo CLAUDE.md is a 68 KB probe ledger rather than project instructions — Medium

- **Where:** `CLAUDE.md:30` (whole file; e.g. `:105`, `:123`, `:149`)
- **Problem:** Every agent session loads this file as authoritative instructions, but most of its 68,501 bytes are dated narrative. It records mailbox local IDs, PIDs, notarization submission IDs and test counts, plus 25 references to gitignored `.build/<uuid>` artifacts. The durable rules (contract, module DAG, invariants, commands) are buried in it. The user's own standard is that history belongs in commit messages, and neither SubTrack nor Zephyr has a CLAUDE.md like this.
- **Scenario:** Future agents spend context on stale probe logs, take claims like "33 package tests pass" or "no Important issues" as current, and cite evidence paths that exist on no other checkout.
- **Fix:** Cut it down to the contract, module DAG, invariants and commands. Move the milestone and probe ledger to commit history or an archived doc that is not loaded as instructions.
<!-- sources: temp/repo#9 -->

#### 9.4 Mail extension is a dry-run heartbeat probe; `.mailKit` route is dead — Medium

- **Where:** `MailExtension/MessageActionHandler.swift:21` (also `:30-43`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:8`, `:36-37`, `:198-201`, `SpamWise/AppModel.swift:58`, `SpamWise/LocalizedLabels.swift:97`)
- **Problem:** On every callback, before checking settings, the extension writes `lastExtensionCallback`/`lastBodyCallback`, which the app never reads. With the default `.unverified` route it then runs the full pipeline, including `ConfiguredClassifier`, with `accountID: nil` and `forceDryRun: true`, so the result can never be acted on or deduplicated against the app's records. `IncomingRoute.mailKit` is never assigned, and `Settings.callbackDeadline` has no editor.
- **Scenario:** After onboarding with Claude consent, every incoming message triggers a paid classification that produces an uncorrectable, account-less Activity row and reserves budget (§9.2). Because the store lock is `LOCK_NB`, callbacks during an app sweep can make the app's own transactions fail with `lockUnavailable` and fail open.
- **Fix:** Productize a MailKit route, or make the extension a no-op until there is a trustworthy account bridge: no classification and no per-callback writes. Delete `.mailKit`, `callbackDeadline` and the heartbeat fields, or move the heartbeat into a DEBUG-only diagnostic. If a preview is wanted, gate it behind a setting and skip paid backends.
<!-- sources: temp/core#2, temp/app#15, temp/repo#16 -->

#### 9.5 App Store variant exists only as a command-line compilation override — Medium

- **Where:** `Scripts/app-store-check.sh:44` (also `docs/app-store.md:57`, `SpamWiseCore/Sources/SpamWiseCore/DistributionCapabilities.swift:5,13`, `SpamWise/DirectUpdateModel.swift:1`, `SpamWise/UpdateSettingsView.swift:10`)
- **Problem:** `APP_STORE` is defined only by `SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE` in one script. That override also drops `$(inherited)`. The project has only Debug and Release, and SpamWiseDirect is the only shared scheme. SubTrack and Zephyr define MAS and download schemes and targets.
- **Scenario:** An App Store build made with Product > Archive or `archive.sh` silently includes the PCC provider, the executable Rspamd option and public-DNS Spamhaus that the store build is supposed to exclude, which creates App Review rejection risk with no warning.
- **Fix:** Define the distributions in the project, for example a `Release-MAS` configuration with `$(inherited) APP_STORE`, or separate targets, plus a shared scheme for each, following SubTrack. Then delete the command-line override.
<!-- sources: temp/repo#7 -->

#### 9.6 Help book ships development and acceptance notes — Medium

- **Where:** `SpamWise/SpamWise.help/Contents/Resources/en.lproj/troubleshooting-mail-integration.html:11` (also `:7`, `filtering-strength.html:3,9`, `what-data-is-sent.html:11`, `correcting-mistakes.html:11`, `getting-started.html:9`, and the es/fr equivalents)
- **Problem:** The user Help, in all three languages, contains the developer's release-readiness ledger. Examples: "A successful build or notarization does not prove live Mail callbacks… Keep pending runtime checks visible and use disposable messages for acceptance tests", "MailKit remains dry-run-only", the evaluation CLI and candidate thresholds, "paid-call ceiling starts at $150", and labeled-calibration-corpus export.
- **Scenario:** A user opens Help › Troubleshooting and reads that notarization does not prove Mac App Store acceptance. That is irrelevant to them, makes the product look unfinished, and App Review may read it the same way.
- **Fix:** Rewrite the Help for end users. Move the build, notarization, evaluation-CLI and calibration material to `docs/`, and update the ES and FR pages to match.
<!-- sources: temp/app#11 -->

#### 9.7 Direct-update feature is inert scaffolding; standard build shows a dead "App updates" section — Medium

- **Where:** `SpamWise.xcodeproj/project.pbxproj:876` (also `:871-872`, `:925-931`, `SpamWise/Info.plist:5-10`, `SpamWise/UpdateSettingsView.swift:9-33`, `SpamWiseCore/.../DirectUpdateConfiguration.swift:9`)
- **Problem:** SpamWiseDirect sets `SPAMWISE_UPDATE_OWNER`/`REPOSITORY` to empty strings, so `DirectUpdateConfiguration` is always nil, and its product name shows as "SpamWiseDirect". The notarized artifact is the standard target, which has no updater at all. Even so, General always renders an "App updates" section that says only "Update checks are unavailable in this build." The App Store branch adds an informational section with no control. The shared Info.plist writes empty `SpamWiseDistribution`/`SpamWiseUpdate*` keys into every build, the store archive included. Sharing the store bundle ID is allowed by the contract, but it conflicts if both copies are installed.
- **Scenario:** Every Developer ID user sees, near the top of General, that they cannot get updates, and has no way to learn about new releases.
- **Fix:** Either finish the feature (configure owner and repository, give the variant its own Info.plist and display name, and make it the notarized build) or delete SpamWiseDirect and the `DirectUpdate*` code. Render the section only when `SPAMWISE_DIRECT_UPDATES` is set and configured, and move the update keys out of the shared Info.plist.
<!-- sources: design/settings#10, design/onboarding-consistency#23, temp/app#12, temp/repo#8 -->

#### 9.9 Development-status, probe and troubleshooting copy shown throughout the UI — Medium

- **Where:** `SpamWise/AdvancedSettingsView.swift:41` (also `:35-48`, `SpamWise/GeneralSettingsView.swift:18`, `SpamWise/ModelSettingsView.swift:31`, `:46`, `:75`, `:86-93`, `SpamWise/KeyEntryView.swift:22`, `SpamWise/MailHealthView.swift:36-47`, `SpamWise/MailDestinationView.swift:29`, `SpamWise/MailConnectionView.swift:70`, `SpamWise/RuleFormView.swift:21`, `SpamWise/CorpusView.swift:22`, `SpamWise/DecisionDetailView.swift:35-37`, `:100-103`, `:126`, `SpamWise/AppModel.swift:118`, `:240`, `SpamWise/AppModelErrors.swift:24`, `SpamWise/ActivityStatisticsView.swift:54`, `SpamWise/UpdateSettingsView.swift:28`, `:32`)
- **Problem:** Many captions are the agent's ledger caveats, not user guidance. Examples: "MailKit remains dry-run-only pending signed timing and account identity validation", "Confidence thresholds are provisional until calibrated" (directly under Filtering strength in General), "sidecars", "Authorized ceiling/Conservative commitments", "Next page offset", "Check signing and App Group access", "Check the signed app's shared Keychain entitlement". The inspector also shows a "Threat assessment: Not assessed" section on every row. A few disclaimers, such as "Scores are not calibrated probabilities", are defensible, but most describe internal state the user cannot act on, and many appear in default-visible places.
- **Scenario:** A typical Mail user reads that their thresholds are "provisional" and sees "Next page offset: 40" under their iCloud account. When the App Group fails to open, they are told to check code signing.
- **Fix:** Rewrite captions as user outcomes and errors as user-actionable messages. Remove the calibration, MailKit and validation caveats, and track them in `TODO.md`. Move paging, route, retry and destination diagnostics into one Advanced "Diagnostics" disclosure or the redacted export. Hide the threat section until a detector ships (§9.15), and derive model names from configuration instead of hard-coding them.
<!-- sources: design/settings#9, design/onboarding-consistency#17, comments/app-views-settings#2, temp/app#7, temp/repo#5 -->

#### 9.10 Shortcuts intents require a user-typed "Request UUID" — Medium

- **Where:** `SpamWise/AutomationIntents.swift:29` (also `:56`, `:137`)
- **Problem:** "Preview Selected Mail" and "Correct Selected Mail" declare a required `@Parameter(title: "Request UUID") var requestID: String` so the acceptance harness can test durable replay. `perform()` throws unless the value parses as a UUID.
- **Scenario:** A user adds "Correct Selected Mail" to a shortcut, leaves the UUID empty or types text, and every run fails with "Use a generated UUID for each new operation".
- **Fix:** Generate the request ID inside `perform()` by default. If replay protection must stay, make the parameter optional and label it as advanced, with the explanation in its description.
<!-- sources: temp/app#9 -->

#### 9.11 Evaluation hold-out silently withholds about 20% of corrections from learning — Medium

- **Where:** `SpamWiseCore/Sources/Learning/LearningState.swift:333` (also `:26`, `:112-116`, `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:44-59`, `:83-86`)
- **Problem:** An offline-evaluation hold-out (content-hash prefix divisible by 5, so 52 of 256 prefixes, about 20.3%) is built into the shipping learner. Held-out user corrections never train Bayes or the regularized weights. Held-out corpus imports are left out of both learning and prompt examples, and relabeling one forgets it. `CorpusView` does show a "Held out" count and a Partition column, but the split is on by default and cannot be turned off.
- **Scenario:** A user imports 20 reviewed Junk examples. About four of them contribute nothing, the learner reaches its 20-per-class minimum later than expected, and some corrections seem to have no effect.
- **Fix:** Apply the partition only when spamwise-eval exports or evaluates, or make it an explicit opt-in such as "Reserve 20% of labels for quality measurement", off by default.
<!-- sources: temp/core#4 -->

#### 9.12 Trusted authentication-server set has no production input — Medium

- **Where:** `SpamWiseCore/Sources/Signals/Evidence.swift:57` (also `:66-69`, `:105`, `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift:134-135`, `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:28`, `SpamWiseCore/Sources/Classifier/Types.swift:244`)
- **Problem:** `trustedAuthServers` defaults to `[]`, and the only caller that passes anything else is `SignalsTests.swift:66`. No setting, adapter or state value supplies trusted authserv-ids, so `AuthResult.trusted` is always false in production. That makes the learning contradiction gate, logistic feature index 4 and the prompt's "trusted failure" guidance inert, even though the tests suggest the behavior ships.
- **Scenario:** A provider-stamped `dmarc=fail` is weighted the same as a forged header, and the Bayes gate admits an Inbox verdict the code meant to reject as contradictory.
- **Fix:** Finish the feature by deriving each account's trusted authserv-id from Mail or IMAP configuration, or from a per-account setting. Otherwise remove the flag, its consumers and the prompt sentence.
<!-- sources: temp/core#7 -->

#### 9.13 Probe naming and evaluation tooling embedded in product modules — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/CorpusManagement.swift:16` (also `SpamWise/CorpusView.swift:93`, `Tools/Corpus/`, `Tools/Preferences/`, `Tools/DocumentWorker/`)
- **Problem:** `importMessages` rejects an entire batch if any subject starts with `[SpamWise Probe]`. That is an inline magic string, the import's DocC never mentions it, and the rejection is reported as `ParseError.tooLarge`. Keeping setup probes out of training may be intended, but the exclusion lives on a user-facing path with a misleading error. The same history fills the product repository with research harnesses (`Tools/Corpus` and its reports, `Tools/Preferences`, the `Tools/DocumentWorker` XPC harness). The public raw-mail `export(role:to:)` is covered in §9.31.
- **Scenario:** A user imports reviewed Junk that includes one message with that subject, perhaps a leftover setup probe. The whole import fails with "The message exceeds the supported content limits."
- **Fix:** Remove the check from product import, or extract a shared `isSetupProbe` predicate, throw a dedicated error case with an accurate reason, and document the exclusion. Move the research harnesses into a separate research package or repository.
<!-- sources: architecture#16, conventions/core-pipeline-store#18, comments/core-pipeline-store#2 -->

#### 9.14 Experimental options that cannot work are offered in Developer ID Settings — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/DistributionCapabilities.swift:11` (also `:3-18`, `SpamWise/ModelSettingsView.swift:36-40`, `:75`, `SpamWise/EvidenceSettingsView.swift:52-58`, `SpamWise/AccountSettingsView.swift:10`, `SpamWise/IMAPSettingsView.swift:26-28`, `:43`, `SpamWiseCore/Sources/SpamWiseCore/ConfiguredClassifier.swift:40-44`, `SpamWiseCore/Sources/Signals/RspamdLookup.swift:70-78`, `SpamWiseCore/Sources/Signals/ExternalEvidence.swift:153-158`)
- **Problem:** The capability flags check the distribution channel instead of what actually works. That is backwards for PCC: the doc comment calls it "ungranted… experimental", the entitlements lack it, and `docs/app-store.md:146-150` says only the App Store can ever be eligible, yet only App Store builds hide it. The sandboxed Developer ID app also offers a "Command-line client" Rspamd transport with a free-form `rspamc` path, which the project's own probe shows cannot run. Settings also exposes the IMAP transport with a pasted, non-refreshing OAuth token. The roadmap puts IMAP out of scope, it has never been live-tested, and the privacy and support pages do not mention it. All of these fail open, with no wrong mail action.
- **Scenario:** A Developer ID user picks Private Cloud Compute or the command-line client, and every classification or lookup becomes "unclassified" or unknown, explained only by an entitlement note. A user who switches Connection to IMAP has their validated Apple Mail route reset. Their pasted Gmail token expires within an hour, and IMAP filtering silently stops.
- **Fix:** Hide PCC in all builds until the entitlement is granted, then gate it on a runtime capability check. Keep the executable Rspamd transport out of the sandboxed app, for the CLI/daemon only or behind `#if DEBUG`. Put the IMAP UI behind an explicit experimental flag, or document it in the privacy and support pages if it stays.
<!-- sources: distribution/packaging#15, distribution/product#6, temp/core#5, temp/app#8, temp/repo#6 -->

#### 9.15 Threat-assessment scaffold runs on every message with no detector — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineThreatAssessment.swift:15` (also `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:21`, `SpamWiseCore/Sources/Evaluation/CachedThreatDetector.swift:5`, `ThreatMetrics.swift`, `SpamWiseEval/main.swift:13-43`, `SpamWise/DecisionDetailView.swift:35-37`)
- **Problem:** No production type conforms to `ThreatDetector`, and `TODO.md:38` still lists "Connect a quality-validated production detector". Even so, every successful classification JSON-encodes and hashes the parsed message (up to 100K characters plus headers) into a `ThreatInput` and saves five "unknown" findings in `DecisionRecord.threats`.
- **Scenario:** With 5,000 retained records, the single state blob carries about 25,000 boilerplate findings that are re-encoded on every save. Every inspector shows a threat panel that can never say anything but "Not assessed".
- **Fix:** Store `threats = nil` when no detector is configured. Move `ThreatDetector`, `CachedThreatDetector`, `ThreatMetrics` and `--threat-report` into the Evaluation/tooling target, and hide the inspector section when no detector ran.
<!-- sources: temp/core#3 -->

#### 9.16 Compiled `.scpt` and help indexes are hand-synced build outputs — Low

- **Where:** `Resources/SpamWiseRule.applescript:1` (also `SpamWise/SpamWiseRule.scpt`, `SpamWise/AppModelNavigation.swift:15`, `SpamWise/SpamWise.help/Contents/Resources/{en,es,fr}.lproj/search.cshelpindex`, `Scripts/help-index.sh:6`, `Scripts/archive.sh:16`)
- **Problem:** The app ships the committed binary `SpamWise/SpamWiseRule.scpt`. No build phase compiles it from the source in a top-level `Resources/` folder, which holds only that one file. The two match today only because someone keeps them in sync by hand. The tracked help indexes are rewritten in the source tree on every archive run, while SubTrack gitignores `*.cshelpindex`.
- **Scenario:** Someone edits the `.applescript`, and the Mail rule keeps running the old compiled script. Every `archive.sh` run leaves modified index files in the working tree.
- **Fix:** Compile the script in a Run Script phase (`osacompile -o "$TARGET_BUILD_DIR/…"`) and untrack the `.scpt`, keeping the source next to the app target. Generate help indexes into the product or gitignore them.
<!-- sources: temp/core#11, temp/repo#17 -->

#### 9.17 Documented build scripts are written around agent-only `agent-lock` tooling — Low

- **Where:** `Scripts/check.sh:3` (also `Scripts/ui-check.sh:3-7`, `Scripts/archive.sh:3-5`, `Scripts/store-check.sh:3-4`, `Scripts/app-store-check.sh:3`, `Scripts/evidence-runtime-check.sh:3`, `Tools/DocumentWorker/check.sh:3`, `README.md:17`)
- **Problem:** Every script requires a worker token, with the error "Pass a token from agent-lock worker", and the README's build section leads with `agent-lock worker`. Most scripts accept any string, but `ui-check.sh` calls `agent-lock run ui` directly.
- **Scenario:** A contributor or CI job running `bash Scripts/ui-check.sh` fails with `agent-lock: command not found`, and the documented checks are confusing to anyone who has never used the tool.
- **Fix:** Default the token (`worker="${1:-local}"`), call `agent-lock` only when it is installed, and move the agent workflow into agent-specific notes.
<!-- sources: temp/repo#12 -->

#### 9.18 One-off probe harnesses mixed into `Scripts/` — Low

- **Where:** `Scripts/swiftdata-probe.swift:1` (also `Scripts/document-probe.swift:5`, `Scripts/store-probe.swift`, `Scripts/store-check.sh`, `Scripts/evidence-runtime-probe.swift`, `Scripts/evidence-runtime-check.sh`, `Scripts/rspamd-http-fixture.swift`, `Scripts/rspamd-runtime-check.sh`, `Scripts/store-provider-key.swift`, `Scripts/evaluate-with-keychain.swift`, `Scripts/test_export_store_match.py`)
- **Problem:** The sister repos keep only durable tooling in `Scripts/`. Here release scripts share the directory with about ten investigation probes, which are outside the SwiftLint roots and outside CI.
  - **Superseded:** `swiftdata-probe` (by `store-probe`) and `document-probe` (by the DocumentWorker XPC harness), though both remain the reproduction recipes cited in the docs.
  - **Fragile:** `store-check.sh` compiles `Store.swift` standalone. `document-probe` busy-polls with `Thread.sleep`, and two files declare types named `Result` that shadow `Swift.Result`.
  - **Never run:** `test_export_store_match.py` is not invoked by any script or workflow.
- **Scenario:** Maintainers cannot tell supported workflows from history. The probes rot silently; for example, `store-check.sh` breaks once `Store.swift` gains a dependency. The packaging tests never run.
- **Fix:** Delete the superseded probes, keeping their findings in `docs/probes`, or move all probes to `Tools/Probes/` with a README that marks them historical and add that directory to lint. Wire the Python tests into `check.sh` or CI.
<!-- sources: config/ci-automation#22, conventions/eval-scripts#17, comments/eval-scripts#14, temp/repo#11 -->

#### 9.19 Xcode multiplatform "MyApp" template residue, partly shipped in Info.plist — Low

- **Where:** `SpamWise.xcodeproj/project.pbxproj:11` (also `:12`, `:134`, `:136`, `:222`, `:312`, `:482-588`, `:611`, `:617-626`, `:667-676`, `:706`, `:738`, `:857-866`, `:911-920`, `SpamWise/MyApp.swift`, untracked `SpamWiseKit/`, `SpamWiseKitTests/`)
- **Problem:** The project still carries the multiplatform template:
  - iOS-only `INFOPLIST_KEY_*` settings, which ship `UISupportedInterfaceOrientations~ipad/~iphone`, an empty `UIStatusBarStyle` and `UIApplicationSupportsIndirectInputEvents` in the macOS bundle.
  - Deployment targets for iOS, tvOS, watchOS, visionOS and DriverKit.
  - `productName = MyApp` and `MyApp.swift`.
  - Dangling `(null) in Frameworks` build files.
  - An empty `NSHumanReadableCopyright`.
  - `ENABLE_USER_SELECTED_FILES = readonly`, which contradicts the read-write entitlement.
  - Empty folders from an abandoned SpamWiseKit framework.
- **Scenario:** App Store validation sees meaningless orientation keys. Xcode may rewrite or warn on the null entries. Contributors look for MyApp and SpamWiseKit, which do not exist, and the capability editor shows the wrong file-access mode.
- **Fix:** Delete the iOS keys and non-macOS deployment targets, set `productName = SpamWise` and rename the file to `SpamWiseApp.swift`, and remove the `(null)` entries through Xcode. Set a real copyright or remove the key, align `ENABLE_USER_SELECTED_FILES` with the entitlements, and delete the SpamWiseKit folders.
<!-- sources: config/ci-automation#17, config/swift-xcode#17, temp/repo#13 -->

#### 9.20 Tracked xcuserdata with phantom schemes; main scheme not shared — Low

- **Where:** `SpamWise.xcodeproj/xcuserdata/tmorgan.xcuserdatad/xcschemes/xcschememanagement.plist:12` (also `:27`, `Scripts/check.sh:9`, `Scripts/ui-check.sh:7`, `Scripts/archive.sh:17`, `Scripts/app-store-check.sh:40`)
- **Problem:** Per-user scheme state that names the nonexistent `MyApp` and `SpamWiseKit` schemes is tracked, even though `.gitignore` lists `xcuserdata/`. Meanwhile the `SpamWise` scheme every script uses is Xcode's autogenerated, unshared one, and there is no test plan. The sister repos commit shared schemes.
- **Scenario:** On another machine, or once autocreation stops, `-scheme SpamWise` resolves to a different scheme or none, and which tests it runs is undefined.
- **Fix:** Run `git rm --cached` on the xcuserdata directory, and commit shared schemes (with a test plan) for SpamWise and each distribution variant.
<!-- sources: temp/repo#14 -->

#### 9.21 `--ui-testing` launch argument is honored in Release builds — Low

- **Where:** `SpamWise/AppModel.swift:63` (also `:52`, `:64-72`, `:86-94`, `:233`, `SpamWise/AppModelScanning.swift:78`, `SpamWise/NotificationSettingsView.swift:42`, `:53`)
- **Problem:** The fixtures and runners are `#if DEBUG`, but `uiTesting = preview || arguments.contains("--ui-testing")` is not. In Release the flag still does all of the following:
  - Switches to a UUID-named `UserDefaults` suite that is never removed.
  - Switches to a temporary store.
  - Skips notification setup.
  - Disables monitoring.
  - Makes `checkMail` throw `permissionDenied`.
  The real `SystemAppleEventRunner` and `ConfiguredClassifier` stay in use, and the `preview` path reuses the same flag. This breaks the swiftui-conventions rule that test-mode flags stay out of production paths; SubTrack gates its whole harness. The flag has to be passed deliberately, and the fresh store shows onboarding again, so the impact is local.
- **Scenario:** `open -a SpamWise --args --ui-testing` on the notarized app opens an empty, unpersisted session that never scans and reports Mail permission as denied. Any manual action that reaches Mail has its persisted-before-action record written to a temp directory that is discarded.
- **Fix:** Compute the flag under `#if DEBUG` and use `uiTesting = preview` in Release, or better, inject the test environment from a DEBUG-only factory. Separate `isPreview` from `isUITesting`, and have UI tests remove their defaults suite on teardown.
<!-- sources: config/swift-xcode#16, distribution/packaging#18, security/app-logic#5, correctness/app-logic#18, conventions/app-logic#9, conventions/tests#18, comments/app-logic#5, temp/app#4, temp/repo#3 -->

#### 9.22 Key verification writes a synthetic Activity record and hard-codes "Haiku 5.5" — Low

- **Where:** `SpamWise/AppModelCredentials.swift:50` (also `:17`, `:25`, `:58-62`, `SpamWise/DecisionDetailView.swift:156`, `:168`, `SpamWise/KeyEntryView.swift:22`, `SpamWiseCore/Sources/SpamWiseCore/ConfiguredClassifier.swift:58`)
- **Problem:** Verifying a key inserts a fake "SpamWise setup / API connection verification" `DecisionRecord` into the user's mail decisions, and the inspector special-cases it with the string `"verification"`. "Haiku 5.5" is hard-coded in the copy, and the reservation size keys on the literal `"claude-haiku-5-5"`.
- **Scenario:** The first Activity entry after setup is synthetic and counts toward Today and the statistics. If the default model changes, the copy is wrong and every call reserves $1.00.
- **Fix:** Record verification in key status or the audit trail instead of as a decision. Derive the displayed name from `backend.defaultModelID`, and key pricing on the model catalog.
<!-- sources: temp/app#10 -->

#### 9.24 Raw path identifiers, account IDs and paging internals shown to users — Low

- **Where:** `SpamWise/ContentView.swift:84` (also `:75-82`, `SpamWise/ActivityStatisticsView.swift:34-41`, `SpamWise/MailHealthView.swift:38`)
- **Problem:** The Activity Path filter lists raw, unlocalized pipeline identifiers (`model`, `correction`, `selection`, `verification`). Account pickers show opaque Mail account IDs instead of names, and scan health shows the internal "Next page offset". The brief calls for the evidence detail pane and the context-limit settings, so those stay.
- **Scenario:** A Spanish user opens Filter › Path and sees untranslated English identifiers, and Filter › Account shows a UUID instead of "iCloud".
- **Fix:** Map paths to localized reasons or drop the filter, show account names, and move the paging offset into diagnostics.
<!-- sources: temp/app#6 -->

#### 9.25 Evaluation-corpus concepts exposed in Tools menu and Learning settings — Low

- **Where:** `SpamWise/CorpusView.swift:21` (also `:22`, `:30`, `:37`, `:53`, `SpamWise/LearningSettingsView.swift:24-42`, `SpamWise/ToolsCommands.swift:10-14`)
- **Problem:** Reviewed-corpus import, relabel and forget are legitimate SpamSieve-parity features (SS-11) that feed learning. However, the window and settings also show evaluation machinery: a Training/Held out partition column and count, "Retain reviewed text for evaluation export", JSON label export, and SpamSieve provenance copy. None of it is explained or tucked behind progressive disclosure.
- **Scenario:** A user opens Tools › Reviewed corpus (⌥⌘C) and sees partitions and competitor caveats with no idea what they mean. Or they enable retention, and up to 500 messages are kept only to serve an export.
- **Fix:** Keep import, undo and forget in plain language. Move partition details, retention and labeled export to spamwise-eval or a hidden developer preference, and drop the SpamSieve mention.
<!-- sources: temp/app#5, temp/repo#19 -->

#### 9.26 About 65 stale catalog entries for removed copy — Low

- **Where:** `SpamWise/Localizable.xcstrings:1`
- **Problem:** The catalog has 107 entries marked `stale`, and about 65 of them match no source text: old probe copy, "Model: Claude Haiku 5.5…", "Step %lld of 4", and old threshold text. Some stale-marked keys are still used from SpamWiseCore through `Bundle.main`, so the flag cannot be trusted for cleanup.
- **Scenario:** Translators keep maintaining ES and FR text for removed screens, and real missing translations are hard to spot.
- **Fix:** Delete entries that appear in no source. Give SpamWiseCore its own catalog with `bundle: .module`, so extraction marks those strings correctly.
<!-- sources: temp/app#14 -->

#### 9.27 View branches on the UI-test flag instead of an injected service — Low

- **Where:** `SpamWise/NotificationSettingsView.swift:53` (also `:41-43`)
- **Problem:** The view hard-codes test behavior. With the flag set, status reads "Notifications not requested" and save returns "denied" without saving (`guard !model.uiTesting, …`). Combined with §9.21, a Release launch with `--ui-testing` can never save notification preferences, and tests can never exercise the save path.
- **Scenario:** A UI test that enables notifications always takes the denied branch.
- **Fix:** In UI-test mode, inject a stub `notifications` service into `AppModel` with deterministic `status()`/`authorize()`, and remove the `uiTesting` checks from the view.
<!-- sources: conventions/app-views-settings#8, comments/app-views-settings#9 -->

#### 9.28 Undocumented scheduled Gemini price doubling in the compiled price table — Low

- **Where:** `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift:5` (also `:6`, `:42-43`)
- **Problem:** Gemini rates double at `1_798_761_600` (2027-01-01) through a multiplier with no comment or source. The rest of the compiled table, with `verified: "2026-10-16"`, is a reasonable choice, and costs are already labeled as estimates.
- **Scenario:** If Gemini's schedule changes, every Gemini cost estimate is off by a factor of two until a new release ships.
- **Fix:** Cite the source for the scheduled change in a comment or drop the multiplier, and consider moving the table into a versioned bundled resource.
<!-- sources: temp/core#13 -->

#### 9.29 Probe-era info-level logging on every AppleScript run — Low

- **Where:** `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:87` (also `:66`)
- **Problem:** Every Mail script logs both the permission status and the descriptor type at `.info`. The descriptor-type line was added to debug Boolean decoding. The lines contain no content, and `.info` messages are not persisted by default, but sweeps produce thousands of them.
- **Scenario:** Live log streams captured while diagnosing a user report are dominated by these lines.
- **Fix:** Downgrade both to `.debug`, or remove the descriptor line now that `ScriptValue.decode` handles `typeTrue` and `typeFalse`.
<!-- sources: temp/core#9 -->

#### 9.30 Production-dead members (`lastReceipt`, `summary`, `Content.plain`, `messageID`, `localizedTitle`) — Low

- **Where:** `SpamWiseCore/Sources/Signals/Gates.swift:40` (also `:42-52`, `SpamWiseCore/Sources/MessageModel/MIMEParser.swift:338`, `SpamWiseCore/Sources/MessageModel/Message.swift:22`, `SpamWise/LocalizedLabels.swift:17`, `SpamWise/IMAPSettingsView.swift:27-28`)
- **Problem:** Several members have no production reader:
  - `SenderHistory.lastReceipt` is documented as a receipt timestamp, but nothing ever sets it, so it is always nil.
  - `SenderHistory.summary` is unlocalized, has no plurals ("1 times"), and only tests use it.
  - `MIMEParser.Content.plain` is computed through the whole tree and then discarded.
  - `ParsedMessage.messageID` has no reader.
  - `MailTransport.localizedTitle` is unused because the picker hard-codes the same labels.
- **Scenario:** Someone builds a recency gate on `lastReceipt` and it never fires. Someone surfaces `summary` and ships "1 times". The picker and the label drift apart.
- **Fix:** Delete these members and the `summary` test assertions, or populate and localize whichever ones are wanted. Have `IMAPSettingsView` use `ForEach(MailTransport.allCases)` with `localizedTitle`.
<!-- sources: tooling#5, conventions/core-parsing-signals#15, comments/core-parsing-signals#12, comments/core-parsing-signals#13 -->

#### 9.31 Dead and eval-only entry points in the Mail adapter layer — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/MailClientAdapter.swift:27` (also `:29`, `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift:169`, `:172-175`, `:281`, `:353-364`, `SpamWise/AppModelIMAP.swift:48`, `:51`, `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionFixtures.swift:23-24`)
- **Problem:** Periphery found that no caller uses `recentMessages(limit:)` or the no-argument `importHistory()` through the protocol, yet every conformer and test double must implement them. `AppleMailAdapter.nextInboxMessages(limit:)` is an unused second Inbox pager with its own cursor. The public `export(role:to:limit:)`, which writes raw mail to any directory, has only SpamWiseEval as a caller. (`MockClassifier` is also used by the DEBUG fixture, and `--once` is documented, so both can stay.)
- **Scenario:** Maintainers keep two paging implementations correct, new adapters carry forwarding stubs, and the app binary includes a bulk raw-mail exporter that no feature uses.
- **Fix:** Remove the two protocol requirements along with their forwarders and stubs, delete `nextInboxMessages(limit:)`, and move `export` into SpamWiseEval as an extension over `messages(limit:role:)`.
<!-- sources: tooling#4, temp/core#8 -->

#### 9.32 `RetryJob.dryRun` is always false — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:213` (also `:192`, `:248`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:131`)
- **Problem:** `scheduleRetry` returns early when `forceDryRun` is true, so the only place that constructs a `RetryJob` always stores `dryRun: false`. The field's doc comment ("Whether mail actions must be suppressed") describes a capability that does not exist.
- **Scenario:** New code relies on `job.dryRun` to suppress actions, and the flag never changes anything.
- **Fix:** Remove the field (keeping decoding tolerant of the old key) and pass `forceDryRun: false` explicitly.
<!-- sources: conventions/core-pipeline-store#17 -->

#### 9.33 Team ID hard-coded in the Keychain access group — Low

- **Where:** `SpamWiseCore/Sources/Store/Keychain.swift:27` (also `:29`, `:40`, `SpamWiseCore/Sources/Store/Store.swift:52`, `SpamWiseCore/Sources/SpamWiseCore/ConfiguredClassifier.swift:20-23`, `MailExtension/MailExtension.entitlements:15`)
- **Problem:** The code uses the literal `"2NFSK2WB24.codes.tim.SpamWise.shared"`, while the entitlements resolve `$(AppIdentifierPrefix)` from the signing team.
- **Scenario:** If the app is signed under another team (a fork, a transfer, a CI identity), every Keychain query returns `errSecMissingEntitlement` and paid classification fails because the credential appears to be missing.
- **Fix:** Read the access group from an Info.plist key expanded from `$(AppIdentifierPrefix)` and pass it into `APIKeychain`.
<!-- sources: temp/core#10 -->

#### 9.34 Committed probe reports cite ignored local `.build` artifacts — Low

- **Where:** `Tools/Preferences/audit-2026-10-16.json:14` (also `:18`, `Tools/Preferences/results-2026-10-16.json`, `Tools/Corpus/reports/*.json`, `docs/probes/*.json`, `docs/probes/*.md`, `docs/roadmap-progress.md`, `docs/spamsieve-parity-progress.md`, `docs/conventions-and-design-review.md`, `docs/repository-approval.md`, `docs/automation.md`, `docs/app-store.md`, `Tools/DocumentWorker/README.md`)
- **Problem:** About 30 tracked files are dated outputs of one-off screenings, audits and live probes, and 15 of them cite gitignored `.build/<uuid>` paths that exist only on the author's machine. The site workflow publishes only five staged pages, so none of this goes public, but it clutters `docs/` next to the real product documents.
- **Scenario:** No reviewer can check the cited evidence, and the reports go stale as the tools change.
- **Fix:** Move the reports and logs to a research repository or a single `docs/archive/`, remove the `.build/...` paths, and keep in `docs/` only what users and maintainers act on.
<!-- sources: temp/repo#10 -->

#### 9.35 Import-only AppIntents linkage workarounds with no explanation — Low

- **Where:** `UnitTests/UnitTests.swift:1` (also `MailExtension/MailExtension.swift:1`)
- **Problem:** `UnitTests.swift` consists only of `import AppIntents` and `import Testing`. The Mail extension imports AppIntents without using any of it. The only rationale is a CLAUDE.md milestone note ("Added AppIntents linkage to resolve Xcode metadata warning"), and nothing next to the code explains it. Whether removing either import would bring the warning back is unverified.
- **Scenario:** A cleanup pass deletes the empty-looking file or the unused import. If the metadata warning returns, warnings-as-errors builds fail with no obvious cause, and the extension keeps loading a framework it does not use.
- **Fix:** Replace both imports with an explicit build setting, either linking the framework or disabling App Intents metadata extraction for those targets. If an import must stay, rename the file (for example `AppIntentsLinkage.swift`) and add a one-line comment explaining it.
<!-- sources: conventions/tests#17, comments/tests#9, temp/core#12 -->

#### 9.36 Eval fixtures duplicate the package test fixtures — Low

- **Where:** `eval/fixtures/junk/filler-spam.eml:1` (also `eval/fixtures/good/*.eml`, `eval/fixtures/graymail/unsolicited-newsletter.eml`, `eval/mock-responses.json`, `SpamWiseCore/Tests/SpamWiseCoreTests/Fixtures/*.eml`)
- **Problem:** All five `eval/fixtures` messages are byte-identical copies of the package test fixtures. The offline smoke run feeds the mock model fixed verdicts per fixture hash. `docs/evaluation.md` already says the run does not measure quality, and decisions are recomputed, so it is a plumbing and decision check. The stub test file named in the same source finding is covered in §9.35.
- **Scenario:** An edit to one copy silently diverges from the other.
- **Fix:** Keep a single copy, pointing the eval docs at the test fixtures, and describe the mock run as a plumbing check only.
<!-- sources: temp/repo#18 -->

#### 9.37 Untracked template leftovers; ignore rules rely on the global gitignore — Info

- **Where:** `.gitignore:1` (also untracked `SpamWiseKit/`, `SpamWiseKitTests/`, `.codex/config.toml` and `.bak` copies, `Tools/*/__pycache__`, `Scripts/__pycache__`, `docs/superpowers/`)
- **Problem:** Nothing listed here is committed. However, the root `.gitignore` omits `__pycache__/`, `.codex/` and `docs/superpowers/`, which are ignored only by per-directory files or the user's `~/.gitignore`. (`.ruff_cache` ignores itself.) The empty SpamWiseKit folders remain.
- **Scenario:** On a machine without the same global ignore, `git add -A` commits bytecode, agent configuration with absolute home paths, and planning files.
- **Fix:** Delete the SpamWiseKit folders, and add `__pycache__/`, `.codex/`, `*.xcresult` and `docs/superpowers/` to the root `.gitignore`.
<!-- sources: temp/repo#20 -->

#### 9.38 Preview fixtures compiled into Release — Info

- **Where:** `SpamWise/PreviewHelper.swift:4` (also the `#Preview` blocks in `SpamWise/*.swift`)
- **Problem:** `PreviewHelper` and its synthetic records ship in Release, along with the `AppModel(preview: true)` path that sets `uiTesting`. The swiftui-conventions skill requires PreviewHelper-based previews but does not require DEBUG gating, and no production code calls the helper.
- **Scenario:** A future call site that uses `PreviewHelper` by mistake compiles cleanly in Release and runs a fake model.
- **Fix:** Wrap `PreviewHelper.swift` (and optionally the previews) in `#if DEBUG`, as SubTrack does.
<!-- sources: temp/repo#15 -->

## 10. Architecture and simplicity

The module dependency graph is sound and matches the project contract. SpamWiseCore has no MailKit, SwiftUI or AppKit imports, Signals never imports Store, and Decision is a small pure policy layer. Most individual files are tidy, with named bounds and DocC. The structural problems are one level up, in how modules share state and how often the same idea has been implemented more than once.

Persistence is the central design weakness. SwiftData serves only as a single-row key/value store holding the entire `AppState` as one JSON blob: up to 5,000 decision records, learning samples, retries that carry whole parsed messages, and collections that are never pruned (`claimedActions`, `importedIDs`). Each transaction builds a fresh `ModelContainer` and decodes and re-encodes the whole document, roughly 10 to 12 times per message. The app detects cross-process changes by reloading everything every 3 seconds and assigning a non-Equatable state, which invalidates every observing view. Because the lock is non-blocking, a growing blob makes contention more likely. Contention fails open, so the cost is delayed classification and wasted work, not lost mail.

The second systemic pattern is duplication and reinvented infrastructure. The codebase has two MIME walkers with copied limits that already diverge, four hand-rolled bounded HTTP clients (the RDAP one has none of the hardening), two Rspamd transports to the same loopback daemon, a `dig` subprocess with screen-scraped output, a hand-written IMAP stack, AppleScript generated by string interpolation and recompiled on every call, a model catalog in five places across three targets, retention limits redeclared in up to four files, revision invalidation hand-copied at about 14 sites, and hand-rolled argument parsing in both executables. Each copy is a place where a fix can land without reaching its siblings, and several copies have already drifted.

The third pattern is speculative machinery on the hot path. A `ThreatDetector` with no implementation runs on every message and persists five "unknown" findings. The MailKit extension classifies messages it can never act on. IMAP, statistical learning, dual Rspamd and Spamhaus transports, and the threat-assessment abstraction are all off by default or unvalidated per TODO.md, yet they widen `AppState`, settings and the test surface. Pre-release schema shims (optional fields, an unused `schemaVersion`) spread nil-handling across the codebase.

In the app layer, `AppModel` is a roughly 990-line object across 10 files that owns sheets, statuses, scanning, history import and credentials. It also holds the sweep orchestration the headless daemon needs, so the daemon reimplements that loop with a different "already seen" rule. Views alternate between going through the model and calling Store, Keychain and parser APIs directly.

The architecture reviewer also flagged that the agent's own evaluation budget ledger gates production classification. That leak is covered by the temp-code findings, not repeated here. In order of leverage, the reviewer recommends: redesign the Store into split documents or real entities with change notification; extract a core `MailSweeper`; collapse the MIME, HTTP and transport duplicates; then park the unvalidated features until they are validated.

| Module | Responsibility | Depends on | Notes |
|---|---|---|---|
| MessageModel | Bounded MIME parser, HTML to text, message identity, public-suffix domain resolver, OCR, embedded images, deadline race | none | Deliberate dependency-free parser; EmbeddedImages has a second, divergent MIME walker |
| Signals | Evidence bundle, authentication-header parsing, Contacts, sender and content gates, RDAP, Spamhaus (dig and HTTPS), Rspamd (executable and HTTP), process runner | MessageModel | Holds three of the four bounded HTTP clients; two redundant transports; RDAP fetch unhardened |
| Classifier | Prompt builder; Claude, OpenAI, Gemini and Apple providers; pricing; threat-assessment types | MessageModel, Signals, ClaudeForFoundationModels | Providers share request code reasonably well; model catalog duplicated in five places |
| Decision | Pure threshold-to-action policy | Classifier | Small and clean |
| Learning | Bayes, logistic regression, campaign fingerprints, correction retrieval, policy suggestions | Classifier, Signals, MessageModel | Default off, no labeled data; models refit from scratch per message |
| Store | SwiftData key/value blob, flock, Keychain wrapper | Declares MessageModel, Signals, Classifier, Decision; imports none of them | Single-row JSON document; new ModelContainer per transaction |
| SpamWiseCore | AppState, Pipeline and extensions, rule/corpus/backup/undo management, budget, notifications, automation | All of the above; `@_exported` re-exports all six | Core invariants hold (no MailKit or SwiftUI; Signals does not import Store) |
| MailIntegration | AppleScript Mail adapter and script generators; hand-written IMAP client, TLS transport, daemon configuration | SpamWiseCore | Business logic (history ingestion, probes, eval export) lives inside adapters |
| Evaluation | Offline metrics, comparison and threat reports, response caches | SpamWiseCore | Research tooling, correctly kept out of app products |
| spamwise-eval, spamwise-daemon | Command-line tools | SpamWiseCore, MailIntegration, Evaluation (eval only) | Hand-rolled argument parsing; the daemon duplicates the app's sweep loop |
| App (SpamWise, SpamWiseDirect) | SwiftUI interface, AppModel, App Intents | SpamWiseCore, MailIntegration, GitHubUpdateChecker (local path outside the repository) | AppModel is a god object that also holds the sweep orchestration |
| MailExtension | MailKit message callback | SpamWiseCore | Dry-run only; writes heartbeat fields nothing reads; its route case is never set |

### Findings

| # | Severity | Location | Finding |
|---|---|---|---|
| 10.2 | Medium | `SpamWise/AppModel.swift:10` | AppModel is a god object, and views call persistence directly |
| 10.3 | Medium | `SpamWise/AppModel.swift:159` | Full-store polling every 3 seconds and per-message reloads invalidate every view |
| 10.4 | Medium | `SpamWise/AppModelScanning.swift:107` | Sweep orchestration lives in the app and is reimplemented, divergently, by the daemon |
| 10.5 | Medium | `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:150` | Hand-written IMAP client with duplicated move logic and a forwarding wrapper |
| 10.6 | Medium | `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:130` | AppleScript built by interpolation, recompiled per call, embedding full message source |
| 10.7 | Medium | `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:53` | Two divergent MIME walkers; each message parsed three or four times |
| 10.8 | Medium | `SpamWiseCore/Sources/Signals/RDAP.swift:16` | Four hand-rolled bounded HTTP clients; RDAP fetch unhardened |
| 10.9 | Medium | `SpamWiseCore/Sources/Signals/RspamdLookup.swift:76` | Redundant Rspamd executable transport; DNS lookups scrape `dig` output |
| 10.10 | Medium | `SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift:68` | Revision invalidation hand-copied at 14 sites and applied inconsistently |
| 10.11 | Medium | `SpamWiseCore/Sources/SpamWiseCore/State.swift:163` | Optional-as-migration fields, unused `schemaVersion`, history-style comments |
| 10.12 | Medium | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:129` | Supported-model knowledge duplicated in five places |
| 10.13 | Medium | `SpamWiseCore/Sources/Store/Store.swift:90` | All shared state is one JSON blob in one SwiftData row, rebuilt about 10 times per message |
| 10.14 | Low | `SpamWise/ContentRuleEditorView.swift:136` | Content-rule preview re-implements rule precedence in the view |
| 10.15 | Low | `SpamWise/MailReviewView.swift:30` | Junk review parses raw MIME per row on every render |
| 10.16 | Low | `SpamWiseCore/Package.swift:39` | Store declares unused dependencies; `@_exported` undoes import visibility |
| 10.17 | Low | `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:77` | Learning refits from scratch twice per message; tokenizer reinvents NaturalLanguage |
| 10.18 | Low | `SpamWiseCore/Sources/SpamWiseCore/MailClientAdapter.swift:23` | MailClientAdapter protocol wider than its only generic consumer needs |
| 10.19 | Low | `SpamWiseCore/Sources/SpamWiseCore/NotificationPlanning.swift:53` | "Latest record per message" reduction implemented three times |
| 10.20 | Low | `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:53` | Evidence collection split across two stages; Rspamd runs even when a sender rule decides |
| 10.21 | Low | `SpamWiseCore/Sources/SpamWiseCore/PipelineThreatAssessment.swift:15` | Placeholder threat assessment computed and stored for every message |
| 10.22 | Low | `SpamWiseCore/Sources/SpamWiseCore/State.swift:240` | Resource limits and clamping duplicated across modules and UI |
| 10.23 | Low | `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:151` | Both executables hand-roll argument parsing |
| 10.24 | Info | `SpamWiseCore/Sources/Evaluation/CachedThreatDetector.swift:5` | CachedThreatDetector has no production or CLI caller |

#### 10.2 AppModel is a god object, and views call persistence directly — Medium

- **Where:** `SpamWise/AppModel.swift:10` (`SpamWise/ContentRuleEditorView.swift:68-85`, `:126-157`, `SpamWise/CorpusView.swift:82-111`, `SpamWise/BackupSettingsView.swift:70-86`, `SpamWise/NotificationSettingsView.swift:46-62`, `SpamWise/TrustExclusionsView.swift:21-27`, `SpamWise/SpamhausSettingsView.swift:62-77`)
- **Problem:** One `@MainActor` object with about 30 stored properties across 10 files (about 990 lines) owns the store, pipeline, adapter, scanning, contact refresh, history import, credential checks, IMAP construction, every sheet flag and every status string, and 40+ views take the whole model. The facade is applied unevenly: sender rules, provider keys and folders go through AppModel extensions, while content rules, corpus, backup restore, notifications, trust exclusions and the Spamhaus Keychain key are called from view bodies. This conflicts with swiftui-conventions ("keep logic in view models covered by Swift Testing unit tests").
- **Scenario:** A change to one feature touches a type every view observes. Store and Keychain behavior in the bypassing views can only be checked by UI tests. Previews must build the entire model, with store and pipeline, to show one form.
- **Fix:** Split by feature: a sheet/navigation router, a mail-connection model, a scan coordinator, a corrections model and a settings model, each given only its dependencies. Route every persistence and credential mutation through those models, and pass each view the narrow model it needs.
<!-- sources: architecture#4, conventions/app-views-settings#6 -->

#### 10.3 Full-store polling every 3 seconds and per-message reloads invalidate every view — Medium

- **Where:** `SpamWise/AppModel.swift:159` (`SpamWise/AppModel.swift:6`, `:129-132`, `SpamWise/AppModelScanning.swift:126`, `:136`, `SpamWise/AppModelFolders.swift:121`, `SpamWiseCore/Sources/SpamWiseCore/State.swift:160`)
- **Problem:** `monitor()` calls `refresh()` every 3 seconds, which decodes the whole `AppState`, assigns it unconditionally and loads `MailHealthRepository`. `AppState` is not Equatable, so Observation re-runs every visible body, including the Activity table's filter over up to 5,000 records. During a sweep, `classify` also reloads the full state to confirm a record the pipeline already persisted, then calls `refresh()` again, and folder training reloads per envelope.
- **Scenario:** With a full activity log, the idle app does a full-store decode and table re-filter every 3 seconds. A 20-message page costs more than 40 full decodes under the cross-process lock, slowing sweeps, adding contention with the extension, and making the Activity table stutter while nothing has changed.
- **Fix:** Post a Darwin notification (or bump a small change-counter key) after each commit and reload only when it changes. Make the state Equatable and assign only on a difference. Drop the per-message verify load, and refresh once per page instead of once per message.
<!-- sources: architecture#3, comments/app-logic#16 -->

#### 10.4 Mail sweep orchestration lives in the app target and is reimplemented by the daemon — Medium

- **Where:** `SpamWise/AppModelScanning.swift:107` (`SpamWise/AppModelScanning.swift:37-75`, `:113-124`, `SpamWise/AppModelFolders.swift:54-114`, `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:96-105`)
- **Problem:** The business logic for automatic filtering (seen-message predicate, cursor advancement, health accounting, retry scheduling, training-folder observation) sits in a SwiftUI `@MainActor` model, so the headless daemon has its own simpler loop. The two "seen" predicates already differ: the app reprocesses paused, superseded and dry-run records, while the daemon treats any record as seen.
- **Scenario:** A message first recorded as `.paused` is reprocessed by the app after Resume, but the daemon skips it forever. Fixes to sweep semantics, such as the unreadable-page handling, must be made twice.
- **Fix:** Move the sweep into core (for example a `MailSweeper` actor taking adapter, store, pipeline and scope, emitting progress and health events). Have AppModel and the daemon both call it, with one `AppState.isAlreadyHandled(_:)` predicate.
<!-- sources: architecture#5 -->

#### 10.5 Hand-written IMAP client and TLS transport, with internal duplication and a forwarding wrapper — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift:150` (`IMAPAdapter.swift:12`, `:32`, `:140`, `:144`, `:183`, `:213-233`, `:247-264`, `IMAPProtocol.swift:19-254`, `IMAPTransport.swift:46-140`, `SpamWise/AppModelIMAP.swift:43-57`)
- **Problem:** The project implements an IMAP4 wire parser, literal reader and NWConnection continuation transport from scratch for a feature that is off by default and, per TODO.md, still unvalidated. Within the adapter, `perform` and `probeMove` repeat the select, lookup, `UID MOVE`, COPYUID mapping and re-verify sequence, and the MOVE/IMAP4REV2 capability check appears three times. An actor-local `validated` flag forces `IMAPCorrectionAdapter` to forward four protocol methods just to call `validateReadOnly()` first, and `withSession` opens a new TLS session per call.
- **Scenario:** A fix to COPYUID handling or post-move verification lands in `perform` but not `probeMove`, so the account probe validates behavior production moves no longer have. Each correction on an IMAP account opens two or more TLS connections with LOGIN and CAPABILITY round trips.
- **Fix:** Decide whether IMAP belongs in the product before it is validated. If it stays, adopt swift-nio-imap for parsing, share one `moveAndVerify` helper between `perform` and `probeMove`, use the persisted `IMAPAccountValidation` instead of the in-memory flag, and delete `IMAPCorrectionAdapter`.
<!-- sources: architecture#9 -->

#### 10.6 AppleScript built by string interpolation and recompiled per call, embedding the full message source as a literal — Medium

- **Where:** `SpamWiseCore/Sources/MailIntegration/MailScripts.swift:130` (`MailScripts.swift:158`, `:182`, `:212-265`, `MailFolderScripts.swift:34-76`, `AppleMailAdapter.swift:76`, `:236`, `:245-276`)
- **Problem:** Every Mail operation concatenates the shared helper text with interpolated values and compiles a new `NSAppleScript`. Exact-content checks embed the whole message source, up to 2 MB, into the action, verification and mark-read scripts. The page loop is copied across three scripts, and `folderPage` hard-codes `min(1000, limit)` and `depth > 16` rather than the Swift constants. `literal()` does escape backslash, quote, CR, LF and tab, so injection is not demonstrated; the cost is compile time and fragility.
- **Scenario:** Moving a 1.5 MB newsletter to Junk and marking it read compiles three scripts of about 1.5 MB each under an 8-second timeout. On a busy Mail this plausibly exceeds the deadline (not measured), recording a failure after Mail may already have moved the message.
- **Fix:** Compile one handler library once and invoke handlers with `executeAppleEvent(_:error:)`, passing account, IDs and expectations as `NSAppleEventDescriptor` parameters. Compare content in Swift (have the handler return the source or its size and compare `stableHash` locally), and factor the page loop into one handler.
<!-- sources: architecture#11 -->

#### 10.7 The MIME traversal is implemented twice, and each message is parsed three or four times — Medium

- **Where:** `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift:53` (`EmbeddedImages.swift:6-13`, `:47`, `:98-142`, `MIMEParser.swift:6-13`, `:202`, `:228-257`, `DocumentInspection.swift:30-31`, `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:35-50`)
- **Problem:** EmbeddedImages redeclares MIMEParser's message, header, nesting, part and boundary limits and runs its own header split and multipart walk. The two already diverge: the header limit is `<=` in one and `<` in the other, the close delimiter is matched exactly versus by `hasSuffix("--")`, only MIMEParser rejects control bytes in header names, and EmbeddedImages decodes as UTF-8 where MIMEParser preserves bytes. On the hot path, Pipeline parses once, DocumentInspection parses twice more, and OCR re-walks the raw bytes.
- **Scenario:** A parsing hardening fix or a raised `maximumParts` lands in MIMEParser only, so OCR accepts adversarial structures text extraction rejects, or rejects messages text extraction accepts. A 2 MB message with attachments and OCR enabled is tokenized four times before classification starts.
- **Fix:** Have MIMEParser produce a bounded part tree once (headers plus decoded bytes per leaf) and derive body text, attachment text and image payloads from it in a single walk. Keep only ImageIO validation in EmbeddedImages and remove DocumentInspection's double parse.
<!-- sources: architecture#6, comments/core-parsing-signals#25 -->

#### 10.8 Four hand-rolled bounded HTTP clients, three identical redirect delegates, and an unhardened RDAP fetch — Medium

- **Where:** `SpamWiseCore/Sources/Signals/RDAP.swift:16` (`RDAP.swift:18-21`, `Classifier/ModelHTTPClient.swift:8-33`, `:68-75`, `Signals/RspamdLoopbackHTTP.swift:8-85`, `Signals/SpamhausHTTPS.swift:38-105`)
- **Problem:** The model-provider, Rspamd and Spamhaus clients each repeat the ephemeral configuration, cookie/cache/credential nil-ing, a redirect-refusing delegate and a streamed byte cap. They already differ without documentation: only the loopback client disables proxies, and the intended auth-challenge differences carry no comment. The fourth client, RDAP, uses `URLSession.shared`, follows redirects, uses shared cookie and cache storage, and checks its 2 MB limit only after buffering the whole response. RDAP is opt-in, which limits exposure.
- **Scenario:** An IANA-listed RDAP server redirects to an arbitrary host or streams 200 MB; URLSession follows the redirect and buffers everything before the size check rejects it. A future redirect or proxy hardening fix reaches only some copies.
- **Fix:** Add one internal `BoundedHTTPClient` configured by maximum bytes, timeout, accepted status codes, proxy and auth-challenge policy, owning a single delegate, with the intended differences documented there. Use it for model providers, Spamhaus, Rspamd and RDAP, and delete the three delegates and `URLSessionFetcher`.
<!-- sources: architecture#7, comments/core-parsing-signals#26 -->

#### 10.9 The Rspamd executable transport duplicates the HTTP transport, and DNS lookups spawn and parse `dig` — Medium

- **Where:** `SpamWiseCore/Sources/Signals/RspamdLookup.swift:76` (`Signals/RspamdLoopbackHTTP.swift:29`, `Signals/EvidenceProcess.swift:31-66`, `Signals/ExternalEvidence.swift:153-171`, `SpamWiseCore/AdvancedSettings.swift:79-85`, `SpamWiseCore/Pipeline.swift:56`, `SpamWiseCore/PipelineClassification.swift:170`)
- **Problem:** `rspamc --connect=127.0.0.1:11333` reaches the same daemon the in-process HTTP transport reaches at `127.0.0.1:11333/checkv2`, so the executable path adds process spawning, a settings field, a legacy shim (`selectedRspamdTransport`) and a compile-time distribution split with no capability gain. The public-DNS Spamhaus path shells out to `/usr/bin/dig` and scrapes human-readable text such as `status: NXDOMAIN,`. Both fail safe to unknown.
- **Scenario:** A user configures `rspamcPath` on the Developer ID build; it works there but silently does nothing in the App Store build. A future `dig` output change makes every DBL lookup report unknown.
- **Fix:** Delete `RspamdTransport.executable`, `rspamcPath`, `selectedRspamdTransport` and `EvidenceProcess`, keeping only the HTTP transport. For DNS, drop the public-DNS transport in favor of HTTPS, or query in-process with libresolv `res_nquery`.
<!-- sources: architecture#8 -->

#### 10.10 The revision-invalidation protocol is hand-copied at 14 sites and applied inconsistently — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift:68` (`RuleManagement.swift:79`, `:109`, `ContentRuleManagement.swift:25`, `:49`, `:60`, `CorpusManagement.swift:66`, `:93`, `:111`, `CorrectionUndo.swift:44`, `StateBackup.swift:90-92`, `State.swift:249-273`, `PipelineCorrections.swift:67-68`, `SpamWise/AppModel.swift:337-340`)
- **Problem:** "Stale classification work must never act" is a core invariant, but each mutation re-implements `revision += 1`, retry clearing and auditing by hand. The account-probe site bumps the revision without clearing retries or auditing. Conversely, `editSettings` clears all retries and the correction-undo snapshot on every edit, including cosmetic ones such as the weekly-digest and notification toggles.
- **Scenario:** After an account probe, old-revision retries linger (discarded only lazily) with no audit record. Toggling "Weekly digest" silently drops pending retries and the Undo snapshot, so the Undo button disappears after an unrelated change.
- **Fix:** Add `mutating func invalidatePendingWork(_:detail:)` on `AppState` that bumps the revision, clears retries and undo, and audits. Call it from every policy mutation, and from `editSettings` only when a policy-relevant field changes (strength, policy, limits, backend, consent, scope).
<!-- sources: architecture#12 -->

#### 10.11 Optional-as-migration fields, an unused `schemaVersion`, and history-style comments make state evolution fragile — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:163` (`State.swift:38-51`, `:171-209`, `AdvancedSettings.swift:39-133`, `MailPreferences.swift:16-18`, `LearningState.swift:124`, `Types.swift:25-31`, `ModelTokenPricing.swift:7`, `Pipeline.swift:39`, `PipelineClassification.swift:112`, `PipelineCorrections.swift:97`, `TrainingFolders.swift:50`)
- **Problem:** Synthesized Codable throws `keyNotFound` for any missing non-optional key, so each new field is declared Optional purely to decode older stores. This produces tri-state Bools (`textAttachments`, `domainRegistrationLookup`, `markJunkRead`) and about 57 `== true` / `?? false` / `?? []` compensations. `schemaVersion` is never read. Comments such as "absent in Phase 1 stores" and "legacy labels came from corrections" describe history, which the global CLAUDE.md comment test forbids. The owner's installed app has persisted state, so the store does need a real migration path.
- **Scenario:** A contributor adds a plain `var foo = false` to Settings. Every existing store then fails to decode in `Store.read`, every callback fails open as "persistence or integration unavailable", and the app cannot load state until the store is deleted.
- **Fix:** Give `AppState`, `Settings`, `AdvancedSettings` and `MailPreferences` custom `init(from:)` using `decodeIfPresent(...) ?? default` (or a small default-value property wrapper), and make the fields non-optional. Either use `schemaVersion` for explicit migrations or remove it. Rewrite the comments to describe current behavior.
<!-- sources: conventions/core-pipeline-store#12, architecture#22 -->

#### 10.12 Supported-model knowledge is duplicated in five places — Medium

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:129` (`SpamWiseCore/AdvancedSettings.swift:16-24`, `Classifier/ClaudeClassifier.swift:22-26`, `Classifier/ModelTokenPricing.swift:28-60`, `SpamWiseEval/main.swift:116-132`, `SpamWiseEval/Options.swift:17-18`, `SpamWiseCore/ConfiguredClassifier.swift:5-6`, `:45-61`)
- **Problem:** Model IDs, backends and pricing are hard-coded in `ModelBackend.defaultModelID`, the Claude initializer switch, `ModelTokenPricing.rates`, the daemon's `backend(for:)`, and the evaluator's prefix mapping and usage text. The classifier factory is written twice, and the evaluator repeats the 0.10/1.0 reservation literals that `ConfiguredClassifier` keeps as constants.
- **Scenario:** Adding `claude-haiku-5-6` to the classifier and pricing but not the daemon makes `spamwise-daemon --model claude-haiku-5-6` throw `invalidConfiguration`. Changing the Haiku reservation leaves the evaluator reserving the old amount.
- **Fix:** Introduce one `ModelCatalog` table (id, backend, display name, pricing, provider constructor) in Classifier, derive every lookup and the usage text from it, and expose one `ClassifierFactory.make(modelID:credential:)` used by both the app and spamwise-eval.
<!-- sources: architecture#13 -->

#### 10.13 All shared state is one JSON blob in a single SwiftData row, rebuilt about 10 times per message — Medium

- **Where:** `SpamWiseCore/Sources/Store/Store.swift:90` (`Store.swift:5-9`, `:101-109`, `SpamWiseCore/State.swift:243`, `SpamWiseCore/Pipeline.swift:36`, `:99`, `:136`, `:271`, `:293`, `:303`, `:321`, `SpamWiseCore/PipelineReadStatus.swift:10-43`, `SpamWiseCore/ConfiguredClassifier.swift:26`, `SpamWiseCore/EvaluationBudget.swift:50`, `MailIntegration/AppleMailAdapter.swift:312`)
- **Problem:** SwiftData stores one `StoredValue` row holding the whole `AppState` under `application-v1`: up to 5,000 decision records, 100 retries with full parsed messages, up to 10,000 learning samples, 500 reviewed labels, and the never-pruned `claimedActions` and `importedIDs`. Every read and read-modify-write builds a fresh `ModelContainer` and re-encodes everything under a `LOCK_NB` flock, about 10 to 12 times per message. The design pays for SwiftData without using queries and for a hand-rolled lock without the simplicity of a plain file.
- **Scenario:** After a few weeks the blob reaches several MB, and each message costs about 12 multi-MB encode/decode cycles. Contention with the extension heartbeat and the app's polling increasingly yields `lockUnavailable`. That fails open, so messages are delayed and reprocessed on the next sweep and the UI shows "Shared storage unavailable"; mail is not lost.
- **Fix:** Pick one model and use it fully: real SwiftData entities queried with predicates and paged fetches, or small atomic JSON documents (settings, rules, records, learning, histories) under flock without SwiftData, so hot paths never decode the activity log or learning state. Bound `claimedActions` and `importedIDs` by age, and keep one container or file handle per process.
<!-- sources: architecture#2 -->

#### 10.14 Content-rule preview re-implements rule precedence in the view — Low

- **Where:** `SpamWise/ContentRuleEditorView.swift:136` (`ContentRuleEditorView.swift:132-157`, `SpamWiseCore/Sources/Signals/ContentRules.swift:82`)
- **Problem:** `preview()` stamps `draft.updatedAt = .now`, merges the draft into the candidates and calls `Gates.evaluate` with `contact: nil` and empty history, reproducing in the view the sender-rule-first precedence and the newest-`updatedAt`-wins ordering that core owns. No named API or test pins that behavior.
- **Scenario:** If core switches content-rule ordering to an explicit priority, the pipeline changes but the preview keeps reporting "This rule wins for the selected message" for rules that no longer win.
- **Fix:** Add a core `ContentRules.previewOutcome(of:among:senderRules:message:)` that reuses the pipeline's gate ordering, cover it with Swift Testing, and have the view only map its result to text.
<!-- sources: comments/app-views-settings#8 -->

#### 10.15 Junk review parses up to 2 MB of raw MIME per row on every render — Low

- **Where:** `SpamWise/MailReviewView.swift:30` (`MailReviewView.swift:30-40`)
- **Problem:** The `List` row closure calls `MIMEParser().parse(envelope.raw)` for every row on each body evaluation, and the detail pane parses the selected message again, so selection and status changes re-parse all 20 messages. The pane also lacks `ContentUnavailableView` states and a page indicator.
- **Scenario:** Selecting messages in a page of large HTML newsletters can make the sheet stutter (not measured). An empty Junk folder shows a blank list beside "Select a message".
- **Fix:** Parse once in `loadJunk` into a lightweight row model (subject, sender, text). Add `ContentUnavailableView` states and a "Page n of m" label.
<!-- sources: design/onboarding-consistency#26 -->

#### 10.16 Package manifest declares unused Store dependencies, and `@_exported` re-exports defeat import visibility — Low

- **Where:** `SpamWiseCore/Package.swift:39` (`SpamWiseCore/Package.swift:7-9`, `SpamWiseCore/Sources/SpamWiseCore/Exports.swift:1-6`, `SpamWiseCore/Sources/Store/Store.swift:1-3`, `SpamWiseCore/Sources/Store/Keychain.swift:1-2`)
- **Problem:** Store declares MessageModel, Signals, Classifier and Decision but imports only Foundation, SwiftData, Darwin and Security, contradicting the stated DAG that Store depends only on value types and widening rebuilds. `@_exported import` of all six modules makes every SpamWiseCore client implicitly see them, which undoes the `MemberImportVisibility` and `InternalImportsByDefault` discipline the package enables.
- **Scenario:** An edit to Signals rebuilds Store and everything above it. App and extension files use MessageModel and Classifier symbols without importing them, so a future split of SpamWiseCore breaks dozens of files at once.
- **Fix:** Reduce Store to `dependencies: []`. Replace `Exports.swift` with explicit imports in the files that use each module, or expose a deliberate public API from SpamWiseCore.
<!-- sources: architecture#19, correctness/core-pipeline-store#20 -->

#### 10.17 Learning refits logistic regression from scratch twice per message, and tokenization reinvents NaturalLanguage — Low

- **Where:** `SpamWiseCore/Sources/Learning/StatisticalLearning.swift:77` (`StatisticalLearning.swift:48-55`, `Learning/LearningState.swift:226`, `:288`, `Learning/CorrectionLearning.swift:90-103`, `SpamWiseCore/PipelineClassification.swift:48`, `:78-83`)
- **Problem:** `estimate` and `admitPrediction` each run a full 120-iteration logistic fit over up to 2,000 samples and rebuild Bayes token counts for the same message, treating derived parameters as per-call work. The tokenizer is a hand-rolled split with an English-only stop-word list, although the app ships Spanish and French. The compute cost is milliseconds, not a meaningful share of the deadline.
- **Scenario:** With Bayes enabled, every message repeats two identical fits and count rebuilds. Spanish and French function words pass through as tokens; their effect on scores is unmeasured.
- **Fix:** Cache fitted weights and token counts in `LearningState`, invalidated when samples change, and reuse the message's estimate in `admitPrediction`. Use `NLTokenizer(unit: .word)` with language-specific stop words or none.
<!-- sources: architecture#27 -->

#### 10.18 The MailClientAdapter protocol is wider than its only generic consumer needs — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/MailClientAdapter.swift:23` (`MailClientAdapter.swift:26-29`, `Pipeline.swift:306`, `PipelineCorrections.swift:113`, `PipelineReadStatus.swift:28`, `SpamWise/AppModel.swift:294`, `SpamWise/AppModelIMAP.swift:48-53`)
- **Problem:** The protocol requires `recentMessages(limit:)` and `importHistory()`, but Pipeline uses only `lookup`, `perform` and `markReadInJunk`, and the app calls the concrete adapters' transport-specific overloads. Every conformer and wrapper must implement or forward the unused methods.
- **Scenario:** A new test double must implement history import it never uses. `AppleMailAdapter`'s protocol-level `importHistory()` calls `importHistory(previous: [:])`, silently discarding previous history for any caller that goes through the protocol.
- **Fix:** Narrow Pipeline's dependency to a `MailActionPerforming` protocol (lookup, perform, markReadInJunk). Keep discovery and history on the concrete adapters or in a separate protocol consumed by the sweep coordinator (10.4).
<!-- sources: architecture#20 -->

#### 10.19 The "latest record per message" reduction is reimplemented three times — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/NotificationPlanning.swift:53` (`AdvancedSettings.swift:153-155`, `ActivityQuery.swift:60`)
- **Problem:** Notifications, the Review digest and Activity statistics each group up to 5,000 records by identity and take the newest, on every 3-second notification check and every digest refresh.
- **Scenario:** If "current" changes (for example, to prefer correction records over later dry-run previews), one copy is missed and notifications and the digest disagree with Activity.
- **Fix:** Add `AppState.latestRecords` (or a cached index keyed by `identity.key`) and use it in all three places.
<!-- sources: architecture#26 -->

#### 10.20 Evidence collection is split between two stages, so Rspamd runs even when a sender rule decides — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift:53` (`Pipeline.swift:39-63`, `PipelineClassification.swift:100-123`, `:148-192`)
- **Problem:** The local Rspamd scan runs before the deterministic gates even though its result only feeds the model prompt; RDAP and Spamhaus run later in `enrich`. Attachment text and OCR do need to run early because content rules match on them. The two-phase gate is expressed by calling `Gates.evaluate` twice with placeholder arguments (`contact: nil, history: .init()`, then `rules: []`).
- **Scenario:** For a sender with an explicit allow rule, the full raw message is still sent to the local Rspamd daemon, spending up to 3 seconds of the MailKit budget on a result the gate path ignores.
- **Fix:** Order `process` as parse, attachment/OCR extraction, `senderRuleGate`, `contentRuleGate`, `relationshipGate`, then one evidence collector (Rspamd, RDAP, Spamhaus) before classification. Split `Gates.evaluate` into named `senderRule` and `relationship` helpers.
<!-- sources: architecture#25 -->

#### 10.21 ThreatDetector has no production implementation, yet every message computes and stores five "unknown" findings — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/PipelineThreatAssessment.swift:15` (`Classifier/ThreatAssessment.swift:98-102`, `:132`, `:151-153`, `SpamWiseCore/State.swift:72`, `SpamWise/AppModel.swift:96-102`)
- **Problem:** The app never passes `threatDetector:`, so every message gets `ThreatAssessment.unavailable`, which JSON-encodes and SHA-256-hashes the full threat input and persists five unknown findings in the record. The only conformers are test fixtures and the evaluation cache. The abstraction is intentional groundwork for a TODO item, and the per-record overhead is a few hundred bytes.
- **Scenario:** Every classified message pays for serializing and hashing its whole parsed message, and the shared blob that every transaction re-encodes (10.13) carries placeholder findings across up to 5,000 records.
- **Fix:** Store `threats = nil` when no detector is configured instead of computing a fingerprinted "unavailable" assessment, or keep the protocol and metrics in Evaluation until a real detector exists.
<!-- sources: architecture#14 -->

#### 10.22 Resource limits and clamping are duplicated across modules and the UI — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseCore/State.swift:240` (`State.swift:241`, `:256-263`, `Classifier/ClassificationLimits.swift:8-9`, `SpamWise/AdvancedSettingsView.swift:14`, `:20`, `Types.swift:141-152`, `:278-281`, `:301-304`, `AppleClassifier.swift:81-84`, `RemoteVerdict.swift:45-50`, `PipelineCorrections.swift:4-8`, `:116-121`, `CorpusManagement.swift:6-10`, `StateBackup.swift:24-27`, `:116`, `Pipeline.swift:6`, `ContentRules.swift:58`, `ContentRuleManagement.swift:5`)
- **Problem:** Each file has named constants, but the same bound (correction and token-budget ranges, 200 corrections, 500 labels, 16,000 characters, 100 content rules) is redeclared privately in up to four files, and already-clamped values are re-clamped downstream. Drift already exists: StateBackup allows 8,000 policy characters while ClassificationLimits uses 4,000.
- **Scenario:** Raising the stored-correction cap to 300 in PipelineCorrections leaves `StateBackup.validate` rejecting every backup with more than 200 corrections, so users cannot restore their own backups.
- **Fix:** Define shared retention limits once (a `RetentionLimits` enum next to `AppState`) and reference them from the pipeline, corpus, backup and Settings steppers. Add `Comparable.clamped(to:)`, clamp only at the input boundary, and share one `ParsedMessage.boundedForRetention()` between correction and corpus import.
<!-- sources: architecture#17 -->

#### 10.23 Both executables hand-roll argument parsing instead of using swift-argument-parser — Low

- **Where:** `SpamWiseCore/Sources/SpamWiseDaemon/main.swift:151` (`SpamWiseDaemon/main.swift:10-26`, `:151-191`, `SpamWiseEval/Options.swift:6-27`, `:47-76`)
- **Problem:** The daemon uses a manual flag loop that throws one `invalidConfiguration` for every mistake; the evaluator uses a stride-by-2 parser with string lookups and one `EvaluationError.arguments`. Usage text is maintained by hand. The global CLAUDE.md asks not to reinvent established dependencies.
- **Scenario:** `spamwise-eval --cache` with no value fails with "Invalid arguments. Use --help for usage." without naming the problem, and each new option needs coordinated edits to the allow-list, parser, conflict checks and usage text.
- **Fix:** Add swift-argument-parser; model spamwise-eval as subcommands (corpus, reviewed, export, compare, threat-report) and spamwise-daemon as an `AsyncParsableCommand` with `@Option`, `@Flag` and `validate()`.
<!-- sources: architecture#21 -->

#### 10.24 CachedThreatDetector is public API with no production or CLI caller — Info

- **Where:** `SpamWiseCore/Sources/Evaluation/CachedThreatDetector.swift:5` (`SpamWiseCore/Tests/SpamWiseCoreTests/EvaluationTests.swift:208`, `:222`, `docs/threat-assessments.md:45`, `SpamWiseCore/Sources/SpamWiseEval/main.swift:161`)
- **Problem:** Only tests construct `CachedThreatDetector`. The evaluator builds `Pipeline(store:classifier:)` without a detector, and `--threat-report` only aggregates precomputed observations, yet docs/threat-assessments.md presents the actor under "Cache and evaluation" as part of the workflow. It is `public` only across package targets, since Evaluation is not a product.
- **Scenario:** A reader expects spamwise-eval runs to produce or reuse cached threat assessments, but every evaluation record has an unavailable assessment, and maintainers keep its cache-key schema compatible for no consumer.
- **Fix:** Wire it into an explicit evaluator option (for example `--threat-detector` or `--assess`), or document it as library-only groundwork (or remove it with its test) until a detector is selected.
<!-- sources: correctness/eval-scripts#16, comments/eval-scripts#16 -->
## Appendix A. Method and coverage

59 reviewers ran (56 planned plus 3 gap reviews chosen by a completeness critic; 0 returned no result). They raised 978 findings. Each reviewer's findings were checked by an adversarial batch verifier; critical and high findings, and any finding the batch verifier did not rule on, received independent extra votes with a tiebreaker on disagreement. 965 findings were kept, 13 refuted and 0 could not be verified. Severity is the lower median of the confirming votes.

Critic assessment: File coverage is close to complete. I compared all 344 tracked files (`git ls-files`, data files excluded) against the union of files the reviewers read. Every tracked Swift source, test, script, plist, entitlements file, string catalog, workflow, Help HTML page and Markdown doc was read by at least one reviewer. The only unread items are static assets and generated files, and I checked those myself: - **Help book:** `help.css` uses `Canvas`/`CanvasText` with `color-scheme: light dark`, so dark mode is fine. Each locale's `search.cshelpindex` (23:40) is newer than every page it indexes. - **Site:** `docs/lifecycle.html`, `mail-compatibility.html` and `support.html` are regenerated after their `.md` sources. `site.css` is light-only (minor, cosmetic). - **Spot checks with no new findings:** - AppleScript string escaping: `literal()` covers backslash, quote, CR, LF and tab, and folder paths are interpolated through it. - IMAP: commands are quoted, TLS is implicit and verified. - Backup encryption: random 256-bit key with AES-GCM, authenticated data supplied. - Keychain items: data-protection keychain with ThisDeviceOnly accessibility. - App Intents: mutating intents require device authentication. - Privacy manifest: required-reason UserDefaults use is declared. Lens coverage is dense, and many findings are duplicated (the $150 ledger appears about 20 times). Three real gaps remain: 1. **Project brief compliance.** `docs/phase-one-brief.md` is the project's controlling contract under CLAUDE.md, but it was only skimmed. No reviewer checked the implementation against its principles, its 'never user-facing' signal-tier rule, the §5 data-egress list, the §6 UI spec, the §10 quality bar or the §12 still-unverified list. 2. **Third-party code in the trust path.** Two reviewers said they did not review the vendored ClaudeForFoundationModels package, even though it is the default provider and carries the user's API key and full mail content. The sibling GitHubUpdateChecker/GitHubReleaseDiscovery library was read only as `Package.swift`. 3. **SF Symbols and the visual system.** The user asked for this explicitly, but coverage is thin. The few findings are 'weak tab symbols' and 'text-only toolbar'. Only about 12 symbol uses exist in the app, and nobody inventoried symbol choices, color-only status, or the visual consistency of the menu bar extra and status indicators. Runtime claims (tests pass, notarization, live Mail behavior) remain unverified by design. Nothing further can be done about them under the read-only rules.

| Reviewer | Files read | Raised | Kept | Gaps noted |
|---|---|---|---|---|
| tooling | 10 | 10 | 10 | - **UnitTests not run:** running them launches the SpamWise.app test host, which the ground rules forbid. I only confirmed they compile. - **Not done, per instructions:** UI tests,… |
| todo/roadmap | 37 | 10 | 10 | I could not verify any claim that tests or builds pass, or any notarization, signing or install result, because the review was read-only with no building or testing. Live runtime c… |
| todo/spamsieve-a | 45 | 10 | 10 | I did not build, test or run the app (read-only scope), so all runtime claims (live corrections, callback timing, closed-window scanning) rest on the docs and could not be independ… |
| todo/spamsieve-b | 47 | 15 | 15 | I could not check runtime-only claims, because the read-only rules forbid launching the app or Mail, using Apple Events, the Keychain or the network. That covers SS-14 sub-item 2 (… |
| config/ci-automation | 77 | 26 | 26 | I did not build, test or run xcodebuild resolution from a clean clone. That a missing local GitHubUpdateChecker breaks package resolution for the whole project is inferred from Xco… |
| config/swift-xcode | 44 | 23 | 23 | Per the read-only rules, I did not build, archive or test, so I did not check whether a missing local package path fails resolution for the whole project or only for SpamWiseDirect… |
| distribution/packaging | 45 | 18 | 17 | I did no builds, archives, signing, notarytool or altool runs, and made no network calls (read-only rules). Notarization acceptance, Gatekeeper results and the store package's sign… |
| distribution/product | 75 | 18 | 18 | I could not verify runtime behaviour: no builds, app launches, Apple Events or network calls were made. The following are inferred from code only: - How Mail orders messages in the… |
| design/main-window | 20 | 30 | 30 | I did not run the app, so these runtime behaviors are inferred from SwiftUI and AppKit semantics, not observed: dropped and late sheet presentation, MenuBarExtra key equivalents no… |
| design/settings | 30 | 22 | 22 | I did not launch the app or render previews (read-only review). Layout judgments rest on the code plus screenshots whose timestamps postdate the view's last change: rspamd-ui (Evid… |
| design/onboarding-consistency | 55 | 29 | 29 | I didn't build, run or launch the app (read-only rules), so layout judgements rest on the code plus screenshots. Most screenshots in .build/3fd3b409… and the ui-evidence folders pr… |
| content | 88 | 20 | 20 | I did not build or run the app, so I could not check rendered layouts, truncation, or whether Xcode actually compiles the stale catalog entries at runtime. That means the stale-ent… |
| architecture | 96 | 29 | 29 | I read the core package, MailIntegration, both executables' entry points and options, the MailKit extension, all AppModel files and several key views in full. Read only partially o… |
| concurrency | 57 | 16 | 14 | I did not build, test or run anything (read-only rules), so the timing claims (scan durations, lock hold times, main-thread hitches) are inferred from the code and not measured. Ma… |
| privacy-dataflow | 90 | 16 | 16 | Read-only static review; no runtime verification. In particular: - **Runtime behavior not observed:** MailKit invocation under `.unverified`, Mail's scripting message ordering, how… |
| security/core-parsing-signals | 18 | 14 | 14 | I did not build or run the project (read-only rules). The quadratic regex cost was measured with Python's backtracking `re` engine in the scratchpad, not with NSRegularExpression/I… |
| security/core-classifier-learning | 18 | 6 | 6 | I did not review the vendored ClaudeForFoundationModels package. ClaudeClassifier does not use ModelHTTPClient, so the redirect, response-size, cookie and cache protections for Cla… |
| security/core-pipeline-store | 33 | 11 | 11 | I did not build, run or test anything, so the runtime claims are inferred from code. These include lock-contention frequency, state-blob size and transaction latency, and the exten… |
| security/mail-integration | 22 | 11 | 10 | I ran nothing that executes against Mail or the network, so these points are inferred from code only: Mail's runtime behaviour, how Mail lets users remap the Junk/Trash roles, Exch… |
| security/app-logic | 39 | 11 | 11 | I did not read the Mail extension's MessageActionHandler, the AppleScript generation in MailScripts/AppleMailAdapter (I only confirmed that `literal()` escapes backslash, quote, CR… |
| security/eval-scripts | 29 | 6 | 6 | Read-only static review; nothing was built or run, and no Keychain or network access was attempted. I did not check whether legacy-keychain ACLs for items created by `swift` interp… |
| security/tools | 43 | 5 | 5 | I did not build or run anything: no check.sh, no swiftc, no repo tests. The DocumentWorker byte/character mismatch was established by reading the code and the UTF-8/JSONEncoder esc… |
| correctness/core-parsing-signals | 19 | 15 | 15 | I could not run code (read-only, no swift run), so behaviour was established by reading the code. Two points are inferred rather than observed: (a) that swift-foundation's `String(… |
| correctness/core-classifier-learning | 24 | 13 | 13 | I could not verify the Gemini 3.8 Flash and GPT-5.4-mini prices, or the 2027-01-01 Gemini price-doubling date, against live provider pages because network access was not allowed. C… |
| correctness/core-pipeline-store | 34 | 20 | 20 | I could not measure real AppState sizes or lock contention rates. Findings 2 and 3 rest on code-path analysis, not runtime measurement, because building and running were out of sco… |
| correctness/mail-integration | 28 | 17 | 17 | Everything here comes from reading the code. Per the ground rules I did not run the app, Mail, IMAP servers or any tests, so these are unverified: - **Mail's scripting behaviour:**… |
| correctness/app-logic | 44 | 21 | 21 | I could not verify runtime behavior; the review was read-only with no builds or launches. In particular: - Mail's ordering of `messages of mailbox`. It changes where new mail sits … |
| correctness/app-views-main | 39 | 15 | 15 | Read-only: I did not run the app or tests, so the SwiftUI runtime behaviors behind finding #2 (whether a sibling sheet raised while another is presented is dropped or deferred on m… |
| correctness/app-views-settings | 38 | 15 | 14 | I did not build or run anything, so all findings come from reading the code. The SwiftUI runtime claims are unverified: Escape not dismissing the onboarding sheet when it has no ca… |
| correctness/eval-scripts | 36 | 16 | 14 | I did not build, run or test anything, as the read-only ground rules require. These points are unverified as a result: - What Foundation actually does when `.atomic` and `.withoutO… |
| correctness/tools | 48 | 10 | 10 | I did not build or run anything, by assignment: no swiftc/check.sh, no Python unittest, no screen/spaphish runs. So these remain unverified: runtime XPC routing to a live instance … |
| correctness/tests | 44 | 19 | 19 | I ran no tests or builds, per the read-only rules, so pass/fail, flakiness and the UI-timing concerns are inferred from the code, not observed. I traced the production code behind … |
| conventions/core-parsing-signals | 20 | 23 | 21 | I did not build, run or test anything (the review is read-only by assignment), so the ICU/NSRegularExpression progress-callback behavior behind the regex-deadline finding is unveri… |
| conventions/core-classifier-learning | 18 | 17 | 17 | Per the ground rules I did not build or run tests, so I could not confirm whether the `@Guide(description:)` and `.range(...)` macro arguments accept named constants instead of lit… |
| conventions/core-pipeline-store | 31 | 22 | 22 | I did not build or run anything, as required by the read-only rules. Statements that the UI shows raw strings rest on reading the call sites (DecisionDetailView.swift, ContentView.… |
| conventions/mail-integration | 23 | 19 | 19 | I didn't build, test or run anything, by design: it's a read-only review and no tooling was assigned to me. Behavior claims such as the SInt64 truncation and the timeout surfacing … |
| conventions/app-logic | 32 | 21 | 21 | I didn't build or run anything (read-only review), so I didn't verify the runtime claims behind the medium-confidence findings: whether two simultaneous sheets drop one, how much t… |
| conventions/app-views-main | 20 | 22 | 22 | Read-only static review: nothing was built, run or previewed, so the layout and keyboard-shortcut observations are inferred from code and not checked visually. AppModel.swift, Loca… |
| conventions/app-views-settings | 23 | 27 | 27 | I could not check rendered layout, Dynamic Type behavior or VoiceOver output, because the rules forbid launching the app or building. Design observations come from reading the sour… |
| conventions/eval-scripts | 28 | 19 | 19 | I did not build, run or test anything, per the read-only rules. So I did not verify that evidence-runtime-check.sh's `-lSpamWiseCore`/`-I debug` linkage works with current SwiftPM … |
| conventions/tools | 42 | 18 | 18 | I didn't build or run anything, per the read-only rules: no `check.sh`, `swiftc`, `python -m unittest` or model screening. Compile-time effects of adding the upcoming-feature flags… |
| conventions/tests | 42 | 18 | 18 | I could not build or run any tests (read-only mandate), so these claims are not verified: that the tests compile and pass, that Swift Testing reports issues from detached tasks (th… |
| comments/core-parsing-signals | 17 | 27 | 27 | I read the bundled public_suffix_list.dat only for structure: the header with version and commit, and spot checks of its IDN entries. I checked how often doc claims about callers a… |
| comments/core-classifier-learning | 16 | 18 | 17 | I did not build or run anything, per the ground rules, so DocC rendering, and whether these modules produce DocC warnings, is unverified. I did not check that the external Gemini p… |
| comments/core-pipeline-store | 31 | 17 | 17 | No code was built or run, per the read-only rules. The $150 budget finding is based on reading the code; it was not confirmed at runtime. I checked that the limit cannot be raised … |
| comments/mail-integration | 20 | 19 | 19 | I made no builds or runtime checks, per the ground rules. I did not verify the AppleScript error-number semantics against a live Mail session. They are inferred from the Swift mapp… |
| comments/app-logic | 26 | 18 | 18 | The review was read-only: nothing was built or run, so the behavioral consequences in failure scenarios (e.g. `--ui-testing` in Release, stalled training claims) come from reading … |
| comments/app-views-main | 24 | 11 | 11 | I read only the English help pages in full. The es/fr translations are assumed to mirror them; I did not diff them. I didn't build or run the app, so these were not observed at run… |
| comments/app-views-settings | 21 | 11 | 11 | I did not read the Spanish and French Help pages in full. I only confirmed with grep that they contain the same build, notarization and $150 sentences. I read the supporting core f… |
| comments/eval-scripts | 30 | 17 | 16 | I didn't run the CLI, scripts or tests (read-only constraint). The diagnostic text for threat-report failures comes from reading `diagnostic(for:)` and the error definitions, not f… |
| comments/tools | 50 | 16 | 15 | I followed the read-only ground rules, so nothing was compiled or run. The low-confidence compiler-flag finding (`-enable-experimental-feature StrictMemorySafety` vs `-strict-memor… |
| comments/tests | 36 | 14 | 14 | I ran no tests or builds, as the task required. So the claim that the UnitTests target runs in no script comes from reading Scripts/check.sh, Scripts/ui-check.sh and the shared-sch… |
| comments/repo-docs | 45 | 13 | 13 | I skimmed docs/phase-one-brief.md for structure only; it is preserved verbatim and its markdownlint failure is already known. docs/superpowers/plans and specs (about 8 KB) are outs… |
| temp/core | 92 | 13 | 13 | The review was read-only, so I didn't run anything. Two claims are inferred from code plus the project's own probe notes rather than observed: that the rspamc executable transport … |
| temp/app | 72 | 16 | 16 | I did not build or run the app, so these points are unverified: - Which `ENABLE_USER_SELECTED_FILES` value ends up in the signed binary. - Whether the sandboxed app can actually ru… |
| temp/repo | 62 | 20 | 20 | Read-only rules meant no builds, so two claims are unverified: whether a missing local package breaks package resolution for the SpamWise scheme on a clean clone (inferred from Xco… |
| gap/brief-conformance | 31 | 11 | 11 | I did not build, test or run the evaluator, so §10's zero-warning and test-pass claims, and the §9 export helper and cache identity, are unverified beyond reading the code. I did n… |
| gap/dependency-trust-path | 52 | 7 | 7 | I skimmed but did not read line by line the library files that ClaudeClassifier never exercises: AppAttestSession.swift (read the first 140 of 622 lines; App Attest auth is not use… |
| gap/sf-symbols-visual-system | 23 | 7 | 6 | I did not run the app, so menu icon rendering in macOS 27 menus, toolbar tooltip behavior and dark-mode or increased-contrast rendering are inferred from code, not observed. Symbol… |

<details><summary>Findings refuted during verification</summary>

- distribution/packaging#16 — The spamwise://check-inbox URL lets any web page or app trigger a full scan and classification (`SpamWise/AppModelNavigation.swift:8`)
- concurrency#9 — Overlapping refresh() calls on the main actor can overwrite newer state with an older snapshot (`SpamWise/AppModel.swift:129`)
- concurrency#14 — App Intents wrap work in unstructured Tasks, so ordinary task cancellation never reaches the operation (`SpamWise/AutomationIntents.swift:35`)
- security/mail-integration#10 — Apple Mail Junk destination is not checked against Trash, unlike the IMAP path (`SpamWiseCore/Sources/MailIntegration/MailScripts.swift:162`)
- correctness/app-views-settings#15 — Edit/Add sheets read selection state that the body otherwise never reads (possible stale sheet content) (`SpamWise/RuleEditorView.swift:59`)
- correctness/eval-scripts#8 — Report file names are derived by character offset and can be garbled when enumerated paths differ from the root (`SpamWiseCore/Sources/SpamWiseEval/main.swift:247`)
- correctness/eval-scripts#13 — match_password truncates unquoted passwords containing # and diverges from dotenv parsing (`Scripts/notarize-match.py:18`)
- conventions/core-parsing-signals#14 — Content-rule regex deadline is only checked at enumeration callbacks; catastrophic backtracking may not be interruptible (`SpamWiseCore/Sources/Signals/ContentRules.swift:117`)
- conventions/core-parsing-signals#23 — ContactsLookup is a stateless actor wrapping a blocking enumeration (`SpamWiseCore/Sources/Signals/Evidence.swift:112`)
- comments/core-classifier-learning#10 — MailAction doc describes an absence with reviewer-directed "deliberately" (`SpamWiseCore/Sources/Decision/Decision.swift:25`)
- comments/eval-scripts#4 — document-probe.swift's only comment is a reviewer-directed justification, not a description (`Scripts/document-probe.swift:5`)
- comments/tools#6 — Screen report limitation contradicts the false-positive rate it now reports (`Tools/Corpus/screen.py:128`)
- gap/sf-symbols-visual-system#6 — Two empty states use symbols for the wrong concept: an Inbox tray for the Review digest and a filter glyph for sender rules (`SpamWise/ReviewDigestView.swift:16`)

</details>

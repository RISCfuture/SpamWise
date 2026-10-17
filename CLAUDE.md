# SpamWise development

## Contract and architecture

The Phase 1 brief is preserved in `docs/phase-one-brief.md`. The implementation plan supplied in the session controls rule precedence and provisional thresholds where it refines that brief. Work proceeds on `codex/phase-one`; existing app/extension bundle IDs, team `2NFSK2WB24`, and App Group `group.codes.tim.SpamWise` are preserved.

Local package modules: MessageModel (bounded MIME and shared identity), Signals (gates/evidence), Classifier (prompt and provider), Decision (pure action policy), Store (durable state), SpamWiseCore (pipeline), spamwise-eval (CLI). Core has no MailKit or SwiftUI dependency. Integrations belong to app/extension. Swift 6 strict concurrency, macOS 27 minimum. Never expose delete/Trash. Persist before action, fail open on every error. Rules: address > domain > contacts/history. Correction replaces same-scope rule; domain scope must be explicit.

## Integration probes — 2026-10-15

- `xcodebuild -version`: Xcode 27.0 (27A266a); `swift --version`: Swift 6.4. SDK headers confirm `MEMessage.rawData`, no `bodyData`. `MEMessage` exposes no stable account identifier. No arbitrary-mailbox MailKit action or completion/outcome acknowledgement exists.
- Starter build fails Swift 6 checks: mutable/non-Sendable shared MessageActionHandler singleton. Replaced by stateless instance pending integration.
- `security find-identity -v -p codesigning`: initially **0 identities inside the tool sandbox**; unrestricted verification on 2026-10-16 finds six, including Developer ID Application. Signed extension runtime, shared Keychain access, body callback, configured accounts, server-routed Junk, controlled network delays, and cancellation are **not runtime verified**. No credentials/test messages supplied. Do not infer a safe Mail deadline from SDK compilation. Default disabled actions/dry run; route activation requires explicit recorded validation.
- Apple Mail's installed `/System/Applications/Mail.app/Contents/Resources/Mail.sdef` declares source, message id, account id, Sent, flag index and background color. Sandboxed entitlement candidate: automation.apple-events + temporary-exception.apple-events for com.apple.mail, usage description. Automation approval and disposable moves remain unverified. Never inspect Mail's databases or request Full Disk Access. Use Apple Events for initial and incremental history.
- SwiftData reproducible probe: compile `Scripts/swiftdata-probe.swift` with Swift 6.4, initialize a store, start two processes each inserting 50 unique records, then read in a third. Exit codes 0/0, final count **100**. Fresh contexts see committed rows. Under tool sandbox CoreData change notifications emit registration errors; do not rely on notifications. Retain SwiftData, serialize read/modify/write with a process-shared advisory lock and use fresh contexts/read polling. Signed App Group entitlement access remains a separate runtime check.
- Provider source pinned to `0262e1a766c461a4268dcec656eca95dd74cebf8` from <https://github.com/anthropics/ClaudeForFoundationModels> (Apache-2.0). It includes `.haiku5_5`, guided generation, `timeout`, fresh sessions, and measured `session.usage`. Cache reads exposed; cache-write accounting is folded into input so dollar amounts remain estimates. No model fallback is configured. User-supplied `.apiKey` is appropriate here: never bundled, stored only in shared Keychain.
- Current pricing verified against <https://platform.claude.com/docs/en/models/haiku-5-5/overview> and <https://platform.claude.com/docs/en/about-claude/pricing>: under 100K prompt tokens, $0.10/M input, $0.50/M output, $0.01/M cache reads. Cache writes cost more; show estimated cost. No live API test has run.

## Commands

`bash Scripts/check.sh <worker-token>` runs package tests and the warning-free app build using isolated caches. Obtain the token with `agent-lock worker`.

`bash Scripts/ui-check.sh <worker-token>` runs the development-signed XCTest UI flow under the UI lock.

See `docs/evaluation.md` and `docs/packaging.md` for CLI, archive, and notarization commands. Live tests are opt-in only. Default logs must contain no keys or message content. Tool-sandbox builds need approval for Swift compiler caches and macro subprocesses; this is distinct from the application's App Sandbox.

## Milestone ledger

1. Scaffold — package test passes; app and extension build with warnings treated as errors. Added AppIntents linkage to resolve Xcode metadata warning.
2. Message parsing — implemented; fixture checks pass.
3. Gates/evidence — implemented; precedence and unknown evidence checks pass.
4. Classifier — implemented; mock tests and one signed-app Haiku verification pass; representative quality evaluation pending.
5. Decisions — implemented; fail-open, correction, and duplicate-action tests pass.
6. Mail integration — signed Automation connection and settled Inbox/Junk/flag probes verified for iCloud and Google; incoming body callbacks remain unvalidated.
7. UI/corrections — implemented; provisioned UI runner passes offline onboarding, simulated denied Mail permission, dry-run status, Pause, address-rule replacement, explicit domain correction, and retained corrections after action failure. Live Mail acceptance remains pending.
8. Evaluation — implemented and offline-verified; representative calibration corpus pending.
9. Help/packaging — implemented; Developer ID archive/export, notarization, stapling, and Gatekeeper acceptance verified.

Ruling: work in the clean supplied checkout on a new branch, preserving review visibility; no extra worktree needed. Original brief received after initial inspection, copied verbatim. Shared interfaces follow the module dependency DAG; Store depends on value types, pipeline depends on Store, so Signals never imports Store. Runtime prerequisites do not justify guessing a successful route. Implementation supports explicit runtime validation states rather than claiming either route tested.

### MIME selection

Evaluated <https://github.com/miximka/MimeParser> (MIT, Swift 5.3 manifest, MIME resources/tests, no Swift 6 Sendable contract or resource bounds promised) and <https://github.com/igorrendulic/MimeEmailParser> (MIT, latest checkout `0cc9038`, 2020-04-19, Swift 5.2, small XCTest suite, no concurrency contract). Neither establishes bounded adversarial parsing or the five product fixtures. Selected a dependency-free value parser, explicitly limited to 2 MB input, 64 KB headers, 12 nesting levels, 128 parts, text/plain and text/html, QP/base64 and Foundation-supported charsets. Attachments ignored; invalid encodings/ambiguous critical headers fail open. HTML is converted lexically without WebKit or loading resources. The bundled Mozilla Public Suffix List (MPL-2.0, source/license in file) handles wildcard, exception, ICANN and private suffixes; refresh deliberately and rerun boundary tests.

Milestone 2: fixture/domain tests observed failing before implementation, now six test functions (including five fixture cases) pass; warning-free package/app checks pass.

Milestone 3: address/domain precedence and same-scope replacement tested red→green; missing history remains unknown. Evidence parses provider authentication claims without treating an arbitrary sender header as trusted. Contacts denied/unrequested yields unknown. RDAP discovers HTTPS endpoints from IANA, caches successes for seven days and unknowns for one hour; failures never become spam evidence. SwiftData Store uses a nonblocking cross-process lock, fresh container/context, and atomic save; lock contention fails open. Store sharing/rollback and stub-network RDAP tests pass. MIME candidate `miximka/MimeParser` latest checkout `0903ca7` dates to 2023-06-09.

Milestone 4: pinned provider uses `.haiku5_5`, fixed low effort, no fallbacks, bounded 1,024 response tokens, and a fresh guided session per message. Fixed instructions are separate from JSON-escaped preferences/correction quotations and untrusted message data. Default 40 examples and 6,000 body characters (~1,500 tokens), quoted replies removed. Measured input/output/cache counts are recorded; cost remains an estimate because cache-write premiums are not separately exposed. Hard deadline races discard late responses, support cancellation and never wait for an uncooperative provider. Classifier errors are typed; persistent retries are composed with the decision pipeline in milestone 5. Shared Keychain is the only app credential store. Live test requires SPAMWISE_LIVE_API=1 and is skipped by default.

Milestone 4 gate correction: package tests passed, but the first app check failed because Xcode applied both -suppress-warnings and -warnings-as-errors to the external package. Explicit SWIFT_SUPPRESS_WARNINGS=NO resolves the contradictory build settings; rerun required before proceeding.

Milestone 5: 23 test functions pass (live API skipped), app/extension warning-free. Pipeline separates verdict, intended decision, and outcome, persists before dispatch, records at-most-once action claims, and retains claims beyond display-log retention. Failures never request new actions. Review defaults to orange flag; strength 99/95/90 remains uncalibrated. Persistent retry queue holds at most 100 bounded messages, at most 3 retries, exponential 30/60/120-second delays, and 24-hour expiry. Corrections atomically replace address rules by default, bound stored examples, increment revision and invalidate retries. Stale classifier results cannot act. External actions already dispatched cannot be recalled; failed/unknown action acknowledgements are never automatically retried. These may require a manual correction.

Milestone 6: MailClientAdapter provides lookup, bounded history import, recent dry runs and supported actions. Apple Events requires account id, resolves exactly one message, checks source before action, and resolves account-specific special Inbox/Junk mailboxes without guessing names. Generated scripts compile against the installed Mail dictionary; execution/permission/moves remain unverified. MailKit requests rawData and completes via a tested exactly-once guard with a watchdog; it is deliberately dry-run-only pending a trustworthy account bridge and signed timing probes. The AppleScript route can be enabled per account only after the explicit disposable-message probe; no route is declared runtime validated by this implementation session. See docs/probes/runtime-checklist.md. Twenty-eight tests pass; app/extension build without warnings. Integration uses a bounded history window and labels it partial; receipt recognition is a conservative heuristic, not proof of a purchase.

Milestone 7 implementation: four-step onboarding, Activity/detail/corrections, four Settings tabs, pause/dry-run controls, explicit denied-permission states, accessible text statuses, and injected previews. History updates retain and deduplicate earlier imports; monthly estimated charges outlive Activity retention and are not double-counted on outcome updates. Manual dry runs never consume live-action retries. Swift 6 upcoming features and strict memory safety are enabled; C/Objective-C unsafe boundaries are narrowly annotated. Twenty-eight package tests pass (live API skipped); app/extension builds are warning-free. Swift formatting, strict SwiftLint, shellcheck, and YAML lint pass.

Ruling: commit the UI implementation with UI execution explicitly pending — macOS kills UITests-Runner before XCTest connects. Unsigned, ad-hoc, Developer ID, and automatic development-signed launches were attempted; unified logs show Gatekeeper rejection and, for Developer ID, an ineligible runner provisioning profile. No system security controls were disabled. The test remains runnable via `bash Scripts/ui-check.sh <worker-token>` after local runner approval/provisioning is resolved. Cost if unresolved: onboarding and correction UI acceptance is not established.

Probe correction (2026-10-16): unrestricted `security find-identity -v -p codesigning` finds six valid identities, including Developer ID Application for team 2NFSK2WB24. The initial zero-identity observation was tool-sandbox-limited, not evidence of absent credentials. Signed runtime Mail callbacks, API credentials, Automation permission, and disposable mail actions remain unverified.

Milestone 8: added the Evaluation module and labeled-directory CLI, Mail export, explicit mock/Claude model selection, whole/per-path binary confusion counts, graymail separation, original-model confidence buckets, exact one-sided binomial bounds, rule-of-three estimates, candidate thresholds, token provenance, new-call cost, and mismatches with reasons. Cache keys include content, effective prompt/evidence/instructions, model, schema, and mock-response identity; decisions are recomputed. Thirty package tests pass; app/extension warning-free; strict lint passes. The five-fixture offline run has the expected outcomes, and a second run has five cache hits and zero new usage. No live-model quality claim follows from these synthetic responses.

Ruling: use a plain CLI — the installed macOS SDK exposes no Evaluations framework. Keep production thresholds provisional because no representative held-out calibration corpus was supplied; choosing calibrated values from mock fixtures would be invalid. Cost if delayed: live automatic Junk decisions still require user-selected uncalibrated thresholds.

Milestone 9 packaging: six Help pages registered in the app plist, indexed by `hiutil` with named anchors, and verified in the exported bundle. Hardened-runtime archive and Developer ID export succeeded on 2026-10-16. `codesign --verify --deep --strict` passes for the app and nested extension; unrestricted entitlement inspection confirms original bundle IDs, team, sandbox, networking, shared App Group and Keychain group. Tool-sandbox codesign inspection can misleadingly report invalid entitlements; use unrestricted inspection. Match repository investigation found its existing encrypted App Store Connect API key. The helper authenticated with Apple's notarization service using the existing SubTrack MATCH_PASSWORD; no secret was printed or persisted beyond a mode-600 temporary key. Final notarization follows the whole-branch review so the submitted artifact includes any review fixes.

## Whole-branch review and final verification — 2026-10-16

The fresh review of `2a5f21a..c5fc58b` found seven Important issues and one Minor issue; all were accepted and addressed in one fix pass. Field-level settings transactions and an ordered optimistic UI queue preserve Pause/dry-run across rapid edits. Automatic Inbox discovery advances bounded pages and repeats sweeps, so retained first-page mail cannot permanently hide later messages; mailbox mutations may delay discovery until the next sweep. Cursors are process-local and restart from the beginning after relaunch. Manual previews neither replace nor consume live retries. Authorized Contacts refresh hourly while the app runs, and refresh failures/staleness are explicit. Automatic history maintenance pages through Sent and previously classified Inbox mail; unclassified messages and pending retries cannot establish their own receipt gate. Unsupported mailbox syntax fails open rather than extracting a misleading address substring. Distinct MIME alternatives contribute interleaved bounded text. MailKit records heartbeat/body availability but skips classification when the Mail-rule route is selected.

Regression checks reproduced eight assertion failures before the parsing/retry fixes. After the fix pass, all 33 package test functions pass (the opt-in live API test remains skipped), app/extension builds are warning-free, generated AppleScripts compile without executing Mail, and strict SwiftLint reports zero violations. The production Store probe (`bash Scripts/store-check.sh <worker-token>`) runs two processes performing 50 atomic increments each and a third process verifies 100; it passed. This verifies the lock/transaction implementation on a local store, not signed App Group access.

Direct UI inspection launched the Developer ID export with isolated test storage and verified a readable first onboarding page without overlap. Full onboarding/corrections interaction remains unverified: XCTest's runner is rejected before connection, and the available direct UI automation could not obtain an accessible hierarchy. The user observed only a Move to Trash prompt; no system security controls were bypassed. The five-minute fresh-setup acceptance target is not established.

Scope ruling: fingerprints and URI/DNS blocklists remain deferred under the supplied implementation plan and §11; no decisive fingerprint/blocklist gate is claimed. Calibration remains pending a representative held-out corpus. The existing `codex/phase-one` branch is retained locally under the project contract; no merge or push is part of this implementation.

Final packaging result: Apple accepted submission `a64e1cf2-60b7-42f7-bcf6-4b1292c3df11`. Stapling and ticket validation passed; `spctl --assess --type execute --verbose=2` reports **accepted, Notarized Developer ID**. Deep strict signature verification passes for the final app and nested extension. The stapled distribution ZIP is `.build/65e4c22c-94b4-441b-9059-5d9ee9cd0ec2/SpamWise-notarized.zip`. Notarization establishes distribution signing acceptance, not live Mail or model behavior. The final five-fixture offline smoke test again produced two Inbox, two Junk, and one Review using explicit mock responses.

## UI runner resolution — 2026-10-16

Unified logs identify the launch rejection as `taskgated-helper: no eligible provisioning profiles found`. The development-signed runner claimed `com.apple.application-identifier = 2NFSK2WB24.codes.tim.SpamWise.UITests.xctrunner` but contained no embedded profile. Xcode's macOS UI-test product defaults to not requiring provisioning. Setting `PROVISIONING_PROFILE_REQUIRED = YES` on UITests Debug and Release makes automatic signing embed the team's wildcard Mac development profile. XCTest now launches and connects without a security override, certificate replacement, or human approval.

The running test then reproduced a stack-overflow crash during accessibility queries on the API-key page. Removing the custom accessibility-label override from its selectable status text and putting the same prefix in the visible text resolves the crash. The test reads macOS static-text values and the current nested selectable Mail-status text. Temporary crash-recovery handling was removed after diagnosis; the final test launches normally.

`bash Scripts/ui-check.sh c9bb73f1-a63e-4dc1-bc30-c2b388a122fb` passed the existing onboarding/activity test in 10.321 seconds with zero failures. It exercises all four offline setup steps, simulated denied Mail permission, dry-run status, and Pause. The result bundle is `.build/c9bb73f1-a63e-4dc1-bc30-c2b388a122fb/ui-results.xcresult`. This does not establish live setup timing, Mail integration, API behavior, or correction UI acceptance.

Final checks pass: 33 package test functions (live API opt-in remains skipped), warning-free app/extension and hardened-runtime archive builds, Swift formatting, strict SwiftLint, Markdown lint, and project plist validation. The updated Developer ID app was accepted under notarization submission `4a085091-1ebf-4371-87c4-682fe00934ca`; stapling, ticket validation, deep strict signature verification, and Gatekeeper assessment pass. The updated distribution is `.build/c9bb73f1-a63e-4dc1-bc30-c2b388a122fb/SpamWise-notarized.zip`.

## Live setup and correction checks — 2026-10-16

The supplied API key was saved directly from clipboard to login Keychain under service `codes.tim.SpamWise.anthropic.setup`, account `user-api-key`, without printing it or creating a plaintext file. Signed-app verification also saved the operational shared Keychain item. One synthetic Haiku 5.5 verification succeeded: measured 990 input tokens, 78 output tokens, zero cache reads, estimated cost $0.000138. No fallback or additional live-model calls were made during Mail troubleshooting. Independent extension access to the key remains unverified.

Two UI tests passed at 07:43 PDT: corrections (22.277 seconds) and offline onboarding (11.134 seconds). Correction testing uses real parsing, state, and pipeline operations with a denied Apple Events boundary and isolated temporary storage. It verifies address Allow → Block replacement, explicit domain Allow, and persistent rules despite failed Mail actions. Native Settings toolbar tabs omit SwiftUI accessibility identifiers; the test pins English for that toolbar control. The extension display name is now configured as SpamWise; Mail's cached presentation still needs confirmation.

Signed-app Mail connection attempts returned -1712. At 07:51 PDT, TCC logs showed a consent request for SpamWise → Mail, followed eight seconds later by “ACCESS DENIED, because the prompt timed out.” The eight-second script timeout also bounded initial consent. AppleScript execution now runs on a dedicated serial executor, with initial framework setup on the main actor. Check Mail requests Automation permission separately through `AEDeterminePermissionToAutomateTarget`; ordinary scripts preflight without prompting and retain their eight-second execution limit. No sandbox restrictions were removed. At 07:54:59 PDT, after the user clicked Allow, the signed app returned permission status 0 and read two accounts successfully. Disposable-message actions remain pending.

The 07:55 PDT disposable-message probe refused an ambiguous selection before any move. A read-only selection count confirmed 27 messages selected in Mail. A single selected `[SpamWise Probe]` message is still required. Dry run remains enabled and onboarding incomplete; recorded model spend remains $0.000138.

Verification after the permission fix: all 33 package test functions pass (opt-in live API test skipped), app/extension builds pass with warnings treated as errors, and strict SwiftLint/Swift formatting/Markdown lint pass. Both UI tests pass again: corrections 22.612 seconds, onboarding 11.044 seconds, zero failures. Saved result: `.build/66db9f95-d4bc-4e49-9be9-cec34f7d16a0/ui-results.xcresult`.

The updated hardened-runtime archive and Developer ID export pass. Apple accepted notarization submission `9ea82379-f89e-43cb-a284-8c95f0c9761f`; stapling, ticket validation, deep strict signature verification, and Gatekeeper assessment pass. Distribution: `.build/66db9f95-d4bc-4e49-9be9-cec34f7d16a0/SpamWise-notarized.zip`. The app is installed at `~/Applications/SpamWise.app`; its extension plist declares display name SpamWise. Runtime Mail presentation remains a separate check.

The user authorized sending one probe to `tim@tim.codes`. Mail accepted the send and delivered `[SpamWise Probe] Acceptance 2026-10-16 08:01`. Native UI selection was required: setting `selected messages` through Apple Events did not reliably change Mail's application-level selection. Mail Settings now visibly shows the enabled extension as SpamWise. Both bundle name and display name are set to SpamWise.

The selected probe and Sent copy share an account and Message-ID but have different local IDs. The ordinary lookup correctly refuses that ambiguity. A controlled native AppleScript round trip initially reported unique account-specific Junk/Inbox destinations, unchanged source, both moves, and orange flag. Mail changes the local ID after each move. After synchronization, however, Mail put the received copy in Recovered Messages (iCloud), logging “Moving 1 invalid messages to Recovered Mail” at 08:08:35 PDT. Restoration to Inbox was initially visible; a subsequent single move to Junk did not remain visible in Inbox, Junk, or Recovered Messages after synchronization. The Sent copy remains intact. No Trash/delete command was issued. Move testing stopped, and the account remains unvalidated.

The setup probe retains normal account/Message-ID ambiguity rejection. It now waits 30 seconds after acknowledged actions and rechecks source and original mailbox before allowing local validation. A regression test demonstrated that the old implementation returned success for a probe subsequently located in a recovery mailbox; it now fails open. The delay is a provisional observation window, not a server acknowledgement. UI status instructs the user to inspect the probe in Mail before turning off dry run. Delayed Mail/iCloud synchronization remains an unresolved runtime gate.

The live message also exposed an extension startup crash: MailKit's `MEExtension` header is marked `NS_SWIFT_UI_ACTOR`, but Mail constructs the principal object from `com.apple.NSXPCConnection.user.endpoint`. The crash stack enters Swift's isolation assertion from `_createPrincipalObject`. The stateless principal class and handler factory are explicitly `nonisolated`. Warning-free package/app/archive builds pass with this correction; a successful live body callback remains a separate acceptance check.

Final verification after the sync guard: 33 package tests pass (live API opt-in skipped), both UI flows pass in 33.658 seconds, and app/extension/archive builds are warning-free. Swift formatting, strict SwiftLint, Markdown lint and plist checks pass. Final UI artifact: `.build/66db9f95-d4bc-4e49-9be9-cec34f7d16a0/ui-final-results.xcresult`. Apple accepted submission `2b877963-61d4-4ee3-a52a-63d2fe88120d`; stapling, signature verification and Gatekeeper acceptance pass. The final stapled ZIP replaces the earlier ZIP at `.build/66db9f95-d4bc-4e49-9be9-cec34f7d16a0/SpamWise-notarized.zip`, and the app is installed at `~/Applications/SpamWise.app`. Stale registrations for prior test exports were removed without deleting their artifacts. Automatic actions remain disabled; total measured verification usage is still 990 input / 78 output tokens, estimated $0.000138.

## Live move implementation — 2026-10-16

The user authorized generating additional probe messages. Three uniquely named cross-account probes (`[SpamWise Probe] Cross-account 3403d764 A/B/C`) were sent through Mail: A/B from Google to <tim@tim.codes>, C from iCloud to Google. Their receiving accounts have no matching Sent copy. Controlled native AppleScript tests of A/B observed successful, settled moves through both concrete account mailboxes and the existing special-mailbox destinations. This does not establish a defect in special-mailbox resolution or explain the earlier recovery event conclusively.

Every adapter move now waits 30 seconds before resolving the message afresh and checking its exact source and membership in the account's intended special mailbox. The probe verifies the initial Inbox, stops after any failed move verification, and checks the orange flag and final Inbox location. This accounts for Mail changing local message IDs during moves. Confirmation means an observed client state, not an independent server acknowledgement; the observation window remains provisional.

The first signed-app attempt stopped before moving because AppleScript's Boolean result was decoded as text. A direct `NSAppleScript` reproduction returned descriptor types `1953658213` (`true`) and `1717660787` (`fals`), rather than only `typeBoolean`. The decoder now accepts all three Boolean descriptor types, including nested results. The real AppleScript decoding test failed with three assertions before the fix and passes afterward. The move-verification regression also reproduced a false confirmed receipt before the change. Stubs cover rejection before a reverse move and successful restoration with changed local IDs.

At 08:42 PDT the rebuilt Developer ID app completed the iCloud A probe: observed Junk, restored Inbox, and orange flag. Independent Apple Events inspection confirmed Inbox local ID 63286 and flag index 1. Shared state recorded the validated account while retaining dry run and incomplete onboarding. No additional Anthropic calls were made.

At 08:45 PDT the same signed app completed the Google C probe. Independent inspection observed Google Junk local ID 63287 during settling, then Inbox local ID 63288 with orange flag index 1. Shared state now contains both validated account IDs and the AppleScript route. Dry run remains enabled and onboarding incomplete, so automatic filtering has not been activated. API usage remains 990 input / 78 output tokens and estimated total $0.000138.

Final follow-up at 08:47 PDT again found both received probes uniquely in their respective Inboxes with orange flags. All 33 package tests pass (live API opt-in skipped); both UI flows pass in 33.427 seconds. Package/app/extension/archive builds are warning-free; Swift formatting, strict SwiftLint, Markdown lint and plist validation pass. UI evidence is `.build/3403d764-e035-4ecc-a3a4-69204fd5d447/ui-results.xcresult`. Apple accepted submission `ab57130e-7118-475c-9d17-64ed4bcbfbae`; stapling, ticket validation, deep strict signatures and Gatekeeper acceptance pass. The installed app is `~/Applications/SpamWise.app`, with its enabled extension as the sole registered SpamWise plug-in. Distribution: `.build/3403d764-e035-4ecc-a3a4-69204fd5d447/SpamWise-notarized.zip`. Signed incoming MailKit callbacks, representative calibration, and fresh live onboarding remain separate acceptance work.

## Expanded roadmap implementation — 2026-10-16

After the cross-account Apple Mail move spike passed, the user authorized the deferred roadmap, selected Spanish and French, and set a maximum additional evaluation spend of $150. No personal labeled corpus exists yet. Optional capabilities remain disabled by default; labels can accumulate through corrections and optionally retain bounded text for export. No new paid calls were made during implementation.

Implemented explicit Apple on-device/PCC, OpenAI and Gemini providers alongside Claude; provider-specific credentials and conservative persistent budget reservations; bounded correction retrieval, policy suggestions, campaign fingerprints, Bayes and regularized evidence weights; optional DBL/Rspamd evidence and embedded-image OCR; TLS IMAP and a headless daemon; editable/importable/exportable rules; reviewed-label export/evaluation and a local Review digest. Spanish/French catalogs, permission descriptions and six Help pages are included. PCC, external-provider credentials, IMAP account validation and App Review remain separate runtime or external prerequisites, documented in TODO.md.

Whole-change review identified and resolved three important issues: IMAP paging now resumes before messages deferred by its aggregate byte budget; daemon retries are account-scoped and run even on an empty discovery page; statistical inference uses enriched evidence consistent with training. A follow-up review found no new important issues. Headless provider credentials accept explicit environment/login-Keychain references without provider fallback or embedded secrets. Model selection changes only the selected backend/model through the existing settings transaction.

Fresh package verification passes 72 test functions; the opt-in paid API test remains skipped. The app and extension build with warnings treated as errors. Strict SwiftLint and Swift formatting pass. A five-fixture explicit mock evaluation produces two Inbox, two Junk and one Review, with zero paid calls. An actual Apple on-device evaluation completes all five fixtures with measured 3,172 input and 255 output tokens, no API charge, and all five decisions Review. It demonstrates availability, not useful filtering accuracy or calibration; four fixture labels differ. Default Claude selection and provisional thresholds remain unchanged.

Native UI inspection covered all four onboarding steps, denied Mail permission, Activity, all four Settings tabs, advanced learning/evidence controls and the empty digest in English, Spanish and French. No overlaps or clipped labels were observed. Count wording, localized default policy and completed-onboarding empty-state copy were corrected after inspection. Final integrated UI and distribution results follow below when available.

Final UI suite at 10:00 PDT: correction persistence/replacement/Review flow and four-step offline onboarding both pass, zero failures in 40.903 seconds. Result: `.build/644e5a3f-1ff7-4f04-8a2f-82f42fbf8540/ui-final-results.xcresult`. Tests use isolated state and a denied Mail boundary; they do not establish live Mail action acceptance.

Targeted inspection of the rebuilt app confirms the corrected footer, default policy and post-onboarding empty text in English, Spanish and French. Evidence: `.build/81b2e5c5-e5fe-4ca8-be6e-58b7ebece695/ui-evidence/`. A separate App Store development-signed optimized archive preserved all original sandbox/App Group/Keychain entitlements. Local distribution export reached the Apple Distribution private-key prompt but its parent exited before approval and produced no package; the abandoned signer was terminated. No store upload or publication occurred.

The final hardened-runtime archive and Developer ID export pass without warnings. Apple accepted submission `1fc8e163-e06c-4514-9ef0-a2a406610128`; stapling, ticket validation, deep strict signatures and Gatekeeper assessment pass. Original bundle IDs, team, sandbox, App Group and shared Keychain entitlements are preserved. The app is installed at `~/Applications/SpamWise.app`; stapled ZIP: `.build/644e5a3f-1ff7-4f04-8a2f-82f42fbf8540/SpamWise-notarized.zip`. Implementation commit: `e5c6f1b` (verified SSH signature).

An optional five-fixture live Haiku CLI evaluation stopped at login Keychain access before the evaluator launched. The pending reader was canceled without retrying; no key was output or written. Before/after budget snapshots show zero new reservations and zero paid calls. Prior signed-app measured Haiku verification remains 990 input / 78 output tokens, estimated $0.000138; additional roadmap spend remains $0. The $150 ceiling is not a spending target.

Final installed-app acceptance at 10:06 PDT: the exact `~/Applications/SpamWise.app` process connected to both configured Mail accounts without a new permission prompt. One authorized synthetic Google-to-iCloud message, `[SpamWise Probe] Final acceptance 644e5a3f E`, arrived uniquely in iCloud Inbox (local ID 63318 observed at 10:07:26 PDT). No ordinary-mail scan, move or paid classification was initiated. During the following observation window the shared incoming/body callback timestamps remained absent; MailKit callback acceptance remains unresolved. The installed extension process launched from the exact installed path (PID 31718), but this does not establish a body callback. A separate unowned Xcode app/extension registration was left untouched. Dry run remains enabled, onboarding incomplete and the AppleScript route selected. The prior generated cross-account move checks remain the evidence for Apple Mail actions.

## Repository conventions and interface review — 2026-10-16

Reviewed every project-owned code file against the Swift and SwiftUI conventions in
`~/Repositories/shell-files/dotfiles/agents/skills/`. The exhaustive 140-file ledger
and compatibility decisions are in `docs/conventions-and-design-review.md`.
Declaration ordering is enforced by SwiftLint; public APIs use DocC, errors expose
localized categories and reasons, production bounds are named, and Swift Testing
cases use prose identifiers. Existing persistence, prompt and wire identities are
preserved. Signed integer API/storage fields and collection indices retain their
existing validation and compatibility contracts.

The design follows Apple's native Settings, toolbar, inspector, layout and disclosure
patterns. Activity has four columns and an inspector; Settings separates General,
Accounts, Rules, Preferences and Advanced. First-run setup occupies the main window;
General can reopen its four steps as a sheet. Conditional controls and disclosures
reduce persistent explanatory text. Help buttons use the native AppKit component.
Spanish and French translations cover the revised interface. UI-test preferences
and fixture storage are isolated from production data.

The native review exercises all 27 view/representable types. It exposed status-footers
overlapping native scrollable forms; the footers now have separate layout space.
Permission guidance appears once in the Mail form. Rule editing keeps its draft and
error visible until persistence succeeds; IMAP transport selection is disabled while
its connection operation is busy. The preview denied-state fixture includes the
actual localized failure text.

This review uses offline fixtures and a denied Apple Events test boundary. No real
Mail actions, provider requests or credential changes are part of the review; its
new API spend is zero. Existing live integration and calibration limitations remain.

Final verification: all 72 package tests pass (live API opt-in skipped), both XCTest
UI flows pass with zero failures in 71.713 seconds, and app/extension builds are
warning-free. Strict SwiftLint, Swift formatting, shellcheck, YAML/Markdown lint,
plist checks, 420-entry localization coverage, Help links/indexes, Store concurrency
and offline evaluation checks pass. Final UI result:
`.build/ca664761-7b58-458e-9bda-cd338002266a/DerivedData/Logs/Test/Test-SpamWise-2026.10.16_12-03-01--0700.xcresult`.
Developer ID archive/export and deep strict signature verification pass; this review
does not repeat notarization or install the rewritten app. Native evidence covers
English, Spanish and French, with Activity at 720 pixels wide and setup sheets at
560 × 500. Settings remained 800 × 628 despite attempted resizing; smaller Settings
layouts are unverified. No remaining overlap was observed in the final checks.

## Probe lifecycle and candidate corpus — 2026-10-16

The user requests cleanup of agent-created test messages when their checks finish.
Resolve only documented generated probes by account and exact identity, including
their Sent copies and leftover drafts, then move them to that account’s Trash and
verify the resulting location. Do not empty Trash or include ordinary mail. This
is authorized operator cleanup; the SpamWise product still exposes no delete/Trash
operation.

The user is accumulating SpamSieve-classified messages in each account’s Junk
folder over the next few weeks. Preserve those candidate samples and track their
provisional provenance separately from human-confirmed labels. The evaluation
workflow and outstanding calibration task are recorded in `docs/evaluation.md`
and `TODO.md`; no automatic collection or paid evaluation is scheduled.

Cleanup completed: 11 distinct probe copies (six iCloud, five Google), including
two leftover drafts and all discovered Sent copies. iCloud’s six copies are in its
Trash destination. Mail’s Google Trash destination resolves to the custom Gmail
label `Deleted Messages`, and one draft reappeared during synchronization. The
Gmail API moved all five exact Google message IDs to the system `TRASH` label;
server queries verify five in Trash and zero matching probes outside Trash. Future
Google cleanup must verify the system label rather than trusting that custom folder.
Trash was not emptied; ordinary mail and the Junk folders were left untouched.
No model calls were made.

## SpamSieve parity implementation — 2026-10-16

Mail.app-only parity work is tracked in `TODO.md` and
`docs/spamsieve-parity-progress.md`. The completed SS-10/11/12/13/15/16 work includes
content rules, reviewed corpus/undo, searchable Activity/audit, statistics, trust
exclusions and encrypted backup. Other parent items retain explicit runtime,
independent-label, hosting or second-device gates; checked child steps identify
implementation without claiming those gates passed.

The latest batch adds optional count-only notifications, separate post-Junk read
status, bounded text/HTML attachments and extra still-image formats, account role
previews, UUID-protected App Intents and frozen paired-comparison reporting. PDF/Office
extraction, native-intent registry acceptance, a hosted signed updater and actual
quality comparisons remain open. Development `AppIntentsTesting` reports metadata
error 400 even though build extraction lists all four intents; the opt-in test records
that prerequisite separately from normal UI acceptance. No provider calls or new mail
were needed. The $150 cap and ordinary Junk-folder preservation remain in force.

Current checks: 82 package tests pass; warning-free app/extension builds; strict
SwiftLint, Swift formatting and Markdown lint; two UI flows pass in 103.196 seconds
with one explicit intent-test skip. Result bundle is under worker
`26e096e9-f0a7-465e-90b7-aa67c5b2b2f7`, timestamp `14-56-59`. Activity uses a single
window so Tools commands do not create duplicate corpus sheets. This batch has not
yet been accepted as a new notarized distribution or through live Mail workflows.

## Resumed detector, document and distribution work — 2026-10-16

The execution blockers are resolved: native Terminal and resumed agent checks
run SwiftPM successfully; Xcode MCP works after `XcodeOpenWorkspace` requests its
agent/project authorization. Earlier sandbox and approval-policy errors were
execution-environment failures, not Swift source failures.

Independent threat assessments now persist separate spam/phishing/spearphishing/
fraud/malware states, detector provenance and coverage. Successful gate and model
paths use the same bounded assessment boundary without changing action rules.
Preference-derived learned scores are excluded. Missing or failed detection is
unknown; historical records remain unassessed. The inspector and objective-report
CLI make that distinction explicit. No production detector is selected. Cache
keys include effective content, account, evidence and detector/schema identities.
See `docs/threat-assessments.md`.

Document text coverage is explicit; optional extraction failure preserves the
body. All ten isolated PDF probe cases pass, including encryption and parent
termination of a hung worker. No production PDF parser, memory ceiling or
malware-safety claim follows from that probe. See `docs/probes/document-inspection.md`.

The historical hard-ham development cohort contains 232 accepted messages. The
candidate local model falsely detects spam in 60.8%/65.5% at threshold 0.5 with
384/1,024-token inputs; it is unsuitable for production. Reserved holdouts remain
unscored. The separate twelve-context synthetic graymail probe produced policy-
consistent model labels in EN/ES/FR; examples gave no categorical improvement.
All unwanted effective actions remain Review at the unchanged 95 threshold.
Measured usage: 15,514 input/1,043 output/zero cache tokens; estimated new cost
$0.0020729 and $1.20 additional conservative commitments in the existing $150
ledger. No personal mail, fine tuning, new Mail probes or new ledger was used.

`SpamWiseDirect` supports manual release discovery via the local library's
`GitHubReleaseDiscovery` product, committed as `eab9c1d` on
`codex/release-discovery`. No host is configured and no installer is linked.
Warning-free direct and APP_STORE builds and binary/resource checks establish
store exclusion, not signed updater or migration acceptance. Library tests: 30
pass; discovery-only compilation passes with warnings treated as errors.

The initial native status intent passed through AppIntentsTesting (one test,
2.207 seconds) after replacing stale Launch Services registration with a current
signed metadata-bearing fixture app. Expanded acceptance follows below.

Final integrated checks: 86 package tests pass (paid provider tests remain opt-in),
app/extension and hardened-runtime archive builds have zero warning/error
diagnostics, and Developer ID export/signature verification passes. Two UI flows
pass with zero failures in 108.738 seconds, including explicit unassessed coverage;
the default suite skips the separately passed native-intent test. UI result:
`.build/ee61ddf4-7935-4486-bad5-b4b2016979cf/DerivedData/Logs/Test/Test-SpamWise-2026.10.16_21-15-00--0700.xcresult`.
Swift formatting, strict SwiftLint, Python unit/lint checks and Markdown checks
pass. Independent read-only review found no Important or Critical issues.

Apple accepted notarization `4dca30b7-ae98-47ab-8c78-6679abd9a5bf`. Stapling,
ticket validation, deep strict signatures and Gatekeeper assessment pass.
The updated standard Developer ID artifact is
`.build/ee61ddf4-7935-4486-bad5-b4b2016979cf/SpamWise-notarized.zip`.
It has not replaced the installed app or been published. This archive does not
contain the separate direct-update target. Remaining runtime, quality, release
hosting and App Review acceptance stays open in `TODO.md`.

## Native automation acceptance — 2026-10-16

All four App Intents pass through the signed application: preview and correction
parameter binding, durable request replay, a saved address rule after a denied
mail action, and redacted status/file export. The DEBUG-only automation fixture
requires both UI-testing and automation arguments, supplies one synthetic
selection, denies every other Mail script and uses a mock classifier without RDAP.
Explicit registered-app paths keep XCTest and App Intents on the same temporary
store; separate running copies previously made the UI assertion inspect the wrong
fixture. The full suite now uses the supplied path for every app launch.

After dismissing Shortcuts' first-run panel, a saved status shortcut worked in the
editor. Implicit output left CLI execution waiting even though the app returned
within milliseconds. Adding **Stop and Output** produced successful CLI and
AppleScript-bridge runs with matching decoded diagnostics. The temporary shortcut
was removed; the four original saved shortcuts were retained. No provider calls
or actual Mail operations occurred. SS-19 is complete for this documented scope;
live selected-message correction remains separate acceptance.

Fresh checks: 86 package tests pass; app/extension and signed test builds have zero
warning/error diagnostics; strict SwiftLint and Swift formatting pass. The final
UI suite passes all three flows with zero failures in 116.075 seconds, including
the expanded native test in 8.481 seconds. Evidence:
`.build/7ae09be2-7487-4cc9-900a-1c1b9fb169c9/automation-final-ui.xcresult`.
Independent review found no Important or Critical issues. See
`docs/automation.md` for reproduction and CLI artifacts.

## Correction identity and local candidate screening — 2026-10-16

Reviewed corrections now retain an explicit sample identity even when content
retention and statistical learning are disabled. Enabling content-based learning
upgrades linked examples to the semantic identity; disabling it preserves that
identity. Corpus relabel and Forget therefore reach the linked correction
examples and derived learning while retaining explicit sender rules. The existing
correction test reproduced four failing assertions before the fix. Already
persisted legacy examples with no sample identity are not automatically matched
by sender or subject, because those fields do not uniquely identify a message.

OpenTextShield raw-input screening is recorded in
`docs/probes/opentextshield-screening.md`. Both token budgets score the same 491
real development records, plus eleven separate synthetic cases; holdouts remain
unscored. Difficult legitimate email has 40.5%/43.1% spam false alarms at 96/384
tokens and a 0.5 score threshold. The synthetic targeted-payment pair is reversed.
The candidate is rejected for production selection; no calibrated threshold or
useful local detector is claimed. No paid calls were made.

Verification for the correction-identity change: all 86 package tests pass,
app/extension and hardened-runtime archive builds pass with warnings treated as
errors, and Developer ID export passes strict signature verification. Swift
formatting, strict SwiftLint, all six corpus-tool tests, Ruff, compileall and
Markdown lint using the global configuration pass. Independent review found no
Important or Critical issue. Earlier native automation/UI acceptance in this
session predates this identity change; the new behavior is covered by the
extended core correction test.

The correction-identity build was accepted by Apple's notarization service as
`fb685339-3630-449a-8ca8-53b6180c574b`. Stapling, ticket validation, deep strict
signature verification and Gatekeeper assessment pass. The stapled artifact is
`.build/7ae09be2-7487-4cc9-900a-1c1b9fb169c9/SpamWise-notarized.zip`.

## Signed selected-message correction and rescue — 2026-10-16

The existing notarized installation completed menu-bar Mark as Junk and Review
Junk → Mark Good and restore for one generated Google-to-iCloud probe. Each
persisted outcome was applied. Independent Apple Events reads confirmed exact
account/mailbox membership and unchanged source after the adapter's settling
window. Automatic account scope was empty and provider consent remained off;
there were no paid model calls or ordinary-mail mutations. Details and limits
are in `docs/probes/live-corrections.md`.

Both exact generated mail copies were moved to their accounts' Trash for cleanup.
The test sender rule and reviewed label were removed through the app; two
captured legacy correction-example UUIDs were removed through a guarded typed
Store transaction. Independent reads confirm zero remaining probe rules, labels
and examples. Product mail actions still expose no Trash or delete operation.

Final correction UI test on the rebuilt app passed in 91.363 seconds with zero
failures, including address/domain precedence, denied-action persistence, undo,
and Forget retaining sender rules. Result:
`.build/7ae09be2-7487-4cc9-900a-1c1b9fb169c9/correction-final-ui.xcresult`.
The notarized update is installed and running at `~/Applications/SpamWise.app`.
Original settings are restored: paused false, dry run true, all-account scope
and no folder plans. The temporary test extension registration was removed;
PlugInKit's selected entry resolves to the installed app. Existing other build
registrations and the user's Xcode workspace were retained. The app's recorded
monthly estimate remains $0.000936; no additional paid calls were made.

## Unreadable mailbox page recovery — 2026-10-16

Account and configured-folder pages now distinguish visited positions from readable
envelopes. Oversized, empty and explicitly unavailable sources remain untouched,
are counted in health and are retried on a subsequent sweep. Permission errors,
timeouts, ambiguous identities and malformed page responses still fail the page.
The original paging test reproduced the oversized-message stall before this fix.
Training observations reset at every traversal boundary, while incomplete coverage
cannot release action claims; review found and corrected this distinction before
completion. See `docs/probes/unreadable-mail-pages.md` for behavior and limits.

All 86 package tests pass with warnings treated as errors, including expanded
paging and training-claim tests. Generated AppleScripts compile without invoking
Mail. App/extension and signed UI-test builds pass with no compiler warnings.
Strict SwiftLint and Swift formatting pass. Spanish and French translations cover
the new unreadable-mail labels. No paid calls or live mail mutations were made.

Independent review found no remaining Important or Critical issues. Xcode component
previews are readable in English, Spanish and French in the grouped Settings-style
container. Full Settings navigation remains unverified: a pre-existing Screenshot
overlay blocked expansion of scan health. See `docs/probes/unreadable-mail-ui.md`.
The isolated fixture and preview processes were closed; production settings were
not changed.

The final hardened-runtime archive/export passes. Apple accepted submission
`cff37898-ec0d-48c5-b19b-fc8e964ef77d`; stapling, ticket validation, deep strict
signatures and Gatekeeper assessment pass. The distribution is
`.build/5464e5b9-9f33-4901-b002-8686c83306da/SpamWise-notarized.zip`.
The update is installed at `~/Applications/SpamWise.app`, and PlugInKit selects
its extension. The app was already closed and was left closed. Read-only state
verification confirms paused false, dry run true and unchanged monthly estimated
spend of $0.000936. Controlled incoming delivery, sleep/wake, offline recovery
and mutating-mailbox acceptance remain open in TODO.md.

## Acceptance, corpus integrity and release preparation — 2026-10-16

The frozen corpus audit preserves all 18,201 original record/group/split assignments
and all 2,782 holdouts. Source labels, real/synthetic provenance, objective indices
and evaluation-only restrictions pass. The separate development partition joins
421 high-overlap links into 1,311 groups, moving 29 original training records only
in that derived manifest to validation. Thirty-seven lower-overlap cross-split
candidates remain unresolved. Inferred real-development language counts are 1,539
English, five Spanish, nine French, 47 other and 134 unknown; original reviewed
language fields remain unknown. No held-out text was scored, no model was selected,
and no additional paid request was made. See `docs/probes/corpus-integrity-audit.md`.

A signed sandboxed harness verifies six native Vision synthetic image cases and
local-mode rejection of remote providers before credential access. On-device
classification completes, with empty observed process network counters and a
successful loopback observer control. Service-aware traffic observation, real-image
quality and shipping-app acceptance remain distinct. A separate signed XPC document
harness passes 24 boundary/resource checks, including mutual code requirements,
file/network denial, invalid replies and crash recovery. Its resident watchdog
overshoots; public RLIMIT_AS/RSS was rejected with EINVAL. Launchd imposes roughly
ten-second restart spacing. Production PDF extraction remains disabled pending
containment and lifecycle work; see `Tools/DocumentWorker/README.md`.

Signed live Mail follow-up at `f7635ac` observes a new body callback two seconds
after controlled delivery following graceful Mail restart. Generated-message Junk
and subsequent read status are independently confirmed with unchanged source.
Historical folder preview requests no action; renamed scope fails closed. Account
scanning continues with all windows closed and resumes after app relaunch. Four
exact generated received/Sent copies are confirmed in Trash, without emptying it;
the temporary folder and generated training state are removed, full preferences
restored, and the app left closed. No ordinary Junk was relabeled. The saved OpenAI
setup key could not be read noninteractively, so operational import remains pending.
See `docs/probes/live-mail-followup.md` for exact scope and artifacts.

The source fix maps unresolved account/folder paths to an actionable folder error
instead of a misleading duplicate-message error. Provider consent now links to
retention terms and explains Gemini unpaid-service limitations in EN/ES/FR. Privacy,
support, reviewer/exception notes and a targeted dependency/required-reason audit
are prepared. Five script-free static prerelease pages under `docs/` pass generation
and browser checks at desktop and mobile widths. No host, remote, public URL or
release was created.

Local App Store packaging now succeeds through existing encrypted Match identities
in an explicitly addressed temporary keychain. Original app/extension identifiers,
App Group, sandbox and shared Keychain entitlements are preserved; the final store
artifact excludes the direct updater and debugging entitlement and includes the
privacy manifest. App/extension and installer signatures pass. Temporary signing
material is removed and the original login search list retained. Authenticated
`altool` validation reports no App Store Connect app record for `codes.tim.SpamWise`
(error 19). One intervening tool startup failed to read Defaults.properties; after
checking altool availability, the final retry reproduces the missing-app-record gate.
No package was uploaded. See `docs/app-store.md` for reproducible commands and results.

Independent review found two Important issues: an unbounded subprocess-cleanup
wait and missing corpus kind/provenance validation. Both are corrected and their
behavioral reproductions pass. Three packaging tests and eight corpus tests pass;
all 86 core tests and app/extension/store archive builds pass with warnings treated
as errors. The existing correction concurrency test uses explicit start/release
coordination instead of timing sleeps. The signed document harness was independently
reviewed with no remaining blocking finding.

The final Developer ID archive/export is notarized under submission
`3c687cd4-883c-4444-831a-20b33ab62ede`. Stapling, ticket validation, deep strict
signatures and Gatekeeper acceptance pass. The local distribution artifact is
`.build/cb38d7c0-dd6a-48b3-b59d-6cc4c75083d0/SpamWise-notarized.zip`.

A pinned native Rspamd 4.2.2 source build validates the production adapter against
one synthetic marker and an ordinary body: observed score 1.5 and empty symbols,
respectively. The signed sandbox harness returns unknown before client execution,
and the stopped service returns unknown outside the sandbox. Zero DNS requests
were logged. The disposable loopback server/configuration are removed; LuaJIT
2.2 MB and Ragel 2.4 MB developer dependencies remain installed. Upstream C/C++
warnings are documented separately; no production sandbox entitlement was changed.
See `docs/probes/rspamd-runtime.md`.

Direct inspection of the expanded Gemini consent disclosure and retention link
passes in English, Spanish and French with isolated fixture storage. Initial UI
suite startup failures coincided with the stopped credential helper's lingering
Keychain prompt, visible in the failure recording; the prompt expired without
approval. No production/test wiring was changed to suppress that failure.

The unchanged UI suite then passed corrections in 91.729 seconds and onboarding
in 16.413 seconds, zero failures. The opt-in registered-intent test was skipped.
Result: `.build/cb38d7c0-dd6a-48b3-b59d-6cc4c75083d0/DerivedData/Logs/Test/Test-SpamWise-2026.10.16_23-45-12--0700.xcresult`.
The notarized app is installed at `~/Applications/SpamWise.app`, verified again
with deep strict signatures and Gatekeeper. It is left closed; the prior app is
retained under the worker's `previous-installed/` directory. Only this worker's
test extension registration was removed. PlugInKit's selected entry resolves to
the installed app. Other workers' build artifacts/registrations and unrelated
Xcode/catalog edits are preserved. Final lint, site generation and independent
Rspamd-probe review pass; no further material findings remain in this change.

## Containment, local evaluation and cancellation follow-up — 2026-10-17

The signed PDF-worker harness now handles cancellation before continuation
installation, during identity/response waiting, and after work starts. A first-wins
completion latch rejects duplicate and late completions; connection loss exits an
active worker, and recovery requires a different process. One document per process
preserves cumulative CPU accounting and allocation reclamation. The exact-source
signed run passes 28 request observations and three completion-order checks;
cancellation completion measured 0.000156 seconds. Evidence is
`.build/594427e7-0238-4e70-ad69-7a5595634c83/document-worker-final.log`.

Public resource-limit, memory-pressure, XPC and established-parser research is in
`docs/probes/pdf-containment.md`. No evaluated public mechanism establishes the
required whole-process memory cap. The sampled 128 MiB watchdog again overshot,
reaching 148,439,040 bytes; launchd restart spacing remains roughly ten seconds.
MuPDF allocator control and bounded WebAssembly are documented experiments, with
licensing and host/runtime allocation limits explicit. No new parser or production
PDF integration is shipped.

SpaPhish v5 supplies a separate CC BY 4.0 Spanish development source: 1,395
messages, including 664 legitimate examples. A hash-pinned fixed character-TF-IDF
and logistic baseline fits only development training subject/body text after
conservative template/campaign grouping. Validation at score 0.5 detects 188/212
phishing messages with 5/176 legitimate false alarms. At 0.9 it detects 46/212
with zero observed false alarms. These uncalibrated scores do not justify automatic
actions. Source, tool, helper, dependency and partition hashes are recorded in
`Tools/Corpus/reports/spaphish-development.json`; reproduction yielded identical
scores and partitions. Existing 18,433 records and 2,782 frozen holdouts remain
untouched. No paid API calls or personal-mail processing were used.

The explicit local HTTP Rspamd transport uses `127.0.0.1:11333/checkv2` only,
rejects redirects/authentication challenges, disables proxies/cookies/credential
storage/cache, limits streamed responses to 64 KiB, and respects a three-second
maximum or shorter caller deadline. A signed sandbox harness scanned native
Rspamd 4.2.2 and passed redirect-without-forwarding, oversized streaming response,
service-error, timeout, cancellation, concurrent-request and stopped-service checks.
Temporary servers/listeners were removed. Evidence is
`.build/053e029e-a477-4600-94f0-b8d53af1b4d7/rspamd-runtime.log`.
No new sandbox entitlement is needed. Executable transport remains unavailable in
store builds and fails safely in the signed harness; neither transport silently
falls back. Both default off and local-only mode blocks them. Settings, Spanish/
French labels, privacy text and the distribution-difference ledger reflect this.
The scanner's own rules, logging and outbound behavior remain a separate acceptance
boundary.

Cancellation tests reproduced four failed assertions from removing all due retries
before processing. The pipeline now atomically claims one exact scheduled job at a
time; cancellation retains unstarted jobs, and Pause/revision changes reject stale
claims. Pre-cancelled and mid-batch cases reopen the durable store and successfully
resume remaining jobs. An already claimed job may be consumed by cancellation;
this does not introduce an automatic retry of a potentially dispatched action.

Final core verification passes 87 tests and warning-free app/extension builds.
The unsigned optimized `APP_STORE` archive also passes, including the new HTTP
transport and disabled executable capability. Eight corpus tests, strict SwiftLint,
Swift formatting, shellcheck, Ruff, Markdown lint and static-site generation checks
pass. Independent reviews found no important issues in the retry flow, worker
lifecycle, Rspamd transport/wiring or Spanish baseline. The baseline's helper-hash
provenance improvement was applied and rerun.

The signed UI suite passes corrections (91.919 seconds) and onboarding (15.997
seconds), zero failures; the environment-gated registered-intent test is skipped.
Native English, Spanish and French inspection verifies transport selection,
conditional path/disclosure layout, and saved selection after reopening Settings.
An untranslated Off choice was corrected, rebuilt and observed as Desactivado and
Désactivé. Screenshots/hierarchies are under
`.build/ec7d754d-4fc0-4434-8b23-c5b48c750b31/rspamd-ui/`; the test result is
`.build/ec7d754d-4fc0-4434-8b23-c5b48c750b31/DerivedData/Logs/Test/Test-SpamWise-2026.10.17_00-02-04--0700.xcresult`.
Owned UI fixtures/registrations are removed and the UI lock is released. No live
Mail actions, production-setting changes, new notarization or installed-app
replacement were performed by this follow-up. Unrelated project/catalog changes
remain unstaged.

# SpamWise development

## Contract and architecture

The Phase 1 brief is preserved in `docs/phase-one-brief.md`. The implementation plan supplied in the session controls rule precedence and provisional thresholds where it refines that brief. Work proceeds on `codex/phase-one`; existing app/extension bundle IDs, team `2NFSK2WB24`, and App Group `group.codes.tim.SpamWise` are preserved.

Local package modules: MessageModel (bounded MIME and shared identity), Signals (gates/evidence), Classifier (prompt and provider), Decision (pure action policy), Store (durable state), SpamWiseCore (pipeline), spamwise-eval (CLI). Core has no MailKit or SwiftUI dependency. Integrations belong to app/extension. Swift 6 strict concurrency, macOS 27 minimum. Never expose delete/Trash. Persist before action, fail open on every error. Rules: address > domain > contacts/history. Correction replaces same-scope rule; domain scope must be explicit.

## Integration probes — 2026-10-15

- `xcodebuild -version`: Xcode 27.0 (27A266a); `swift --version`: Swift 6.4. SDK headers confirm `MEMessage.rawData`, no `bodyData`. `MEMessage` exposes no stable account identifier. No arbitrary-mailbox MailKit action or completion/outcome acknowledgement exists.
- Starter build fails Swift 6 checks: mutable/non-Sendable shared MessageActionHandler singleton. Replaced by stateless instance pending integration.
- `security find-identity -v -p codesigning`: **0 valid identities** in this environment. Signed extension runtime, shared Keychain access, body callback, configured accounts, server-routed Junk, controlled network delays, and cancellation are **not runtime verified**. No credentials/test messages supplied. Do not infer a safe Mail deadline from SDK compilation. Default disabled actions/dry run; route activation requires explicit recorded validation.
- Apple Mail's installed `/System/Applications/Mail.app/Contents/Resources/Mail.sdef` declares source, message id, account id, Sent, flag index and background color. Sandboxed entitlement candidate: automation.apple-events + temporary-exception.apple-events for com.apple.mail, usage description. Automation approval and disposable moves remain unverified. Never inspect Mail's databases or request Full Disk Access. Use Apple Events for initial and incremental history.
- SwiftData reproducible probe: compile `Scripts/swiftdata-probe.swift` with Swift 6.4, initialize a store, start two processes each inserting 50 unique records, then read in a third. Exit codes 0/0, final count **100**. Fresh contexts see committed rows. Under tool sandbox CoreData change notifications emit registration errors; do not rely on notifications. Retain SwiftData, serialize read/modify/write with a process-shared advisory lock and use fresh contexts/read polling. Signed App Group entitlement access remains a separate runtime check.
- Provider source pinned for upcoming integration to `0262e1a766c461a4268dcec656eca95dd74cebf8` from https://github.com/anthropics/ClaudeForFoundationModels (Apache-2.0). It includes `.haiku5_5`, guided generation, `timeout`, fresh sessions, and measured `session.usage`. Cache reads exposed; cache-write accounting is folded into input so dollar amounts remain estimates. No model fallback is configured. User-supplied `.apiKey` is appropriate here: never bundled, stored only in shared Keychain.
- Current pricing verified against https://platform.claude.com/docs/en/models/haiku-5-5/overview and https://platform.claude.com/docs/en/about-claude/pricing: under 100K prompt tokens, $0.10/M input, $0.50/M output, $0.01/M cache reads. Cache writes cost more; show estimated cost. No live API test has run.

## Commands

`swift test --package-path SpamWiseCore -Xswiftc -warnings-as-errors`

`xcodebuild -project SpamWise.xcodeproj -scheme SpamWise -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/SpamWise-build CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build`

Evaluation and archive commands are completed with milestones 8–9. Live tests are opt-in only. Default logs must contain no keys or message content. Tool-sandbox builds need approval for Swift compiler caches and macro subprocesses; this is distinct from the application's App Sandbox.

## Milestone ledger

1. Scaffold — package test passes; app and extension build with warnings treated as errors. Added AppIntents linkage to resolve Xcode metadata warning.
2. Message parsing — pending.
3. Gates/evidence — pending.
4. Classifier — pending.
5. Decisions — pending.
6. Mail integration — pending signed runtime verification.
7. UI/corrections — pending.
8. Evaluation — pending calibration corpus.
9. Help/packaging — pending signing credentials.

Ruling: work in the clean supplied checkout on a new branch, preserving review visibility; no extra worktree needed. Original brief received after initial inspection, copied verbatim. Shared interfaces follow the module dependency DAG; Store depends on value types, pipeline depends on Store, so Signals never imports Store. Runtime prerequisites do not justify guessing a successful route. Implementation supports explicit runtime validation states rather than claiming either route tested.

### MIME selection

Evaluated https://github.com/miximka/MimeParser (MIT, Swift 5.3 manifest, MIME resources/tests, no Swift 6 Sendable contract or resource bounds promised) and https://github.com/igorrendulic/MimeEmailParser (MIT, latest checkout `0cc9038`, 2020-04-19, Swift 5.2, small XCTest suite, no concurrency contract). Neither establishes bounded adversarial parsing or the five product fixtures. Selected a dependency-free value parser, explicitly limited to 2 MB input, 64 KB headers, 12 nesting levels, 128 parts, text/plain and text/html, QP/base64 and Foundation-supported charsets. Attachments ignored; invalid encodings/ambiguous critical headers fail open. HTML is converted lexically without WebKit or loading resources. The bundled Mozilla Public Suffix List (MPL-2.0, source/license in file) handles wildcard, exception, ICANN and private suffixes; refresh deliberately and rerun boundary tests.

Milestone 2: fixture/domain tests observed failing before implementation, now six test functions (including five fixture cases) pass; warning-free package/app checks pass.

Milestone 3: address/domain precedence and same-scope replacement tested red→green; missing history remains unknown. Evidence parses provider authentication claims without treating an arbitrary sender header as trusted. Contacts denied/unrequested yields unknown. RDAP discovers HTTPS endpoints from IANA, caches successes for seven days and unknowns for one hour; failures never become spam evidence. SwiftData Store uses a nonblocking cross-process lock, fresh container/context, and atomic save; lock contention fails open. Store sharing/rollback and stub-network RDAP tests pass. MIME candidate `miximka/MimeParser` latest checkout `0903ca7` dates to 2023-06-09.

Milestone 4: pinned provider uses `.haiku5_5`, fixed low effort, no fallbacks, bounded 1,024 response tokens, and a fresh guided session per message. Fixed instructions are separate from JSON-escaped preferences/correction quotations and untrusted message data. Default 40 examples and 6,000 body characters (~1,500 tokens), quoted replies removed. Measured input/output/cache counts are recorded; cost remains an estimate because cache-write premiums are not separately exposed. Hard deadline races discard late responses, support cancellation and never wait for an uncooperative provider. Classifier errors are typed; persistent retries are composed with the decision pipeline in milestone 5. Shared Keychain is the only app credential store. Live test requires SPAMWISE_LIVE_API=1 and is skipped by default.

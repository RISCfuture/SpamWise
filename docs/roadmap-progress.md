# Roadmap progress

Scope: the expanded roadmap in `TODO.md`.
Baseline: `5164a55`

Ruling: The user's request to finish TODO.md expands the former Phase 1 exclusions and authorizes reversible implementation. Existing branch and checkout are retained. Repeated design permission checkpoints would duplicate that authorization; consequential external publication still requires a concrete final review.

Ruling: No labeled corpus exists. Implement label collection/export and calibration readiness, but keep thresholds uncalibrated. Treat $150 as an additional evaluation ceiling, not a spending target. Optional providers require explicitly entered credentials; managed entitlements and distribution approval remain external prerequisites.

Pre-flight: Shared interfaces are Classifier/TokenUsage, MessageIdentity, optional Settings/AppState fields, and EvidenceBundle. The root worker owns shared-state integration and the package manifest. Independent workers coordinate any changes to existing shared value types before editing.

- Tasks 1–3: provider adapters, bounded learning, TLS IMAP and headless polling are implemented. Offline provider and IMAP transcripts pass. No new provider credentials or IMAP credentials have been supplied.
- Task 4: bounded DNS/Rspamd evidence and local embedded-image OCR are implemented. Offline error, refusal, output-bound and timeout checks pass. A test caught newline separators exceeding the OCR text cap; the final joined output is now bounded.
- Task 5: migration-safe optional settings, persistent spending commitments, reviewed labels, rule editing/import/export, provider/transport controls and local digest are implemented. The final package run passes 72 tests; the app and extension build without warnings.
- Task 6: Spanish/French catalogs and all six Help topics are implemented. Native inspection covers setup and all Settings tabs in three languages. App Store archive/export preparation exists; store approval and PCC eligibility are external prerequisites. Xcode rejected symbol generation for punctuation-only localization keys; the catalog source-extraction configuration resolves that failure.
- Tasks 7–8: whole-change review and follow-up review are complete. IMAP byte-budget paging, account-scoped retries and enriched learning inference issues are fixed. Final XCTest UI flows pass with zero failures in 40.903 seconds. Developer ID delivery and controlled live acceptance remain in progress.

Spending: no additional paid calls have been made during roadmap implementation. Every configured paid backend reserves a conservative upper bound before making a request. The app, extension and headless worker use the shared ledger. Evaluation defaults to that same store; an explicitly supplied alternate budget store is a separate authorization ledger, not a way for this implementation session to bypass the $150 ceiling. Commitments are deliberately not reported as actual charges.

Correction handling: Review is an explicit graymail label, removes the same-address binary rule, preserves explicit domain rules, and requests only the configured annotation. IMAP connection checks occur after saving a correction. A confirmed IMAP move carries its proven destination UID/UIDVALIDITY into the recorded identity so later corrections do not reuse a stale Inbox UID.

Evaluation: the five-fixture mock run yields two Inbox, two Junk and one Review. An actual on-device run completes five requests (3,172 input / 255 output tokens, no API charge), but returns Review for all five. That verifies model availability, not filtering quality. No production thresholds or default provider were changed.

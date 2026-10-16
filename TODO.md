# Roadmap implementation and acceptance

The signed Apple Mail move spike passed for generated cross-account probes in iCloud and Google. The user then authorized implementing the deferred roadmap. Optional capabilities remain off by default; production thresholds remain uncalibrated. Implementation and live acceptance are tracked separately below.

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
- [x] TLS IMAP adapter and headless executable, with UIDVALIDITY/UID identity, SPECIAL-USE discovery, capability checks, disposable-message validation and verified move identities. Other mail clients can use the same server-side IMAP route; no unsupported client automation is claimed.
- [x] Local weekly digest of unresolved Review items, without sending email.
- [x] Explicit Good/Junk/Review label collection and optional bounded reviewed-text export for later evaluation.
- [x] Persistent conservative spending reservations. The authorized additional evaluation ceiling is $150, not a spending target.
- [x] Mac App Store archive preflight and local export configuration. These do not submit or publish an app.
- [x] Finish Spanish/French catalog verification, localized Help indexing and UI checks.
- [x] Finish whole-change review, package/app/UI/archive checks, signed commits and notarized delivery.

See [roadmap progress](docs/roadmap-progress.md), [evidence](docs/evidence.md), [IMAP](docs/imap.md), [evaluation](docs/evaluation.md), and [App Store preparation](docs/app-store.md) for limits and reproducible commands.

## Live acceptance and external prerequisites

- [ ] Verify each newly selected provider with its own credentials and evaluate quality before relying on it. OpenAI/Gemini credentials were not supplied. Apple on-device completed five synthetic requests but returned Review for every fixture; quality remains unvalidated. PCC entitlement/quota remain runtime gates; refusal is never spam evidence.
- [ ] Validate an explicitly configured IMAP account read-only, then run a disposable-message move probe. No IMAP credentials have been supplied; transcript tests do not establish provider interoperability. OAuth tokens require a separately authorized flow or supplied token; no mailbox credentials are extracted from Mail.
- [ ] Validate optional DNS service terms/resolver, local Rspamd availability and real OCR fixtures on the signed distribution. A sandbox-denied optional operation remains unknown.
- [ ] Complete signed live onboarding/correction acceptance and incoming MailKit callback/account/deadline observations. Apple Mail's validated account-scoped route remains independent of MailKit's unresolved account bridge.
- [ ] Extend move synchronization coverage to slow/offline servers and longer observation windows. Existing 30-second cross-account observations are not a separate server acknowledgement; ambiguous same-account Sent copies remain untouched.
- [ ] Measure automatic sweep latency on large and mutating mailboxes. Bounded repeating scans do not promise immediate coverage.
- [ ] Accumulate independently reviewed labels and calibrate on a representative held-out corpus. No labeled personal corpus exists yet. Conservative 99, Balanced 95 and Aggressive 90 remain provisional. Approximately 1,500 good examples with zero false positives are needed for a rule-of-three upper bound of 0.2%; mock fixtures do not establish that target.
  - The user is accumulating SpamSieve-classified mail in each account’s Junk folder over the coming weeks. Preserve these folders as candidate sources; keep SpamSieve predictions separate from human-confirmed labels. Include reviewed wanted mail and graymail, exclude generated probes, deduplicate, and reserve a holdout before tuning. See `docs/evaluation.md`.
- [ ] Obtain PCC managed entitlement approval and matching profiles if PCC is desired.
- [ ] Complete App Store Connect metadata/privacy disclosures, Mail Automation exception justification, signed store export, store validation and App Review. Drafts and a signed archive exist; local export stopped at Apple Distribution Keychain access before producing a package. No upload or publication has been performed.

# Deferred work

- **Apple model backends.** On-device `SystemLanguageModel`: 4,096-token context per session; default guardrails check input and output and throw `guardrailViolation`/`refusal`; `permissiveContentTransformations` works **only for string output**, not guided generation — so classifying adult/scam spam likely needs string output parsed into a verdict, or treating guardrail errors as a weak spam signal. `PrivateCloudComputeLanguageModel`: 32K context, light/moderate/deep reasoning, per-user daily quota (`quotaUsage`, `quotaLimitReached`; higher with iCloud+), requires the managed entitlement `com.apple.developer.private-cloud-compute` (eligibility application), guardrails not configurable, requires network. Compare with the eval harness before offering.
- **OpenAI / Gemini backends** via their Foundation Models providers or a Chat Completions–compatible `LanguageModel`.
- **Blocklist/allowlist editing UI** with import/export.
- **Policy distillation** from accumulated correction examples.
- **Retrieval-based examples** (k most similar corrections per message).
- **Learned per-user weights** (logistic regression over evidence + verdict, regularized toward defaults).
- **Fingerprinting** user-junked mail to catch campaign variants.
- **URI/DNS blocklist lookups** (Spamhaus DBL etc.) with correct usage-terms handling.
- **Rspamd sidecar:** run Rspamd locally and pass its symbols (via `rspamc`) into the EvidenceBundle.
- **Bayes as a weak signal**, auto-trained only from high-confidence model verdicts no other signal contradicts.
- **Direct IMAP mode** (server-side, protects iPhone/iPad; headless).
- **Other mail clients** via `MailClientAdapter`.
- **Image-only spam** via multimodal input or Vision OCR.
- **Mac App Store distribution.**
- **Full Help book coverage**, localization.
- **Weekly digest** of Review items.

## Follow-up context

- Direct IMAP findings: a separate IMAP connection can see server-routed Junk and protect other devices, but requires per-provider OAuth or app passwords, UIDVALIDITY/UID account-scoped identity, mailbox SPECIAL-USE discovery, IDLE reconnect and conflict handling. No IMAP code is included in Phase 1. Start with a read-only spike and provider terms review.
- Validate signed runtime integration: use the checklist in docs/probes before selecting an automatic route. SDK support does not establish callback timing or account coverage.
- Investigate delayed iCloud move synchronization. The disposable native AppleScript round trip initially acknowledged success, then Mail recovered the received copy; a later move did not remain visible after synchronization. Keep that account unvalidated. Setup now delays and rechecks source/mailbox, but this is not a server acknowledgement. Self-sent probes also duplicate Message-ID in Sent, so use a different sender account when testing ordinary account-scoped lookup.
- Calibrate thresholds on a representative held-out corpus. 99/95/90 are provisional, uncalibrated; zero errors on fixtures do not demonstrate the ≤1-in-500 target. About 1,500 good examples with zero false positives are needed for the rule-of-three 0.2% upper bound.
- Each item above needs evaluation/UX work before release; existing entries retain the original brief’s rationale and constraints.
- Complete live onboarding and correction acceptance. The provisioned XCTest runner passes offline four-step onboarding, simulated denied Mail permission, dry-run status, Pause, address-rule replacement, explicit domain correction, and retained corrections after action failure. One signed-app Haiku verification succeeded with measured usage; actual Mail permissions and live correction actions remain separate acceptance checks.
- Measure sweep latency on large/mutating mailboxes during the signed runtime probe. Discovery uses bounded repeating pages and restarts after app relaunch; it does not promise immediate coverage.

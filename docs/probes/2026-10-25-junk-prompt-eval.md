# Junk prompt evaluation, October 25, 2026

The classification prompt was changed so that Claude Haiku's Junk verdicts on
clear-cut spam and scams can reach the provisional Junk thresholds (90, 95 and 99 in
`Decision.swift`, unchanged). This page compares main's prompt with two candidate
wordings on the same public good and junk messages and the five fixtures. Status is in
[TODO.md](../../TODO.md).

## Change

The shipped wording (run "final" below):

- Opens with "Use review for messages whose content leaves it genuinely unclear
  whether the recipient wants them" in place of "Prioritize precision: uncertain
  messages belong in review".
- Says spam and scams belong in Junk when the content shows them, in place of "scams
  belong in junk or review", and that a sales pitch from an identifiable business is a
  promotion, not spam.
- Defines confidence as certainty in the chosen label and asks for 95 or more for Junk
  only when the content alone shows spam or a scam no legitimate sender would send
  (payment, credential, bank-detail, gift-card or cryptocurrency demands, or a
  well-known brand impersonated from an unrelated domain), and less when a legitimate
  sender could plausibly have sent it.
- Says trusted authentication matters for believing a sender is who it claims, and
  that unverified or untrusted authentication is no reason for Review or lower
  confidence when the content shows spam or a scam.
- When the account has no trusted receiving servers (`trustedServersConfigured` false),
  the message context carries an empty `authResults` and one `unverifiedAuthentication`
  line, such as `dkim=pass, dmarc=pass, spf=pass`, built only from the parsed mechanism
  and result values.

Category preferences, the injection rules and fail-open handling are unchanged. The
evaluation response cache keys on the full instructions and prompt, so no verdict from
the old prompt is reused. The first candidate ("v1") lacked the confidence definition
and the promotion sentence, and named "a brand offer from an unrelated domain".

## Set

| Set | Source | Messages | Label |
| --- | --- | --- | --- |
| Hard ham | SpamAssassin `20030228_hard_ham` (evaluation-only source) | 80 | good |
| Spam | Bruce Guenter archive, 2026-09 | 25 | junk |
| Phishing | Jose Nazario phishing corpus, 2025 | 25 | junk |
| Fixtures | `eval/fixtures` with `eval/fixture-state.json`, three passes each | 5 × 3 | 2 good, 2 junk, 1 graymail |

The downloads matched the SHA-256 hashes in
[`Tools/Corpus/sources.json`](../../Tools/Corpus/sources.json). Each source's messages
of at most 2 MB were sorted by SHA-256 of their bytes and the first 80, 25 and 25
taken. Hard ham is non-spam mail from 2002 that resembles spam (newsletters, mailing
lists, vendor mail), so it is a difficult negative set, though dated. Labels are the
sources' own. No account trusted a receiving server and no user mailbox was used. Each
class ran as its own corpus directory so per-message verdicts could be attributed.

## Commands

Each run used the built `spamwise-eval` for its prompt, a fresh cache and the task's
own ledger:

```sh
swift Scripts/evaluate-with-keychain.swift /path/to/spamwise-eval claude --live \
  corpus /private/path/SET --budget-store /private/path/budget.store \
  --budget-limit 4 --reservation 0.008 \
  --cache /private/path/cache-RUN --output /private/path/report-RUN.json \
  [--state eval/fixture-state.json]
```

`--reservation 0.008` is above Haiku's $0.0077 full-size request bound, which the CLI
enforces as the option's minimum.

## Results

Model labels, with confidence, and Balanced (95) decisions:

| Set | Run | Model labels | Model Junk confidence | Balanced decisions |
| --- | --- | --- | --- | --- |
| Hard ham (80) | baseline | 49 Inbox, 31 Review, 0 Junk | — | 49 Inbox, 31 Review |
| | v1 | 60 Inbox, 18 Review, 1 Junk; 1 network failure | 90 (a newsletter trial offer) | 60 Inbox, 19 Review, 1 unclassified |
| | final | 58 Inbox, 22 Review, 0 Junk | — | 58 Inbox, 22 Review |
| Spam and phishing (50) | baseline | 40 Junk, 8 Review, 2 Inbox | 72–97; 3 at 90 or more, 2 at 95 or more | 2 Junk, 46 Review, 2 Inbox |
| | v1 | 42 Junk, 6 Review, 2 Inbox | 80–98; 26 at 90 or more, 24 at 95 or more | 24 Junk, 24 Review, 2 Inbox |
| | final | 42 Junk, 6 Review, 2 Inbox | 80–98; 22 at 90 or more, 17 at 95 or more | 17 Junk, 31 Review, 2 Inbox |
| Good fixtures (6) | baseline | 6 Inbox, 80–85 | — | 6 Inbox |
| | v1 | 6 Inbox, 85–90 | — | 6 Inbox |
| | final | 6 Inbox, 85–90 | — | 6 Inbox |
| Junk fixtures (6) | baseline | filler spam Junk 72, 72, 72; cart Review 60–62 | 72 | 6 Review |
| | v1 | filler spam Junk 96, 96, 96; cart Review 60–62 | 96 | 3 Junk, 3 Review |
| | final | filler spam Junk 88, 88, 90; cart Review 60–62 | 88–90 | 6 Review |
| Graymail fixture (3) | baseline | Review 80 | — | 3 Review |
| | v1 | Review 0, 2, 8 | — | 3 Review |
| | final | Review 80, 85, 85 | — | 3 Review |

Final, by source under Balanced: 3 of 25 Guenter spam and 14 of 25 Nazario phishing
went to Junk (baseline 0 and 2). The two phishing messages that went to Inbox did so
under every prompt. At Aggressive (90), the final prompt would move 22 of 50 junk
messages and no good message.

No legitimate message received a model Junk verdict from the final prompt at any
confidence, so none could reach Junk under any strength. Its hard-ham confidence
buckets were Inbox: 4 below 70, 10 at 70–79, 41 at 80–89, 1 at 90–94, 2 at 95 or
more; Review: 12 below 70, 5 at 70–79, 5 at 80–89. Baseline's were Inbox: 7, 22, 20,
0, 0; Review: 11, 13, 7.

v1 is not shipped: it gave one hard-ham promotion a model Junk verdict at 90 (the
promotion preference bounded it to Review) and sometimes returned confidence 0–8 for
Inbox and Review labels. The final wording removed the Junk verdict and fixed the
graymail fixture, but 11 hard-ham Inbox or Review verdicts still have confidence 0–5,
where baseline's lowest was 40. Decisions don't use confidence for those labels, but
the app shows it and the Review digest sorts by it.

## Cost

Four hundred and forty requests (145 per prompt, plus a five-message mixed fixture
check on the baseline) used about 1.8 million input and 44,500 output tokens, an
estimated **$0.19**, with one failed request. The task ledger committed $3.52 of its
$4 ceiling at $0.008 per request. Commitments in the ledgers found locally total
about $37 of the $150 evaluation ceiling.

## Limits

One model, one run of each corpus per prompt, and the wording was revised after seeing
these hard-ham results, so this is a development set. It bounds no false-positive
rate: 80 good messages with no Junk verdict put the one-sided 95% upper bound near
3.7%. Hard ham is from 2002 and has no modern receipts or account notices. Thresholds
need a separate calibration holdout.

# Graymail first-run screening

On 2026-10-21, a bounded private-mail screening favored a less presumptive default
policy: keep ordinary wanted mail in Inbox and surface unfamiliar sales promotions
in Review. This improves the observed review burden; it does not establish general
accuracy or reliable one-shot personalization.

## Method

- Evaluated the production pipeline from `5d302d7`, using `claude-haiku-5-5`,
  balanced strength and forced dry run. No mail actions were dispatched.
- The owner authorized Claude for this evaluation only, with a $10 ceiling inside
  the existing $150 evaluation ceiling. The app's ongoing Claude consent stayed off.
- Read Junk through Apple Mail's mailbox export, never its databases. The two
  exported mailboxes contained 308 messages. Only 16 selected graymail candidates
  and four selected wanted controls were sent to Claude, alongside synthetic cases.
- Reserved eight graymail candidates, two wanted controls and four synthetic wanted
  controls before policy tuning. Development used the same counts. Sender domains
  were disjoint between the two real-mail sets, and recognized related storefront
  messages stayed together. This was not an exhaustive campaign/template audit.
- Junk membership was a sampling signal, not a confirmed user label. An agent
  reviewed the four real wanted controls. Eight authored wanted controls covered
  receipts, shipping, security, verification, appointments, maintenance, community
  updates and substantive newsletters. Report these separately from real mail.
- Each condition started without sender rules, Contacts, purchase or correspondence
  history, trusted receiving servers, or optional network evidence. The candidate
  changed only the editable policy. It was frozen before scoring the reserved set.
- The one-shot condition added one simulated Junk correction for a development
  abandoned-cart example, scoped to the evaluation account, with an example limit
  of one. Decoding and account eligibility were checked. No production learning or
  sender rule was written, and the correction was not an owner-confirmed preference.
- Four additional authored deceptive messages tested payment pressure, delivery-fee
  credential theft, payment diversion and prompt injection. They were frozen before
  their calls and are a separate challenge set, not an independent real-mail holdout.
- Failed classifications were retained and not retried. One initial successful
  baseline result was replayed from cache; it was not a second paid request.

Raw messages, state snapshots, the frozen selection manifest, per-case reports and
cached verdicts remain in private ignored local artifacts. No message content,
addresses, credentials, or owner-specific rules are included in this report.

## Results

These are **effective dry-run decisions** after the unchanged action policy. Counts
are Inbox / Review / Junk / unclassified, and each row's denominator includes
failures.

| Set | Cases | Original default | Revised default | Revised + one example |
| --- | ---: | --- | --- | --- |
| Development graymail candidates | 8 | 0 / 7 / 0 / 1 | 1 / 7 / 0 / 0 | Not run |
| Development real wanted controls | 2 | 1 / 1 / 0 / 0 | 2 / 0 / 0 / 0 | Not run |
| Development synthetic wanted controls | 4 | 0 / 4 / 0 / 0 | 4 / 0 / 0 / 0 | Not run |
| Reserved graymail candidates | 8 | 0 / 7 / 0 / 1 | 0 / 7 / 0 / 1 | 0 / 8 / 0 / 0 |
| Reserved real wanted controls | 2 | 1 / 1 / 0 / 0 | 2 / 0 / 0 / 0 | 1 / 0 / 0 / 1 |
| Reserved synthetic wanted controls | 4 | 0 / 4 / 0 / 0 | 4 / 0 / 0 / 0 | 4 / 0 / 0 / 0 |
| Synthetic deceptive challenges | 4 | 0 / 2 / 2 / 0 | 0 / 3 / 1 / 0 | Not run |

Across development and reserved cases, the original policy put 2/4 real wanted
controls and 0/8 synthetic wanted controls in Inbox. The revised policy put 4/4 and
8/8 there respectively. Both surfaced 14/16 graymail candidates as Review. The
revised policy kept one substantive informational newsletter in Inbox; treating
this owner's dislike of it as a universal default would overfit.

The original policy's reasons repeatedly treated missing history as evidence of
unwanted mail or demanded an order match for ordinary transactional notices. The
revised policy explicitly preserves unknown history and distinguishes informational
content from sales intent. No sender, brand, topic interest or recipient address
was added to the default.

The one-shot run changed two reserved model labels from Review to Junk, but their
confidence stayed below the unchanged balanced Junk threshold of 95, so their
effective decisions remained Review. Its support-control failure also means the
observed eighth graymail Review is not evidence of a reliable improvement. Keep
examples optional; these results do not justify stronger automatic actions or a
claim of one-shot success.

There were four invalid-output failures among 78 paid attempts: two under the
original default, one under the revised default and one in the one-shot run. They
failed open. All eight challenge classifications stayed out of Inbox, but four
authored cases cannot establish phishing protection; one challenge moved from
effective Junk to Review under the revised policy.

## Spending and reproducibility

The task ledger reserved **$7.80 for 78 attempts** against its $10 cap. Prior
evaluation commitments were $2.60, making combined conservative commitments $10.40
against the overall $150 ceiling. Valid responses reported approximately **$0.0255**
in token-cost estimates. That is not an invoice: failed-output usage and undisclosed
cache-write charges are not fully represented, so the conservative reservation is
the spending bound.

Candidate policy SHA-256, UTF-8 without a trailing newline:

```text
a343a62a6ec44cd3190460e4a7493d30dc8d1facbef76679c54f5e5e1a792358
```

To repeat with separately authorized mail, freeze a small sender-disjoint selection
and wanted controls first; run each case through `spamwise-eval corpus` with an
isolated `--state`, `--budget-store`, `--cache` and `--output`. Compare the original
policy, the candidate, and the candidate with one account-scoped correction. Keep
failed outcomes in the denominator, report model labels separately from effective
actions, and reserve new accounts and campaigns for the next evaluation. Do not
reuse this scored reserved set as a fresh holdout for another tuning round.

## Product changes and remaining acceptance

The initial editable policy now uses the screened generic policy, with Spanish and
French settings translations. Existing saved policies are not migrated. Junk
thresholds, rule precedence, consent, dry run and action safeguards are unchanged.

Sampling also exposed an export crash: Foundation rejects combining `.atomic` and
`.withoutOverwriting`. Export now uses `.withoutOverwriting`; the repaired path
successfully exported a bounded Inbox sample. A repeat export returned an ordinary
existing-file error and left the exported bytes and file count unchanged.

The Xcode app's first policy save failed with a missing `ZCHANGEROW` table while
the store still had its V1 schema. A private backup opened and migrated with the
current core; restarting the Xcode app then migrated the live store successfully.
The policy editor saved the screened policy, verified against the stored policy
hash. Filtering remained paused, dry run stayed on and Claude sharing stayed off.
The current app's Junk review loaded 19 messages on its first page and explicitly
reported one unreadable message; no restore action was chosen.

Its settings showed no saved app API key; paid comparisons used the Keychain-backed
evaluator rather than a signed-app provider request. A clean end-to-end signed-app
setup/classification remains an acceptance gap.

This is one English-language owner's selected mail, one provider/model, one pass
per condition and a very small reserved set. Broader owners, language coverage,
owner-adjudicated wanted newsletters, matched transactional hard negatives,
campaign-disjoint samples and repeated runs remain necessary. The translations
were supplied for the UI; their classification efficacy was not measured here.

Verification passed: `Scripts/check.sh` ran localization and Help checks, 384
package tests, both edition builds, the extension build and 63 hostless tests.
Strict SwiftLint reported zero violations. Markdown lint and static-site
generation/check passed. The native checks above used the current Xcode build;
the automated UI suite was not run for this policy-only change.

# Junk-folder first-run screening

On 2026-10-24, a bounded private screening of the owner's Junk folders shaped
first-run category preferences, a setup step that learns from existing Junk, and
corrections that tune whole categories. It also found that one provider request in
four failed open on real mail because of a reason-length check. It does not establish
general accuracy, Junk-move readiness or a one-shot benefit.

## Method

- Read each account's Junk and a bounded Inbox sample through Mail scripting, never
  its databases. Exported 495 unique Junk messages: 453 iCloud and 42 Google. One
  Google message over 2 MB was skipped. No probes were present. Inbox messages were
  read only to choose wanted controls.
- The owner confirmed that everything in Junk is unwanted spam or graymail, so Junk
  membership is the owner's label here. Its subcategory (promotion, newsletter and so
  on) was assigned by an agent from sender and subject, not by the owner.
- Wanted controls were 15 agent-selected Inbox messages: bulk and transactional mail
  the owner kept, such as club events and surveys, a product update from a sender
  whose promotions were in Junk, settlement notices, tickets, invoices and a renewal.
  Personal and medical correspondence was excluded. These are provisional labels.
- The manifest was frozen before any model call. Messages were grouped by registrable
  domain, or by display name for Hide My Email relays, with one representative per
  sender. Sender groups were disjoint between development (31 unwanted, 6 wanted) and
  holdout (40 unwanted, 9 wanted). Every sender from the 2026-10-21 screening was
  excluded.
- Each case ran alone through `spamwise-eval corpus` with `claude-haiku-5-5`,
  balanced strength, forced dry run, and an isolated state, cache and report. There
  were no sender rules, Contacts, history, trusted receiving servers or network
  evidence. Failures were kept and not retried.
- Conditions:
  - **A:** the shipped prompt and policy, as a frozen binary.
  - **B:** this change's prompt with categories and first-run preferences.
  - **C:** B with the preferences the owner's Junk implies: every graymail category
    Junk except product news (Flag) and clubs and groups (Keep).
  - **D:** C plus the setup import, with one excerpted example from each of the 100
    most frequent Junk senders outside the holdout, imported without a category.

  B was compared with A on development and frozen without revision. A, C and D then
  ran once on the holdout.

Raw messages, manifests, states, per-case reports and cached verdicts stay in private
ignored local artifacts. No message content, addresses or owner-specific rules are in
this report.

## What the Junk folders hold

| Agent subcategory | Messages | Senders |
| --- | ---: | ---: |
| Store promotions | 311 | 91 |
| Newsletters | 48 | 17 |
| Event and ticket offers | 40 | 18 |
| Product news | 22 | 14 |
| Social network notifications | 20 | 7 |
| Spam | 12 | 4 |
| Card and loan offers | 9 | 7 |
| Cart reminders | 8 | 5 |
| Surveys and review requests | 8 | 3 |
| Fundraising | 6 | 4 |
| Sales pitches | 6 | 5 |
| Scams | 4 | 2 |
| Other (a verification code) | 1 | 1 |

Of the 495 messages, 418 carry List-Unsubscribe. Almost all of this owner's Junk is
legitimate bulk mail, often from brands they deal with, rather than spam. The Inbox
also keeps bulk mail from some of the same senders and kinds: club events and
surveys, product updates for a device the owner bought, and renewal notices. One
sender appears in both folders depending on content. Preferences therefore apply to
a message's kind, not to its sender, and clubs and groups are their own category.

## Results

Effective dry-run decisions, as Inbox / Review / Junk / unclassified. An
unclassified message stays in Inbox untouched.

| Condition | Unwanted | Wanted controls |
| --- | --- | --- |
| A, development | 6 / 18 / 0 / 7 | 3 / 2 / 0 / 1 |
| B, development | 7 / 24 / 0 / 0 | 3 / 3 / 0 / 0 |
| A, holdout | 5 / 25 / 0 / 10 | 2 / 4 / 0 / 3 |
| C, holdout | 0 / 40 / 0 / 0 | 2 / 7 / 0 / 0 |
| D, holdout | 0 / 40 / 0 / 0 | 2 / 7 / 0 / 0 |

- **Failures:** 21 of A's 86 requests (24%) failed with `invalidOutput`. The model's
  reasons often ran past 240 characters, and the guided and JSON decoders rejected
  them instead of shortening them as `Verdict` already does. Shortening them, and
  asking for 200 characters, left no failures in B, C or D's 135 requests.
- **First-run defaults (B):** flagged every development promotion, cart reminder,
  card offer and survey, and kept the event offers, newsletters and product news that
  the cautious defaults keep. That is the intended zero-shot behavior. These are the
  categories setup now asks about.
- **Owner preferences (C):** flagged all 40 holdout messages, against 25 for A,
  where 10 more failed open. The model labeled 38 of them Junk, but at confidences
  of 0–92. None reached the balanced threshold of 95, so none was moved.
- **Wanted controls under C:** Junk preferences also caught mail the owner kept: a
  museum event and a clinic registration (events), an insurance offer and a device
  maker's discount. A threshold of 85 would have moved 20 unwanted holdout messages,
  and 2 of these 9 controls, to Junk. Two transactional notices were flagged because
  no receiving server was trusted.
- **Model categories:** matched the agent subcategory for 32 of 40 holdout messages.
  The differences were mostly cold outreach, spam or product news called promotion.
- **Junk import (D):** gave the same effective decisions as C. Three model labels
  moved from Junk to Review. This is no evidence of a one-shot benefit.

Junk thresholds stay unchanged. A Junk preference flags graymail for Review until the
classifier is confident enough for the filtering strength. Moving it automatically
needs calibration on owner-reviewed mail with trusted receiving servers.

## Product changes

- **Classifier:**
  - The model also names one of 15 categories.
  - The generic first-run guidance (unknown history is not unwanted, a claimed
    subscription is not proof) moved into the fixed instructions.
  - The editable policy is now "additional instructions" with an empty default.
    Saved shipped defaults migrate to empty; custom text is kept.
  - Reasons are shortened rather than rejected.
- **Decision:** applies the user's graymail preference to model verdicts only. Keep
  never moves to Junk, Flag always flags, and Junk never leaves mail unflagged.
  Personal, transactional, spam and scam verdicts and every gate decision keep the
  existing policy.
- **Setup:** a new step chooses Keep, Flag or Junk per kind. It can scan up to 400
  recent Junk messages per Apple Mail account and save one reviewed example per
  sender, skipping Contacts and correspondents. The import creates no rules and moves
  no mail.
- **Corrections:**
  - Each correction keeps a 160-character local excerpt and the model's category.
    Full reviewed content and learning stay off by default.
  - After a Good, Review or Junk correction of graymail, the inspector offers to
    apply that choice to the whole category.
  - An unverified Junk correction can be saved as a scam without a Block rule.
- **Settings:** Preferences replaces Policy. It suggests a category change when at
  least three corrections from at least two domains agree.

## Spending

The task ledger reserved **$22.50 for 225 attempts** against its $25 cap: the 221
cases above and four diagnostic reruns of failed baseline cases. Combined with the earlier $10.40,
conservative commitments are $32.90 of the $150 ceiling. Valid responses reported
about **$0.11** in token-cost estimates, which is not an invoice.

## Limits

This is one English-language owner, one provider and model, and one pass per
condition. The holdout is small, wanted controls are agent-selected Inbox mail, and
subcategories are agent-assigned. No receiving server was trusted, and the scored
holdout must not be reused for the next tuning round.

Still needed:

- owner-adjudicated wanted graymail;
- trusted receiving servers in evaluation;
- multilingual mail;
- repeated runs;
- a signed-app setup with a real Junk import.

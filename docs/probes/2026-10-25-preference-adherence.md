# Preference adherence, October 25, 2026

This evaluation measures whether SpamWise gives each message the action that the
user's mail choices call for, and sets `FilteringStrength.graymailThreshold`: the
category confidence at which graymail in a category the user chose Junk for moves to
Junk, whatever its label. It compares main (`0c74636`, label policy only) with the
category-confidence change (`0b7db68`, provisional 95, 85 and 75). The result sets the
values to 95, 90 and 85. They are still provisional. Status is in
[TODO.md](../../TODO.md).

## Data

There are 155 messages. The harness and message set are in `Tools/Preferences`
(`adherence.py`, `authored.toml`, `profiles.json`).

| Source | Messages | Kind |
| --- | --- | --- |
| Marketeam (`marketeam-56377f4`) | 80 | Synthetic, LLM-written agency work mail, wrapped as colleague mail from fictional `.example` domains |
| Authored (`authored.toml`) | 65 (50 en, 8 es, 7 fr) | Synthetic graymail, wanted controls and boundary cases from reserved `.example` domains |
| Nazario phishing, 2025 | 5 | Public, unmodified |
| Guenter spam, 2026-09 | 5 | Public, unmodified |

The downloads matched the SHA-256 hashes in
[`Tools/Corpus/sources.json`](../../Tools/Corpus/sources.json). Only the five
phishing samples carry Authentication-Results, their original headers, and no
profile configures a trusted receiving server. Message ids are shuffled across
sources, and the manifest holds no categories.

Two labelers, both Claude agents working independently from a written rubric that
lists `MailCategory` and asks for each message's main purpose, labeled all 155
messages. They agreed on all 155 (raw agreement 100%, Cohen's kappa 1.000, chance
agreement 0.317), and no message was excluded. Their notes differ in wording and name
different considered alternatives, but perfect agreement between two labelers from
the same model family says more about shared bias than about easy mail. Frozen labels
match the author's intended category for all 65 authored messages. A seeded split,
stratified by category, gives 78 dev and 77 holdout messages.

| Category | Dev | Holdout |
| --- | --- | --- |
| personal | 42 | 43 |
| transactional | 5 | 5 |
| community | 3 | 2 |
| promotion | 3 | 3 |
| abandonedCart | 2 | 2 |
| newsletter | 4 | 3 |
| productUpdate | 2 | 2 |
| event | 2 | 2 |
| socialNotification | 2 | 1 |
| survey | 2 | 2 |
| financialOffer | 2 | 3 |
| fundraising | 2 | 2 |
| coldOutreach | 3 | 3 |
| spam | 1 | 1 |
| scam | 3 | 3 |

All 80 Marketeam messages were labeled personal. Two Guenter spam samples were labeled
coldOutreach and one scam.

## Profiles

`profiles.json` defines five profiles. The $5 ledger allowed four profile runs (see
Cost), so two were run on both binaries:

- `declutter`: Junk for promotions, carts, events, social notifications, surveys,
  financial offers, fundraising and cold outreach; Flag for newsletters and product
  updates; Keep for community mail.
- `deal-seeker`: Junk for carts, financial offers and cold outreach; Flag for
  fundraising; Keep for the rest, including promotions and events.

`defaults` and `permissive` choose no Junk, so the change can't affect their
decisions. `inbox-minimalist` was not run.

## Method

Each profile ran under Balanced with its own AppState snapshot: its category
preferences, dry run, and no rules, corrections, Contacts, history or trusted
receiving servers. Each run used its own cache and Claude Haiku 5.5 through
`Scripts/evaluate-with-keychain.swift`, with no retry and no model fallback.

The expected action is the profile's choice for graymail (Keep is Inbox, Flag is
Review, Junk is Junk) and Inbox for personal and transactional mail. Spam and scams
are scored separately as the spam path. The measures are:

- **Adherence**: the effective action equals the expected one.
- **Wrong Junk**: expected Inbox or Review, but Junk.
- **Missed Junk**: expected Junk, but not Junk.
- **Review burden**: the share of scored messages flagged for Review.
- **Category accuracy**: the model's category equals the frozen label.

Rates carry Wilson 95% intervals. An unclassified message counts against adherence.

The candidate reports every message's label, confidence, category and category
confidence, so its decisions were recomputed offline at each threshold from 50 to
100 using `Decision.evaluate`'s rule. Below the threshold the label policy applies,
so a Junk label at 95 or more still moves the message. A plain rule that uses Review
below the threshold gives identical numbers at every threshold, because no
Junk-preferred verdict combined a Junk label at 95 or more with a category confidence
below the threshold. The harness's `score` sweep reproduces them.

The threshold was chosen on dev only. The rule was the lowest threshold with zero dev
wrong Junk across both profiles and the highest adherence among those, so the dev
numbers alone determine it. The choice was recorded before the holdout scores were
written, although the same batch had already computed the holdout sweep.

Three candidate requests failed: one timeout (m119) in `declutter` and two network
errors (m110, m111) in `deal-seeker`, all dev messages. They stay unclassified, which
is how the app fails open: the mail is left untouched. The harness used for these
runs stopped a profile whose first pass left a message unclassified, before its
replay pass, so those two profiles' results were taken from the evaluator's complete
`observations` list. The harness now reads that list itself in one pass and gives
the same rows. The baseline evaluator has no such list, and its two runs completed
both passes with no failures.

## Results

The candidate's "85" rows are the decisions the run made at Balanced 85. Its "90"
rows recompute those verdicts at 90. The baseline has no category threshold.

### Dev

| Binary | Profile | Adherence | Wrong Junk | Missed Junk | Review burden | Category accuracy | Spam path (Junk, Review, Inbox) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| baseline | declutter | 42/74 56.8% (45.4–67.4) | 0/56 0.0% (0.0–6.4) | 18/18 | 51.4% | 83.3% | 2, 2, 0 |
| baseline | deal-seeker | 50/74 67.6% (56.3–77.1) | 0/67 0.0% (0.0–5.4) | 7/7 | 35.1% | 83.3% | 2, 2, 0 |
| baseline | both | 92/148 62.2% (54.1–69.6) | 0/123 0.0% (0.0–3.0) | 25/25 | 43.2% | 83.3% | 4, 4, 0 |
| candidate 85 | declutter | 53/74 71.6% (60.5–80.6) | 0/56 0.0% (0.0–6.4) | 0/18 | 35.1% | 83.3% | 3, 1, 0 |
| candidate 85 | deal-seeker | 53/74 71.6% (60.5–80.6) | 1/67 1.5% (0.3–8.0) | 0/7 | 27.0% | 79.5% | 2, 2, 0 |
| candidate 85 | both | 106/148 71.6% (63.9–78.3) | 1/123 0.8% (0.1–4.5) | 0/25 | 31.1% | 81.4% | 5, 3, 0 |
| candidate 90 | declutter | 51/74 68.9% (57.7–78.3) | 0/56 0.0% (0.0–6.4) | 2/18 | 37.8% | 83.3% | 2, 2, 0 |
| candidate 90 | deal-seeker | 53/74 71.6% (60.5–80.6) | 0/67 0.0% (0.0–5.4) | 0/7 | 28.4% | 79.5% | 2, 2, 0 |
| candidate 90 | both | 104/148 70.3% (62.5–77.0) | 0/123 0.0% (0.0–3.0) | 2/25 | 33.1% | 81.4% | 4, 4, 0 |

### Holdout

| Binary | Profile | Adherence | Wrong Junk | Missed Junk | Review burden | Category accuracy | Spam path (Junk, Review, Inbox) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| baseline | declutter | 30/73 41.1% (30.5–52.6) | 0/55 0.0% (0.0–6.5) | 18/18 | 65.8% | 67.5% | 3, 1, 0 |
| baseline | deal-seeker | 38/73 52.1% (40.8–63.1) | 0/65 0.0% (0.0–5.6) | 8/8 | 50.7% | 67.5% | 2, 2, 0 |
| baseline | both | 68/146 46.6% (38.7–54.7) | 0/120 0.0% (0.0–3.1) | 26/26 | 58.2% | 67.5% | 5, 3, 0 |
| candidate 85 | declutter | 43/73 58.9% (47.4–69.5) | 0/55 0.0% (0.0–6.5) | 0/18 | 47.9% | 68.8% | 2, 2, 0 |
| candidate 85 | deal-seeker | 47/73 64.4% (52.9–74.4) | 3/65 4.6% (1.6–12.7) | 0/8 | 34.2% | 68.8% | 2, 2, 0 |
| candidate 85 | both | 90/146 61.6% (53.6–69.1) | 3/120 2.5% (0.9–7.1) | 0/26 | 41.1% | 68.8% | 4, 4, 0 |
| candidate 90 | declutter | 40/73 54.8% (43.4–65.7) | 0/55 0.0% (0.0–6.5) | 3/18 | 52.1% | 68.8% | 2, 2, 0 |
| candidate 90 | deal-seeker | 46/73 63.0% (51.5–73.2) | 0/65 0.0% (0.0–5.6) | 1/8 | 39.7% | 68.8% | 2, 2, 0 |
| candidate 90 | both | 86/146 58.9% (50.8–66.6) | 0/120 0.0% (0.0–3.1) | 4/26 | 45.9% | 68.8% | 4, 4, 0 |

The baseline's Junk choices never reached Junk. The model labeled all 51
Junk-preferred graymail messages Junk, at confidence 0–92, so Balanced's 95 turned
each into Review. On main, choosing Junk for a category behaves like choosing Flag.

### Wrong Junk by category

Every wrong Junk at any threshold was personal Marketeam colleague mail that the model
called cold outreach. The model put 34 of 85 personal messages in coldOutreach under
`declutter` and 36 under `deal-seeker`, at category confidence 40–85. Genuine
Junk-preferred graymail scored 85–96.

| Threshold | Dev | Holdout |
| --- | --- | --- |
| 75 or 80 | 11 (personal → coldOutreach) | 22 (personal → coldOutreach) |
| 85 | 1: m140 (`deal-seeker`) | 3: m013, m035, m152 (`deal-seeker`) |
| 90 | 0 | 0 |

The same four messages scored 80 under `declutter` and 85 under `deal-seeker`. Across
the 152 messages both candidate runs classified, the category matched for 139, and
category confidence differed by 3.2 points on average (at most 45). The preferences
in the prompt are enough to move a verdict across the boundary.

### Missed Junk at 90

All six had category confidence exactly 85: dev m102 (event) and m128 (survey) in
`declutter`; holdout m060 (survey), m114 (coldOutreach) and m135 (event) in
`declutter`, and m114 in `deal-seeker`. Each was marked Review.

### Threshold sweep, both profiles

| Threshold | Dev adherence | Dev wrong Junk | Dev missed Junk | Holdout adherence | Holdout wrong Junk | Holdout missed Junk |
| --- | --- | --- | --- | --- | --- | --- |
| 50–55 | 106/148 | 22/123 | 0/25 | 90/146 | 45/120 | 0/26 |
| 60 | 106/148 | 21/123 | 0/25 | 90/146 | 44/120 | 0/26 |
| 65–70 | 106/148 | 17/123 | 0/25 | 90/146 | 32/120 | 0/26 |
| 75–80 | 106/148 | 11/123 | 0/25 | 90/146 | 22/120 | 0/26 |
| 85 | 106/148 | 1/123 | 0/25 | 90/146 | 3/120 | 0/26 |
| 90 | 104/148 | 0/123 | 2/25 | 86/146 | 0/120 | 4/26 |
| 95 | 87/148 | 0/123 | 19/25 | 72/146 | 0/120 | 18/26 |
| 100 | 81/148 | 0/123 | 25/25 | 64/146 | 0/120 | 26/26 |

Below 90, adherence stays flat while wrong Junk rises. Wanted mail that the model
misfiles into a Junk category is non-adherent either way (Review or Junk), and only
the harm grows.

## Threshold choice

- **Balanced: 90.** It is the lowest threshold with zero dev wrong Junk, and nothing
  above it scores higher. Holdout agrees: 0 of 120 wrong Junk at 90, 3 at 85.
  Category confidence clusters at 80, 85, 92 and 95, so 90 in effect means "92 or
  more". The margin over misfiled wanted mail (at most 85) is one step of the
  model's scale.
- **Aggressive: 85, not Balanced − 10 = 80.** On dev, 80 matched 85 on adherence and
  missed Junk but had 11 wrong Junk against 1. Lowering it only adds harm.
- **Conservative: 95, not min(Balanced + 10, 100) = 100.** No dev verdict reached
  category confidence 100 (the maximum was 97), so 100 would turn the category path
  off for Conservative. 95 had zero dev wrong Junk. This amendment was recorded
  after the holdout scores were written, on that dev-only reason.

`Decision.swift` now has 95, 90 and 85. The Help pages on filtering strength
(en, es, fr), `docs/evaluation.md` and the evaluation test that sits between
Aggressive and Balanced use the new values.

## Cost

There were 620 requests (155 per profile run), with 3 failures. They used 2,006,757
input and 60,061 output tokens, an estimated **$0.23** at Haiku's captured rates
($0.10 and $0.50 per million). The task ledger committed **$4.96 of its $5 ceiling**
at $0.008 per request, the evaluator's minimum reservation (about $0.0078) rounded
up. The ledger never refunds a reservation, so it, and not the actual spend, limited
the runs to four. The replay passes used their own zero-ceiling ledgers and made no
provider request.

## Limitations

- All graymail and all wanted mail are synthetic, and the 80 colleague messages come
  from one LLM-written dataset. The public spam and phishing controls number 10.
- The labelers are Claude agents, and so is the classifier (Haiku). Their perfect
  agreement may reflect a shared reading of the rubric.
- One model, one run per profile, and two of five profiles. Variation between runs
  wasn't measured, but the two profiles alone moved category confidence across the
  85 boundary.
- No trusted receiving server, Contacts, history, rules or corrections. With a trusted
  receiving server, relationship gates send known colleagues to Inbox before the
  model sees them, so the colleague-mail risk measured here applies to new or
  unverified senders.
- Small counts: 25 or 26 Junk-expected and about 120 wrong-Junk-eligible messages per
  split. Zero wrong Junk bounds the rate only below about 3%.
- The threshold was chosen on dev, the scale is coarse, and 90 sits one step above
  the highest misfiled wanted mail.
- The candidate's Inbox-expected adherence was lower than the baseline's on dev (73
  against 84 of 115) and close on holdout (57 against 61 of 113). Single runs can't
  separate an effect of the v4 prompt from noise.

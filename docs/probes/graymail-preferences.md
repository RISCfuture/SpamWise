# Synthetic graymail preferences — 2026-10-16

A twelve-call Haiku probe changed the model's category with an explicit user
policy in English, Spanish and French. It did not establish filter accuracy,
calibration, a benefit from correction examples, or fine-tuning performance.

## Frozen inputs and method

[Authored inputs](../../Tools/Preferences/cases.json) contain one gardening
newsletter translated into three languages, each with practical advice and an
ordinary plant promotion. The same message bytes run under wanted and unwanted
policies. Each policy is tested without examples (zero-shot policy) and with two
analogous correction examples from different subjects and sender domains. The
policy is identical between these conditions. There are three translated
messages and twelve contexts, not twelve independent email samples.

All text, preferences, labels and examples were authored for this probe. The
synthetic target stays outside model input; every CLI corpus entry is graymail.
Correction labels are supplied only on the two different example messages. No
sender rules, Contacts, history, retrieved private examples or statistical
models are supplied. No weight update, fine tuning, real-user personalization or
model selection occurred.

The [runner](../../Tools/Preferences/README.md) passed all twelve conditions through
the existing CLI in explicit mock mode before live execution. Its two tests
verify paired-message/state isolation and first-failure stopping. Twelve distinct
prompt cache keys and separate cache directories keep all live conditions
uncached. The three messages each retain one stable hash across all four contexts.
The CLI uses isolated temporary classification state and forced dry run; no Mail
actions or production settings change.

Primary [Haiku documentation](https://platform.claude.com/docs/en/models/haiku-5-5/overview)
and [pricing](https://platform.claude.com/docs/en/about-claude/pricing) were checked
before the first request. The explicit model was `claude-haiku-5-5`, low effort,
no fallback, maximum 1,024 output tokens. Rates for these short prompts were
$0.10/$0.50/$0.01 per million input/output/cache-read tokens. Cache-write premiums
are not separately exposed, so cost remains estimated.

## Observations

| Language | Policy | Policy-only model label / confidence | With two examples model label / confidence | Effective decision in both conditions |
| --- | --- | --- | --- | --- |
| English | Wanted | Inbox / 80 | Inbox / 78 | Inbox |
| English | Unwanted | Junk / 90 | Junk / 88 | Review |
| Spanish | Wanted | Inbox / 88 | Inbox / 72 | Inbox |
| Spanish | Unwanted | Junk / 90 | Junk / 88 | Review |
| French | Wanted | Inbox / 82 | Inbox / 85 | Inbox |
| French | Unwanted | Junk / 85 | Junk / 88 | Review |

Reasons cited practical gardening content and the user's stated inclusion or
exclusion policy. Some also noted unavailable sender history. Exact reasons and
per-condition tokens are in
[the synthetic results](../../Tools/Preferences/results-2026-10-16.json).
The unchanged Balanced threshold is 95, so all six model Junk judgments became
Review. Confidence values remain uncalibrated.

Policy-only prompts already produced the intended category contrast in each
language. Examples changed confidence but no category, showing no categorical
benefit here. One stochastic run per condition cannot distinguish example
effects from sampling variability.

## Usage and artifacts

All twelve requests succeeded sequentially with zero cache hits and no retries
or fallback. Measured usage was 15,514 input tokens, 1,043 output tokens and zero
cache-read tokens. Estimated new cost was **$0.0020729**. Successful requests
reserved **$1.20** in the existing shared $150 ledger before dispatch: twelve
$0.10 commitments, within this task's $2 authorization. Reservations are separate
from billed cost. The current total shared-ledger balance was not inspected;
prior commitments remain intact. No substitute budget store was created.

Local artifacts are `.build/preferences-20261016-offline/` and
`.build/preferences-20261016-live/`. The latter contains the manifest, twelve
synthetic states/messages, raw reports and private caches. Reproduction inputs,
results and [source/executable hashes](../../Tools/Preferences/audit-2026-10-16.json)
are retained under `Tools/Preferences/`.
Live reproduction spends again and is unnecessary to inspect the recorded results.

## Limits

The explicit matching policies make this contrast deliberately straightforward.
Translations were not independently reviewed by native speakers. There are no
conflicting examples, ambiguous policies, transactional messages, adversarial
messages or independently labeled real emails. Reserved public-corpus holdouts
and personal mail were not accessed. This is an in-context preference smoke test;
it does not establish multilingual accuracy, safe Junk thresholds, beneficial
fine tuning or superiority over another filter.

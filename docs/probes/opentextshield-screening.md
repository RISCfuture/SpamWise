# OpenTextShield email development screening — 2026-10-16

OpenTextShield is an SMS-trained local spam/phishing candidate. This probe tests
transfer to the existing email development cohort; it does not establish useful
universal email detection or select an automatic filtering threshold.

## Provenance and execution boundary

The [immutable model card](https://huggingface.co/telecomsxchange/OpenTextShield/blob/9e839db78bd1daff8062ae2f2638af0b64b416ae/README.md)
declares MIT, multilingual BERT and SMS-domain training. The linked source's
[MIT license](https://github.com/TelecomsXChangeAPi/OpenTextShield/blob/918431dc910bebfb9a77e37f45c83c54c742a28c/LICENSE)
was inspected. The pinned Hugging Face revision is
`9e839db78bd1daff8062ae2f2638af0b64b416ae`; its configuration maps output indices
0/1/2 to `ham`/`spam`/`phishing`, with 512 position embeddings. Both label maps
are checked before interpreting scores. The model contains 177,855,747 parameters.

Only Safetensors weights and tokenizer/configuration data are loaded, using
standard installed Transformers classes. No downloaded repository Python runs.
The model weight is 711,446,532 bytes with SHA-256
`8e5f65efc7fecafc8280b8a817215f80738871d4da206bab94cce1ca43781fe9`, matching
Hugging Face's LFS identity. The complete model/tokenizer/card download is under
716 MB, below the 2 GB ceiling. Public downloads use no authentication; inference
uses offline-only loading, disabled telemetry and implicit authentication,
`trust_remote_code=False`, CPU, eager attention and two threads.

Inputs are raw text from the existing corpus preparation tool. The independent
synthetic smoke inputs concatenate subject, newline and body. Neither run applies
OpenTextShield's production Unicode normalizer. The
[pinned normalization source](https://github.com/TelecomsXChangeAPi/OpenTextShield/blob/918431dc910bebfb9a77e37f45c83c54c742a28c/src/api_interface/services/enhanced_preprocessing.py)
was read, not executed: it removes invisible characters, folds selected
compatibility characters and conditionally folds Greek/Cyrillic look-alikes.
The 96-token run matches the published production token limit, **not the full
production preprocessing pipeline**. The 384-token run remains within the
model's 512-position capacity. Neither reproduces the card's benchmark numbers.

The card reports SMS block rates separately from phishing recall; some benchmarks
overlap its training data. Those author-reported metrics are not our observations
and cannot establish email-transfer quality. A model's multilingual base also
does not establish French/Spanish email accuracy.

## Corpus and label boundaries

Both runs require the complete `spamwise-corpus-v1` manifest and verify all
`records.jsonl` bytes against SHA-256
`1f089e1c8f8e7556fb22ab009c5a2bc3d87d05914aabbc2327737ba625f4f2b9`.
Inference selects exactly the same 491 real validation records as the earlier
Horizon comparison: 181 source-spam positives in 123 template groups, 78
source-phishing positives in 70 groups and 232 source-non-spam records in 225
groups. All real/synthetic train and holdout records, and synthetic validation
records, are excluded from inference. The eleven separately supplied synthetic
smoke cases never enter these cohort metrics.

Spam and phishing are evaluated against their own output scores. Non-spam labels
do not become phishing negatives. Combined spam-plus-phishing alarm counts on
hard-ham are not phishing false-positive rates. This corpus supplies no explicit
phishing negatives. Graymail preference remains separate and is not inferred
from a threat label.

## Reproduction

From the repository root, after installing the pinned
`Tools/Corpus/requirements-model.txt` into the `spamwise-corpus` pyenv environment
and downloading the named snapshot:

```sh
PYENV_VERSION=spamwise-corpus pyenv exec python Tools/Corpus/screen.py \
  --candidate opentextshield --max-tokens 96 \
  --corpus .build/corpus-negatives-20261016/prepared-v1 \
  --snapshot .build/model-screening/opentextshield/9e839db78bd1daff8062ae2f2638af0b64b416ae \
  --output .build/corpus-negatives-20261016/opentextshield-96 \
  --synthetic docs/probes/multilingual-model-smoke.json
```

Repeat with `--max-tokens 384` and a fresh output directory. The default CLI
candidate remains the original pinned Horizon model. Local per-record artifacts
contain identities and scores, not message bodies; committed summaries contain
aggregates plus the independently named synthetic smoke results. No paid calls,
training, app changes, Mail access or production detector integration occur.

## Observed email results

| Observation | 96 tokens | 384 tokens |
| --- | ---: | ---: |
| Source spam: top output spam | 67/181 | 89/181 |
| Source spam: top output ham | 65/181 | 11/181 |
| Source spam: top output phishing | 49/181 | 81/181 |
| Source phishing: top output phishing | 67/78 | 70/78 |
| Source phishing: phishing score at least 0.95 | 59/78 | 57/78 |
| Hard-ham: spam score at least 0.5 | 94/232 (40.5%) | 100/232 (43.1%) |
| Hard-ham: spam score at least 0.95 | 73/232 | 84/232 |
| Hard-ham: spam score at least 0.99 | 64/232 | 72/232 |
| Hard-ham: combined spam/phishing score at least 0.5 | 201/232 | 222/232 |
| Truncated messages | 467/491 | 348/491 |
| Truncated hard-ham messages | 231/232 | 203/232 |
| Median / p95 inference | 21.3 / 22.0 ms | 72.2 / 75.2 ms |
| Peak Python process memory | 0.94 GB | 1.07 GB |
| Process CPU time | 14.6 seconds | 41.2 seconds |

[96-token report](../../Tools/Corpus/reports/opentextshield-development-96.json)
and [384-token report](../../Tools/Corpus/reports/opentextshield-development-384.json)
include full aggregate counts, exact model/corpus hashes, library versions and
separate smoke scores. Both scored-ID sets were checked against the existing
Horizon 384-token run and match exactly. Total measured process CPU time is under
56 seconds, below the five-minute budget. Inference timings exclude loading and
tokenization; process memory includes the runtime. Shared-machine timings do not
establish application latency. No paid calls were made.

The 384-token run reduces missed source spam and increases phishing top-label
count slightly, while increasing historical hard-ham spam alarms. It also
frequently assigns the phishing label to source-spam messages; missing phishing
truth for that cohort prevents calling those phishing false positives. Neither
length supports automatic email filtering. Scores remain uncalibrated.

## Observed synthetic boundary cases

All eleven smoke inputs fit within 96 tokens, so both runs produce the same
scores. The exact text is preserved in [the original smoke input](multilingual-model-smoke.json).

| Constructed case | Observed result |
| --- | --- |
| English personal lunch message | Ham 0.9987 |
| French personal messages, accented and unaccented | Ham 0.9985–0.9986 |
| Spanish personal messages, accented and unaccented | Ham 0.9988–0.9990 |
| Subscribed gardening newsletter | Spam 0.9661 |
| Unsolicited bulk leads offer | Phishing 0.9858 |
| Mailbox password lure | Phishing 0.99994 |
| Targeted confidential payment diversion | Ham 0.9590 |
| Legitimate password-reset notice | Ham 0.9560 |
| Payment change requiring independent phone confirmation | Phishing 0.99957 |

The targeted-payment pair is reversed: the suspicious instruction is retained
while the independently verified counterpart receives a high phishing score.
The subscribed newsletter is labeled spam without any personal preference.
These constructed failures support rejecting the raw candidate for production
selection, despite its useful-looking phishing-positive count. They do not
establish general multilingual accuracy or evaluate a personalized graymail model.

## Decision and limitations

Keep OpenTextShield as a reproducible rejected raw-model candidate. Do not wire
it into SpamWise or choose Junk thresholds from this development sample.
Production-normalized evaluation remains unperformed; these results apply to the
explicit raw-input path, not a claim about every OpenTextShield deployment.

Historical hard-ham selection, quarantined extraction failures, related templates,
source-label uncertainty, unknown pretrained exposure and absent modern
financial/security and French/Spanish negative cohorts limit generalization.
No phishing false-positive rate is available. All reserved holdouts remain
unscored. Useful universal spam/phishing detection and separate personalized
graymail remain open product requirements.

Verification: all six corpus unit tests pass, including extended assertions for
candidate label maps, separate phishing output and unknown-negative abstention.
Ruff checks/formatting, Python compileall and Markdown lint pass. No app source
changed; no app build or UI test was needed for this offline tooling probe.

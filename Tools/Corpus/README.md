# Offline corpus preparation

Prepare the source-pinned downloads described in
[training data](../../docs/training-data.md) for separate detection objectives.
This development tool does not access Mail, use API keys, make network requests
or change application settings. Corpus contents remain private local artifacts.

## Setup and checks

From this directory, using pyenv and pyenv-virtualenv:

```sh
pyenv virtualenv 3.14.8 spamwise-corpus
pyenv exec pip install -r requirements.txt
pyenv exec ruff check --fix .
pyenv exec ruff format .
pyenv exec python -m unittest -v
```

Skip environment creation if `spamwise-corpus` already exists. The preparation
command uses Python's standard library and macOS `/usr/bin/bsdtar`; Ruff is only
needed for development checks. Local model screening additionally uses the pinned
packages in `requirements-model.txt`.

## Prepare

```sh
pyenv exec python prepare.py \
  --input /absolute/private/downloads \
  --output /absolute/private/prepared-corpus
```

The input directory must contain all four files named in `sources.json`, with
their exact recorded SHA-256 hashes. Preparation refuses changed inputs, incorrect
record counts, unknown label names, special archive entries, and existing output
directories. Limits include 2 MB per message, 100,000 text characters, 128 MIME
parts, 12 nesting levels, 200,000 records per source and 512 MB expanded archives.
Archive paths are never extracted; attachments are ignored. Source-pinned
`excluded_archive_members` omit only audited metadata files, after archive size
and member-type checks. HTML receives lexical
text extraction, without rendering or network access. Corpus extraction uses
Python's `email` package; it does not claim equivalence to the app's MIME parser.

Output directories have mode 700 and output files mode 600:

- `records.jsonl`: bounded text, content identity, source positions and labels,
  raw message hashes, unknown language, real/synthetic provenance, template group
  and assigned split. Text may contain personal information; do not publish it.
- `objectives/<task>/<kind>/<split>.json`: record IDs and explicitly supplied
  labels for that objective. Unknown and conflicting labels are excluded.
- `quarantine.json`: source positions and processing failure codes, without bodies.
- `manifest.json`: source attribution/terms, hashes, aggregate counts and caveats.
  Written last, with `complete: true` and a hash of `records.jsonl`. A failed run
  may leave an incomplete directory; consumers must require the complete manifest
  and verify the records hash. Use a fresh output path when retrying.

Guenter's label supplies spam evidence only. Nazario supplies phishing evidence
only. Neither supplies negative labels for the other objectives. Marketeam text
has no labels and cannot silently become legitimate training data. Deduplication
retains each contributing source; conflicting labels abstain for that objective.
SpamAssassin hard-ham supplies `spam: false` only; its phishing and other threat
labels remain unknown. The archive's `hard_ham/cmds` metadata is excluded.
Graymail preferences, fraud, spearphishing and malware remain unknown unless
separately labeled. Source labels are not independent human review.

A source with `usage: "evaluationOnly"` is confined to validation. Every linked
duplicate/template record shares that restriction, including records from other
sources that permit training. Such messages never appear in training indices.
Unspecified usage retains the audited training permission of the pinned starting
sources; new sources still require a terms audit before being added.

## Splits and leakage limits

Unicode/case/whitespace-normalized text identifies exact textual duplicates.
Body templates additionally mask URLs, email addresses and numeric runs, with a
minimum normalized length of 80 characters. Transitive links share one group
across sources. Deterministic group hashing assigns approximately 70% training,
15% validation and 15% holdout. Real and synthetic records retain separate indices.

These are provisional partitions. Template hashing misses paraphrases and some
campaigns and can merge unrelated templates. Review group membership, audit
pretrained exposure, add legitimate difficult negatives and verify language
coverage before treating any partition as a trustworthy benchmark. Hash splits
are not chronological. Adding sources can join groups and change assignments;
freeze the complete manifest before training. Changing the seed is not a remedy
for unfavorable results. Do not tune on the reserved holdout.

## Screen the pinned candidate

Install optional model dependencies into the selected pyenv environment:

```sh
pyenv exec pip install -r requirements-model.txt
pyenv exec python screen.py \
  --corpus /absolute/private/prepared-corpus \
  --snapshot /absolute/cache/snapshots/f1dddff04e7f56dc9f0f068d4e7f0383c583e392 \
  --output /absolute/private/development-screen
```

This command requires an already downloaded Horizon-Labs model snapshot. It
disables network loading, implicit Hugging Face authentication and remote code,
and requires Safetensors. It scores only real validation records, with two CPU
threads and 384 input tokens by default; `--max-tokens 1024` runs the longer-input
development comparison. Reserved holdout and synthetic records are excluded
from inference. The report includes weight/corpus hashes, versions, truncation,
latency and model scores; it contains no message text.

The model's outputs are legitimate/spam/fraud. Fraud scores are explicitly a
proxy on the source-phishing cohort, not an independently trained phishing
assessment. Source-labeled SpamAssassin hard-ham provides a historical non-spam
development comparison, confined to validation because its source offers filter
testing and broader training permission has not been established. The report
counts negative template groups, false alarms at each score threshold and
combined spam/fraud alarms. Combined alarms on non-spam are not evidence of a
fraud false-positive rate: that objective has no supplied negative labels.
Unknown labels never enter either objective's denominator. These data do not
establish modern specificity, calibration or safe Junk thresholds.

## Audit frozen preparation

```sh
pyenv exec python audit.py \
  --corpus /absolute/private/prepared-corpus \
  --baseline /absolute/private/original-prepared-corpus \
  --downloads /absolute/private/downloads \
  --output /absolute/private/fresh-audit
```

This read-only audit verifies both corpus hashes, every original identity/group/
split, source-label fidelity, conflict abstention, objective-index membership and
evaluation-only group restrictions. It compares only real training/validation
text for high-overlap five-word shingles across existing template groups. It
never runs a detector, examines holdout text for similarity, or changes splits.
The 10,000-word limit and 0.8 Jaccard threshold identify review candidates, not
proof of a shared campaign. Short messages and paraphrases can be missed.

The audit also verifies downloaded source hashes and accepted development-origin
hashes before counting Date and Content-Language headers. These are untrusted
sender claims, not verified collection dates or language labels. Outputs use
mode 600 within a fresh mode-700 directory. `audit.json` has aggregate counts;
`campaign-candidates.json` contains local record identities, split pairs and
similarity values without message bodies. Keep the latter private.

`development-partition.json` is a separate real-development manifest. It joins
existing groups connected by at least 0.95 shingle overlap and keeps the complete
component in validation if any member was already validation or evaluation-only.
It never promotes validation records to training, changes the frozen corpus, or
includes holdouts. Previously scored validation remains development data. The
report counts any remaining cross-split candidates below 0.95; their semantic
campaign relationship remains unresolved.

For optional local inferred language coverage, compile the installed macOS
NaturalLanguage helper with an isolated compiler cache, then pass its path as
`--language-tool` to the audit command:

```sh
AGENT_WORKER_ID=<worker-token> xcrun swiftc \
  -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -enable-experimental-feature StrictMemorySafety \
  -module-cache-path ../../.build/<worker-token>/ModuleCache \
  language-audit.swift -o ../../.build/<worker-token>/language-audit
```

The Python tool verifies and selects real non-holdout records before passing text
to this local executable. Recognition uses at most 20,000 characters and requires
40 letters, a top hypothesis of at least 0.8 and a margin of 0.2; other inputs stay
unknown. These hypotheses are neither calibrated language accuracy nor independent
review. The report pins macOS and executable identity. Per-record annotations go
to private `inferred-languages.json`; original language fields stay unknown.

The [2026-10-16 audit](../../docs/probes/corpus-integrity-audit.md) found substantial
development overlap missed by exact-template grouping. Frozen partitions remain
unchanged; the derived development manifest and inferred language counts support
further audit, not independent benchmark claims.

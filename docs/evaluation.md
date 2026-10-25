# Evaluation

`spamwise-eval` is the `SpamWiseCore` package's evaluation executable. It has five
subcommands: `corpus`, `reviewed`, `export`, `compare` and `threat-report`; `--help` on
each lists its options. Every run is a dry run and requests no Mail action. Examples
below use `spamwise-eval` for

```sh
swift run --package-path SpamWiseCore --scratch-path .build/swiftpm spamwise-eval
```

## Offline fixture check

```sh
spamwise-eval corpus eval/fixtures --model mock \
  --mock-responses eval/mock-responses.json --state eval/fixture-state.json \
  --cache .build/eval-cache --output .build/eval-report.json
```

The five samples get explicitly supplied synthetic verdicts, keyed by message hash, so
this is a plumbing check: it verifies parsing, rules, decisions, caching, reporting
and the expected two Inbox, two Junk and one Review outcomes, but never exercises the
prompt, instructions or evidence encoding, and says nothing about model quality.
`eval/fixture-state.json` seeds receipt history for the order-confirmation sender;
that history becomes a decisive gate only when the fixture account trusts its
receiving server, and otherwise reaches the model as evidence. Repeat with
`--strength conservative` to recompute actions from cached responses. Cache identity
includes the raw message hash, fixed instructions, effective preferences, evidence and
body prompt, model ID and schema ID; changing the mock-response file also invalidates
mock entries.

## Corpus and live runs

Place independently human-labeled `.eml` files in `good/`, `junk/`, and optionally `graymail/`. Duplicate message bytes are rejected to prevent inflated sample sizes. Include personal mail, wanted newsletters, club notices, receipts, order confirmations, and realistic spam. Reserve a separate held-out set before tuning.

`spamwise-eval corpus DIRECTORY` evaluates such a directory. Live calls require `SPAMWISE_LIVE_API=1`. Select `--model claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`, `gpt-5.4-mini`, or `gemini-3.8-flash`, with the corresponding `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GEMINI_API_KEY` in the process environment. The CLI never saves keys. `apple-on-device` uses Apple's Foundation Models framework without an API key. Private Cloud Compute is not selectable. Unsupported or unavailable models fail without fallback. Rates are captured for the selected model; optional `--input-price`, `--output-price`, and `--cache-price` override report estimates in USD per million tokens. Provider cache-write premiums are not separately exposed.

Paid models require `--budget-store PATH`, an evaluation ledger that the CLI never defaults to the app's shared store. Before each uncached paid request, the CLI atomically reserves a conservative upper bound there: $0.10 for Haiku, $1 for other paid models. `--reservation USD` lowers it, but never below the cost of a full-size prompt with a full response at the model's standard rates. A new ledger refuses every request until `--budget-limit USD` records its ceiling; changing the ceiling keeps existing commitments. Reservations are commitments, not measured billing; failed calls retain their reservation because a timeout cannot prove that the provider did not bill, and the report counts them as `failedProviderCalls`. Passing the app's existing store continues the ledger recorded there, without touching the app's monthly spending. The report's measured-token cost estimate (`newEstimatedCostUSD`) is distinct from reserved budget. A budget or storage refusal stops the run with exit status 1 and writes no report. Neither a new ledger nor a report-price override grants permission to spend; the authorized additional evaluation ceiling is $150.

### Using a saved setup key

Run `swift Scripts/store-provider-key.swift openai` (or `claude`/`gemini`) and type or
paste the key at its prompt, which doesn't echo it. To read the key from a password
manager instead, pipe it in, for example
`op read "op://Private/OpenAI/credential" | swift Scripts/store-provider-key.swift openai`.
The setup key is a login-Keychain item, separate from the signed app's operational
shared-Keychain item. It does not change the app's selected provider or grant
permission to send ordinary mail. To remove it, delete the item in Keychain Access
whose service starts with `codes.tim.SpamWise.` and ends in `.setup`.

For an explicitly authorized live evaluation, pass the built evaluator to the
Keychain launcher:

```sh
swift Scripts/evaluate-with-keychain.swift /absolute/path/to/spamwise-eval \
  openai --live corpus /private/path/to/corpus \
  --budget-store /private/path/to/budget.store \
  --cache /private/path/to/cache --output /private/path/to/report.json
```

The launcher supplies the provider's explicit supported model and reads the key
directly into the child process environment. It never writes a plaintext key or
places it in command arguments. It removes unrelated provider credentials from
that environment, requires `--live` and an explicit `--budget-store`, and rejects
model overrides. Keychain authorizes each executable separately, so a newly compiled
launcher may be refused setup-key access until it is approved.

Filesystem permission, an unconfigured ledger or budget exhaustion prevents
evaluation. The store's transaction and cross-process lock remain responsible for
each reservation.

For `corpus`, optional `--state snapshot.json` reads an `AppState` with rules, corrections, Contacts, history under account ID `eval`, category preferences and filtering strength; `--strength` overrides the snapshot's strength. Each run uses a fresh temporary classification store, forces dry run, and clears action claims and retries. It does not mutate the app's classification state; paid requests reserve spending in the explicit `--budget-store` ledger. RDAP is unknown, external DNS/Rspamd and image OCR are disabled, and no remote URLs from mail are fetched.

## Reviewed-label exports

Before correcting messages, turn on **Keep text of reviewed messages** in Settings → Advanced → Learning from corrections; then open Tools → **Reviewed Messages** and choose More → **Export Reviewed Messages…**. Labels created without retained text remain useful metadata but cannot supply evaluation input. Evaluate the export directly:

```sh
spamwise-eval reviewed /private/path/reviewed-labels.json --model mock \
  --partition held-out --output /private/path/reviewed-report.json
```

The default partition is `held-out`. The stable content identity uses normalized subject and body, independently of delivery headers, correction date, or label. The loader rejects duplicate retained content across the entire export before making model calls. Export limits are 64 MiB, 10,000 labels, and 2 MB per retained parsed message. `reviewedCorpus` reports total labels, missing content, partition exclusions, and selected messages. Metadata-only labels are skipped explicitly; a selection with no retained messages produces zero observations and clear counts. Graymail remains separate.

Retained `ParsedMessage` values go directly to the pipeline; human labels are used only for metrics and never enter prompts. The default state is empty. `--state` is accepted only with `--partition training`, and is rejected for `held-out` and `all` to prevent imported rules or learned state from leaking labels. `--partition training` permits a supplied state for exploratory testing; `training` and `all` cannot establish held-out quality. Clearing retained text preserves an available sample identity and its split, but makes that sample unavailable to the evaluator.

This is a statistical content holdout, not proof of independent live full-pipeline quality. Earlier corrections may already have influenced user policy or model selection, and retained messages omit original MIME images and delivery context. An independent, representative corpus and separately validated live integrations remain necessary before claiming a calibrated false-positive rate.

## Reports and calibration

JSON reports include a true-label/effective-label confusion matrix, overall and
per-path Junk precision/recall (keyed by decision path), unclassified counts,
original-model confidence buckets, a `calibration` section, newly incurred tokens with
their pricing, cache hits, estimated cost, failed provider calls, and every mismatched
filename with its reason. `observations` lists every message with the model's `modelLabel`,
`confidence`, `category` and `categoryConfidence`, the effective `label` and `action`, the
`preference` for its category and the decision `reason`, so decisions can be recomputed
offline at any threshold. Graymail remains separate from binary good/junk metrics.
Review and failures count as missed junk for recall; failures are also reported
explicitly. Calibration uses original model Junk labels, even when a policy threshold
reduces them to Review. Gate results are excluded from model calibration.

`calibration.curve` scores every Junk threshold from 85 to 100, holding the category
confidence that moves graymail the user chose Junk for at the run strength's
(`calibration.graymailThreshold`). For each filtering strength, `calibration.strengths`
reports the current threshold and the lowest threshold whose exact one-sided 95%
Clopper-Pearson false-positive upper bound on the training partition meets the
strength's target: 0.1% Conservative, 0.2% Balanced, 0.5% Aggressive, holding that
strength's graymail category threshold. It then validates that threshold on the held-out partition. Selection
therefore needs both partitions: use `reviewed --partition all`, or a corpus whose
hash split covers both. The targets are provisional.

The rule-of-three approximation is reported alongside the exact bound for zero
errors. With two good fixtures and zero false positives, the approximation is capped
at 100%, not 0.2%; approximately 1,500 representative good messages with zero false
positives are needed for the 0.2% bound. Confidence is not a calibrated probability.
The production thresholds stay 99/95/90, and the graymail category thresholds 95/85/75,
until separately validated; the CLI never changes production settings.

## Export from Mail

```sh
spamwise-eval export inbox --destination /path/to/unlabeled --limit 500
```

The helper reads through Apple Events and may require Automation permission. Supported source roles are Inbox, Junk, and Sent. No move/delete operation is exposed. Source mailbox placement is not a human label: review exported messages before placing them in corpus folders. Existing export files are never overwritten. Exported mail, cached reasons, and reports may contain personal data; keep them outside the repository.

## Accumulating SpamSieve samples

The test accounts' Junk folders accumulate SpamSieve-classified messages. Preserve
those messages as candidate evaluation data. A SpamSieve decision is a provisional
label, not an independently confirmed answer; folder membership alone does not
establish which filter moved a message.

When collecting a snapshot, retain account, collection date and known label source
alongside the private export. Keep unreviewed samples outside the evaluator’s
`good/`, `junk/` and `graymail/` directories. Review samples before assigning those
labels, include representative wanted mail from each account, exclude generated
`[SpamWise Probe]` messages, deduplicate, and reserve a separate holdout before
tuning. A Junk-only collection cannot establish a false-positive rate for wanted
mail. Collection itself requires no model calls; the existing $150 ceiling applies
to any later authorized paid evaluation.

## Frozen comparisons with SpamSieve or another configuration

`spamwise-eval compare MANIFEST.json --output comparison.json` computes paired
metrics offline. It performs no Mail operation, model call, collection or training.
The version-1 example is
`SpamWiseCore/Tests/SpamWiseCoreTests/Fixtures/comparison.json`; its synthetic numbers
exercise reporting only and provide no evidence of product quality.

Freeze the cohort and each system's configuration before predictions. The manifest
contains `holdoutID`, ISO-8601 `frozenAt`, `humanReviewed`, `trainingCampaigns`,
`messages`, and `runs`. Each message has an opaque `id`, a campaign group, independent
human `truth` (`good`, `junk`, `graymail`) and candidate `source`
(`spamsieve`, `server`, `unknown`, `other`). Source never supplies truth. Keep only one
representative per campaign in this comparison cohort; training campaign overlap,
duplicate messages/campaigns and unequal result sets are rejected.

Each run records a distinct `system`, immutable `configurationID`, `learningFrozen`,
`priorExposure` (`none`, `known`, `unknown`), positive whole-run `elapsedSec`, and a
result for every message. Results contain `id`, `label` (`inbox`, `junk`, `review`,
or null for unclassified), optional reason, and optional measured `latencySec`,
`reviewSec` and `corrections`. Null predictions remain in the denominator. Missing
rows fail validation. Record zero review time/corrections only when actually observed,
not as a substitute for missing measurements.

Optional run-level `cpuSec`, `peakMemoryBytes`, `costUSD` and `costBasis`
(`measured` or `estimated`) preserve their provenance. The report includes paired
confusion matrices, graymail separately, abstentions, p50/p95 latency, throughput,
review minutes and corrections per thousand messages, resource figures and cost.
Percentiles use nearest rank; latency/review aggregates are absent unless every
message has a measurement. Compare equal concurrency and warm/cache conditions and
retain machine/OS details with the configuration records.

`eligibleForBoundedComparison` requires every run to attest no prior exposure and
meet the exact one-sided 95% upper false-positive bound of 0.2%. It is not a
superiority finding, and attestations are not independently verified. Known/unknown
prior exposure stays visible. Do not retune on the frozen holdout. This tool also
supports policy/no-policy and local/cloud experiments once their independent review
and privacy prerequisites are met; it does not authorize cloud escalation or
spending. Keep the $150 ceiling and ordinary Junk-folder preservation in force.

## Independent threat metrics

Use `spamwise-eval threat-report observations.json --output report.json` for
independently labeled spam/phishing/spearphishing/fraud/malware observations.
This report never derives threat labels from Inbox/Junk preferences. See
[observation format, cache identities and unknown coverage](threat-assessments.md).

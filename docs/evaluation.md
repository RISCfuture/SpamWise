# Evaluation

Build with `bash Scripts/check.sh <worker-token>`. The executable is the `spamwise-eval` product of `SpamWiseCore`; use `swift run --package-path SpamWiseCore --scratch-path .build/<worker-token>/swiftpm spamwise-eval --help` for options.

## Offline smoke test

```sh
swift run --package-path SpamWiseCore --scratch-path .build/<worker-token>/swiftpm spamwise-eval \
  --input eval/fixtures --model mock --mock-responses eval/mock-responses.json \
  --cache .build/<worker-token>/eval-cache --output .build/<worker-token>/eval-report.json
```

The five samples use explicitly supplied synthetic verdicts. This verifies parsing, decisions, caching, reporting, and the expected fixture outcomes; it does not measure Claude quality. Repeat with `--strength conservative` to recompute actions using cached model responses. Cache identity includes raw message hash, fixed instructions, effective preferences/evidence/body prompt, model ID, and schema ID. Changing the mock-response file also invalidates mock cache entries.

## Corpus and live runs

Place independently human-labeled `.eml` files in `good/`, `junk/`, and optionally `graymail/`. Duplicate message bytes are rejected to prevent inflated sample sizes. Include personal mail, wanted newsletters, club notices, receipts, order confirmations, and realistic spam. Reserve a separate held-out set before tuning.

Live calls require `SPAMWISE_LIVE_API=1`. Select `--model claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`, `gpt-5.4-mini`, or `gemini-3.8-flash`, with the corresponding `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GEMINI_API_KEY` in the process environment. The CLI never saves keys. `apple-on-device` and `apple-private-cloud-compute` use Apple's Foundation Models framework without an API key; PCC requires Apple's managed entitlement and availability. Unsupported or unavailable models fail without fallback. Rates are captured for the selected model; optional `--input-price`, `--output-price`, and `--cache-price` override report estimates in USD per million tokens. Provider cache-write premiums are not separately exposed.

Before each uncached paid request, the CLI atomically reserves a conservative upper bound in the application's shared persistent $150 evaluation budget: $0.10 for Haiku, $1 for other paid models. App, extension and CLI share this ledger by default. Reservations are commitments, not measured billing; failed calls retain their reservation because a timeout cannot prove that the provider did not bill. `--budget-store PATH` selects a separate ledger and therefore requires separate spending authorization; it must not be used to bypass an exhausted shared allowance. The report's measured-token cost estimate is distinct from reserved budget. Neither a custom path nor a report-price override grants permission to spend.

Optional `--state snapshot.json` reads an `AppState` with rules, corrections, Contacts, and history under account ID `eval`. Each run uses a fresh temporary classification store, forces dry run, and clears action claims and retries. It does not mutate the app's classification state; paid requests update the shared budget ledger. RDAP is unknown, external DNS/Rspamd and image OCR are disabled, and no remote URLs from mail are fetched.

## Reviewed-label exports

Enable local reviewed-content retention in the app before correcting messages, then export reviewed labels from Settings. Labels created without retained text remain useful metadata but cannot supply evaluation input. Evaluate the export directly:

```sh
spamwise-eval --reviewed /private/path/reviewed-labels.json --model mock \
  --partition held-out --output /private/path/reviewed-report.json
```

`--reviewed` replaces `--input`; the default partition is `held-out`. The stable content identity uses normalized subject and body, independently of delivery headers, correction date, or label. The loader rejects duplicate retained content across the entire export before making model calls. Export limits are 64 MiB, 10,000 labels, and 2 MB per retained parsed message. `reviewedCorpus` reports total labels, missing content, partition exclusions, and selected messages. Metadata-only labels are skipped explicitly; a selection with no retained messages produces zero observations and clear counts. Graymail remains separate.

Retained `ParsedMessage` values go directly to the pipeline; human labels are used only for metrics and never enter prompts. The default state is empty. `--state` is rejected for `held-out` and `all` partitions to prevent imported rules or learned state from leaking labels. `--partition training` permits a supplied state for exploratory testing; `training` and `all` cannot establish held-out quality. Clearing retained text preserves an available sample identity and its split, but makes that sample unavailable to the evaluator.

This is a statistical content holdout, not proof of independent live full-pipeline quality. Earlier corrections may already have influenced user policy or model selection, and retained messages omit original MIME images and delivery context. An independent, representative corpus and separately validated live integrations remain necessary before claiming a calibrated false-positive rate.

## Reports and calibration

JSON reports include a true-label/effective-label confusion matrix, overall and per-path Junk precision/recall, unclassified counts, original-model confidence buckets, threshold candidates, newly incurred tokens, cache hits, estimated cost, and every mismatched filename with its reason. Graymail remains separate from binary good/junk metrics. Review and failures count as missed junk for recall; failures are also reported explicitly. Calibration uses original model Junk labels, even when a policy threshold reduces them to Review. Gate results are excluded from model calibration.

The exact one-sided 95% Clopper-Pearson false-positive upper bound is reported alongside the rule-of-three approximation for zero errors. With two good fixtures and zero false positives, the approximation is capped at 100%, not 0.2%. Approximately 1,500 representative good messages with zero false positives are needed for the 0.2% bound. Confidence is not a calibrated probability. Candidate Conservative/Balanced/Aggressive thresholds remain 99/95/90 until separately validated; the CLI never silently changes production settings.

## Export from Mail

```sh
spamwise-eval --export inbox --destination /path/to/unlabeled --limit 500
```

The helper reads through Apple Events and may require Automation permission. Supported source roles are Inbox, Junk, and Sent. No move/delete operation is exposed. Source mailbox placement is not a human label: review exported messages before placing them in corpus folders. Existing export files are never overwritten. Exported mail, cached reasons, and reports may contain personal data; keep them outside the repository.

## Accumulating SpamSieve samples

The user’s iCloud and Google accounts each have a Junk folder that will accumulate
SpamSieve-classified messages over the coming weeks. Preserve those messages as
candidate evaluation data. A SpamSieve decision is a provisional label, not an
independently confirmed answer; folder membership alone does not establish which
filter moved a message.

When collecting a snapshot, retain account, collection date and known label source
alongside the private export. Keep unreviewed samples outside the evaluator’s
`good/`, `junk/` and `graymail/` directories. Review samples before assigning those
labels, include representative wanted mail from each account, exclude generated
`[SpamWise Probe]` messages, deduplicate, and reserve a separate holdout before
tuning. A Junk-only collection cannot establish a false-positive rate for wanted
mail. Collection itself requires no model calls; the existing $150 ceiling applies
to any later authorized paid evaluation.

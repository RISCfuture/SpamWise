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

Live calls require `SPAMWISE_LIVE_API=1` and `ANTHROPIC_API_KEY` supplied to the process environment. The CLI never saves the key. Select `--model claude-haiku-5-5`, `claude-sonnet-5-5`, or `claude-opus-5-5`; unsupported models fail, and there is no fallback. The app remains fixed to Haiku 5.5. Set `--input-price`, `--output-price`, and `--cache-price` in USD per million tokens for non-Haiku models; otherwise their cost is unknown. Haiku estimates use the prices recorded in CLAUDE.md. Provider cache-write premiums are not separately exposed.

Optional `--state snapshot.json` reads an `AppState` with rules, corrections, Contacts, and history under account ID `eval`. Each run uses a fresh temporary store, forces dry run, clears action claims and retries, and never mutates the app's store. RDAP is deliberately unknown in reproducible offline runs; no remote URLs from mail are fetched.

## Reports and calibration

JSON reports include a true-label/effective-label confusion matrix, overall and per-path Junk precision/recall, unclassified counts, original-model confidence buckets, threshold candidates, newly incurred tokens, cache hits, estimated cost, and every mismatched filename with its reason. Graymail remains separate from binary good/junk metrics. Review and failures count as missed junk for recall; failures are also reported explicitly. Calibration uses original model Junk labels, even when a policy threshold reduces them to Review. Gate results are excluded from model calibration.

The exact one-sided 95% Clopper-Pearson false-positive upper bound is reported alongside the rule-of-three approximation for zero errors. With two good fixtures and zero false positives, the approximation is capped at 100%, not 0.2%. Approximately 1,500 representative good messages with zero false positives are needed for the 0.2% bound. Confidence is not a calibrated probability. Candidate Conservative/Balanced/Aggressive thresholds remain 99/95/90 until separately validated; the CLI never silently changes production settings.

## Export from Mail

```sh
spamwise-eval --export inbox --destination /path/to/unlabeled --limit 500
```

The helper reads through Apple Events and may require Automation permission. Supported source roles are Inbox, Junk, and Sent. No move/delete operation is exposed. Source mailbox placement is not a human label: review exported messages before placing them in corpus folders. Existing export files are never overwritten. Exported mail, cached reasons, and reports may contain personal data; keep them outside the repository.

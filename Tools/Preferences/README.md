# Synthetic graymail preference probe

This probe compares the same synthetic gardening newsletter under wanted/unwanted
policies in English, Spanish and French. Each policy runs without examples and
with two analogous corrections from other subjects and senders. All content and
labels are synthetic. This is in-context prompting, not fine tuning.

`cases.json` contains the authored inputs. `run.py` writes twelve isolated states,
identical message bytes across each language's four conditions, separate caches
and a manifest. Synthetic target outcomes appear only in the manifest. The
evaluator receives every message under `graymail/`, without sender rules, Contacts
or history. The CLI forces dry run and temporary classification storage. Default
Balanced filtering retains the provisional 95-confidence Junk threshold.

## Offline validation

Use the existing `spamwise-corpus` pyenv virtualenv:

```sh
pyenv exec ruff check --fix .
pyenv exec ruff format .
pyenv exec python -m unittest -v
pyenv exec python run.py --executable /absolute/path/to/spamwise-eval \
  --output /absolute/private/preferences-offline
```

The default invokes the CLI's explicit mock model. It validates all twelve state
documents and message parses without provider requests. Mock Review outputs test
plumbing only. The output directory must not exist; generated files are private.
Tests cover paired-message identity, state isolation, bounded examples and
stopping after the first unsuccessful condition.

## Authorized live execution

With current spending authorization and verified provider pricing:

```sh
pyenv exec python run.py --executable /absolute/path/to/spamwise-eval \
  --output /absolute/private/preferences-live --live
```

The runner invokes `Scripts/evaluate-with-keychain.swift` with explicit Claude
and `--live`. That helper reads the existing Anthropic setup key directly into
the child environment, supplies the application's existing shared budget path,
and refuses absent stores or model/budget overrides. This probe never reads or
prints the key, creates another ledger, or changes production preferences.

Calls run sequentially, starting with English wanted policy without examples.
Any launcher error, timeout, missing verdict or classification failure stops
subsequent conditions without retry or model fallback. There are at most twelve
conditions and $1.20 in conservative $0.10 reservations per invocation. Failed
requests can retain reservations. The reported maximum reservation is an upper
bound, not measured billing or the current total shared-ledger balance.

`results.json` separates model outputs, effective decisions and measured token
estimates. Raw CLI reports are retained per condition. The CLI's graymail mismatch
convention assumes Review; use this probe's explicit synthetic targets when
inspecting preference behavior, not binary accuracy. Separate directories and
effective-prompt cache keys prevent reuse across policy contexts. No reserved
corpus holdout is involved.

See [observations and limitations](../../docs/probes/graymail-preferences.md).

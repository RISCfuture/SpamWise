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
  --output /absolute/private/preferences-live --live \
  --budget-store /absolute/private/evaluation-budget.store
```

The runner invokes `Scripts/evaluate-with-keychain.swift` with explicit Claude
and `--live`, passing the explicit `--budget-store`. That helper reads the
existing Anthropic setup key directly into the child environment and refuses
model overrides; the evaluator refuses a ledger with no recorded ceiling. This
probe never reads or prints the key, configures a ceiling, or changes production
preferences.

Calls run sequentially, starting with English wanted policy without examples.
Any launcher error, timeout, missing verdict or classification failure stops
subsequent conditions without retry or model fallback. There are at most twelve
conditions and $1.20 in conservative $0.10 reservations per invocation. Failed
requests can retain reservations. The reported maximum reservation is an upper
bound, not measured billing or the current total ledger balance.

`results.json` separates model outputs, effective decisions and measured token
estimates. Raw CLI reports are retained per condition. The CLI's graymail mismatch
convention assumes Review; use this probe's explicit synthetic targets when
inspecting preference behavior, not binary accuracy. Separate directories and
effective-prompt cache keys prevent reuse across policy contexts. No reserved
corpus holdout is involved.

See [observations and limitations](../../docs/probes/graymail-preferences.md).

## Preference adherence

`adherence.py` measures whether each message gets the action a stated preference
profile calls for, without the user labeling mail: graymail follows the profile
(Keep → Inbox, Review → Review, Junk → Junk), personal and transactional mail
expects Inbox, and spam and scams are scored separately as the spam path. Its four
subcommands build a blind message set, freeze two labelers' agreed categories, run
each profile through `spamwise-eval` and score the reports. Every output directory
or frozen file must not already exist; outputs are private (mode 700/600).

### Message set

```sh
pyenv exec python -I adherence.py build \
  --downloads /absolute/private/downloads \
  --output /absolute/private/adherence/messages \
  --intent /absolute/private/intent-by-template.json \
  --private /absolute/private/adherence/private
```

The downloads directory holds the `sources.json` files; their SHA-256 hashes are
verified. A fixed seed selects 80 Marketeam records spread round-robin across
subject themes and greeting audiences, wrapped as colleague mail from fictional
agency domains, plus five unmodified Nazario phishing and five Guenter spam
samples. `authored.toml` supplies 65 synthetic messages (50 English, 8 Spanish,
7 French) covering the graymail categories Marketeam lacks, wanted controls and
boundary cases. Authored and Marketeam senders use reserved `.example` domains and
carry no Authentication-Results; the public samples keep their original headers,
including the phishing samples' Authentication-Results, which no profile trusts. Ids
`m001`… are shuffled across sources, and the build is byte-for-byte reproducible.

`manifest.json` records each id's source, source record or template key and
SHA-256, never a category. Authored templates carry no intended category either.
`--intent` takes the author's private template-key → category map and writes
`authored-intent.json` keyed by message id under `--private`, which labelers must
not read; `score --intent` compares it with the frozen labels as a sanity check.

### Labels

Labelers follow a rubric that lists `MailCategory`'s categories and descriptions
and asks for each message's main purpose, not its sender. Each writes
`{"labeler": …, "labels": {"m001": "promotion", …}, "notes": {…}}`.

```sh
pyenv exec python -I adherence.py freeze \
  --messages /absolute/private/adherence/messages \
  --labels /absolute/private/adherence/labeling/labeler-a.json \
           /absolute/private/adherence/labeling/labeler-b.json \
  --output /absolute/private/adherence/frozen/labels.json
```

`labels.json` keeps only messages both labelers labeled alike, with raw agreement,
Cohen's kappa, each excluded id with both labels, and a seeded 50/50 dev/holdout
split stratified by category. Freezing refuses to overwrite an existing file.

### Runs

`profiles.json` defines five profiles. `defaults` matches
`CategoryPreferences.defaults`. `declutter` sends selling (promotions, carts,
events, financial offers, fundraising, cold outreach), social notifications and
surveys to Junk, newsletters and product news to Review, and keeps community
mail. `deal-seeker` keeps
promotions and events, sends carts, financial offers and cold outreach to Junk and
fundraising to Review, keeping the rest. `inbox-minimalist` sends every graymail
category to Junk except newsletters, which go to Review. `permissive` keeps
everything.

```sh
pyenv exec python -I adherence.py run \
  --executable /absolute/path/to/spamwise-eval --tag baseline \
  --commit "$(git rev-parse HEAD)" \
  --messages /absolute/private/adherence/messages \
  --output /absolute/private/adherence/runs
```

Each profile gets its own AppState snapshot (its `categoryPreferences`, Balanced
strength, dry run, and no rules, corrections, Contacts, history or trusted
servers), cache and reports under `runs/<tag>/<profile>/`. Profiles run
sequentially and the first unusable pass stops the tag, without retry or model
fallback. An evaluator that lists every message's result in `observations` needs
one pass under `good/`; a message it could not classify stays in the results and
scores as unclassified, as the app leaves such mail untouched. An older evaluator
lists only results that differ from a folder's expected label, so each profile
runs twice over identical bytes: once under `good/`, which lists every non-Inbox
result, and once under `junk/`, which lists every non-Junk result.
`observations.json` holds every result; a `categoryConfidence` field, when the
evaluator reports one, is kept. Without `--live`, runs use the
explicit mock model with deterministic verdicts keyed by message hash, which
check plumbing only.

With spending authorization, add
`--live --budget-store /absolute/private/evaluation-budget.store --budget-limit USD`
(optionally `--reservation`, default $0.008). The first pass of each profile goes
through `Scripts/evaluate-with-keychain.swift` with explicit Claude. When a second
pass follows, the first must classify every message with no failed provider call,
and the second replays the cache against a fresh zero-ceiling ledger, so any
uncached request is refused rather than sent. Five profiles over 155 messages reserve at most 775 requests,
$6.20 at the default reservation. A `--timeout` (default 3600 seconds per
invocation) kills the launcher's whole process group, evaluator included.

### Scores

```sh
pyenv exec python -I adherence.py score \
  --frozen /absolute/private/adherence/frozen/labels.json \
  --runs /absolute/private/adherence/runs --tag baseline --tag candidate \
  --output /absolute/private/adherence/scores
```

`score.json` and `score.md` report dev and holdout separately, per profile and
pooled: adherence, expected-versus-effective action confusion, wrong Junk
(expected Inbox or Review; ids listed), missed Junk, Review burden, model category
accuracy against the frozen labels and spam-path outcomes. Adherence and wrong-Junk
rates carry Wilson 95% intervals. A recorded preference that differs from the
profile's state stops scoring. When every model result carries
`categoryConfidence`, a threshold sweep from 50 to 100 in steps of 5 recomputes
each Junk-preferred graymail decision as `Decision.evaluate` does: Junk at or above
the threshold, and below it Junk only for a Junk label confident enough for the
run's strength, otherwise Review. Every other effective label is kept. Choose a threshold on dev and
confirm it on holdout.

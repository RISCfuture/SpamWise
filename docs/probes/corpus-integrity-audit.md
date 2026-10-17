# Corpus integrity, campaign and exposure audit — 2026-10-16

The frozen corpus preserves its source labels and partitions, but its existing
template groups do not establish independent campaigns. A second, development-only
similarity check found 136 high-overlap training/validation pairs. A conservative
derived development partition resolves 421 very-high-overlap links, and local
language recognition quantifies sparse inferred French/Spanish coverage. No threat
classifier was trained or evaluated, no holdout was scored, and no personal mail
was accessed.

## Reproduction and integrity

Run the [audit tool](../../Tools/Corpus/audit.py) from the repository root:

```sh
PYENV_VERSION=spamwise-corpus pyenv exec python Tools/Corpus/audit.py \
  --corpus .build/corpus-negatives-20261016/prepared-v1 \
  --baseline .build/e85b1d5f-04fe-4493-80a9-6fc7785ec9ad/corpus-prepared-v1 \
  --downloads .build/corpus-negatives-20261016/downloads \
  --language-tool .build/<worker-token>/language-audit \
  --output .build/<worker-token>/corpus-audit/fresh
```

The [aggregate report](../../Tools/Corpus/reports/corpus-integrity-audit.json)
pins both corpus hashes. The actual local outputs are under
`.build/89f5ef8a-0fe6-4e2d-913f-6b94a7916693/corpus-audit/derived-final/`.
Per-pair identities remain private local artifacts. Both preparation manifests
and all four downloaded source hashes were verified before processing.
Build the optional language helper using the [tool instructions](../../Tools/Corpus/README.md#audit-frozen-preparation);
omit that argument for a metadata/campaign-only audit.

- All 18,201 original identities, template groups and splits remain unchanged,
  including all 2,782 holdout records: 259 real and 2,523 synthetic.
- All 18,433 current records preserve source-label mapping and conflict
  abstention. Objective files exactly match the supplied labels and partitions.
- All 225 evaluation-only template groups remain in validation. None enters a
  training objective index.
- Zero records carry independent review, and all 18,433 language labels remain
  unknown. Source-label fidelity does not prove source-label correctness.

## Development campaign overlap

The audit selects 1,734 real records outside holdout: 1,243 training and 491
validation. It removes the preparer's subject prefix, normalizes Unicode/case/
whitespace and builds distinct five-word shingles from at most 10,000 words per
body. Records need at least 20 shingles; 1,713 qualify. It compares pairs in
different existing groups and reports Jaccard intersection/union of at least 0.8.
URLs, addresses and numbers are not masked in this second check.

| Observation | Count |
| --- | ---: |
| High-overlap pairs in different existing groups | 487 |
| Distinct records in those pairs | 198 |
| Pairs crossing training/validation | 136 |
| Distinct records in crossing pairs | 73 |
| Within Guenter source | 475 pairs |
| Within historical hard-ham source | 9 pairs |
| Within Nazario source | 3 pairs |
| Cross-source candidate pairs | 0 |

This is evidence of grouping limitations, not independent adjudication of each
campaign. Shared boilerplate can create false links; paraphrases, short bodies,
and changes after the word limit can be missed. The test excludes synthetic
records and holdout content, so its absence of cross-source candidates says
nothing about those partitions. Holdout metadata is read for integrity checks;
its text is never passed to similarity analysis or model inference.

The tool writes a separate `spamwise-development-partition-v1` manifest for the
1,734 real development records. Its conservative threshold is 0.95, accepting 421
links and merging their existing groups transitively. A connected component stays
in validation if any member was validation or evaluation-only. This avoids
promoting historical hard-ham or previously screened examples into training and
does not assign a shared semantic campaign label to merely similar newsletters.

The result contains 1,311 groups, 1,214 training records and 520 validation records;
29 former training records move to derived validation. Every accepted overlap
pair is now within one partition. Thirty-seven lower-overlap candidate pairs
still cross the derived split and remain review candidates. Original records,
objective indices, seed and holdout artifacts are unchanged. The manifest includes
no holdout text or identities. It cannot be loaded as a complete prepared corpus
by the screening command.

Original validation has already been scored repeatedly during candidate
development. The derived split does not erase that exposure or turn development
results into an independent benchmark. No new metrics are reported. Before model
training, review the remaining candidates and source/label/rights gaps; any
eventual benchmark needs a separate contamination protocol before its one-time
evaluation. Neither these links nor exact-template groups establish complete
campaign independence.

## Time and language coverage

The tool rereads only accepted real development origins for header analysis and
checks each raw-message hash against its stored origin. Counts below are source
origins, so merged duplicates can make them larger than unique-record counts.

| Source | Accepted development origins | Untrusted Date claims | Untrusted Content-Language claims |
| --- | ---: | --- | --- |
| Guenter September 2026 | 1,256 | 1,253 in 2026; 3 unknown | 1 `en-in`, 1 `en-us`; 1,254 missing/multiple/invalid |
| Nazario 2025 | 412 | 408 in 2025; 1 in 2024; 3 unknown | 4 `en-us`, 1 `pt-br`; 407 missing/multiple/invalid |
| SpamAssassin hard-ham | 232 | All 232 in 2002 | All 232 missing/multiple/invalid |

Archive periods supply collection context; sender-controlled Date headers do not
establish arrival time. The hard-ham archive was assembled in 2003, despite these
2002 message dates. Synthetic generation dates remain unknown. There is no
contemporary legitimate development cohort and no chronological holdout.

Content-Language is neither authenticated nor a reliable language annotation.
There are no verified English, Spanish or French coverage counts. Unknown states
remain explicit instead of inferring English from ASCII or synthetic marketing
text.

The optional helper uses the installed macOS 27.0.1 NaturalLanguage recognizer,
without downloading a model or calling a provider. Python first selects the 1,734
real development records; no holdout or synthetic text reaches recognition. It
uses at most 20,000 characters, at least 40 letters, a top language hypothesis of
0.8 or higher and at least 0.2 margin; otherwise it records unknown. The report
pins the executable hash. These are inferred annotations with no calibrated
accuracy claim; existing corpus language/review fields are unchanged.

| Source | Inferred English | Inferred Spanish | Inferred French | Other inferred | Unknown |
| --- | ---: | ---: | ---: | ---: | ---: |
| Guenter | 1,048 | 1 | 8 | 23 | 37 |
| Nazario | 320 | 4 | 1 | 15 | 45 |
| Historical hard-ham | 171 | 0 | 0 | 9 | 52 |
| Total | 1,539 | 5 | 9 | 47 | 134 |

Sparse inferred Spanish/French positive coverage and zero inferred negatives for
those languages reinforce the need for more development data. Mixed-language,
boilerplate-heavy and historical marketing text may be misidentified even above
the recognizer threshold. These counts support review prioritization, not
reviewed multilingual labels or modern financial/security workflow coverage.

## Pretrained exposure assessment

The immutable model cards for all three screened candidates were inspected. This
is a documentation audit; no exhaustive training-example inventory or overlap
comparison was available, and absence of disclosed overlap is not proof of absence.

| Candidate | Disclosed training evidence | Exposure conclusion |
| --- | --- | --- |
| [BERT-Tiny Enron, pinned card](https://huggingface.co/mrm8488/bert-tiny-finetuned-enron-spam-detection/blob/2f5580bfd62e4a167d05742f0de321d570df5a21/README.md) | Fine-tuned on SetFit/enron_spam; underlying BERT-Tiny; training/evaluation-data section is incomplete | Enron is an exposed source for this candidate. Current hard-ham, Guenter and Nazario overlap is unmeasured; do not call them unseen |
| [Horizon, pinned card](https://huggingface.co/Horizon-Labs/phishing-scam-detector-base/blob/f1dddff04e7f56dc9f0f068d4e7f0383c583e392/README.md) | 98,379 teacher-generated messages, 59,403 FineWeb/FineWeb-2 snippets, mmBERT base and Qwen teacher; author says public test sets were evaluation-only | The release describes fine-tuning but does not establish complete base/teacher exposure or exclude our messages and campaign variants |
| [OpenTextShield, pinned card](https://huggingface.co/telecomsxchange/OpenTextShield/blob/9e839db78bd1daff8062ae2f2638af0b64b416ae/README.md) | mBERT base, public SMS corpora plus an in-house multilingual corpus; UCI and Mishra/Soni overlap training and are regression benchmarks | SMS benchmark exposure is disclosed. Email-corpus exposure, complete in-house membership and base-model exposure remain unverified |

Horizon and Tiny card snapshots are in the local audit directory. Their SHA-256
values are respectively
`2d877d6ac89600fdd0585272edd43d10138da07dfa230d52105a7905e8776107` and
`115fc1a03fd8e4d161e7d5dcab9c90b59d70fcc4af9bdad87ea959ae5a859f2e`.
The existing pinned OpenTextShield snapshot has SHA-256
`12c00f347ff0c1d8be0887ad358b7f12902cf51fee8c1a4474644082cb6db423`.
Release/upload dates alone cannot establish a training-data cutoff. Historical
public hard-ham has particularly weak unseen-data provenance; recent source files
may still repeat older campaigns. Synthetic generation can inherit teacher
exposure. No candidate/source combination receives an exposure-clear designation.

## Consequences and verification

Repeated model screening on this corpus cannot resolve missing legitimate modern
or multilingual labels, source-label uncertainty, campaign dependence, or unknown
pretrained exposure. No further classifier inference was justified by this audit;
the existing rejected-candidate findings stand, and no production threshold is
selected.

Autonomous grouping and language triage are now recorded separately. A
quality claim still needs legitimately licensed contemporary negative examples,
independent task/language review, exposure documentation or new unseen collection,
and a separately frozen evaluation protocol. These are evidence gaps, not a reason
to relabel unlabeled synthetic records or consume the reserved holdout.

Verification covers eight offline corpus test functions, including changed
source-label/index rejection, frozen membership rejection, missed-template overlap,
derived partition isolation, inferred-language membership and holdout exclusion;
Ruff checks/formatting, Python compilation and Markdown lint. The NaturalLanguage
helper compiles under Swift 6 strict concurrency/memory safety with warnings as
errors; Swift formatting and strict SwiftLint pass. The application source is
unchanged by this audit.

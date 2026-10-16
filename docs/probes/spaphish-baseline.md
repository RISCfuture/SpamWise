# Spanish email corpus and local baseline — 2026-10-16

SpaPhish supplies a useful missing development cohort: explicit Spanish phishing
negatives with published training terms. A fixed character TF-IDF/logistic model
trained locally detects 188 of 212 phishing examples, but also alarms on 5 of 176
legitimate examples at score 0.5. This is a useful reproducible baseline, not a
production detector or a calibrated Junk policy. No paid API calls were made.

## Acquisition and rights

The [original SpaPhish v5 release](https://data.mendeley.com/datasets/hz2d6gz7pc/5)
(DOI `10.17632/hz2d6gz7pc.5`, published May 12, 2026) declares CC BY 4.0.
Credit Lazaro Bustio-Martinez and coauthors. The authors describe anonymized
Spanish mail from contributor inboxes and expert phishing annotation. This probe
uses only their binary phishing label, subject and body; other threat objectives
remain unknown. The annotation rationales and persuasion labels never become
model inputs. Neither language nor labels were independently adjudicated here.

The CSV, schema and dictionary were downloaded from the original host and checked
against its published SHA-256 values. The source page and file inventory were
saved beside them in private ignored output. Contrary to the dictionary's
semicolon description, the pinned CSV is comma-separated UTF-8 with a BOM.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `Spaphish dataset - DiB.csv` | 5,098,917 | `656b2245d58da72d640680e5c2a168673a130b38607f2a427c773bbb167e995e` |
| `dataset_schema.json` | 17,798 | `51d501037e05f2dd117f8d46c4131d08971fa1f21b220bcc401670741605cdba` |
| `README.txt` | 3,212 | `ce44b6c86de0873f8b5d8baf4aaeb1a1710916e81966b97bbc549cfd294ab7ca` |
| Source/license page snapshot | 150,827 | `bd97fd28d5362c03793623612d176ac3504645e0e39aabd86930460d1932da2a` |

Actual parsing finds 1,395 unique source hashes and normalized texts, 47 columns,
664 phishing-negative and 731 phishing-positive rows, and no conflicting labels.
Sixteen bodies have fewer than 40 letters; they remain included, with no
outcome-driven exclusion. Parsed source dates span 2014–2025; 192 negatives and
614 positives date to 2024–2025. Twenty-four positive dates are missing. The class
age imbalance is a limitation, and these strings do not independently establish
arrival time. The aggregate report preserves the complete year/class counts.

## Partition and model

This is a separate development-only acquisition. The tool does not accept or read
the existing prepared corpus, its historical evaluation-only hard-ham, or any of
the 2,782 reserved holdouts. `sources.json` and all frozen partitions stay unchanged.
No claims of cross-source deduplication or independent benchmark status follow.

Before scoring, the existing corpus helper groups masked body templates and
normalized duplicates. The campaign audit then links all 166 pairs with at least
0.8 Jaccard overlap in five-word shingles, transitively. This conservative cutoff
keeps boilerplate-related examples together even when their campaign relationship
is uncertain. It yields 1,245 groups. A fixed group hash and seed
`spamwise-spaphish-development-v1` assign approximately 70% to training and 30% to
validation. All accepted similarity links stay within a split. Short texts,
paraphrases and other relationships can still escape grouping.

| Development split | Phishing negative | Phishing positive |
| --- | ---: | ---: |
| Training | 488 | 519 |
| Validation | 176 | 212 |

Validation contains 174 negative groups and 172 positive groups. Character
TF-IDF uses word-boundary character n-grams 3–5, minimum document frequency 2,
sublinear term frequency, and at most 100,000 features. Vocabulary and IDF are fit
on training only. Logistic regression uses `C=1`, `liblinear`, seed 0 and at most
1,000 iterations; it converged in five. These choices were fixed before the first
score run; no parameter search occurred. There are 82,645 features. No pretrained
weights, remote model code or serialized executable model is loaded.

The method uses the official scikit-learn
[TF-IDF vectorizer](https://scikit-learn.org/stable/modules/generated/sklearn.feature_extraction.text.TfidfVectorizer.html)
and [logistic regression](https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.LogisticRegression.html).
The dependency lock pins the exact packages used. This baseline tests learnable
local text signal; it does not reproduce the app's MIME extraction or establish
that a more complicated model would improve results.

## Measured development results

| Score threshold | Detected phishing / 212 | Missed phishing | False alarms / 176 legitimate |
| --- | ---: | ---: | ---: |
| 0.5 | 188 (88.68%) | 24 | 5 (2.84%) |
| 0.9 | 46 (21.70%) | 166 | 0 |
| 0.95 | 13 (6.13%) | 199 | 0 |
| 0.99 | 0 | 212 | 0 |

An always-negative baseline detects none and produces no false alarms. Zero
observed false alarms at a higher score is therefore insufficient by itself.
Even treating the 176 negatives as independent would leave a one-sided 95%
zero-event upper bound of about 1.69%; related messages and source sampling
invalidate treating that as a guaranteed deployment bound. No threshold is
selected, and the scores have not been calibrated.

The final run used two CPU threads: 0.92 seconds to vectorize/train, 2.26 seconds
total wall time, 2.05 seconds process CPU, and 282.0 MB peak Python process RSS.
Per-message scoring including vectorization was 0.547 ms median and 1.611 ms p95.
The coefficient array occupies 661,168 bytes, excluding vocabulary, IDF and runtime;
it is not a packaged model-size claim. Shared-host measurements do not establish
app latency. A second run after adding audit metadata reproduced exactly the same
partition, scores and confusion counts; there was no model/threshold adjustment.

## Reproduction and decision

Install `Tools/Corpus/requirements.txt` and `requirements-baseline.txt` in a unique
pyenv environment. Obtain the CSV through the original release's Files section;
the script verifies the exact pinned hash before parsing. The recorded run used:

```sh
PYENV_VERSION=spamwise-spaphish-f6498b20 pyenv exec python Tools/Corpus/spaphish.py \
  --source '.build/f6498b20-a954-4540-9bde-cb7605194f14/spaphish/downloads/Spaphish dataset - DiB.csv' \
  --output .build/d0294911-bcb6-4e23-b906-15f26cc19efa/spaphish-confirmation
```

Use a fresh output directory on reproduction. Private `partition.json` and
`scores.json` preserve record identities without bodies. The
[aggregate report](../../Tools/Corpus/reports/spaphish-development.json)
pins source, tool, imported preparation/audit helpers, dependency files and partition identities. Outputs use private
permissions. No model artifact is exported or integrated into SpamWise.

Retain SpaPhish and this baseline for Spanish phishing development. The 2.84%
false-alarm rate is unsuitable evidence for automatic Junk action, while higher
scores lose most phishing examples. A useful next experiment is a source/time
transfer study with legitimate financial/security workflows; inspecting errors
or tuning now consumes development data. Anonymization shortcuts, limited inbox
sampling and incomplete campaign grouping still need audit. Spanish phishing
results do not establish general spam, graymail, English or French performance.
No comparably licensed modern French legitimate-email source was established by
this search. The Mendeley tri-class low-resource-language release is
[embargoed until December 2, 2026](https://data.mendeley.com/datasets/6yv6nhk92n/1)
and was not acquired.

Verification: all eight corpus unit tests pass, with the existing campaign test
extended for this baseline's grouping, unknown spam labels and conflict
abstention. Ruff checks/formatting and Python compilation pass. Markdown lint
passes. The probe changes no app source and makes no production-model claim.

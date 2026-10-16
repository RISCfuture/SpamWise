# Local model screening — 2026-10-16

The first compact candidate runs locally, but fails several task-boundary examples.
It is a baseline, not a selected production model. No application code, filtering
settings or mail actions were changed by this probe.

## Candidate and provenance

[mrm8488/bert-tiny-finetuned-enron-spam-detection](https://huggingface.co/mrm8488/bert-tiny-finetuned-enron-spam-detection)
declares Apache 2.0, 4.39 million parameters and Enron spam training. Its card is
incomplete about limitations and training data. Pin
`2f5580bfd62e4a167d05742f0de321d570df5a21`, use Safetensors and disable remote
code. No substitute model is loaded.

The model config lacks semantic output names. I independently checked the
training dataset's `label`/`label_text` pairs at
[`SetFit/enron_spam` revision `1916f66c89d52221ae33eb57d44498b4f3a5df22`](https://huggingface.co/datasets/SetFit/enron_spam/tree/1916f66c89d52221ae33eb57d44498b4f3a5df22):
0 means ham and 1 means spam. This establishes the interpreted label mapping,
not the dataset's suitability for phishing, graymail or multilingual training.

## Observed synthetic results

The exact eight inputs, scores and per-call timings are in
[tiny-model-smoke.json](tiny-model-smoke.json). Scores below are rounded neural
outputs, not calibrated probabilities.

| Case | Spam score | Interpretation for candidate selection |
| --- | --- | --- |
| Personal lunch message | 0.0017 | Distinguishes this simple English wanted example |
| Subscribed gardening newsletter | 0.9982 | Conflates legitimate bulk mail with unwanted spam; no personal preference supplied |
| Unsolicited bulk leads offer | 0.9983 | Recognizes this explicit spam example |
| Mailbox password lure | 0.9975 | Flags this lure but supplies no distinct phishing assessment |
| Targeted confidential payment diversion | 0.0017 | Misses this constructed suspicious request as a binary spam detector |
| Legitimate password-reset notice | 0.0051 | Retains this legitimate security example |
| Personal lunch message in unaccented French | 0.9832 | Poor result for this wanted non-English example |
| Personal lunch message in unaccented Spanish | 0.9969 | Poor result for this wanted non-English example |

Measured inference calls took approximately 0.5–3 ms on this Mac after model
loading. This excludes download, startup, tokenization and application integration;
it is not an end-to-end performance benchmark. Eight constructed cases cannot
establish aggregate accuracy or calibrated thresholds. They do demonstrate why
this binary model cannot alone satisfy the product's separate objectives.

## Reproduction

Use a pyenv virtualenv with Python 3.14.8, `torch==2.14.1` and
`transformers==5.20.1`, the versions used for this run. The saved JSON contains all
input text; no private mail or provider credentials are required. From the repo
root, with that virtualenv selected:

```python
import json
import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

with open("docs/probes/tiny-model-smoke.json") as handle:
    probe = json.load(handle)
options = {
    "revision": probe["revision"],
    "token": False,
    "trust_remote_code": False,
    "cache_dir": ".build/model-screening",
}
tokenizer = AutoTokenizer.from_pretrained(probe["model"], **options)
model = AutoModelForSequenceClassification.from_pretrained(
    probe["model"], use_safetensors=True, **options
).eval()
with torch.inference_mode():
    for case in probe["results"]:
        inputs = tokenizer(
            case["subject"] + "\n" + case["body"],
            return_tensors="pt", max_length=512, truncation=True,
        )
        scores = model(**inputs).logits.softmax(dim=-1)[0].tolist()
        print(case["synthetic_case"], scores)
```

The first run downloads public model/tokenizer files; inference is local. The
original run used the worker-specific `.build` directory and explicitly disabled
implicit Hugging Face authentication and telemetry. It made no paid calls.
Core ML conversion, signed app runtime, broader datasets and competing models
remain unverified for this candidate. Continue selection using the [dataset assessment](../training-data.md)
and [independent detection objectives](../detection-design.md).

## Second candidate: multilingual spam and fraud

[Horizon-Labs/phishing-scam-detector-base](https://huggingface.co/Horizon-Labs/phishing-scam-detector-base)
declares Apache 2.0 and a 307M-parameter multilingual ModernBERT model. Revision
`f1dddff04e7f56dc9f0f068d4e7f0383c583e392` explicitly maps output indices to
`legitimate`, `spam` and `fraud`. Its teacher-generated fraud category combines
phishing and other scams; it does not independently distinguish spearphishing.
The model card's reported public benchmarks do not validate the spam/fraud split.

An actual local run used Safetensors, disabled remote code, CPU execution with two
threads, eager attention and a 384-token limit. It reused the eight inputs above
and added accented French/Spanish personal messages and a legitimate payment-change
counterpart that requests independent phone verification. Exact inputs and outputs
are in [multilingual-model-smoke.json](multilingual-model-smoke.json).

| Case | Observed result |
| --- | --- |
| Subscribed newsletter | Legitimate score 0.9522 |
| Bulk leads offer | Spam score 0.9719 |
| Password lure | Fraud score 0.9940 |
| Targeted payment diversion | Fraud score 0.8641 |
| Legitimate payment change requesting independent confirmation | Fraud score 0.9939 — a concerning false alarm on the constructed counterpart |
| French/Spanish personal examples, accented and unaccented | Legitimate scores 0.9970–0.9995 |

Inference took approximately 15–50 ms per case, excluding loading/tokenization.
These eleven synthetic cases support further investigation of this candidate as
an evidence source, not automatic action eligibility. In particular, the higher
fraud score on the legitimate payment example means simply raising a threshold
does not solve this pair. Evaluate legitimate financial workflows and relationship
context before choosing or fine-tuning a model. No production model was selected,
no mail action was requested, and no paid API call was used for this screening.

## Real-mail development screening

The [offline corpus tool](../../Tools/Corpus/README.md) prepared source-attributed,
duplicate/template-grouped splits. Two actual CPU runs scored the same 259 real
validation messages: 181 Guenter spam records in 123 template groups and 78
Nazario phishing records in 70 groups. The 259 reserved real holdout messages and
all synthetic partitions were excluded from inference. Source labels have not
been independently reviewed; missing labels remain unknown.

| Observation | 384 tokens | 1,024 tokens |
| --- | ---: | ---: |
| Spam source: top output spam | 98/181 | 125/181 |
| Spam source: top output legitimate | 79/181 | 55/181 |
| Phishing source: top output fraud | 30/78 | 28/78 |
| Phishing source: top output legitimate | 41/78 | 34/78 |
| Spam source: spam score at least 0.95 | 5/181 | 5/181 |
| Phishing source: fraud score at least 0.95 | 5/78 | 5/78 |
| Truncated messages | 174/259 | 141/259 |
| Median / p95 inference | 103 / 105 ms | 396 / 400 ms |
| Peak Python process memory | 1.51 GB | 1.69 GB |

Full aggregate reports pin model weights, corpus hash and library versions:
[384 tokens](local-model-development-384.json) and
[1,024 tokens](local-model-development-1024.json). Per-record results remain local
and contain IDs/scores rather than message bodies. Timing excludes model loading
and tokenization; memory includes the Python runtime. No paid calls were made.

Longer input improves the model's bulk-spam top-label count in this development
set, but does not improve its fraud top-label count on phishing. A broad fraud
score remains a proxy, not a distinct phishing detector. Neither run contains
verified legitimate negatives, so false-positive rates and safe action thresholds
are unknown. Repeated templates also prevent treating all records as independent
trials. These results, together with the legitimate-payment false alarm above, do
not support packaging this candidate as the production automatic filter. No model
or threshold was selected, and no claim of superiority over SpamSieve follows.

## Historical hard-ham development comparison

The [source audit](../training-data.md#historical-difficult-negatives-acquired)
added 232 usable SpamAssassin hard-ham messages in 225 template groups. The source
explicitly labels them non-spam and permits filter testing; broader model-training
permission is unestablished. They are confined to real validation, with
`spam: false` and other objectives unknown. Eighteen source messages failed text
extraction and were quarantined. This exclusion can introduce selection bias.

The pinned Horizon-Labs candidate was rerun locally with the same two CPU threads,
Safetensors and offline-only settings. Each run scored 491 real validation
records: 181 source spam, 78 source phishing and 232 source non-spam. All 18,201
original records retain their split; the 259 real and 2,523 synthetic holdout
records were not scored. No training, paid calls or production setting changes
were made.

| Hard-ham observation | 384 tokens | 1,024 tokens |
| --- | ---: | ---: |
| Top output spam | 152/232 | 159/232 |
| Top output legitimate | 80/232 | 73/232 |
| Spam score at least 0.5 | 141/232 (60.8%) | 152/232 (65.5%) |
| Spam score at least 0.9 | 13/232 | 7/232 |
| Spam score at least 0.95 | 1/232 | 1/232 |
| Spam score at least 0.99 | 0/232 | 0/232 |
| Combined spam/fraud score at least 0.5 | 155/232 | 164/232 |
| Truncated hard-ham messages | 216/232 | 170/232 |

Aggregate reports pin weights, corpus identity and runtime versions:
[384 tokens](../../Tools/Corpus/reports/hard-ham-development-384.json) and
[1,024 tokens](../../Tools/Corpus/reports/hard-ham-development-1024.json).
Per-record results remain under
`.build/corpus-negatives-20261016/development-screen-{384,1024}/` and contain
identities/scores rather than message bodies. Whole-cohort inference median/p95
was 103/108 ms and 398/604 ms respectively, excluding loading/tokenization;
observed peak process memory was 1.55 GB and 1.71 GB. Shared-machine timing is
descriptive, not an application latency guarantee.

Longer input does not resolve this candidate's false alarms on historical
hard-ham. Raising the spam threshold to 0.95 leaves one false alarm while detecting
only five of 181 source-spam positives in either run. These observations reject
this candidate as an automatic production filter; they do not choose a safe
threshold. The source has no independent phishing/fraud-negative labels, so the
combined alarm count is not a phishing or fraud false-positive rate. Template
correlation, historical sampling, unknown pretrained exposure and missing modern
financial/security and Spanish/French legitimate cohorts prevent generalizing
these proportions to current personal mail.

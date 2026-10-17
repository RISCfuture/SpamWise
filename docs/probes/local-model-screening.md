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

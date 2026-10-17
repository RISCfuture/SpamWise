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
remain unverified. Continue selection using the [dataset assessment](../training-data.md)
and [independent detection objectives](../detection-design.md).

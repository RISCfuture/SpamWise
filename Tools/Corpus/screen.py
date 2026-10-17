"""Screen a pinned local candidate on development data without scoring the holdout."""

import argparse
import hashlib
import json
import math
import os
import platform
import resource
import statistics
import time
from collections import Counter
from pathlib import Path

from prepare import SCHEMA, write_json

MODEL = "Horizon-Labs/phishing-scam-detector-base"
REVISION = "f1dddff04e7f56dc9f0f068d4e7f0383c583e392"
LABELS = ("legitimate", "spam", "fraud")


def development_records(corpus):
    """Verify corpus identity and select only real validation records."""
    manifest = json.loads((corpus / "manifest.json").read_text())
    if manifest.get("schema") != SCHEMA or manifest.get("complete") is not True:
        raise ValueError("incomplete_corpus")
    path = corpus / "records.jsonl"
    with path.open("rb") as stream:
        if (
            hashlib.file_digest(stream, "sha256").hexdigest()
            != manifest["records_sha256"]
        ):
            raise ValueError("corpus_hash")
    with path.open() as stream:
        records = [json.loads(line) for line in stream]
    selected = [
        row for row in records if row["split"] == "validation" and row["kind"] == "real"
    ]
    if not selected:
        raise ValueError("empty_development_split")
    return selected, manifest


def summarize(rows):
    """Report explicitly labeled cohorts and abstain from metrics with unknown labels."""
    cohorts = {}
    for task, score_label in (("spam", "spam"), ("phishing", "fraud")):
        selected = [row for row in rows if row["labels"].get(task) is True]
        negatives = [row for row in rows if row["labels"].get(task) is False]
        if not selected and not negatives:
            continue
        false_positives = sum(row["scores"][score_label] >= 0.5 for row in negatives)
        cohorts[task] = {
            "positive_records": len(selected),
            "template_groups": len({row["group"] for row in selected}),
            "argmax_counts": dict(Counter(row["prediction"] for row in selected)),
            "scored_output": score_label,
            "output_is_task_proxy": task != score_label,
            "threshold_hits": {
                str(threshold): sum(
                    row["scores"][score_label] >= threshold for row in selected
                )
                for threshold in (0.5, 0.9, 0.95, 0.99)
            },
            "spam_or_fraud_at_0.5": sum(
                row["scores"]["spam"] + row["scores"]["fraud"] >= 0.5
                for row in selected
            ),
            "negative_records": len(negatives),
            "negative_argmax_counts": dict(
                Counter(row["prediction"] for row in negatives)
            ),
            "threshold_false_positives": {
                str(threshold): sum(
                    row["scores"][score_label] >= threshold for row in negatives
                )
                for threshold in (0.5, 0.9, 0.95, 0.99)
            },
            "false_positive_rate": false_positives / len(negatives)
            if negatives
            else None,
            "false_positive_threshold": 0.5,
            "spam_or_fraud_at_0.5_negative": sum(
                row["scores"]["spam"] + row["scores"]["fraud"] >= 0.5
                for row in negatives
            ),
        }
    timings = sorted(row["inference_ms"] for row in rows)
    return {
        "cohorts": cohorts,
        "evaluated_records": len(rows),
        "truncated_records": sum(row["truncated"] for row in rows),
        "inference_ms": {
            "p50": statistics.median(timings) if timings else None,
            "p95": timings[math.ceil(len(timings) * 0.95) - 1] if timings else None,
        },
        "limits": [
            "Development data only; reserved holdout is excluded from scoring.",
            "Positive-only cohorts do not establish false-positive rates; thresholds remain uncalibrated.",
            "Fraud is a broad model output, not a separately trained phishing score.",
            "Template groups are heuristic; records are not assumed independent.",
            "Labels, languages and pretrained exposure have not been independently audited.",
        ],
    }


def screen(corpus, snapshot, output, max_tokens=384):
    """Run Safetensors-only CPU inference from an explicit offline model snapshot."""
    if snapshot.name != REVISION:
        raise ValueError("model_revision")
    if max_tokens not in (384, 1024):
        raise ValueError("token_budget")
    if output.exists():
        raise ValueError("output_exists")
    records, manifest = development_records(corpus)
    for key in (
        "HF_HUB_OFFLINE",
        "TRANSFORMERS_OFFLINE",
        "HF_HUB_DISABLE_TELEMETRY",
        "HF_HUB_DISABLE_IMPLICIT_TOKEN",
    ):
        os.environ[key] = "1"
    import torch
    import transformers
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    torch.set_num_threads(2)
    options = {"local_files_only": True, "trust_remote_code": False, "token": False}
    tokenizer = AutoTokenizer.from_pretrained(snapshot, **options)
    model = AutoModelForSequenceClassification.from_pretrained(
        snapshot, use_safetensors=True, attn_implementation="eager", **options
    ).eval()
    if tuple(model.config.id2label[index] for index in range(3)) != LABELS:
        raise ValueError("model_labels")
    weights = snapshot / "model.safetensors"
    with weights.open("rb") as stream:
        weights_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    rows = []
    start = time.perf_counter()
    with torch.inference_mode():
        for record in records:
            inputs = tokenizer(
                record["text"],
                return_tensors="pt",
                truncation=True,
                max_length=max_tokens,
            )
            length = len(
                tokenizer(record["text"], truncation=False, verbose=False)["input_ids"]
            )
            inference_start = time.perf_counter()
            scores = model(**inputs).logits.softmax(dim=-1)[0].tolist()
            elapsed = (time.perf_counter() - inference_start) * 1000
            if not all(math.isfinite(score) and 0 <= score <= 1 for score in scores):
                raise ValueError("model_scores")
            rows.append(
                {
                    "id": record["id"],
                    "group": record["group"],
                    "labels": record["labels"],
                    "prediction": LABELS[
                        max(range(3), key=lambda index: scores[index])
                    ],
                    "scores": dict(zip(LABELS, scores, strict=True)),
                    "truncated": length > max_tokens,
                    "inference_ms": elapsed,
                }
            )
    report = {
        "model": MODEL,
        "revision": REVISION,
        "weights_sha256": weights_hash,
        "corpus_sha256": manifest["records_sha256"],
        "seed": manifest["seed"],
        "torch": torch.__version__,
        "transformers": transformers.__version__,
        "python": platform.python_version(),
        "platform": platform.platform(),
        "max_tokens": max_tokens,
        "elapsed_seconds_excluding_load": time.perf_counter() - start,
        "peak_process_memory_bytes_macos": resource.getrusage(
            resource.RUSAGE_SELF
        ).ru_maxrss,
        "paid_calls": 0,
        **summarize(rows),
        "results": rows,
    }
    output.mkdir(mode=0o700, parents=True)
    previous_umask = os.umask(0o077)
    try:
        write_json(output / "results.json", report)
        write_json(
            output / "summary.json",
            {key: value for key, value in report.items() if key != "results"},
        )
    finally:
        os.umask(previous_umask)
    return report


def main():
    """Run the reproducible offline development screen."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--snapshot", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--max-tokens", type=int, choices=(384, 1024), default=384)
    args = parser.parse_args()
    report = screen(args.corpus, args.snapshot, args.output, args.max_tokens)
    print(
        json.dumps({"evaluated_records": report["evaluated_records"], "paid_calls": 0})
    )


if __name__ == "__main__":
    main()

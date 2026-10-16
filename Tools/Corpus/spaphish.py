"""Audit SpaPhish v5 and fit one fixed, local Spanish phishing development baseline."""

import argparse
import csv
import hashlib
import importlib.metadata
import json
import os
import platform
import re
import resource
import statistics
import time
import warnings
from collections import Counter
from datetime import datetime
from pathlib import Path

from audit import development_campaigns
from prepare import digest, group_records, normalized, template_key, write_json

SOURCE_SHA256 = "656b2245d58da72d640680e5c2a168673a130b38607f2a427c773bbb167e995e"
SOURCE = "spaphish-hz2d6gz7pc-v5"
SEED = "spamwise-spaphish-development-v1"


def source_records(path):
    """Verify the published file and map only its explicit phishing labels."""
    if path.is_symlink() or path.stat().st_size > 8_000_000:
        raise ValueError("source_file")
    if hashlib.sha256(path.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("source_hash")
    with path.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != 1395 or Counter(row["Label"] for row in rows) != {
        "0": 664,
        "1": 731,
    }:
        raise ValueError("source_counts")
    if len({row["hash"] for row in rows}) != len(rows):
        raise ValueError("source_identity")
    records, dates = [], Counter()
    for row in rows:
        if len(row) != 47 or not re.fullmatch(r"[0-9a-f]{64}", row["hash"]):
            raise ValueError("source_schema")
        body = row["body"].strip()
        text = f"Subject: {row['subject'].strip()}\n\n{body}"
        if not body or len(text) > 100_000:
            raise ValueError("source_text_bounds")
        try:
            year = str(datetime.strptime(row["date"], "%d/%m/%Y").year)
        except ValueError:
            year = "unknown"
        dates[f"{row['Label']}/{year}"] += 1
        records.append(
            {
                "id": digest(normalized(text)),
                "text": text,
                "template": template_key(body),
                "provenance": [
                    {
                        "source": SOURCE,
                        "position": row["hash"],
                        "labels": {"phishing": row["Label"] == "1"},
                        "synthetic": False,
                        "source_year": year,
                    }
                ],
            }
        )
    return records, dict(sorted(dates.items()))


def development_partition(records):
    """Group this separate development source before assigning train/validation."""
    rows = group_records(records, SEED)
    for row in rows:
        row["split"] = "train"
    campaign_audit, pairs = development_campaigns(rows)
    indexed = {row["id"]: row for row in rows}
    parents = {row["group"]: row["group"] for row in rows}

    def root(group):
        while parents[group] != group:
            parents[group] = parents[parents[group]]
            group = parents[group]
        return group

    for pair in pairs:
        left, right = (root(indexed[identity]["group"]) for identity in pair["ids"])
        parents[max(left, right)] = min(left, right)
    for row in rows:
        row["group"] = root(row["group"])
        fraction = int(digest(f"{SEED}:{row['group']}")[:8], 16) / 2**32
        row["split"] = "train" if fraction < 0.7 else "validation"
    if any(
        len({indexed[identity]["split"] for identity in pair["ids"]}) > 1
        for pair in pairs
    ):
        raise ValueError("campaign_leakage")
    campaign_audit["group_assignments_changed"] = True
    campaign_audit["accepted_overlap_threshold"] = 0.8
    campaign_audit["accepted_cross_split_pairs_after_grouping"] = 0
    return rows, campaign_audit


def threshold_metrics(rows, threshold):
    """Count explicit phishing outcomes without assigning missing threat labels."""
    counts = Counter()
    for row in rows:
        actual = row["phishing"]
        predicted = row["score"] >= threshold
        counts[(actual, predicted)] += 1
    tp, fn = counts[(True, True)], counts[(True, False)]
    fp, tn = counts[(False, True)], counts[(False, False)]
    return {
        "tp": tp,
        "fn": fn,
        "fp": fp,
        "tn": tn,
        "recall": tp / (tp + fn) if tp + fn else None,
        "false_positive_rate": fp / (fp + tn) if fp + tn else None,
        "precision": tp / (tp + fp) if tp + fp else None,
    }


def run(source, output):
    """Train on grouped development training text and score development validation."""
    if output.exists() or output.is_symlink():
        raise ValueError("output_exists")
    started, cpu_start = time.perf_counter(), time.process_time()
    records, dates = source_records(source)
    rows, campaign_audit = development_partition(records)
    selected = [row for row in rows if row["labels"]["phishing"] is not None]
    training = [row for row in selected if row["split"] == "train"]
    validation = [row for row in selected if row["split"] == "validation"]
    if any(
        {row["labels"]["phishing"] for row in cohort} != {False, True}
        for cohort in (training, validation)
    ):
        raise ValueError("missing_class")

    from sklearn.exceptions import ConvergenceWarning
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.linear_model import LogisticRegression
    from threadpoolctl import threadpool_limits

    vectorizer = TfidfVectorizer(
        analyzer="char_wb",
        ngram_range=(3, 5),
        min_df=2,
        max_features=100_000,
        sublinear_tf=True,
    )
    model = LogisticRegression(C=1.0, solver="liblinear", max_iter=1000, random_state=0)
    fit_start = time.perf_counter()
    with threadpool_limits(limits=2), warnings.catch_warnings():
        warnings.simplefilter("error", ConvergenceWarning)
        matrix = vectorizer.fit_transform([row["text"] for row in training])
        model.fit(matrix, [row["labels"]["phishing"] for row in training])
        fit_seconds = time.perf_counter() - fit_start
        positive_index = list(model.classes_).index(True)
        scores, timings = [], []
        for row in validation:
            inference_start = time.perf_counter()
            score = float(
                model.predict_proba(vectorizer.transform([row["text"]]))[
                    0, positive_index
                ]
            )
            timings.append((time.perf_counter() - inference_start) * 1000)
            scores.append(
                {
                    "id": row["id"],
                    "group": row["group"],
                    "phishing": row["labels"]["phishing"],
                    "score": score,
                }
            )
    timings.sort()
    report = {
        "schema": "spamwise-spaphish-development-v1",
        "source": {
            "id": SOURCE,
            "doi": "10.17632/hz2d6gz7pc.5",
            "sha256": SOURCE_SHA256,
            "license": "CC-BY-4.0",
            "attribution": "Lazaro Bustio-Martinez et al., SpaPhish v5",
            "source_declared_language": "es",
            "source_date_years_by_label": dates,
        },
        "input_records": len(records),
        "unique_records": len(rows),
        "conflicting_phishing_records_excluded": len(rows) - len(selected),
        "groups": len({row["group"] for row in rows}),
        "campaign_audit": campaign_audit,
        "split_seed": SEED,
        "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "requirements_sha256": hashlib.sha256(
            Path(__file__).with_name("requirements-baseline.txt").read_bytes()
        ).hexdigest(),
        "helper_sha256": {
            name: hashlib.sha256(
                Path(__file__).with_name(name).read_bytes()
            ).hexdigest()
            for name in ("audit.py", "prepare.py", "requirements.txt")
        },
        "split_identity_sha256": {
            name: digest("\n".join(sorted(row["id"] for row in cohort)))
            for name, cohort in (("train", training), ("validation", validation))
        },
        "body_fewer_than_40_letters": sum(
            sum(character.isalpha() for character in row["text"].split("\n\n", 1)[-1])
            < 40
            for row in rows
        ),
        "split_counts": dict(
            Counter(f"{row['split']}/{row['labels']['phishing']}" for row in selected)
        ),
        "validation_groups_by_label": {
            str(label): len(
                {
                    row["group"]
                    for row in validation
                    if row["labels"]["phishing"] == label
                }
            )
            for label in (False, True)
        },
        "model": {
            "type": "character TF-IDF + logistic regression",
            "parameters": {
                "analyzer": "char_wb",
                "ngram_range": [3, 5],
                "min_df": 2,
                "max_features": 100_000,
                "sublinear_tf": True,
                "C": 1.0,
                "solver": "liblinear",
                "max_iter": 1000,
                "random_state": 0,
            },
            "features": len(vectorizer.vocabulary_),
            "coefficient_bytes": model.coef_.nbytes + model.intercept_.nbytes,
            "iterations": model.n_iter_.tolist(),
            "input": "subject and body only",
            "fit_seconds": fit_seconds,
        },
        "thresholds": {
            str(value): threshold_metrics(scores, value)
            for value in (0.5, 0.9, 0.95, 0.99)
        },
        "all_negative_baseline": threshold_metrics(
            [{**row, "score": 0.0} for row in scores], 0.5
        ),
        "runtime": {
            "python": platform.python_version(),
            "platform": platform.platform(),
            "packages": {
                name: importlib.metadata.version(name)
                for name in ("scikit-learn", "numpy", "scipy", "threadpoolctl")
            },
            "thread_limit": 2,
            "inference_including_vectorization_ms": {
                "p50": statistics.median(timings),
                "p95": timings[int(len(timings) * 0.95)],
            },
            "wall_seconds": time.perf_counter() - started,
            "cpu_seconds": time.process_time() - cpu_start,
            "peak_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        },
        "limits": [
            "Separate development source only; no existing frozen corpus or reserved holdout is read.",
            "No threshold or hyperparameter search; probabilities are uncalibrated.",
            "Heuristic grouping is not proof of campaign independence; split is not temporal.",
            "Source-declared Spanish and expert phishing labels are not independently reviewed here.",
            "Anonymization and contributor-inbox sampling can create shortcuts and limit transfer.",
            "Spam, fraud, targeting, malware and graymail labels remain unknown.",
            "No production model artifact is serialized or shipped; no paid API call is made.",
        ],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir(mode=0o700)
    previous_umask = os.umask(0o077)
    try:
        write_json(output / "scores.json", scores)
        write_json(
            output / "partition.json",
            [
                {key: row[key] for key in ("id", "group", "split", "labels")}
                for row in rows
            ],
        )
        write_json(output / "report.json", report)
    finally:
        os.umask(previous_umask)
    return report


def main():
    """Run the hash-pinned offline SpaPhish development probe."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report = run(args.source, args.output)
    print(
        json.dumps(
            {key: report[key] for key in ("split_counts", "thresholds", "runtime")}
        )
    )


if __name__ == "__main__":
    main()

"""Audit frozen corpus metadata and development campaigns without model inference."""

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
from collections import Counter, defaultdict
from email import policy
from email.parser import BytesHeaderParser
from email.utils import parsedate_to_datetime
from pathlib import Path

from prepare import SCHEMA, TASKS, digest, normalized, source_messages, write_json


def read_corpus(path):
    """Require a completed, content-verified corpus before inspecting metadata."""
    manifest = json.loads((path / "manifest.json").read_text())
    if manifest.get("complete") is not True or manifest.get("schema") != SCHEMA:
        raise ValueError("incomplete_corpus")
    with (path / "records.jsonl").open("rb") as stream:
        if (
            hashlib.file_digest(stream, "sha256").hexdigest()
            != manifest["records_sha256"]
        ):
            raise ValueError("corpus_hash")
    rows = [
        json.loads(line) for line in (path / "records.jsonl").read_text().splitlines()
    ]
    if len({row["id"] for row in rows}) != len(rows):
        raise ValueError("duplicate_identity")
    return rows, manifest


def verify_metadata(rows, manifest, directory):
    """Check source-label fidelity, conflict abstention and exact objective membership."""
    sources = {source["id"]: source for source in manifest["sources"]}
    groups, expected = defaultdict(set), defaultdict(list)
    evaluation_groups = set()
    for row in rows:
        groups[row["group"]].add(row["split"])
        kinds = {origin["synthetic"] for origin in row["provenance"]}
        expected_kind = (
            "synthetic" if kinds == {True} else "real" if kinds == {False} else "mixed"
        )
        if not kinds or row["kind"] != expected_kind:
            raise ValueError("source_kind_mismatch")
        for origin in row["provenance"]:
            source = sources[origin["source"]]
            if origin["labels"] != source["labels"]:
                raise ValueError("source_label_mismatch")
            if origin["synthetic"] != source["synthetic"] or origin.get(
                "usage", "training"
            ) != source.get("usage", "training"):
                raise ValueError("source_usage_mismatch")
            if source.get("usage") == "evaluationOnly":
                evaluation_groups.add(row["group"])
        conflicts = []
        for task in TASKS:
            votes = {
                origin["labels"][task]
                for origin in row["provenance"]
                if origin["labels"].get(task) is not None
            }
            label = next(iter(votes)) if len(votes) == 1 else None
            if row["labels"].get(task) is not label:
                raise ValueError("effective_label_mismatch")
            if len(votes) > 1:
                conflicts.append(task)
            if label is not None:
                key = f"{task}/{row['kind']}/{row['split']}"
                expected[key].append({"id": row["id"], "label": label})
        if conflicts != row["conflicts"]:
            raise ValueError("conflict_mismatch")
    if any(len(splits) != 1 for splits in groups.values()):
        raise ValueError("group_split_leakage")
    if any(groups[group] != {"validation"} for group in evaluation_groups):
        raise ValueError("evaluation_training_leakage")
    actual = {
        str(path.relative_to(directory / "objectives").with_suffix("")): json.loads(
            path.read_text()
        )
        for path in (directory / "objectives").rglob("*.json")
    }
    if actual != dict(expected):
        raise ValueError("objective_membership_mismatch")
    return {
        "records": len(rows),
        "groups": len(groups),
        "source_labels_and_indices_verified": True,
        "evaluation_only_groups": len(evaluation_groups),
        "split_counts": dict(
            sorted(Counter(f"{r['kind']}/{r['split']}" for r in rows).items())
        ),
        "language_labels": dict(Counter(row["language"] for row in rows)),
        "independently_reviewed_records": sum(row["reviewed"] for row in rows),
    }


def compare_frozen(rows, baseline):
    """Require every prior identity, template group and split to remain unchanged."""
    current = {row["id"]: (row["group"], row["split"]) for row in rows}
    if any(current.get(row["id"]) != (row["group"], row["split"]) for row in baseline):
        raise ValueError("frozen_membership_changed")
    return {
        "preserved_records": len(baseline),
        "preserved_holdout_records": sum(row["split"] == "holdout" for row in baseline),
    }


def development_campaigns(rows):
    """Find high-overlap real development bodies across existing template groups."""
    selected = [
        row for row in rows if row["kind"] == "real" and row["split"] != "holdout"
    ]
    postings, shingles, pairs = defaultdict(list), [], []
    for index, row in enumerate(selected):
        body = (
            row["text"].split("\n\n", 1)[-1]
            if row["text"].startswith("Subject:")
            else row["text"]
        )
        words = re.findall(r"\w+", normalized(body))[:10_000]
        current = {tuple(words[i : i + 5]) for i in range(len(words) - 4)}
        if len(current) < 20:
            current = set()
        overlaps = Counter(other for shingle in current for other in postings[shingle])
        for other, intersection in overlaps.items():
            previous = selected[other]
            union = len(current) + len(shingles[other]) - intersection
            if previous["group"] != row["group"] and intersection / union >= 0.8:
                pairs.append(
                    {
                        "ids": [previous["id"], row["id"]],
                        "splits": [previous["split"], row["split"]],
                        "jaccard": intersection / union,
                    }
                )
        for shingle in current:
            postings[shingle].append(index)
        shingles.append(current)
    summary = {
        "selected_real_non_holdout_records": len(selected),
        "eligible_records": sum(bool(value) for value in shingles),
        "method": "Unmasked normalized five-word shingles; at least 20 distinct shingles; Jaccard >= 0.8; first 10000 words",
        "different_group_candidate_pairs": len(pairs),
        "cross_train_validation_candidate_pairs": sum(
            len(set(pair["splits"])) > 1 for pair in pairs
        ),
        "holdout_content_examined": False,
        "group_assignments_changed": False,
    }
    indexed = {row["id"]: row for row in selected}
    summary["candidate_source_pairs"] = dict(
        Counter(
            " / ".join(
                sorted(
                    {
                        origin["source"]
                        for identity in pair["ids"]
                        for origin in indexed[identity]["provenance"]
                    }
                )
            )
            for pair in pairs
        )
    )
    summary["candidate_distinct_records"] = len(
        {identity for pair in pairs for identity in pair["ids"]}
    )
    summary["cross_split_distinct_records"] = len(
        {
            identity
            for pair in pairs
            if len(set(pair["splits"])) > 1
            for identity in pair["ids"]
        }
    )
    return summary, pairs


def development_headers(rows, manifest, downloads):
    """Count untrusted Date/Content-Language claims for accepted real development origins."""
    origins = {
        (origin["source"], origin["position"]): origin["raw_sha256"]
        for row in rows
        if row["kind"] == "real" and row["split"] != "holdout"
        for origin in row["provenance"]
    }
    result = {}
    for source in manifest["sources"]:
        path = downloads / source["filename"]
        with path.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != source["sha256"]:
                raise ValueError("source_hash")
        if source["synthetic"]:
            continue
        years, languages, count = Counter(), Counter(), 0
        for position, raw in source_messages(source, path):
            identity = origins.get((source["id"], position))
            if identity is None:
                continue
            if digest(raw) != identity:
                raise ValueError("origin_hash")
            headers = BytesHeaderParser(policy=policy.default).parsebytes(raw)
            try:
                year = str(parsedate_to_datetime(str(headers.get("Date", ""))).year)
            except (ValueError, TypeError, OverflowError):
                year = "unknown"
            years[year] += 1
            language = str(headers.get("Content-Language", "")).strip().lower()
            languages[
                language
                if re.fullmatch(r"[a-z]{2,3}(?:-[a-z]{2})?", language)
                else "unknown_or_multiple"
            ] += 1
            count += 1
        if count != sum(key[0] == source["id"] for key in origins):
            raise ValueError("missing_origin")
        result[source["id"]] = {
            "source_period": source["period"],
            "accepted_development_origins": count,
            "untrusted_date_year": dict(sorted(years.items())),
            "untrusted_content_language": dict(sorted(languages.items())),
        }
    return result


def derived_development_partition(rows, pairs):
    """Keep high-overlap development groups together with validation taking precedence."""
    selected = [
        row for row in rows if row["kind"] == "real" and row["split"] != "holdout"
    ]
    indexed = {row["id"]: row for row in selected}
    parents = {row["group"]: row["group"] for row in selected}

    def root(group):
        while parents[group] != group:
            parents[group] = parents[parents[group]]
            group = parents[group]
        return group

    accepted = [pair for pair in pairs if pair["jaccard"] >= 0.95]
    for pair in accepted:
        first, second = (root(indexed[identity]["group"]) for identity in pair["ids"])
        parents[max(first, second)] = min(first, second)
    validation = {
        root(row["group"])
        for row in selected
        if row["split"] == "validation"
        or any(origin.get("usage") == "evaluationOnly" for origin in row["provenance"])
    }
    members = [
        {
            "id": row["id"],
            "original_group": row["group"],
            "original_split": row["split"],
            "group": root(row["group"]),
            "split": "validation" if root(row["group"]) in validation else "train",
        }
        for row in selected
    ]
    counts = {
        "records": len(members),
        "groups": len({row["group"] for row in members}),
        "accepted_overlap_pairs": len(accepted),
        "split_counts": dict(Counter(row["split"] for row in members)),
        "train_records_moved_to_validation": sum(
            row["split"] != row["original_split"] for row in members
        ),
        "holdout_records": 0,
        "prior_development_exposure_preserved": True,
        "independent_evaluation_eligible": False,
    }
    derived = {row["id"]: row for row in members}
    if any(
        len({derived[identity]["split"] for identity in pair["ids"]}) > 1
        for pair in accepted
    ):
        raise ValueError("derived_campaign_leakage")
    counts["accepted_cross_split_pairs"] = 0
    counts["remaining_lower_overlap_cross_split_pairs"] = sum(
        len({derived[identity]["split"] for identity in pair["ids"]}) > 1
        for pair in pairs
    )
    return counts, members


def inferred_development_languages(rows, executable):
    """Annotate real development text locally without changing reviewed language labels."""
    selected = [
        row for row in rows if row["kind"] == "real" and row["split"] != "holdout"
    ]
    result = subprocess.run(
        [str(executable.resolve())],
        input=json.dumps([{"id": row["id"], "text": row["text"]} for row in selected]),
        text=True,
        capture_output=True,
        check=True,
        timeout=180,
    )
    estimates = json.loads(result.stdout)
    indexed = {row["id"]: row for row in estimates}
    if len(indexed) != len(estimates) or set(indexed) != {
        row["id"] for row in selected
    }:
        raise ValueError("language_membership")
    for estimate in estimates:
        if (
            not re.fullmatch(r"[a-zA-Z-]{2,20}", estimate["language"])
            or not 0 <= estimate["confidence"] <= 1
        ):
            raise ValueError("language_estimate")
    sources = defaultdict(Counter)
    for row in selected:
        for source in {origin["source"] for origin in row["provenance"]}:
            sources[source][indexed[row["id"]]["language"]] += 1
    return {
        "records": len(selected),
        "framework": "macOS NaturalLanguage NLLanguageRecognizer",
        "macos_version": platform.mac_ver()[0],
        "executable_sha256": digest(executable.read_bytes()),
        "method": "First 20000 characters; at least 40 letters; highest hypothesis >=0.8 and margin >=0.2; otherwise unknown",
        "inferred_not_reviewed": True,
        "holdout_records": 0,
        "counts": dict(sorted(Counter(row["language"] for row in estimates).items())),
        "source_counts": {
            source: dict(sorted(counts.items()))
            for source, counts in sorted(sources.items())
        },
    }, estimates


def main():
    """Write fresh private audit artifacts without changing corpus records or splits."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--downloads", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--language-tool", type=Path)
    args = parser.parse_args()
    rows, manifest = read_corpus(args.corpus)
    baseline, baseline_manifest = read_corpus(args.baseline)
    report = verify_metadata(rows, manifest, args.corpus)
    report["frozen_membership"] = compare_frozen(rows, baseline)
    report["records_sha256"] = manifest["records_sha256"]
    report["baseline_records_sha256"] = baseline_manifest["records_sha256"]
    report["campaigns"], pairs = development_campaigns(rows)
    report["derived_development"], partition = derived_development_partition(
        rows, pairs
    )
    report["development_header_claims"] = development_headers(
        rows, manifest, args.downloads
    )
    estimates = None
    if args.language_tool:
        report["inferred_development_languages"], estimates = (
            inferred_development_languages(rows, args.language_tool)
        )
    report["limitations"] = [
        "Source-label fidelity is not independent correctness review.",
        "Candidate overlap is not proof of shared campaign; unchanged groups are provisional.",
        "Holdout text is not inspected for campaign similarity or model inference.",
        "Sender-controlled dates/language headers are not verified time/language coverage.",
        "No threat classifier is loaded; pretrained exposure remains unknown.",
    ]
    previous_umask = os.umask(0o077)
    try:
        args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
        write_json(args.output / "campaign-candidates.json", pairs)
        write_json(
            args.output / "development-partition.json",
            {
                "schema": "spamwise-development-partition-v1",
                "complete": True,
                "original_records_sha256": manifest["records_sha256"],
                "method": "Connected existing groups linked by >=0.95 five-word Jaccard; validation takes precedence",
                "summary": report["derived_development"],
                "records": partition,
            },
        )
        write_json(args.output / "audit.json", report)
        if estimates is not None:
            write_json(args.output / "inferred-languages.json", estimates)
    finally:
        os.umask(previous_umask)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

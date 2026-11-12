"""Reconcile saved efficacy metadata and human labels without accessing Mail or providers."""

import argparse
import json
import os
from collections import Counter, defaultdict
from datetime import UTC, datetime
from pathlib import Path

from adherence import JUNK_THRESHOLDS, swept_action

LABELS = {"inbox", "review", "junk"}
AUTOMATIC = {"model", "gate"}


def pooled_records(snapshots):
    """Keep the newest observation of each record, retaining pruned history."""
    records = {}
    accounts = defaultdict(set)
    for snapshot in sorted(snapshots, key=lambda s: s["captured_at"]):
        for row in snapshot["records"]:
            records[row["id"]] = row
    for row in records.values():
        if row.get("account_hash"):
            accounts[row["message_hash"]].add(row["account_hash"])
    if any(len(values) > 1 for values in accounts.values()):
        raise ValueError(
            "Message hashes must already be account-scoped; ambiguous identities found"
        )
    return records


def labeled_observations(observations):
    """Flatten identified human labels, including messages nested in rescue events."""
    events = {}
    for event in observations:
        events[event["event_id"]] = event
    for event in events.values():
        for row in [event, *event.get("messages", [])]:
            if row.get("message_hash") and row.get("user_label") in LABELS:
                yield {**event, **row}


def feedback(records, observations):
    """Join standing explicit training corrections and later human observations by message."""
    labels, training = {}, {}
    for row in sorted(
        records.values(), key=lambda r: (r["timestamp"], r.get("revision", 0))
    ):
        if row["path"] != "correction" or row.get("correction_undone"):
            continue
        label = row.get("corrected_label") or row.get("decision_label")
        if label in LABELS:
            entry = {
                "label": label,
                "at": row["timestamp"],
                "source": "training_correction",
                "record_id": row["id"],
            }
            training[row["message_hash"]] = entry
            labels[row["message_hash"]] = entry
    for row in sorted(
        labeled_observations(observations), key=lambda r: r["observed_at"]
    ):
        key = row["message_hash"]
        if row["observed_at"] >= labels.get(key, {}).get("at", ""):
            labels[key] = {
                "label": row["user_label"],
                "at": row["observed_at"],
                "source": row["kind"],
                "event_id": row["event_id"],
            }
    return labels, training


def first_decisions(records):
    """Select the first automatic classification, excluding setup and corrections."""
    first = {}
    for row in sorted(records.values(), key=lambda r: r["timestamp"]):
        if row["path"] in AUTOMATIC and row.get("decision_label") in LABELS:
            first.setdefault(row["message_hash"], row)
    return first


def sample(first, labels, label):
    """Describe a selected labeled sample without presenting population accuracy."""
    rows = [
        first[key]
        for key, value in labels.items()
        if value["label"] == label and key in first
    ]
    return {
        "count": len(rows),
        "first_labels": dict(Counter(r["decision_label"] for r in rows)),
        "sample_note": "Human-labeled convenience sample; not population accuracy or recall.",
    }


def reconcile(snapshots, observations, live_start=""):
    """Recompute label and dispatch accounting from all available saved evidence."""
    records = pooled_records(snapshots)
    first = first_decisions(records)
    labels, training = feedback(records, observations)
    live = {key: row for key, row in first.items() if row["timestamp"] >= live_start}
    live_first = first_decisions(
        {key: row for key, row in records.items() if row["timestamp"] >= live_start}
    )
    automatic_junk = [
        r
        for r in records.values()
        if r["path"] in AUTOMATIC
        and r.get("action") == "moveToJunk"
        and r["timestamp"] >= live_start
        and r["outcome"] in {"applied", "failed", "requested"}
    ]
    false_positives = []
    for key, label in labels.items():
        actions = [
            r
            for r in automatic_junk
            if r["message_hash"] == key
            and r["outcome"] == "applied"
            and r.get("settled")
        ]
        if label["label"] == "inbox" and actions:
            false_positives.append(
                {
                    "message_hash": key,
                    "automatic_junk_record_ids": sorted(r["id"] for r in actions),
                    "source": label["source"],
                    "observation_timestamp": label["at"],
                    "standing_correction_record_id": training.get(key, {}).get(
                        "record_id"
                    ),
                }
            )
    failures = [r for r in records.values() if r["outcome"] == "failed"]
    gaps = [
        key
        for key, label in labels.items()
        if key in first and label["label"] != training.get(key, {}).get("label")
    ]
    return {
        "pooled_records": len(records),
        "unique_classified_messages": len(first),
        "first_decision_mix": dict(
            Counter(r["decision_label"] for r in first.values())
        ),
        "first_live_decisions": len(live_first),
        "first_live_decision_mix": dict(
            Counter(r["decision_label"] for r in live_first.values())
        ),
        "confirmed_false_positives_total": len(false_positives),
        "confirmed_false_positive_details": false_positives,
        "reviewed_unwanted": sample(first, labels, "junk"),
        "reviewed_wanted": sample(first, labels, "inbox"),
        "reviewed_unwanted_by_epoch": {
            "live": sample(live, labels, "junk"),
            "dry_run_or_pre_live": sample(
                {k: r for k, r in first.items() if k not in live}, labels, "junk"
            ),
        },
        "reviewed_wanted_by_epoch": {"live": sample(live, labels, "inbox")},
        "corrections_total": sum(r["path"] == "correction" for r in records.values()),
        "feedback_without_training_count": len(gaps),
        "feedback_without_training_message_hashes": sorted(gaps),
        "unlinked_labeled_message_count": sum(key not in first for key in labels),
        "integration": {
            "failed_before_dispatch": sum(bool(r.get("never_sent")) for r in failures),
            "failed_after_possible_dispatch": sum(
                not r.get("never_sent", False) for r in failures
            ),
            "contradictory_timeout_record_ids": sorted(
                {
                    r["id"]
                    for snapshot in snapshots
                    for r in snapshot["records"]
                    if r.get("never_sent")
                    and "may still happen" in (r.get("action_error") or "")
                }
            ),
            "note": "never_sent is dispatch evidence; historical error prose does not override it.",
        },
        "automatic_live_junk_moves": {
            "records": len(automatic_junk),
            "outcomes": dict(Counter(r["outcome"] for r in automatic_junk)),
            "paths": dict(Counter(r["path"] for r in automatic_junk)),
            "applied_and_settled": sum(
                r["outcome"] == "applied" and r.get("settled", False)
                for r in automatic_junk
            ),
        },
    }


def calibration(snapshots, observations, settings, live_start=""):
    """Replay category thresholds on labeled live model decisions; never select a release threshold."""
    records = pooled_records(snapshots)
    labels, _ = feedback(records, observations)
    by_category = defaultdict(list)
    for key, row in first_decisions(records).items():
        if (
            key not in labels
            or labels[key]["label"] not in {"inbox", "junk"}
            or row["timestamp"] < live_start
            or row["path"] != "model"
            or row.get("category_confidence") is None
            or settings["categoryPreferences"].get(row.get("category")) != "junk"
        ):
            continue
        by_category[row["category"]].append(
            (
                {
                    "label": row["decision_label"],
                    "path": row["path"],
                    "category": row["category"],
                    "categoryConfidence": row["category_confidence"],
                    "modelLabel": row["model_label"],
                    "confidence": row["confidence"],
                },
                labels[key]["label"],
            )
        )
    results = {}
    for category, rows in sorted(by_category.items()):
        curve = []
        for threshold in range(60, 101):
            pairs = [
                (
                    swept_action(
                        row,
                        settings["categoryPreferences"],
                        threshold,
                        JUNK_THRESHOLDS[settings["strength"]],
                    ),
                    label,
                )
                for row, label in rows
            ]
            curve.append(
                {
                    "threshold": threshold,
                    "wanted_to_junk": sum(
                        a == "junk" and b == "inbox" for a, b in pairs
                    ),
                    "unwanted_to_junk": sum(a == b == "junk" for a, b in pairs),
                    "review": sum(a == "review" for a, _ in pairs),
                }
            )
        results[category] = {
            "wanted": sum(label == "inbox" for _, label in rows),
            "unwanted": sum(label == "junk" for _, label in rows),
            "curve": curve,
        }
    return {
        "categories": results,
        "validated": False,
        "selected_thresholds": None,
        "note": "Exploratory replay under current category preferences and strength; selected human labels, no independent holdout. Do not deploy thresholds from this sample.",
    }


def write_json(path, value):
    """Atomically write private metadata without truncating the prior report on failure."""
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("x", encoding="utf-8") as stream:
        os.chmod(temporary, 0o600)
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    temporary.replace(path)


def main():
    """Write a dated reconciliation and optionally refresh the aggregate's derived fields."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--update-metrics", action="store_true")
    args = parser.parse_args()
    directory = args.directory
    snapshots = [
        json.loads(p.read_text())
        for p in sorted((directory / "snapshots").glob("*.json"))
    ]
    observations = json.loads((directory / "observations.json").read_text())
    metrics_path = directory / "latest-metrics.json"
    metrics = json.loads(metrics_path.read_text())
    live_start = metrics["live_start_verified_by_audit"]
    now = datetime.now(UTC)
    result = reconcile(snapshots, observations, live_start)
    result["reconciled_at"] = now.isoformat()
    result["snapshot_captured_at"] = max(s["captured_at"] for s in snapshots)
    result["observations_through"] = max(
        (o["observed_at"] for o in observations), default=None
    )
    result["calibration"] = calibration(
        snapshots, observations, metrics["settings"], live_start
    )
    result["limitations"] = [
        "Human labels are selected; no population accuracy, recall, or trend can be inferred.",
        "Applied and settled are recorded adapter observations, not fresh Mail audits.",
        "Manual cleanup and a saved human label do not prove SpamWise training occurred.",
        "Unidentified reports remain outside per-message metrics even when cleanup was verified.",
        "No Mail, production store, provider, rule, or settings changes are performed.",
    ]
    report = (
        directory / "reports" / (now.strftime("%Y%m%dT%H%M%S%fZ") + "-reconciled.json")
    )
    write_json(report, result)
    if args.update_metrics:
        archive = report.with_name(report.stem + "-previous-metrics.json")
        write_json(archive, metrics)
        metrics.update(result)
        write_json(metrics_path, metrics)
    print(report)


if __name__ == "__main__":
    main()

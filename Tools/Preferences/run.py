"""Run a bounded synthetic preference probe through the existing evaluation CLI."""

import argparse
import hashlib
import json
import os
import subprocess
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAX_CALLS = 12
RESERVATION_USD = 0.10


def write_json(path, value):
    """Write a readable UTF-8 artifact under the caller's private output directory."""
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def state_for(case, preference, condition):
    """Build isolated policy context without rules, history or test-target labels."""
    examples = []
    if condition == "bounded_examples":
        for index, example in enumerate(case["examples"]):
            examples.append(
                {
                    "id": str(
                        uuid.uuid5(
                            uuid.NAMESPACE_URL,
                            f"{case['language']}:{preference}:{index}",
                        )
                    ),
                    "date": 813456000 + index,
                    "sender": f"editor@analogy-{index}.example",
                    "domain": f"analogy-{index}.example",
                    **example,
                    "label": "inbox" if preference == "wanted" else "junk",
                    "reason": case[f"{preference}_reason"],
                }
            )
    return {
        "schemaVersion": 1,
        "revision": 0,
        "settings": {
            "strength": "balanced",
            "review": "orangeFlag",
            "dryRun": True,
            "paused": False,
            "policy": case[f"{preference}_policy"],
            "correctionLimit": 2,
            "bodyTokenBudget": 1500,
            "onboardingComplete": False,
            "route": "mailRule",
            "validatedAccounts": [],
        },
        "rules": [],
        "corrections": examples,
        "records": [],
        "retries": [],
        "histories": {},
        "claimedActions": {},
    }


def prepare(output):
    """Materialize identical per-language messages across four preference contexts."""
    source = Path(__file__).with_name("cases.json")
    spec = json.loads(source.read_text())
    if spec["synthetic"] is not True or {
        row["language"] for row in spec["languages"]
    } != {"en", "es", "fr"}:
        raise ValueError("invalid_languages_or_provenance")
    runs = []
    for case in spec["languages"]:
        if len(case["examples"]) != 2 or any(
            example["subject"] == case["subject"] for example in case["examples"]
        ):
            raise ValueError("invalid_analogies")
        raw = (
            "From: Garden Notes <newsletter@garden-notes.example>\r\n"
            "To: Reader <reader@example.net>\r\n"
            f"Message-ID: <preferences-{case['language']}@garden-notes.example>\r\n"
            "Date: Fri, 16 Oct 2026 12:00:00 +0000\r\n"
            f"Subject: {case['subject']}\r\n"
            "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n"
            f"Content-Transfer-Encoding: 8bit\r\n\r\n{case['body']}\r\n"
        ).encode()
        for preference in ("wanted", "unwanted"):
            for condition in ("policy_only", "bounded_examples"):
                name = f"{case['language']}-{preference}-{condition}"
                directory = output / name
                corpus = directory / "corpus" / "graymail"
                corpus.mkdir(parents=True)
                (corpus / "newsletter.eml").write_bytes(raw)
                state = state_for(case, preference, condition)
                write_json(directory / "state.json", state)
                runs.append(
                    {
                        "id": name,
                        "language": case["language"],
                        "preference": preference,
                        "condition": condition,
                        "message_sha256": hashlib.sha256(raw).hexdigest(),
                        "state_sha256": hashlib.sha256(
                            (directory / "state.json").read_bytes()
                        ).hexdigest(),
                        "synthetic_target": "inbox"
                        if preference == "wanted"
                        else "junk",
                        "correction_examples": len(state["corrections"]),
                    }
                )
    if len(runs) != MAX_CALLS:
        raise ValueError("call_budget")
    write_json(
        output / "manifest.json",
        {
            "schema": spec["schema"],
            "synthetic": True,
            "cases_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "maximum_calls": MAX_CALLS,
            "maximum_reservation_usd": round(MAX_CALLS * RESERVATION_USD, 2),
            "runs": runs,
        },
    )
    return runs


def evaluate(executable, output, run, budget_store):
    """Invoke one isolated CLI run, live when an evaluation budget store is supplied."""
    directory = output / run["id"]
    arguments = [
        "--input",
        str(directory / "corpus"),
        "--state",
        str(directory / "state.json"),
        "--cache",
        str(directory / "cache"),
        "--output",
        str(directory / "report.json"),
    ]
    command = (
        [
            "swift",
            str(ROOT / "Scripts/evaluate-with-keychain.swift"),
            str(executable),
            "claude",
            "--live",
            "--budget-store",
            str(budget_store),
        ]
        if budget_store
        else [str(executable), "--model", "mock"]
    )
    completed = subprocess.run(
        command + arguments, capture_output=True, timeout=90, check=False
    )
    if completed.returncode != 0:
        return {
            **run,
            "status": "launcher_or_evaluator_failure",
            "exit_code": completed.returncode,
        }
    report = json.loads((directory / "report.json").read_text())
    verdicts = list((directory / "cache").glob("*.json"))
    result = {
        **run,
        "status": "classified" if len(verdicts) == 1 else "classification_failed",
        "provider_calls": report["providerCalls"],
        "cache_hits": report["cacheHits"],
        "new_usage": report["newUsage"],
        "estimated_cost_usd": report.get("newEstimatedCostUSD"),
        "effective_labels": report["metrics"]["confusion"].get("graymail", {}),
    }
    if len(verdicts) == 1:
        verdict = json.loads(verdicts[0].read_text())
        result.update(
            model_label=verdict["label"],
            confidence=verdict["confidence"],
            reason=verdict["reason"],
        )
    else:
        result["failure_reasons"] = [
            row["reason"] for row in report["metrics"]["misclassifications"]
        ]
    return result


def execute(executable, output, runs, budget_store):
    """Stop after any unsuccessful case without retries, fallback or extra calls."""
    results = []
    for run in runs:
        try:
            result = evaluate(executable, output, run, budget_store)
        except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
            result = {**run, "status": "evaluation_interrupted"}
        results.append(result)
        write_json(
            output / "results.json",
            {
                "synthetic": True,
                "mode": "live" if budget_store else "offline_mock",
                "fine_tuning": False,
                "model": "claude-haiku-5-5" if budget_store else "mock",
                "maximum_reservation_usd": round(len(results) * RESERVATION_USD, 2)
                if budget_store
                else 0,
                "completed": len(results) == len(runs)
                and result["status"] == "classified",
                "results": results,
            },
        )
        if result["status"] != "classified":
            break
    return results


def main():
    """Prepare and run twelve synthetic conditions, offline unless explicitly selected."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--budget-store", type=Path)
    args = parser.parse_args()
    if args.live != (args.budget_store is not None):
        parser.error("--live and --budget-store must be supplied together")
    previous_umask = os.umask(0o077)
    try:
        args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
        runs = prepare(args.output)
        results = execute(
            args.executable.resolve(),
            args.output.resolve(),
            runs,
            args.budget_store.resolve() if args.live else None,
        )
    finally:
        os.umask(previous_umask)
    print(
        json.dumps(
            {
                "attempted_conditions": len(results),
                "last_status": results[-1]["status"],
                "live": args.live,
            }
        )
    )


if __name__ == "__main__":
    main()

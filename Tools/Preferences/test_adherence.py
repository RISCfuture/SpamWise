"""Check label freezing, expected actions, adherence scoring and two-pass recovery."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import adherence


def write_json(path, value):
    path.write_text(json.dumps(value))


class FreezeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.messages = self.root / "messages"
        self.messages.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def freeze(self, first, second, ids, output="labels.json"):
        write_json(
            self.messages / "manifest.json",
            {"messages": [{"id": message} for message in ids]},
        )
        paths = [self.root / "a.json", self.root / "b.json"]
        write_json(paths[0], {"labeler": "a", "labels": first})
        write_json(paths[1], {"labeler": "b", "labels": second})
        return adherence.freeze(
            self.messages, paths, self.root / "frozen" / output, "test-seed"
        )

    def test_keeps_only_agreed_labels_and_reports_kappa(self):
        frozen = self.freeze(
            {
                "m1": "promotion",
                "m2": "promotion",
                "m3": "newsletter",
                "m4": "newsletter",
            },
            {
                "m1": "promotion",
                "m2": "newsletter",
                "m3": "newsletter",
                "m4": "newsletter",
            },
            ["m1", "m2", "m3", "m4", "m5"],
        )
        self.assertEqual(set(frozen["labels"]), {"m1", "m3", "m4"})
        self.assertEqual(
            {row["id"]: row["reason"] for row in frozen["excluded"]},
            {"m2": "disagreement", "m5": "missing"},
        )
        stats = frozen["agreement"]
        self.assertEqual((stats["jointly_labeled"], stats["agreed"]), (4, 3))
        self.assertAlmostEqual(stats["raw"], 0.75)
        self.assertAlmostEqual(stats["chance"], 0.5)
        self.assertAlmostEqual(stats["kappa"], 0.5)

    def test_split_is_stratified_and_deterministic(self):
        categories = ["promotion"] * 10 + ["newsletter"] * 7 + ["personal"] * 3
        labels = {f"m{index:02d}": c for index, c in enumerate(categories)}
        first = self.freeze(labels, labels, list(labels), "first.json")
        second = self.freeze(labels, labels, list(labels), "second.json")
        self.assertEqual(first["splits"], second["splits"])
        self.assertEqual(
            first["category_counts"],
            {
                "promotion": {"dev": 5, "holdout": 5},
                "newsletter": {"dev": 4, "holdout": 3},
                "personal": {"dev": 1, "holdout": 2},
            },
        )
        self.assertEqual(
            sorted(first["splits"]["dev"] + first["splits"]["holdout"]), sorted(labels)
        )

    def test_refuses_to_overwrite_frozen_labels(self):
        labels = {"m1": "spam"}
        self.freeze(labels, labels, ["m1"])
        frozen = self.root / "frozen" / "labels.json"
        before = frozen.read_bytes()
        with self.assertRaises(FileExistsError):
            self.freeze({"m1": "scam"}, {"m1": "scam"}, ["m1"])
        self.assertEqual(frozen.read_bytes(), before)


class ExpectedActionTests(unittest.TestCase):
    def test_graymail_follows_profile_and_other_mail_stays_in_inbox(self):
        profiles = adherence.load_profiles()
        declutter, permissive = profiles["declutter"], profiles["permissive"]
        self.assertEqual(adherence.expected_action(declutter, "promotion"), "junk")
        self.assertEqual(adherence.expected_action(declutter, "newsletter"), "review")
        self.assertEqual(adherence.expected_action(declutter, "community"), "inbox")
        for category in ("personal", "transactional"):
            self.assertEqual(adherence.expected_action(declutter, category), "inbox")
        for category in adherence.THREATS:
            self.assertIsNone(adherence.expected_action(declutter, category))
        self.assertEqual(
            {adherence.expected_action(permissive, c) for c in adherence.GRAYMAIL},
            {"inbox"},
        )


PREFERENCES = {category: "keep" for category in adherence.GRAYMAIL} | {
    "promotion": "junk",
    "newsletter": "review",
}


def observation(label, category, category_confidence=None):
    row = {"label": label, "category": category, "path": "model"}
    if category_confidence is not None:
        row["categoryConfidence"] = category_confidence
    return row


class ScoringTests(unittest.TestCase):
    def test_summary_separates_adherence_junk_errors_and_spam_path(self):
        truth = {
            "p1": "promotion",
            "p2": "promotion",
            "n1": "newsletter",
            "t1": "transactional",
            "s1": "spam",
            "s2": "scam",
        }
        observations = {
            "p1": observation("junk", "promotion"),
            "p2": observation("review", "promotion"),
            "n1": observation("review", "newsletter"),
            "t1": observation("junk", "promotion"),
            "s1": observation("junk", "spam"),
            "s2": observation("inbox", "personal"),
        }
        labels = {m: {"category": c, "split": "dev"} for m, c in truth.items()}
        summary = adherence.summarize(
            adherence.items_for(observations, PREFERENCES, labels, "dev")
        )
        self.assertEqual(
            (summary["adherence"]["count"], summary["adherence"]["total"]), (2, 4)
        )
        self.assertEqual(summary["wrong_junk"]["ids"], ["t1"])
        self.assertEqual(summary["wrong_junk"]["total"], 2)
        self.assertEqual(summary["missed_junk"]["ids"], ["p2"])
        self.assertEqual(summary["review_burden"]["count"], 2)
        self.assertEqual(summary["category_accuracy"]["count"], 4)
        self.assertEqual(summary["spam_path"]["caught"]["count"], 1)
        self.assertEqual(summary["spam_path"]["inbox_ids"], ["s2"])
        self.assertEqual(summary["confusion"]["inbox"]["junk"], 1)

    def test_wilson_interval_bounds_zero_errors(self):
        self.assertAlmostEqual(adherence.wilson(0, 10)[1], 0.27754, places=4)
        low, high = adherence.wilson(2, 4)
        self.assertLess(low, 0.5)
        self.assertGreater(high, 0.5)
        self.assertIsNone(adherence.wilson(0, 0))

    def test_sweep_moves_only_junk_preferred_categories_by_category_confidence(self):
        rows = {
            "low": {
                **observation("junk", "promotion", 70),
                "modelLabel": "junk",
                "confidence": 94,
            },
            "confident": {
                **observation("review", "promotion", 70),
                "modelLabel": "junk",
                "confidence": 95,
            },
            "high": observation("review", "promotion", 90),
            "kept": observation("review", "newsletter", 99),
            "older": observation("junk", "promotion"),
        }
        swept = {
            message: adherence.swept_action(row, PREFERENCES, 80)
            for message, row in rows.items()
        }
        self.assertEqual(
            swept,
            {
                "low": "review",
                "confident": "junk",
                "high": "junk",
                "kept": "review",
                "older": "junk",
            },
        )
        self.assertEqual(adherence.swept_action(rows["low"], PREFERENCES, None), "junk")

    def test_recorded_preference_must_match_profile(self):
        rows = {"m1": {**observation("review", "promotion"), "preference": "review"}}
        with self.assertRaises(ValueError):
            adherence.check_preferences("tag", "profile", rows, PREFERENCES)


def report(misclassifications, provider_calls=0, cache_hits=0):
    return {
        "metrics": {
            "confusion": {"good": {"inbox": 3}},
            "unclassified": 0,
            "misclassifications": misclassifications,
        },
        "failedProviderCalls": 0,
        "providerCalls": provider_calls,
        "cacheHits": cache_hits,
    }


class RunTests(unittest.TestCase):
    def test_two_passes_recover_every_result(self):
        review = {"file": "good/m2.eml", "label": "review", "category": "survey"}
        inbox_pass = report(
            [review, {"file": "good/m3.eml", "label": "junk", "category": "spam"}]
        )
        junk_pass = report(
            [
                {"file": "junk/m1.eml", "label": "inbox", "category": "personal"},
                {**review, "file": "junk/m2.eml"},
            ]
        )
        merged = adherence.merge_passes(inbox_pass, junk_pass, {"m1", "m2", "m3"})
        self.assertEqual(
            {message: row["label"] for message, row in merged.items()},
            {"m1": "inbox", "m2": "review", "m3": "junk"},
        )
        with self.assertRaises(ValueError):
            adherence.merge_passes(inbox_pass, junk_pass, {"m1", "m2", "m3", "m4"})
        junk_pass["metrics"]["misclassifications"][1]["category"] = "promotion"
        with self.assertRaises(ValueError):
            adherence.merge_passes(inbox_pass, junk_pass, {"m1", "m2", "m3"})

    def test_listed_results_need_one_pass_and_keep_unclassified_messages(self):
        listed = {
            **report([]),
            "failedProviderCalls": 1,
            "observations": [
                {"file": "good/m1.eml", "label": "inbox", "path": "model"},
                {"file": "good/m2.eml", "label": None, "path": "error"},
            ],
            "model": "mock",
            "strength": "balanced",
            "newUsage": {},
        }
        listed["metrics"]["unclassified"] = 1
        listed["metrics"]["confusion"] = {"good": {"inbox": 1, "unclassified": 1}}

        def evaluate(command, timeout, stderr_path):
            write_json(Path(command[command.index("--output") + 1]), listed)
            return 0

        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "profile"
            config = adherence.RunConfig(executable=Path("/unused"))
            with patch.object(adherence, "invoke", side_effect=evaluate) as runner:
                result = adherence.run_profile(
                    config, directory, "p", PREFERENCES, {"m1": b"", "m2": b""}
                )
            runner.assert_called_once()
            self.assertEqual(result["status"], "completed")
            self.assertEqual(result["unclassified"], ["m2"])
            observations = json.loads((directory / "observations.json").read_text())
            self.assertEqual(
                adherence.effective(observations["observations"]["m2"]), "unclassified"
            )

    def test_live_replay_pass_cannot_spend(self):
        config = adherence.RunConfig(
            executable=Path("/unused/spamwise-eval"),
            live=True,
            budget_store=Path("/private/budget.store"),
            budget_limit=20.0,
        )
        command = adherence.pass_command(
            config,
            Path("corpus"),
            Path("state.json"),
            Path("cache"),
            Path("report.json"),
            Path("replay.store"),
        )
        self.assertEqual(
            command[command.index("--budget-store") + 1 :][:3],
            ["replay.store", "--budget-limit", "0.0"],
        )
        self.assertEqual(
            adherence.pass_problem(report([], provider_calls=1, cache_hits=2), 3, True),
            "replay_not_cached",
        )
        self.assertIsNone(adherence.pass_problem(report([], cache_hits=3), 3, True))

    def test_first_failure_stops_later_profiles(self):
        with tempfile.TemporaryDirectory() as temporary:
            tag = Path(temporary)
            config = adherence.RunConfig(
                executable=Path("/unused"),
                live=True,
                budget_store=Path("/private/budget.store"),
                budget_limit=20.0,
            )
            with patch.object(
                adherence, "run_profile", return_value={"status": "inbox_pass_exit_1"}
            ) as runner:
                results = adherence.execute(
                    config, tag, adherence.load_profiles(), {"m1": b""}, {"tag": "t"}
                )
            runner.assert_called_once()
            self.assertEqual(len(results), 1)
            summary = json.loads((tag / "run.json").read_text())
            self.assertFalse(summary["completed"])
            self.assertAlmostEqual(summary["maximum_reservation_usd"], 0.008)


class MessageSetTests(unittest.TestCase):
    def test_authored_messages_are_reproducible_and_parse(self):
        first = adherence.authored_messages("test-seed")
        second = adherence.authored_messages("test-seed")
        self.assertEqual([e["raw"] for e in first], [e["raw"] for e in second])
        for entry in first:
            adherence.prepare.message_text(entry["raw"])


if __name__ == "__main__":
    unittest.main()

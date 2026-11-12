"""Behavior checks for joining monitoring records with later human observations."""

import unittest

import efficacy


def record(identifier, message, **values):
    return {
        "id": identifier,
        "message_hash": message,
        "timestamp": "2026-10-28T00:00:00+00:00",
        "path": "model",
        "decision_label": "review",
        "outcome": "applied",
        "action": "orangeFlag",
        "settled": True,
        **values,
    }


def snapshot(records, captured="2026-11-01T00:00:00+00:00"):
    return {"captured_at": captured, "records": records}


class ReconciliationTests(unittest.TestCase):
    def test_joins_later_feedback_once_without_treating_cleanup_as_training(self):
        junk = record("j", "wanted", decision_label="junk", action="moveToJunk")
        review = record("r", "unwanted")
        observations = [
            {
                "event_id": "one",
                "observed_at": "2026-11-02",
                "message_hash": "wanted",
                "kind": "confirmed_spamwise_false_positive",
                "user_label": "inbox",
                "automatic_junk_record_ids": ["j"],
            },
            {
                "event_id": "two",
                "observed_at": "2026-11-02",
                "message_hash": "unwanted",
                "kind": "user_confirmed_unwanted_in_inbox",
                "user_label": "junk",
            },
            {
                "event_id": "three",
                "observed_at": "2026-11-02",
                "message_hash": "unwanted",
                "kind": "user_requested_manual_trash_move",
                "user_label": "junk",
            },
            {
                "event_id": "four",
                "observed_at": "2026-11-02",
                "message_hash": "external",
                "kind": "wanted_mail_in_junk",
                "user_label": "inbox",
            },
        ]
        result = efficacy.reconcile([snapshot([junk, review])] * 2, observations * 2)
        self.assertEqual(result["confirmed_false_positives_total"], 1)
        self.assertEqual(result["reviewed_unwanted"]["count"], 1)
        self.assertEqual(result["reviewed_unwanted"]["first_labels"], {"review": 1})
        self.assertEqual(result["feedback_without_training_count"], 2)
        self.assertEqual(result["unlinked_labeled_message_count"], 1)
        self.assertEqual(result["corrections_total"], 0)

    def test_latest_snapshot_and_standing_label_win_over_old_corrections(self):
        junk = record(
            "j", "m", decision_label="junk", action="moveToJunk", outcome="requested"
        )
        correction = record("c", "m", path="correction", corrected_label="junk")
        newer = [
            dict(junk, outcome="applied"),
            dict(correction, correction_undone=True),
        ]
        observations = [
            {
                "event_id": "e",
                "observed_at": "2026-11-03",
                "message_hash": "m",
                "kind": "confirmed_spamwise_false_positive",
                "user_label": "inbox",
                "automatic_junk_record_ids": ["j"],
            }
        ]
        result = efficacy.reconcile(
            [snapshot(newer, "2026-11-02"), snapshot([junk, correction])], observations
        )
        self.assertEqual(result["reviewed_wanted"]["count"], 1)
        self.assertEqual(result["reviewed_unwanted"]["count"], 0)
        self.assertEqual(result["confirmed_false_positives_total"], 1)
        self.assertEqual(result["feedback_without_training_count"], 1)

    def test_never_sent_metadata_controls_dispatch_classification(self):
        rows = [
            record(
                "a",
                "a",
                outcome="failed",
                never_sent=True,
                action_error="A requested change may still happen.",
            ),
            record("b", "b", outcome="failed", never_sent=False),
        ]
        result = efficacy.reconcile([snapshot(rows)], [])
        self.assertEqual(result["integration"]["failed_before_dispatch"], 1)
        self.assertEqual(result["integration"]["failed_after_possible_dispatch"], 1)
        self.assertEqual(
            result["integration"]["contradictory_timeout_record_ids"], ["a"]
        )


class CalibrationTests(unittest.TestCase):
    def test_replays_only_labeled_live_model_rows_with_both_policy_safeguards(self):
        rows = [
            record(
                "protected",
                "protected",
                category="productUpdate",
                category_confidence=99,
                model_label="inbox",
                confidence=99,
            ),
            record(
                "confident",
                "confident",
                category="productUpdate",
                category_confidence=70,
                model_label="junk",
                confidence=96,
            ),
            record(
                "unwanted",
                "unwanted",
                category="productUpdate",
                category_confidence=88,
                model_label="junk",
                confidence=90,
            ),
        ]
        rows += [
            dict(rows[0], id="early", message_hash="early", timestamp="2026-10-01"),
            dict(rows[0], id="rule", message_hash="rule", path="gate"),
            dict(rows[0], id="unlabeled", message_hash="unlabeled"),
        ]
        observations = [
            {
                "event_id": row["id"],
                "observed_at": "2026-11-02",
                "message_hash": row["message_hash"],
                "kind": "human_label",
                "user_label": "junk" if row["id"] == "unwanted" else "inbox",
            }
            for row in rows
            if row["id"] != "unlabeled"
        ]
        result = efficacy.calibration(
            [snapshot(rows)],
            observations,
            {"categoryPreferences": {"productUpdate": "junk"}, "strength": "balanced"},
            "2026-10-27",
        )
        category = result["categories"]["productUpdate"]
        self.assertEqual((category["wanted"], category["unwanted"]), (2, 1))
        curve = {point["threshold"]: point for point in category["curve"]}
        self.assertEqual(curve[85]["unwanted_to_junk"], 1)
        self.assertEqual(curve[90]["unwanted_to_junk"], 0)
        self.assertEqual(curve[60]["wanted_to_junk"], 1)
        self.assertEqual(curve[100]["wanted_to_junk"], 1)
        self.assertFalse(result["validated"])
        self.assertIsNone(result["selected_thresholds"])


if __name__ == "__main__":
    unittest.main()

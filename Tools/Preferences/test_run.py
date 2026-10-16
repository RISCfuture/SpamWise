"""Check paired input isolation and stop-on-failure spending behavior."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import run


class PreferenceProbeTests(unittest.TestCase):
    def test_contexts_change_preferences_without_changing_message_or_adding_gates(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            runs = run.prepare(output)
            self.assertEqual(len(runs), 12)
            for language in ("en", "es", "fr"):
                paired = [row for row in runs if row["language"] == language]
                self.assertEqual(len({row["message_sha256"] for row in paired}), 1)
                self.assertEqual(len({row["state_sha256"] for row in paired}), 4)
                for row in paired:
                    state = json.loads((output / row["id"] / "state.json").read_text())
                    self.assertEqual(state["rules"], [])
                    self.assertEqual(state["histories"], {})
                    self.assertNotIn("synthetic_target", state)
                    self.assertEqual(
                        len(state["corrections"]),
                        0 if row["condition"] == "policy_only" else 2,
                    )
                    self.assertTrue(
                        all(
                            example["sender"] != "newsletter@garden-notes.example"
                            for example in state["corrections"]
                        )
                    )

    def test_first_failure_stops_all_later_calls(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            runs = run.prepare(output)
            with patch.object(
                run, "evaluate", return_value={"status": "classification_failed"}
            ) as evaluator:
                results = run.execute(Path("/unused"), output, runs, True)
            self.assertEqual(len(results), 1)
            evaluator.assert_called_once()
            report = json.loads((output / "results.json").read_text())
            self.assertFalse(report["completed"])
            self.assertEqual(report["maximum_reservation_usd"], 0.10)


if __name__ == "__main__":
    unittest.main()

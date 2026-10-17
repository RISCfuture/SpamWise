"""Behavioral checks for label isolation, leakage controls and bounded imports."""

import base64
import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import audit
import prepare
import screen


def record(text, source, labels, synthetic=False, body=None):
    """Create source evidence without inventing missing objective labels."""
    return {
        "id": prepare.digest(prepare.normalized(text)),
        "text": text,
        "template": prepare.template_key(body or text),
        "provenance": [
            {
                "source": source,
                "position": "1",
                "labels": labels,
                "synthetic": synthetic,
            }
        ],
    }


class CorpusPreparationTests(unittest.TestCase):
    def test_audit_rejects_changed_labels_indices_and_frozen_membership(self):
        rows = prepare.group_records(
            [record("source spam", "source", {"spam": True})], "seed"
        )
        sources = [
            {
                "id": "source",
                "labels": {"spam": True},
                "synthetic": False,
                "expected_records": 1,
            }
        ]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            manifest = prepare.write_records(path, rows, [], sources, "seed")
            self.assertTrue(
                audit.verify_metadata(rows, manifest, path)[
                    "source_labels_and_indices_verified"
                ]
            )
            self.assertEqual(audit.compare_frozen(rows, rows)["preserved_records"], 1)
            for invalid_kind in ("synthetic", "mixed"):
                with self.assertRaisesRegex(ValueError, "source_kind_mismatch"):
                    audit.verify_metadata(
                        [{**rows[0], "kind": invalid_kind}], manifest, path
                    )
            changed = [
                {
                    **rows[0],
                    "split": "holdout" if rows[0]["split"] != "holdout" else "train",
                }
            ]
            with self.assertRaisesRegex(ValueError, "frozen_membership_changed"):
                audit.compare_frozen(changed, rows)
            rows[0]["provenance"][0]["labels"] = {"spam": False}
            with self.assertRaisesRegex(ValueError, "source_label_mismatch"):
                audit.verify_metadata(rows, manifest, path)
            rows[0]["provenance"][0]["labels"] = {"spam": True}
            next((path / "objectives").rglob("*.json")).write_text("[]")
            with self.assertRaisesRegex(ValueError, "objective_membership_mismatch"):
                audit.verify_metadata(rows, manifest, path)

    def test_campaign_audit_finds_split_overlap_without_examining_holdout_text(self):
        body = " ".join(f"word{index}" for index in range(100))
        rows = [
            {
                "id": "a",
                "group": "a",
                "provenance": [{"source": "fixture"}],
                "text": body,
                "split": "train",
                "kind": "real",
            },
            {
                "id": "b",
                "group": "b",
                "provenance": [{"source": "fixture"}],
                "text": body + " changed",
                "split": "validation",
                "kind": "real",
            },
            {"id": "c", "group": "c", "split": "holdout", "kind": "real"},
            {"id": "d", "group": "d", "split": "train", "kind": "synthetic"},
        ]
        summary, pairs = audit.development_campaigns(rows)
        self.assertEqual(summary["selected_real_non_holdout_records"], 2)
        self.assertEqual(summary["cross_train_validation_candidate_pairs"], 1)
        self.assertEqual(pairs[0]["ids"], ["a", "b"])
        self.assertFalse(summary["holdout_content_examined"])
        counts, partition = audit.derived_development_partition(rows, pairs)
        self.assertEqual(counts["train_records_moved_to_validation"], 1)
        self.assertEqual({row["split"] for row in partition}, {"validation"})
        self.assertEqual({row["id"] for row in partition}, {"a", "b"})
        self.assertEqual(rows[0]["split"], "train")
        self.assertEqual(counts["remaining_lower_overlap_cross_split_pairs"], 0)
        lower_overlap = [{**pairs[0], "jaccard": 0.9}]
        counts, _ = audit.derived_development_partition(rows, lower_overlap)
        self.assertEqual(counts["train_records_moved_to_validation"], 0)
        self.assertEqual(counts["remaining_lower_overlap_cross_split_pairs"], 1)
        estimates = [
            {"id": "a", "language": "en", "confidence": 0.99},
            {"id": "b", "language": "fr", "confidence": 0.95},
        ]
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / "language-tool"
            executable.write_bytes(b"fixture")
            with patch(
                "audit.subprocess.run",
                return_value=SimpleNamespace(stdout=json.dumps(estimates)),
            ) as run:
                counts, _ = audit.inferred_development_languages(rows, executable)
                self.assertEqual(counts["counts"], {"en": 1, "fr": 1})
                self.assertEqual(
                    {row["id"] for row in json.loads(run.call_args.kwargs["input"])},
                    {"a", "b"},
                )
                run.return_value.stdout = json.dumps(estimates[:1])
                with self.assertRaisesRegex(ValueError, "language_membership"):
                    audit.inferred_development_languages(rows, executable)
        rows[1]["group"] = "a"
        self.assertEqual(audit.development_campaigns(rows)[1], [])

    def test_screen_excludes_holdout_and_never_treats_unknown_as_negative(self):
        rows = prepare.group_records(
            [
                record("real positive", "phish", {"phishing": True}),
                record("reserved", "spam", {"spam": True}),
            ],
            "seed",
        )
        for row in rows:
            row["split"] = "validation" if row["text"] == "real positive" else "holdout"
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            prepare.write_records(path, rows, [], [], "seed")
            selected, _ = screen.development_records(path)
            self.assertEqual([row["text"] for row in selected], ["real positive"])
            report = screen.summarize(
                [
                    {
                        **selected[0],
                        "scores": {"legitimate": 0.1, "spam": 0.2, "fraud": 0.7},
                        "prediction": "fraud",
                        "inference_ms": 3,
                        "truncated": False,
                    }
                ]
            )
            self.assertEqual(set(report["cohorts"]), {"phishing"})
            cohort = report["cohorts"]["phishing"]
            self.assertTrue(cohort["output_is_task_proxy"])
            self.assertEqual(cohort["threshold_hits"]["0.5"], 1)
            self.assertEqual(cohort["threshold_hits"]["0.9"], 0)
            self.assertIsNone(cohort["false_positive_rate"])
            negatives = [
                {
                    "labels": {"spam": False},
                    "scores": {"legitimate": 0.1, "spam": 0.2, "fraud": 0.7},
                },
                {
                    "labels": {"spam": False},
                    "scores": {"legitimate": 0.1, "spam": 0.8, "fraud": 0.1},
                },
                {
                    "labels": {"spam": None},
                    "scores": {"legitimate": 0.0, "spam": 1.0, "fraud": 0.0},
                },
            ]
            negative_summary = screen.summarize(
                [
                    {
                        **row,
                        "group": "fixture",
                        "prediction": max(row["scores"], key=row["scores"].get),
                        "inference_ms": 1,
                        "truncated": False,
                    }
                    for row in negatives
                ]
            )
            self.assertNotIn("phishing", negative_summary["cohorts"])
            negative_report = negative_summary["cohorts"]["spam"]
            self.assertEqual(negative_report["negative_records"], 2)
            self.assertEqual(negative_report["negative_template_groups"], 1)
            self.assertEqual(negative_report["false_positive_rate"], 0.5)
            self.assertEqual(negative_report["spam_or_fraud_at_0.5_negative"], 2)
            self.assertEqual(negative_report["threshold_false_positives"]["0.9"], 0)
            phishing_rows = [
                {
                    **selected[0],
                    "scores": {"ham": 0.1, "spam": 0.2, "phishing": 0.7},
                    "prediction": "phishing",
                    "inference_ms": 3,
                    "truncated": False,
                },
                {
                    "labels": {"spam": False},
                    "group": "negative",
                    "scores": {"ham": 0.1, "spam": 0.1, "phishing": 0.8},
                    "prediction": "phishing",
                    "inference_ms": 3,
                    "truncated": False,
                },
            ]
            direct = screen.summarize(phishing_rows, "opentextshield")["cohorts"]
            self.assertFalse(direct["phishing"]["output_is_task_proxy"])
            self.assertEqual(direct["phishing"]["threshold_hits"]["0.5"], 1)
            self.assertEqual(direct["phishing"]["negative_records"], 0)
            self.assertIsNone(direct["phishing"]["false_positive_rate"])
            self.assertEqual(direct["spam"]["false_positive_rate"], 0)
            self.assertEqual(direct["spam"]["spam_or_phishing_at_0.5_negative"], 1)
            config = SimpleNamespace(
                id2label={0: "ham", 1: "spam", 2: "phishing"},
                label2id={"ham": 0, "spam": 1, "phishing": 2},
            )
            self.assertEqual(
                screen.validate_labels(config, "opentextshield"),
                ("ham", "spam", "phishing"),
            )
            with self.assertRaisesRegex(ValueError, "model_labels"):
                screen.validate_labels(config, "horizon")
            config.id2label[1], config.id2label[2] = "phishing", "spam"
            with self.assertRaisesRegex(ValueError, "model_labels"):
                screen.validate_labels(config, "opentextshield")
            with (path / "records.jsonl").open("a") as stream:
                stream.write("{}\n")
            with self.assertRaisesRegex(ValueError, "corpus_hash"):
                screen.development_records(path)

    def test_source_labels_stay_independent_and_conflicting_duplicates_abstain(self):
        rows = [
            record("duplicate text", "spam-source", {"spam": True}),
            record("DUPLICATE   TEXT", "phish-source", {"phishing": True}),
            record("duplicate text", "reviewer", {"spam": False}),
            record("marketing language", "synthetic", {}, True),
        ]
        grouped = prepare.group_records(rows, "seed")
        duplicate = next(row for row in grouped if len(row["provenance"]) == 3)
        self.assertIsNone(duplicate["labels"]["spam"])
        self.assertTrue(duplicate["labels"]["phishing"])
        self.assertIsNone(duplicate["labels"]["spearphishing"])
        self.assertEqual(duplicate["conflicts"], ["spam"])
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            report = prepare.write_records(path, grouped, [], [], "seed")
            self.assertEqual(len(report["objective_counts"]), 1)
            self.assertTrue(
                next(iter(report["objective_counts"])).startswith("phishing/real/")
            )
            self.assertFalse((path / "objectives" / "spam").exists())

    def test_template_variants_and_transitive_duplicate_bridges_share_one_split(self):
        template = "Please review the attached project schedule and meeting agenda before responding to ticket {} at https://example.test/{}"
        first = record(
            "Subject one\n" + template.format(17, "alpha"),
            "a",
            {"spam": True},
            body=template.format(17, "alpha"),
        )
        second = record(
            "Subject two\n" + template.format(23, "beta"),
            "b",
            {"phishing": True},
            body=template.format(23, "beta"),
        )
        bridge = {**second, "template": "other-template"}
        third = {
            **record("Different representation", "c", {}),
            "template": "other-template",
        }
        grouped = prepare.group_records([first, second, bridge, third], "seed")
        self.assertEqual(len({row["group"] for row in grouped}), 1)
        self.assertEqual(len({row["split"] for row in grouped}), 1)
        reversed_rows = prepare.group_records([third, bridge, second, first], "seed")
        self.assertEqual(
            [(row["id"], row["split"]) for row in grouped],
            [(row["id"], row["split"]) for row in reversed_rows],
        )
        bridge["provenance"] = [{**bridge["provenance"][0], "usage": "evaluationOnly"}]
        restricted = prepare.group_records([first, second, bridge, third], "seed")
        self.assertEqual({row["split"] for row in restricted}, {"validation"})

    def test_mime_decodes_text_without_attachment_or_hidden_html(self):
        raw = (
            b"Subject: =?utf-8?b?Qm9uam91cg==?=\r\n"
            b"MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=x\r\n\r\n"
            b"--x\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            + base64.b64encode(
                "<head>hidden</head><p>café</p><script>fetch('secret')</script>".encode()
            )
            + b"\r\n--x\r\nContent-Type: text/plain\r\nContent-Disposition: attachment; filename=test.txt\r\n\r\nattachment payload\r\n--x--\r\n"
        )
        text, body = prepare.message_text(raw)
        self.assertEqual(body, "café")
        self.assertIn("Subject: Bonjour", text)
        with self.assertRaisesRegex(ValueError, "text_encoding"):
            prepare.message_text(
                b"Content-Type: text/plain; charset=unknown-charset\n\nbody"
            )
        with self.assertRaisesRegex(ValueError, "message_size"):
            prepare.message_text(b"x" * (prepare.MAX_MESSAGE + 1))

    def test_archive_never_extracts_paths_and_rejects_special_members(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "messages.tar"
            with tarfile.open(path, "w") as archive:
                member = tarfile.TarInfo("../../escape.eml")
                payload = b"Subject: safe\n\nmessage"
                member.size = len(payload)
                archive.addfile(member, io.BytesIO(payload))
                metadata = tarfile.TarInfo("hard_ham/cmds")
                metadata.size = len(payload)
                archive.addfile(metadata, io.BytesIO(payload))
            source = {
                "format": "archive",
                "excluded_archive_members": ["hard_ham/cmds"],
            }
            self.assertEqual(
                list(prepare.source_messages(source, path)), [("1", payload)]
            )
            self.assertEqual(len(list(prepare.archive_messages(path))), 2)
            self.assertEqual(
                sorted(item.name for item in Path(temporary).iterdir()),
                ["messages.tar"],
            )
            with tarfile.open(path, "w") as archive:
                member = tarfile.TarInfo("link")
                member.type = tarfile.SYMTYPE
                member.linkname = "/private/secret"
                archive.addfile(member)
            with self.assertRaisesRegex(ValueError, "archive_special_file"):
                list(prepare.archive_messages(path, excluded_members=("link",)))

    def test_pinned_source_pipeline_is_private_and_refuses_changed_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            raw = b'0\n"synthetic marketing text"\n"synthetic marketing text"\n'
            (path / "source.csv").write_bytes(raw)
            source = {
                "id": "synthetic",
                "filename": "source.csv",
                "format": "csv",
                "sha256": prepare.digest(raw),
                "labels": {},
                "synthetic": True,
                "expected_records": 2,
            }
            manifest = path / "sources.json"
            manifest.write_text(json.dumps([source]))
            output = path / "prepared"
            report = prepare.prepare(path, output, manifest, "seed")
            self.assertEqual(report["duplicate_text_records"], 1)
            self.assertEqual(report["objective_counts"], {})
            self.assertEqual(output.stat().st_mode & 0o777, 0o700)
            self.assertEqual((output / "records.jsonl").stat().st_mode & 0o777, 0o600)
            with self.assertRaisesRegex(ValueError, "output_exists"):
                prepare.prepare(path, output, manifest, "seed")
            (path / "source.csv").write_bytes(raw + b"changed\n")
            with self.assertRaisesRegex(ValueError, "source_hash"):
                prepare.prepare(path, path / "second", manifest, "seed")
            self.assertFalse((path / "second").exists())


if __name__ == "__main__":
    unittest.main()

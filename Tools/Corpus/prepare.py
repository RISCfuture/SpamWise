"""Prepare private, source-attributed email corpora without inferring missing labels."""

import argparse
import csv
import hashlib
import json
import mailbox
import os
import re
import subprocess
import tarfile
import tempfile
import threading
import unicodedata
from collections import Counter, defaultdict
from email import policy
from email.parser import BytesParser
from html.parser import HTMLParser
from pathlib import Path

MAX_MESSAGE = 2_000_000
MAX_TEXT = 100_000
MAX_ARCHIVE = 512_000_000
MAX_RECORDS = 200_000
TASKS = ("spam", "phishing", "spearphishing", "fraud", "malware", "graymail")
SCHEMA = "spamwise-corpus-v1"


def digest(value):
    """Return a stable content identity for bytes or UTF-8 text."""
    return hashlib.sha256(
        value.encode() if isinstance(value, str) else value
    ).hexdigest()


class PlainHTML(HTMLParser):
    """Collect visible lexical text without executing markup or fetching resources."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.hidden = 0
        self.chunks = []

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style", "head"}:
            self.hidden += 1
        elif tag in {"br", "p", "div", "li", "tr"}:
            self.chunks.append("\n")

    def handle_endtag(self, tag):
        if tag in {"script", "style", "head"}:
            self.hidden = max(0, self.hidden - 1)
        elif tag in {"p", "div", "li", "tr"}:
            self.chunks.append("\n")

    def handle_data(self, data):
        if not self.hidden:
            self.chunks.append(data)


def message_text(raw):
    """Extract bounded corpus text with the standard library; never open attachments."""
    if len(raw) > MAX_MESSAGE:
        raise ValueError("message_size")
    message = BytesParser(policy=policy.default).parsebytes(raw)
    chunks = []
    pending = [(message, 0)]
    parts = 0
    while pending:
        part, depth = pending.pop()
        parts += 1
        if depth > 12 or parts > 128:
            raise ValueError("mime_structure")
        if part.get_content_disposition() == "attachment" or part.get_filename():
            continue
        if part.is_multipart():
            pending.extend((child, depth + 1) for child in reversed(part.get_payload()))
            continue
        if part.get_content_type() not in {"text/plain", "text/html"}:
            continue
        payload = part.get_payload(decode=True)
        if payload is None:
            raise ValueError("missing_payload")
        try:
            text = payload.decode(
                part.get_content_charset() or "ascii", errors="strict"
            )
        except (LookupError, UnicodeError) as error:
            raise ValueError("text_encoding") from error
        if part.defects:
            raise ValueError("mime_defect")
        if part.get_content_type() == "text/html":
            parser = PlainHTML()
            parser.feed(text)
            text = "".join(parser.chunks)
        if text.strip() and text not in chunks:
            chunks.append(text)
        if sum(map(len, chunks)) > MAX_TEXT:
            raise ValueError("text_size")
    if message.defects:
        raise ValueError("mime_defect")
    body = "\n\n".join(chunks).strip()
    if not body:
        raise ValueError("empty_text")
    subject = str(message.get("Subject", ""))
    text = f"Subject: {subject}\n\n{body}" if subject else body
    if len(text) > MAX_TEXT:
        raise ValueError("text_size")
    return text, body


def normalized(text):
    """Normalize Unicode, case and whitespace for conservative duplicate detection."""
    return " ".join(unicodedata.normalize("NFKC", text).casefold().split())


def template_key(body):
    """Group identical templates after masking URLs, addresses and numeric runs."""
    text = normalized(body)
    text = re.sub(r"https?://\S+|www\.\S+", " <url> ", text)
    text = re.sub(r"[^\s@]+@[^\s@]+", " <address> ", text)
    text = re.sub(r"\d+", "#", text)
    text = " ".join(text.split())
    return digest(text) if len(text) >= 80 else None


def archive_messages(path, excluded_members=()):
    """Stream archive members through libarchive without extracting member paths."""
    with tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(
            ["/usr/bin/bsdtar", "-cf", "-", f"@{path}"],
            stdout=subprocess.PIPE,
            stderr=errors,
        )
        timer = threading.Timer(120, process.kill)
        timer.start()
        try:
            total = 0
            count = 0
            with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
                for member in archive:
                    if member.isdir():
                        continue
                    count += 1
                    total += member.size
                    if count > MAX_RECORDS or total > MAX_ARCHIVE:
                        raise ValueError("archive_budget")
                    if not member.isfile():
                        raise ValueError("archive_special_file")
                    if member.name in excluded_members:
                        continue
                    with archive.extractfile(member) as stream:
                        yield str(count), stream.read(MAX_MESSAGE + 1)
            if process.wait() != 0:
                raise ValueError("archive_decode")
        finally:
            timer.cancel()
            if process.poll() is None:
                process.kill()
            process.wait()
            process.stdout.close()


def source_messages(source, path):
    """Yield source-local positions and bytes from a pinned supported format."""
    match source["format"]:
        case "archive":
            yield from archive_messages(
                path, source.get("excluded_archive_members", ())
            )
        case "mbox":
            box = mailbox.mbox(path, create=False)
            try:
                for index, key in enumerate(box.iterkeys(), 1):
                    with box.get_file(key, from_=False) as stream:
                        yield str(index), stream.read(MAX_MESSAGE + 1)
            finally:
                box.close()
        case "csv":
            csv.field_size_limit(MAX_MESSAGE)
            with path.open(newline="", encoding="utf-8") as stream:
                reader = csv.DictReader(stream)
                if reader.fieldnames != ["0"]:
                    raise ValueError("csv_schema")
                for index, row in enumerate(reader, 1):
                    if set(row) != {"0"} or row["0"] is None:
                        raise ValueError("csv_row")
                    yield str(index), row["0"].encode()
        case _:
            raise ValueError("source_format")


def ingest(source, path):
    """Preserve every source label and quarantine uninterpretable records."""
    records, rejected = [], []
    count = 0
    for position, raw in source_messages(source, path):
        count += 1
        if count > MAX_RECORDS:
            raise ValueError("source_record_budget")
        origin = {
            "source": source["id"],
            "position": position,
            "raw_sha256": digest(raw) if len(raw) <= MAX_MESSAGE else None,
            "labels": source["labels"],
            "synthetic": source["synthetic"],
            "usage": source.get("usage", "training"),
        }
        try:
            if len(raw) > MAX_MESSAGE:
                raise ValueError("message_size")
            if source["format"] == "csv":
                text = body = raw.decode("utf-8").strip()
                if not text or len(text) > MAX_TEXT:
                    raise ValueError("text_size_or_empty")
            else:
                text, body = message_text(raw)
        except (ValueError, UnicodeError, RecursionError) as error:
            reason = (
                str(error) if isinstance(error, ValueError) else type(error).__name__
            )
            rejected.append(
                {"source": source["id"], "position": position, "reason": reason}
            )
            continue
        records.append(
            {
                "id": digest(normalized(text)),
                "text": text,
                "template": template_key(body),
                "provenance": [origin],
            }
        )
    if count != source["expected_records"]:
        raise ValueError(f"source_count:{source['id']}")
    return records, rejected


def group_records(records, seed):
    """Deduplicate text, merge label evidence and keep template groups in one split."""
    unique = {}
    parents = {}

    def root(key):
        parents.setdefault(key, key)
        while parents[key] != key:
            parents[key] = parents[parents[key]]
            key = parents[key]
        return key

    for record in records:
        identity = record["id"]
        left, right = root(identity), root(record["template"] or identity)
        parents[max(left, right)] = min(left, right)
        if identity in unique:
            unique[identity]["provenance"].extend(record["provenance"])
        else:
            unique[identity] = {**record, "provenance": list(record["provenance"])}
    for record in unique.values():
        record.pop("template")
        record["group"] = root(record["id"])
        record["provenance"].sort(
            key=lambda origin: (origin["source"], origin["position"])
        )
        fraction = int(digest(f"{SCHEMA}:{seed}:{record['group']}")[:8], 16) / 2**32
        record["split"] = (
            "train"
            if fraction < 0.7
            else "validation"
            if fraction < 0.85
            else "holdout"
        )
        record["labels"] = {}
        record["conflicts"] = []
        for task in TASKS:
            votes = {
                origin["labels"][task]
                for origin in record["provenance"]
                if task in origin["labels"] and origin["labels"][task] is not None
            }
            record["labels"][task] = next(iter(votes)) if len(votes) == 1 else None
            if len(votes) > 1:
                record["conflicts"].append(task)
        kinds = {origin["synthetic"] for origin in record["provenance"]}
        record["kind"] = (
            "mixed" if len(kinds) > 1 else "synthetic" if True in kinds else "real"
        )
        record["language"] = "unknown"
        record["reviewed"] = False
    evaluation_groups = {
        record["group"]
        for record in unique.values()
        if any(
            origin.get("usage") == "evaluationOnly" for origin in record["provenance"]
        )
    }
    for record in unique.values():
        if record["group"] in evaluation_groups:
            record["split"] = "validation"
    return sorted(unique.values(), key=lambda row: row["id"])


def write_json(path, value):
    """Write a UTF-8 JSON artifact using the caller's file-creation permissions."""
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def write_records(directory, records, rejected, sources, seed):
    """Write private text records, objective-specific indices and aggregate audit counts."""
    with (directory / "records.jsonl").open("w") as stream:
        for record in records:
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")
    with (directory / "records.jsonl").open("rb") as stream:
        records_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    write_json(directory / "quarantine.json", rejected)
    counts = Counter()
    indices = defaultdict(list)
    groups = defaultdict(set)
    for record in records:
        groups[record["group"]].add(record["id"])
        counts[f"{record['kind']}/{record['split']}"] += 1
        for task, label in record["labels"].items():
            if label is not None:
                key = f"{task}/{record['kind']}/{record['split']}"
                indices[key].append({"id": record["id"], "label": label})
    for key, index in indices.items():
        path = directory / "objectives" / f"{key}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        write_json(path, index)
    report = {
        "complete": True,
        "schema": SCHEMA,
        "records_sha256": records_hash,
        "seed": seed,
        "sources": sources,
        "input_records": sum(source["expected_records"] for source in sources),
        "quarantined": len(rejected),
        "quarantine_reasons": dict(Counter(row["reason"] for row in rejected)),
        "unique_text_records": len(records),
        "duplicate_text_records": sum(len(row["provenance"]) - 1 for row in records),
        "template_groups": len(groups),
        "multi_record_template_groups": sum(len(ids) > 1 for ids in groups.values()),
        "largest_template_group": max(map(len, groups.values()), default=0),
        "label_conflicts": sum(bool(row["conflicts"]) for row in records),
        "split_counts": dict(sorted(counts.items())),
        "objective_counts": {key: len(value) for key, value in sorted(indices.items())},
        "limitations": [
            "Source labels are not independent human review; unspecified labels remain unknown.",
            "Template hashing only detects some campaigns; this is not a leakage-free benchmark.",
            "Hash splits are provisional, not temporal; do not tune on reserved holdout records.",
            "Source negative labels do not establish independent threat review; languages and pretrained exposure remain unaudited.",
            "Corpus extraction uses Python email, not the app MIME parser; quarantine is separate.",
        ],
    }
    write_json(directory / "manifest.json", report)
    return report


def prepare(input_directory, output_directory, source_file, seed):
    """Verify sources and publish a manifest only after writing a fresh private corpus."""
    if output_directory.exists() or output_directory.is_symlink():
        raise ValueError("output_exists")
    sources = json.loads(source_file.read_text())
    identities = set()
    for source in sources:
        if (
            source["id"] in identities
            or Path(source["filename"]).name != source["filename"]
        ):
            raise ValueError("source_identity")
        identities.add(source["id"])
        if source.get("usage", "training") not in {"training", "evaluationOnly"}:
            raise ValueError("source_usage")
        if any(
            task not in TASKS or type(label) is not bool
            for task, label in source["labels"].items()
        ):
            raise ValueError("source_labels")
        path = input_directory / source["filename"]
        if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_ARCHIVE:
            raise ValueError("source_file")
        with path.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != source["sha256"]:
                raise ValueError(f"source_hash:{source['id']}")
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    output_directory.mkdir(mode=0o700)
    previous_umask = os.umask(0o077)
    try:
        records, rejected = [], []
        for source in sources:
            accepted, quarantined = ingest(source, input_directory / source["filename"])
            records.extend(accepted)
            rejected.extend(quarantined)
        return write_records(
            output_directory, group_records(records, seed), rejected, sources, seed
        )
    finally:
        os.umask(previous_umask)


def main():
    """Run the offline corpus preparation command."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--sources", type=Path, default=Path(__file__).with_name("sources.json")
    )
    parser.add_argument("--seed", default="spamwise-public-2026-10-v1")
    args = parser.parse_args()
    try:
        report = prepare(
            args.input.resolve(), args.output.absolute(), args.sources, args.seed
        )
    except (ValueError, OSError, tarfile.TarError, csv.Error):
        parser.exit(
            1,
            "Corpus preparation failed; verify pinned sources, resource limits and output path.\n",
        )
    print(
        json.dumps(
            {
                key: report[key]
                for key in ("input_records", "unique_text_records", "quarantined")
            }
        )
    )


if __name__ == "__main__":
    main()

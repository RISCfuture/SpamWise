#!/usr/bin/env python3
"""Fail when a committed compiled resource no longer matches its source.

The Mail rule script ships compiled as SpamWise/SpamWiseRule.scpt; its decompiled text must match
Resources/SpamWiseRule.applescript, ignoring indentation and blank lines. Each Help language's
search.cshelpindex must hold the same entries that hiutil builds from that language's pages now.
hiutil gives every entry a fresh UUID and writes the archive in no fixed order, so the indexes are
compared by the sorted strings they carry rather than byte for byte.

Usage: python3 Scripts/check-compiled-resources.py
"""

import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULE_SCRIPT = ROOT / "SpamWise" / "SpamWiseRule.scpt"
RULE_SOURCE = ROOT / "Resources" / "SpamWiseRule.applescript"
HELP_RESOURCES = ROOT / "SpamWise" / "SpamWise.help" / "Contents" / "Resources"
INDEX_NAME = "search.cshelpindex"

UUID = re.compile(rb"[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}")
ASCII_RUN = re.compile(rb"[\x20-\x7e]{4,}")
UTF16_RUN = re.compile(rb"(?:[\x20-\x7e]\x00){4,}")


def significant_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def rule_script_is_current():
    compiled = subprocess.run(
        ["osadecompile", str(RULE_SCRIPT)], check=True, capture_output=True, text=True
    ).stdout
    return significant_lines(compiled) == significant_lines(RULE_SOURCE.read_text())


def build_index(book, language, output):
    subprocess.run(
        [
            "hiutil",
            "-I",
            "corespotlight",
            "-C",
            "-a",
            "-s",
            language,
            "-l",
            language,
            "-f",
            str(output),
            str(book),
        ],
        check=True,
    )


def index_strings(index, scratch):
    archive_path = scratch / f"{index.parent.name}-{index.stem}.plist"
    subprocess.run(
        ["compression_tool", "-decode", "-a", "lzfse", "-i", str(index), "-o", str(archive_path)],
        check=True,
    )
    found = []
    for item in plistlib.loads(archive_path.read_bytes())["$objects"]:
        if isinstance(item, str):
            found.append(item.encode())
        elif isinstance(item, bytes):
            found += ASCII_RUN.findall(item)
            found += [run.decode("utf-16-le").encode() for run in UTF16_RUN.findall(item)]
    return sorted(UUID.sub(b"", string) for string in found)


def stale_help_indexes(scratch):
    stale = []
    for book in sorted(HELP_RESOURCES.glob("*.lproj")):
        language = book.stem
        rebuilt = scratch / f"{language}.cshelpindex"
        build_index(book, language, rebuilt)
        committed = book / INDEX_NAME
        if index_strings(committed, scratch) != index_strings(rebuilt, scratch):
            stale.append(committed.relative_to(ROOT))
    return stale


def main():
    failed = False
    if not rule_script_is_current():
        script, source = RULE_SCRIPT.relative_to(ROOT), RULE_SOURCE.relative_to(ROOT)
        print(
            f"error: {script} does not match {source}; run osacompile -o {script} {source}.",
            file=sys.stderr,
        )
        failed = True
    with tempfile.TemporaryDirectory() as scratch:
        for index in stale_help_indexes(Path(scratch)):
            print(f"error: {index} is out of date; run Scripts/help-index.sh.", file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

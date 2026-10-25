#!/usr/bin/env python3
"""Fail when a committed compiled resource no longer matches its source.

The Mail rule script ships compiled as SpamWise/SpamWiseRule.scpt; its decompiled text must match
Resources/SpamWiseRule.applescript, ignoring indentation and blank lines. Each Help language's
search.cshelpindex must hold the same entries that hiutil builds from that language's pages now.
hiutil gives every entry a fresh UUID and writes the archive in no fixed order, so the indexes are
compared by the sorted strings they carry rather than byte for byte. Each entry's attributes are a
binary blob of length-prefixed strings: UTF-16 behind a byte-order mark, or 8-bit text.

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
TEXT_RUN = re.compile(rb"(?:[\x20-\x7e]|[\xc2-\xf4][\x80-\xbf]+){4,}")
BYTE_ORDER_MARK = b"\xff\xfe"


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


def utf16_strings(blob):
    """Decodes each UTF-16 string, whose 32-bit length counts its byte-order mark."""
    strings = []
    start = blob.find(BYTE_ORDER_MARK, 4)
    while start != -1:
        length = int.from_bytes(blob[start - 4 : start], "little")
        end = start + length
        if length >= 2 and length % 2 == 0 and end <= len(blob):
            text = blob[start + 2 : end].decode("utf-16-le", errors="replace")
            strings.append(text.encode())
            start = blob.find(BYTE_ORDER_MARK, end)
        else:
            start = blob.find(BYTE_ORDER_MARK, start + 1)
    return strings


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
            found += TEXT_RUN.findall(item)
            found += utf16_strings(item)
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

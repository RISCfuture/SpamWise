#!/usr/bin/env python3
"""Fail when a SpamWiseCore String(localized:) key lacks translated es/fr catalog entries.

Xcode extracts strings only from app targets, so package sources reach the app's
catalog by hand. Interpolations match any format specifier in a catalog key.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "SpamWiseCore/Sources"
CATALOG = ROOT / "SpamWise/Localizable.xcstrings"
UNLINKED_MODULES = {"Evaluation", "SpamWiseEval", "SpamWiseDaemon"}
LANGUAGES = ("es", "fr")
PLACEHOLDER = "\0"
CALL = re.compile(r"String\(\s*localized:\s*(?=\")")
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:@|ll[du]|l[du]|[dufgesx]|lf)")
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}


def skip_interpolation(text, index):
    """Return the index just past the parenthesis closing an interpolation at `index`."""
    depth = 0
    while index < len(text):
        character = text[index]
        if character == '"':
            _, index = read_literal(text, index)
            continue
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    raise ValueError("Unterminated interpolation")


def read_escape(text, index, output):
    """Append the escape at `index` (just past the backslash) and return the next index."""
    character = text[index]
    if character == "(":
        output.append(PLACEHOLDER)
        return skip_interpolation(text, index)
    if character == "u":
        end = text.index("}", index)
        output.append(chr(int(text[index + 2 : end], 16)))
        return end + 1
    output.append(ESCAPES[character])
    return index + 1


def read_single_line(text, index):
    """Decode a single-line literal whose opening quote is at `index`."""
    output, index = [], index + 1
    while text[index] != '"':
        if text[index] == "\\":
            index = read_escape(text, index + 1, output)
        else:
            output.append(text[index])
            index += 1
    return "".join(output), index + 1


def read_multiline(text, index):
    """Decode a multi-line literal whose opening delimiter is at `index`."""
    start = text.index("\n", index) + 1
    end = text.index('"""', start)
    closing_line = text[text.rindex("\n", 0, end) + 1 : end]
    body = text[start : text.rindex("\n", 0, end)]
    lines = [line.removeprefix(closing_line) for line in body.split("\n")]
    raw = "\n".join(lines)
    output, position = [], 0
    while position < len(raw):
        if raw.startswith("\\\n", position):
            position += 2
        elif raw[position] == "\\":
            position = read_escape(raw, position + 1, output)
        else:
            output.append(raw[position])
            position += 1
    return "".join(output), end + 3


def read_literal(text, index):
    """Decode the string literal starting at `index`; return its text and the next index."""
    if text.startswith('"""', index):
        return read_multiline(text, index)
    return read_single_line(text, index)


def source_keys():
    """Map each localized key in modules the app links to its first location."""
    keys = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        if path.relative_to(SOURCES).parts[0] in UNLINKED_MODULES:
            continue
        text = path.read_text()
        for match in CALL.finditer(text):
            key, _ = read_literal(text, match.end())
            line = text.count("\n", 0, match.start()) + 1
            keys.setdefault(key, f"{path.relative_to(ROOT)}:{line}")
    return keys


def translated(entry, language):
    """Whether every unit for `language` in a catalog entry is translated."""
    localization = entry.get("localizations", {}).get(language)
    if localization is None:
        return False
    units = []

    def collect(node):
        if "stringUnit" in node:
            units.append(node["stringUnit"])
        for variants in node.get("variations", {}).values():
            for variant in variants.values():
                collect(variant)

    collect(localization)
    return bool(units) and all(unit.get("state") == "translated" for unit in units)


def catalog_entries():
    """Map normalized catalog keys to their entries."""
    strings = json.loads(CATALOG.read_text())["strings"]
    return {
        SPECIFIER.sub(PLACEHOLDER, key).replace("%%", "%"): entry
        for key, entry in strings.items()
    }


def main():
    """Report every missing or untranslated key and exit nonzero when any exists."""
    entries = catalog_entries()
    problems = []
    for key, location in source_keys().items():
        entry = entries.get(key)
        missing = (
            list(LANGUAGES)
            if entry is None
            else [language for language in LANGUAGES if not translated(entry, language)]
        )
        if missing:
            shown = key.replace(PLACEHOLDER, "%@")
            problems.append(f"{location}: {', '.join(missing)} missing for “{shown}”")
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

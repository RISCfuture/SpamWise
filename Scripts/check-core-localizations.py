#!/usr/bin/env python3
"""Fail when a SpamWiseCore module's localized strings don't resolve from its own catalog.

Every String(localized:) call passes `bundle: .module`, and the module's
Localizable.xcstrings holds each key with translated es/fr values whose format
specifiers match the key. Interpolations match any format specifier in a catalog
key. Catalog keys that no call uses are reported too.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "SpamWiseCore/Sources"
LANGUAGES = ("es", "fr")
PLACEHOLDER = "\0"
CALL = re.compile(r"String\(\s*localized:\s*(?=\")")
MODULE_BUNDLE = re.compile(r"\s*,\s*bundle:\s*\.module\s*\)")
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:@|ll[du]|l[du]|[dufgesx]|lf)")
POSITION = re.compile(r"%\d+\$")
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


def module_calls():
    """Map each module with localized calls to its keys' first locations and unbundled calls."""
    modules = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        text = path.read_text()
        module = modules.setdefault(path.relative_to(SOURCES).parts[0], ({}, []))
        for match in CALL.finditer(text):
            key, end = read_literal(text, match.end())
            line = text.count("\n", 0, match.start()) + 1
            location = f"{path.relative_to(ROOT)}:{line}"
            module[0].setdefault(key, location)
            if not MODULE_BUNDLE.match(text, end):
                module[1].append(location)
    return {name: calls for name, calls in modules.items() if calls[0]}


def translated(entry, language):
    """Whether every unit for `language` in a catalog entry is translated."""
    localization = entry.get("localizations", {}).get(language)
    if localization is None:
        return False
    units = string_units(localization)
    return bool(units) and all(unit.get("state") == "translated" for unit in units)


def string_units(node):
    """Collect the string units of a localization, including every variation."""
    units = [node["stringUnit"]] if "stringUnit" in node else []
    for variants in node.get("variations", {}).values():
        for variant in variants.values():
            units.extend(string_units(variant))
    return units


def specifier_types(text):
    """The sorted conversion types of a format string, ignoring argument positions."""
    return sorted(
        POSITION.sub("%", specifier)
        for specifier in SPECIFIER.findall(text.replace("%%", ""))
    )


def normalized(key):
    """A catalog key with every format specifier replaced by the interpolation placeholder."""
    return SPECIFIER.sub(PLACEHOLDER, key).replace("%%", "%")


def entry_problems(key, entry):
    """Describe missing translations and format mismatches in one catalog entry."""
    missing = [language for language in LANGUAGES if not translated(entry, language)]
    problems = [f"{', '.join(missing)} missing"] if missing else []
    expected = specifier_types(key)
    for language, localization in entry.get("localizations", {}).items():
        if any(
            specifier_types(unit["value"]) != expected
            for unit in string_units(localization)
        ):
            problems.append(f"{language} format specifiers differ from the key")
    return problems


def module_problems(module, keys, unbundled):
    """Report a module's unbundled calls and its catalog's coverage of its keys."""
    problems = [f"{location}: pass bundle: .module" for location in unbundled]
    catalog = SOURCES / module / "Localizable.xcstrings"
    if not catalog.exists():
        return problems + [f"{catalog.relative_to(ROOT)}: missing catalog"]
    strings = json.loads(catalog.read_text())["strings"]
    entries = {normalized(key): (key, entry) for key, entry in strings.items()}
    for key, location in keys.items():
        shown = key.replace(PLACEHOLDER, "%@")
        if key not in entries:
            problems.append(
                f"{location}: “{shown}” missing from {catalog.relative_to(ROOT)}"
            )
            continue
        catalog_key, entry = entries[key]
        problems += [
            f"{location}: {problem} for “{catalog_key}”"
            for problem in entry_problems(catalog_key, entry)
        ]
    problems += [
        f"{catalog.relative_to(ROOT)}: “{catalog_key}” is unused"
        for normalized_key, (catalog_key, _) in entries.items()
        if normalized_key not in keys
    ]
    return problems


def main():
    """Report every catalog problem and exit nonzero when any exists."""
    problems = [
        problem
        for module, (keys, unbundled) in module_calls().items()
        for problem in module_problems(module, keys, unbundled)
    ]
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

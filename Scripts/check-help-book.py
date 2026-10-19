#!/usr/bin/env python3
"""Fail when the Help book is missing an anchor the app opens, or its pages don't hold together.

The app opens Help through `HelpButton(page:)`, `Help.open(_:)` and the pages
`Help.localizedTitle(for:)` names. Each of those anchors must be an `<a name>` in
every localization. Help opens an anchor wherever the book defines it, so no anchor
may appear on two pages. Every localization must also have the development region's
pages, each page's elements must be properly closed, and every link between pages
must reach an existing page and anchor.
"""

import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_SOURCES = [ROOT / "SpamWise", ROOT / "SpamWise-MAS", ROOT / "SpamWise-download"]
BOOK = ROOT / "SpamWise/SpamWise.help/Contents/Resources"
DEVELOPMENT_REGION = "en"
OPENED_ANCHOR = re.compile(r'(?:HelpButton\(page:|Help\.open\()\s*"([^"]+)"')
TITLE_FUNCTION = re.compile(
    r"func localizedTitle\(for page: String\)[^{]*\{(.*?)\n  \}", re.DOTALL
)
TITLED_ANCHOR = re.compile(r'case "([^"]+)"')
VOID_ELEMENTS = {
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "source",
    "track",
    "wbr",
}


class Page(HTMLParser):
    """The anchors, links and structural errors of one Help page."""

    def __init__(self):
        super().__init__()
        self.anchors, self.links, self.errors, self.open = set(), [], [], []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "a" and attributes.get("name"):
            self.anchors.add(attributes["name"])
        if tag == "a" and attributes.get("href"):
            self.links.append(attributes["href"])
        if tag not in VOID_ELEMENTS:
            self.open.append((tag, self.getpos()[0]))

    def handle_endtag(self, tag):
        if tag not in (open_tag for open_tag, _ in self.open):
            self.errors.append(f"line {self.getpos()[0]}: </{tag}> closes nothing")
            return
        while (unclosed := self.open.pop())[0] != tag:
            self.errors.append(f"line {unclosed[1]}: <{unclosed[0]}> is never closed")

    def close(self):
        super().close()
        self.errors += [
            f"line {line}: <{tag}> is never closed" for tag, line in self.open
        ]


def referenced_anchors():
    anchors = set()
    for directory in APP_SOURCES:
        for source in directory.rglob("*.swift"):
            text = source.read_text(encoding="utf-8")
            anchors.update(OPENED_ANCHOR.findall(text))
            for body in TITLE_FUNCTION.findall(text):
                anchors.update(TITLED_ANCHOR.findall(body))
    return anchors


def read_book(localization):
    pages = {}
    for path in sorted(localization.glob("*.html")):
        page = Page()
        page.feed(path.read_text(encoding="utf-8"))
        page.close()
        pages[path.name] = page
    return pages


def broken_links(pages):
    for name, page in pages.items():
        for link in sorted(set(page.links)):
            if re.match(r"[a-z][a-z0-9+.-]*:", link):
                continue
            target, _, anchor = link.partition("#")
            target = target or name
            if target not in pages:
                yield f"{name}: link to missing page {target}"
            elif anchor and anchor not in pages[target].anchors:
                yield f"{name}: link to missing anchor {target}#{anchor}"


def problems():
    anchors = referenced_anchors()
    if not anchors:
        yield "no Help anchors found in the app sources; update this script's patterns"
    books = {path.stem: read_book(path) for path in sorted(BOOK.glob("*.lproj"))}
    if DEVELOPMENT_REGION not in books:
        yield f"no {DEVELOPMENT_REGION}.lproj Help book"
        return
    for language, pages in books.items():
        missing_pages = set(books[DEVELOPMENT_REGION]) - set(pages)
        yield from (
            f"{language}: missing page {name}" for name in sorted(missing_pages)
        )
        book_anchors = [anchor for page in pages.values() for anchor in page.anchors]
        yield from (
            f"{language}: missing anchor {anchor}"
            for anchor in sorted(anchors - set(book_anchors))
        )
        repeated = {anchor for anchor in book_anchors if book_anchors.count(anchor) > 1}
        yield from (
            f"{language}: anchor {anchor} is on several pages"
            for anchor in sorted(repeated)
        )
        for name, page in pages.items():
            yield from (f"{language}/{name}: {error}" for error in page.errors)
        yield from (f"{language}/{problem}" for problem in broken_links(pages))


def main():
    found = list(problems())
    for problem in found:
        print(f"error: Help book: {problem}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())

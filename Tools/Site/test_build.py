"""Verify publication boundaries and links in the generated site."""

import tempfile
import unittest
from pathlib import Path

import build


class PublicationTests(unittest.TestCase):
    def test_separates_public_navigation_from_repository_documents(self):
        rendered = build.markdown_content(
            "[Privacy](privacy.md#diagnostics) "
            "[Updates](updating.md#library-dependency) "
            "[Roadmap](../TODO.md) "
            "[External](https://example.org/policy.md)"
        )
        for destination in (
            'href="privacy.html#diagnostics"',
            'href="https://github.com/RISCfuture/SpamWise/blob/main/docs/updating.md#library-dependency"',
            'href="https://github.com/RISCfuture/SpamWise/blob/main/TODO.md"',
            'href="https://example.org/policy.md"',
        ):
            self.assertIn(destination, rendered)

    def test_stages_only_the_publication_allowlist(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "site"
            build.stage_site(destination)
            self.assertEqual(
                {path.name for path in destination.iterdir()},
                {
                    "index.html",
                    "privacy.html",
                    "support.html",
                    "lifecycle.html",
                    "mail-compatibility.html",
                    "site.css",
                    ".nojekyll",
                },
            )


if __name__ == "__main__":
    unittest.main()

# Static prerelease site

The site is prepared under `docs/` for GitHub Pages at the planned address
`https://riscfuture.github.io/SpamWise/`. The repository is
`RISCfuture/SpamWise`, created privately pending publication approval. The site is
not published; no release download, custom domain or App Store URL is configured.
It uses local CSS and system fonts, with no JavaScript, analytics,
CDN, external images or form backend. The pages contain prerelease language and
`noindex, nofollow` metadata until publication is deliberately prepared.

## Sources and generation

Policy and support prose has one source of truth:

| Generated page | Maintained source |
| --- | --- |
| `docs/index.html` | `Tools/Site/home.html` |
| `docs/privacy.html` | `docs/privacy.md` |
| `docs/support.html` | `docs/support.md` |
| `docs/lifecycle.html` | `docs/lifecycle.md` |
| `docs/mail-compatibility.html` | `docs/mail-compatibility.md` |

`layout.html` supplies navigation, metadata and the footer. `docs/site.css` is
maintained directly. The generator renders Markdown without embedded HTML,
adds heading anchors and rewrites links between the listed documents to their
HTML equivalents. Deeper implementation references link to Markdown in the
repository's `main` branch. `.nojekyll` preserves the checked-in static output.
Do not edit generated HTML prose independently of its maintained source.

From `Tools/Site`, create the pyenv environment once, then install and generate:

```sh
pyenv virtualenv 3.14.8 spamwise-site
pyenv exec pip install -r requirements.txt
pyenv exec ruff check --fix .
pyenv exec ruff format .
pyenv exec python build.py
pyenv exec python build.py --check
pyenv exec python -m unittest discover
```

Skip environment creation when `spamwise-site` already exists. `--check` is
read-only and exits unsuccessfully if any generated page is missing or stale.
Run it after changes to the Markdown sources, template or generator. The
dependency versions are pinned; rendering needs no network after installation.

Preview from the repository root:

```sh
PYENV_VERSION=spamwise-site pyenv exec python -m http.server 8419 \
  --bind 127.0.0.1 --directory docs
```

Open the printed loopback address. This serves local files and does not publish
them. For automated browser work, use an isolated headless browser and the
`devtools` resource lock rather than the user's desktop session.

## Deployment artifact and approval

`build.py --stage /path/to/new/directory` verifies the generated pages and copies
only the five public HTML pages, stylesheet and `.nojekyll`. Research documents,
probe records and other files under `docs/` are not uploaded as website content.
The destination must be new, preventing leftover files from entering an artifact.

`.github/workflows/site.yml` validates relevant pull requests. Deployment requires
a manual run on `main` with `publish` enabled; merging alone never publishes.
The workflow uses pinned official actions and grants Pages write permissions only
to the deployment job. Its default manual run validates without deployment.

Review [the repository approval checklist](../../docs/repository-approval.md)
before enabling Pages or changing repository visibility. Indexing restrictions and
prerelease labels remain until separately reviewed. A download button or store
badge requires an actual accepted release URL. No DNS or App Store metadata is
changed by this tooling.

# Static prerelease site

The site is prepared under `docs/` for a future static host such as GitHub Pages.
It is not published, and no repository, domain, release download or App Store URL
is configured. It uses local CSS and system fonts, with no JavaScript, analytics,
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
HTML equivalents. Deeper implementation references remain links to existing
Markdown source documents. `.nojekyll` preserves the checked-in static output.
Do not edit generated HTML prose independently of its maintained source.

From `Tools/Site`, create the pyenv environment once, then install and generate:

```sh
pyenv virtualenv 3.14.8 spamwise-site
pyenv exec pip install -r requirements.txt
pyenv exec ruff check --fix .
pyenv exec ruff format .
pyenv exec python build.py
pyenv exec python build.py --check
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

## Publication work still required

Select the hosting repository/domain, review the policy and support drafts, and
decide whether these prerelease pages should be public. Set real public URLs only
after that choice. Remove indexing restrictions only when the owner intends the
site to be indexed. Replace prerelease/publication-draft statements only when
they cease to apply, regenerate all pages and rerun browser/link checks. A download
button or store badge requires a real accepted release URL.

Preparing these files does not enable GitHub Pages, change DNS, configure a remote
or submit App Store metadata. Provider terms and App Privacy questionnaire
decisions remain the release owner's responsibility.

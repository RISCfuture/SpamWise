# Repository and publication approval

The source lives in the private repository
[RISCfuture/SpamWise](https://github.com/RISCfuture/SpamWise). App pricing is free;
external provider usage is billed separately by the provider. No source-code license
has been selected. Whether publication has happened is tracked in
[TODO.md](../TODO.md).

## Planned addresses

| Item | Address or mechanism |
| --- | --- |
| Marketing page | `https://riscfuture.github.io/SpamWise/` |
| Privacy | `https://riscfuture.github.io/SpamWise/privacy.html` |
| Support | `https://riscfuture.github.io/SpamWise/support.html` |
| Download edition releases | `https://github.com/RISCfuture/SpamWise/releases` |
| Site deployment | `.github/workflows/site.yml`, run manually on `main` with `publish` enabled |
| Site payload | Five HTML pages, one stylesheet and `.nojekyll` only |
| Indexing and downloads | Prerelease `noindex` kept; no download or store link until a release exists |

The site workflow validates generated pages, Python lint and format, and the
publication tests on pull requests. Pull requests and ordinary merges cannot deploy,
and a manual run defaults to validation only. GitHub Pages must be enabled for the
repository before a deployment can succeed. The download edition's update checks need
the repository to be public.

## Owner approval before publication

Before changing visibility or deploying, review the generated site locally and the
[privacy](privacy.md), [support](support.md) and [compatibility](mail-compatibility.md)
pages. Run a credential scan over the full history: committed history becomes public
with the repository, and a pattern scan is bounded, not a guarantee about every
possible credential format. Source licensing is a separate choice; a free app price
does not select a source license.

Publishing binaries and submitting to the App Store are separate, concrete release
approvals. See [packaging](packaging.md) and [App Store packaging](app-store.md).

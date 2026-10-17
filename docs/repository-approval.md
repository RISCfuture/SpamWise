# Repository and publication approval

Prepared on 2026-10-17 for Tim Morgan, <tim@tim.codes>. App pricing remains free;
external provider usage is billed separately.

## Created

- Private repository: <https://github.com/RISCfuture/SpamWise>.
- Local `origin`: `git@github.com:RISCfuture/SpamWise.git`.
- No site deployment, public visibility change, release upload or store submission.
- No source-code license has been selected or added.

Automatic tool approval rejected the initial Git push. The remote therefore
remains empty until the prepared commits are uploaded. The committed project
baseline is `7cf6c55`; repository setup is committed afterward on `codex/phase-one`.
Uncommitted Xcode/catalog edits are excluded. A history scan found no matches for
the checked private-key, provider-key and GitHub-token patterns; this is a bounded
scan, not a guarantee about every possible credential format.

## Prepared review

The proposed initial default branch is `main` at `7cf6c55`. The setup changes belong
in a draft pull request from `codex/phase-one`, allowing a focused publication review.

| Item | Proposed result |
| --- | --- |
| Marketing page | `https://riscfuture.github.io/SpamWise/` |
| Privacy | `https://riscfuture.github.io/SpamWise/privacy.html` |
| Support | `https://riscfuture.github.io/SpamWise/support.html` |
| Direct releases | `https://github.com/RISCfuture/SpamWise/releases` |
| Site deployment | GitHub Actions, manually invoked from `main` after approval |
| Site payload | Five HTML pages, one stylesheet and `.nojekyll` only |
| Indexing/downloads | Prerelease `noindex` retained; no invented download or store link |

The workflow validates generated pages, Python lint/format and publication tests.
Pull requests and ordinary merges cannot deploy. A manual run defaults to
validation only. Pages itself must be enabled after approval before a deployment
can succeed. No remote CI success is claimed before the commits are uploaded.

## Owner approval before publication

Review the generated site locally and the [privacy](privacy.md), [support](support.md)
and [compatibility](mail-compatibility.md) drafts. Approve whether to make this
source repository, including its committed history, public and whether to publish
the prerelease site at the addresses above. Source licensing is a separate choice;
a free application price does not select a source license.

Publications of app binaries and App Store submission remain separate, concrete
release approvals. The current direct updater only discovers releases manually;
publishing a repository does not add automatic installation.

## Deferred by the owner

Provider credentials/quota, supervised device acceptance, personal labels and
App Store account steps are skipped for now. Their TODO checkboxes remain open.
The Spamhaus investigation is documented in [the service assessment](spamhaus.md);
no subscription, terms acceptance or live lookup is enabled by that research.

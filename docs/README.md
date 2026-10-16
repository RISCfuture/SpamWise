# SpamWise documentation

Reference documentation describes current behavior, limits and commands. What is done
and what still waits on acceptance is tracked only in [TODO.md](../TODO.md).

## Using SpamWise

- [Support](support.md): setup, troubleshooting and corrections (published page).
- [Install, upgrade, recover and remove](lifecycle.md) (published page).
- [Mail.app compatibility](mail-compatibility.md): tested accounts and the acceptance
  matrix (published page).
- [Privacy policy](privacy.md) (published page) and the
  [privacy data inventory](privacy-audit.md) behind it and the privacy manifests.

## Features

- [Optional evidence and OCR](evidence.md): Spamhaus DBL, local Rspamd and embedded
  image OCR.
- [Spamhaus fit for SpamWise](spamhaus.md): access routes, eligibility and setup.
- [IMAP and headless operation](imap.md): the IMAP route and `spamwise-daemon`.
- [Mail.app automation](automation.md): App Intents, Shortcuts and the native intent
  test.
- [Independent threat assessments](threat-assessments.md).
- [Threat detection design](detection-design.md): separating threats from mail
  preferences.

## Evaluation and data

- [Evaluation](evaluation.md): `spamwise-eval`, fixtures, labeled corpora, calibration
  and frozen comparisons.
- [Public email training data](training-data.md).
- Probe records under [probes/](probes/): model screenings, corpus audits, runtime
  harnesses and live Mail probes. The
  [signed runtime acceptance checklist](probes/runtime-checklist.md) lists the checks
  a release build must pass.

## Building and distribution

- [Packaging](packaging.md): editions, Help book, versions, fastlane lanes and the
  release checklist.
- [Direct release updates](updating.md): the download edition's update checker.
- [Edition differences](distribution-differences.md).
- [App Store feasibility](app-store-feasibility.md), [App Store packaging](app-store.md)
  and [App Review notes](app-review-notes.md).
- [Repository and publication approval](repository-approval.md).
- [Conventions and design decisions](conventions-and-design-review.md).

## Background

- [Phase 1 brief](phase-one-brief.md), the original contract, preserved verbatim.
- [Full code review, 2026-10-17](reviews/2026-10-17-full-review.md).

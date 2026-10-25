# ``SpamWiseEval``

Evaluates SpamWise's classification of labeled mail offline, without moving any message.

## Overview

`spamwise-eval` runs a labeled corpus or exported reviewed labels through the production
pipeline as a dry run and reports Inbox, Review and Junk decisions, model labels and
estimated cost. Paid models need an explicit budget ledger. Run `spamwise-eval --help` for its
commands and options; the repository's `docs/evaluation.md` describes the methodology.

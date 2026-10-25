# ``SpamWiseDaemon``

Filters one explicitly configured IMAP account without the SpamWise app.

## Overview

`spamwise-daemon` runs, validates and probes an IMAP account with SpamWise's pipeline. Its
default command runs one bounded dry run. Secrets are never arguments, and there is no provider
or credential fallback. Run `spamwise-daemon --help` for its commands; the repository's
`docs/imap.md` describes the setup.

# Unreadable mail and repeating sweeps

A source larger than the parser's 2 MB limit previously failed the entire Apple
Mail page. Because progress advances only after handling a page, the same entry
could prevent later mail from being reached. The existing paging test reproduced
this as `IntegrationError.scriptFailed` before the change.

## Page handling

Account and configured-folder reads retain the number of mailbox positions
visited separately from the readable envelopes. A source that is oversized,
empty, or unavailable is counted but never passed to classification, correction,
or a mail action. The next cursor advances by visited positions; subsequent
sweeps retry unavailable entries. Mail's reported message size is checked before
requesting source, and the UTF-8 byte limit is checked again in Swift. Mail's
size metadata is not a hard memory-allocation guarantee.

Unreadable entries still require valid account/mailbox/local-ID fields. Wrong
accounts, wrong configured folders, malformed response shapes, and inconsistent
page lengths fail the page. Permission denial and Apple Events timeouts also
remain whole-page failures; a persistently timed-out source can still block a
page. No such failure is classified as spam. Selected-message corrections and
exact-source action lookups retain their strict envelope decoding.

Health records retain unreadable counts through a traversal, including across
store reopening, and display the completed traversal's count after wrapping.
Account and folder settings show that unreadable mail remains in place. Manual
previews and Junk review also disclose unreadable entries rather than reporting
an entirely readable page. Counts describe observed mailbox positions, not an
independent server inventory or a count of unique classified messages.

## Training folders

A traversal with any unreadable entry cannot establish that a previously trained
message departed. Its action claims remain in place. Traversal completion is
separate from permission to release claims: observation sets reset at every
traversal boundary, including incomplete traversals. Otherwise a permanently
unreadable entry could cause departed identities to accumulate across sweeps and
exhaust the bounded observation store. Failed or uncertain actions remain
claimed even after a fully readable traversal.

Review identified this distinction before completion. The existing training
claim test reproduced premature claim release before the guard was added; it
now checks both retained claims and cleared observations for incomplete empty
and nonempty traversals.

## Evidence and remaining acceptance

The existing paging test covers readable mail following an oversized source,
visited/unreadable counts, a fresh Store reopening at the saved cursor, wrap and
empty-mailbox recovery, an entirely unreadable page, account rejection and
inconsistent response rejection. Generated Inbox and folder AppleScripts compile
against the installed Mail dictionary without executing Mail. These are offline
behavioral checks, not live delivery measurements.

Controlled incoming delivery, large/mutating mailboxes, slow/offline servers,
sleep/wake, and independent end-to-end latency remain open in TODO.md. No paid
model calls or live mail mutations were needed for these checks.

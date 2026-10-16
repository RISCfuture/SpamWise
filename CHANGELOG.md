# Changelog

Release notes for SpamWise. The version headings are what
`Scripts/release-notes.sh` reads, and what the Release workflow attaches to a
GitHub release — so a heading is `## <version>`, matching the tag exactly.

## 1.0

### New

- SpamWise filters junk mail in Apple Mail. Your sender and domain rules,
  your contacts and your own mail history decide first; a language model you
  choose classifies the rest.
- Unwanted mail moves to each account’s own Junk mailbox. Uncertain mail
  stays in your Inbox, flagged for review. SpamWise never deletes mail.
- SpamWise starts in dry run, recording what it would do without changing
  any mail, until you turn mail actions on.
- Correct a decision from the menu bar or the Activity window, and SpamWise
  restores the message and remembers the sender.
- The downloadable edition checks GitHub for new releases on the schedule you
  choose in Settings.

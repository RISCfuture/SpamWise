# Signed runtime acceptance checklist

These are the checks a signed build must pass on a real Mac with real Mail accounts.
Which of them have passed is recorded in [TODO.md](../../TODO.md). Use only generated
`[SpamWise Probe]` messages for any action, never record keys or message bodies, and
clean up probes afterward as `CLAUDE.md` describes. Build success, unit tests and
generated AppleScript compilation are not substitutes for these checks.

1. Build either edition signed for team 2NFSK2WB24, with App Group
   `group.codes.tim.SpamWise` and the shared Keychain group. On a clean macOS 27 user
   account, start a timer and complete the four onboarding steps. Record elapsed time
   (target under five minutes), OS build, signing identity class and configured
   account types.
2. Verify a user-supplied key through onboarding. Record the model ID, measured usage,
   latency and configuration errors, without fallback. A denied or locked Keychain
   must leave mail untouched.
3. Use **Check Mail connection** to grant Automation. Deny once and confirm a clear
   status and no action. Run **Import Inbox and Sent history**; verify known reply and
   receipt cases and the unknown/partial cases. No Full Disk Access or Mail database
   access is required.
4. Send a disposable message from another account with a subject starting
   `[SpamWise Probe]`, put it in Inbox and select only it in Mail. A same-account Sent
   copy with the same Message-ID makes resolution ambiguous. Run **Test selected
   message** under Settings → Advanced → Optional move test. It verifies the initial
   Inbox location, moves the message to that account's Junk and back to Inbox, and
   sets an orange flag. After each move SpamWise polls every two seconds and confirms
   after two consecutive observations of the exact source in the intended mailbox,
   giving up after 30 seconds; the next action requires a confirmed one. The flag is
   read back too. The test neither changes dry run nor validates the account; **Check
   Mail connection** validates accounts from their Inbox and Junk roles. If the return
   fails, find the message in Junk and restore it manually. Repeat per account, and
   test the background color separately. This observes Mail's local state, not a
   server acknowledgement.
5. Only after the action tests pass, turn off dry run in General and confirm.
   Optionally install the bundled `SpamWiseRule.scpt` under
   `~/Library/Application Scripts/com.apple.mail/` and add a Mail rule that runs it;
   the app must be running or launchable by its `spamwise://` URL. The trigger carries
   no mail data; the app re-queries account-scoped messages. Send controlled plain and
   MIME probes to each account, including server-routed Junk, and check each Activity
   reason and evidence. Review stays in Inbox with an orange flag or background.
6. Exercise Mark as Good/Junk/Review from the menu bar, an explicit domain
   correction, Pause, network loss, unavailable storage, duplicate Message-IDs within
   an account, identical IDs across accounts, and a correction during a delayed
   classification. Ambiguous messages stay untouched, and requested or failed actions
   stay distinguishable from confirmed ones.
7. Confirm and then stop trusting an account's receiving servers. A probe from an
   address in Contacts must reach Inbox without classification only while the
   account trusts its servers and the probe's authentication is aligned.
8. Close every window, then lock the screen, sleep and wake, and restart the Mac;
   confirm scanning continues and progress persists each time.
9. Run the held-out evaluation, then archive, sign and notarize the edition being
   accepted and repeat the checks above on that exact artifact.

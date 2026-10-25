# Mail compatibility

SpamWise requires **macOS 27** and Apple Mail. It has been tested on Apple-silicon
Macs; Intel Macs and earlier macOS versions are untested and unsupported. Apple's
on-device model also needs Apple Intelligence to be available and its model
downloaded. SpamWise checks whether the provider you chose is available and never
switches to another one by itself.

## Accounts

SpamWise works with accounts you have added to Mail. It doesn't read Mail's
databases and doesn't need Full Disk Access.

| Account in Mail | Status |
| --- | --- |
| iCloud | Tested: Inbox and Junk moves, Review flag, corrections and Junk rescue |
| Google | Tested: Inbox and Junk moves, Review flag |
| Exchange, Microsoft 365 and Outlook.com | Not tested yet |
| Other accounts in Mail | Not tested yet |

Testing used generated messages on a few accounts; it isn't a guarantee for every
account of that kind. Behavior while offline or reconnecting hasn't been tested yet.

Microsoft 365 and Outlook.com don't name their mail server in the
Authentication-Results header they add. SpamWise instead takes the server's name from
the ARC-Authentication-Results header Microsoft adds when the message arrives, shows
it as a detected server with that explanation, and, once you trust it, trusts the
results in Microsoft's own Authentication-Results header. Mail that reached you
through a forwarder or mailing list that adds its own ARC headers gets no trusted
results this way. You can also enter `mx.microsoft.com` yourself.

## Mailboxes

SpamWise moves mail only to the Inbox and Junk mailboxes that Mail assigns to that
account; it never picks a folder by its name. Check Mailboxes, under each account's
Mailboxes and Details in Settings → Accounts, reads those assignments without opening
any message or changing anything. If an account has no Junk mailbox, or more than one,
SpamWise doesn't move that account's mail; the account's settings say how to fix it
in Mail.

## How moves are checked

After moving a message, SpamWise looks for it every two seconds and counts the move
as done once it finds the message in its new mailbox twice in a row, giving up after
30 seconds. When those 30 seconds have passed it looks once more, and records the move
as unconfirmed if the message is no longer the only copy there. This checks what Mail
shows on the Mac; a mail server can still move the message later.

A message that you sent to yourself in the same account has a Sent copy with the same
Message-ID, so SpamWise can't tell the two apart and leaves both alone. Automatic
moves also leave mail without a Message-ID in place. Correcting such a message still
moves it; SpamWise then finds it by its size and exact content to confirm the move.

If you move a message SpamWise put in Junk back to the Inbox, or choose Not Junk,
SpamWise counts it as marked Good on its next check, once its own move has held for
those 30 seconds. Learning from it doesn't move the message.

## Other filters

SpamWise checks each account's Inbox through Mail about once a minute while SpamWise
and Mail are both open and the Mac is awake. Mail also lists SpamWise's Mail
extension, which leaves every message to Mail: Mail doesn't tell extensions which
account a message belongs to, so all filtering happens through SpamWise's own checks.

Mail's built-in Junk Mail filter, SpamSieve and server rules keep working alongside
SpamWise, and their moves and colors are separate from SpamWise's. Keep dry run on
while you compare SpamWise with another filter; mail another filter moved to Junk is
not treated as your own correction.

## IMAP

Instead of Apple Mail, SpamWise can connect directly to one IMAP account
(Settings → Accounts → Mail connection). That route hasn't been tested against a
live server yet. It reads each message once, so mail it previews in dry run stays
where it is when you start filtering. See [IMAP](imap.md).

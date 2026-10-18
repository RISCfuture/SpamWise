# App Review preparation

Draft for Tim Morgan · Free · Contact <tim@tim.codes>

This document is ready to adapt into App Store Connect review notes. It is not a
submission. Supply the published privacy/support URLs, actual release screenshots,
necessary review access and Apple’s requested issue reference before submitting.

## Product and Mail Automation exception

SpamWise is a sandboxed Apple Mail filtering companion. It reads bounded message
source and history, resolves a message within its account, and supports moving it
to that account’s Inbox or Junk and adding a Review annotation. It never deletes
mail or moves it to Trash. The default is dry run. Leaving it requires an explicit
confirmation after a read-only check that the account’s Inbox and Junk mailboxes
resolve uniquely, and every live move is verified afterward and fails open.

The app requests `com.apple.security.temporary-exception.apple-events` only for
`com.apple.mail`, together with the Automation entitlement and usage description.
The installed Mail scripting dictionary’s composition access group does not grant
the existing-message source/history and mailbox operations the product requires.
MailKit does not expose arbitrary mailbox moves or a stable account identifier for
these workflows. The exception is needed for account-scoped inspection, explicit
corrections and the bounded mailbox-sweep route. macOS Automation consent is requested
before access; denial leaves mail unchanged and appears in the app.

There is no direct Mail database access, Full Disk Access requirement, private Mail
plug-in injection, external executable or code downloaded to change functionality.
The store build contains no updater and does not offer the ungranted Private Cloud
Compute choice. The Mail extension returns no decision for any message. Launch at
login is opt-in. Quitting stops monitoring.

## Suggested review flow

Use a test Mail account with disposable synthetic messages. Do not use the
developer’s private mailbox or API keys.

1. Launch the release app, complete the four setup steps and retain dry run.
2. Grant Automation permission to connect Mail, or deny it to inspect the explicit
   failure state.
3. Set an address rule and preview a matching synthetic message. Inspect its
   explanation and the separate dry-run action outcome. Replace the rule to verify
   that the latest correction at the same scope wins.
4. Inspect Account settings: keys are stored in Keychain, provider sharing is a
   separate opt-in, and the disclosure links to provider data terms. Leave remote
   sharing off unless review credentials and appropriate terms are supplied.
5. For live moves, check the Mail connection so the account’s Inbox and Junk
   mailboxes are validated, then turn off dry run in General and confirm. Correct
   only the selected disposable message, then inspect the separately reported action
   result. No Trash/delete action is offered.
6. Pause processing. Inspect Settings, local Activity, the review digest and Help.
   Denied or failed integration and model requests must leave messages untouched.

The on-device model requires an eligible Mac and available system model. Its
availability does not establish useful filtering quality. Remote providers require
their own account/key and may bill independently. The app itself is free, with no
paid SpamWise license or subscription. Provide an adequate reviewer-access plan
before submission; these notes do not create a working review account.

## Attachments to prepare

- Public [privacy policy](privacy.md) and [support page](support.md) URLs after hosting.
- Screenshots from the accepted release, containing only synthetic mail.
- The requested exception/Feedback reference and accurate privacy questionnaire.
- A locally validated store package and a confirmed test-account/provider-access
  arrangement sufficient for the flows above.

Follow Apple’s [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
and [temporary exception instructions](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html).
Approval of the Mail exception and service-access flow remains Apple’s decision.

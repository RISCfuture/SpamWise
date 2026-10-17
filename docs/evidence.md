# Optional evidence and embedded-image OCR

These features supply observations to the classifier. They do not select a mail
action, override an explicit rule, or bypass a trusted-contact/history gate.
Missing permission, service errors, malformed responses, and timeouts mean
**unknown**. Enable each feature deliberately; all are optional.

## Spamhaus domain and URI-host reputation

SpamWise queries the [Spamhaus Domain Blocklist (DBL)](https://www.spamhaus.org/blocklists/domain-blocklist/)
for sender domains and domains found in message links. A domain is sent as an A
record query beneath `dbl.spamhaus.org`. The original URL, path, query string,
message body, and email address are not sent. The resolver and Spamhaus can still
observe the queried domain.

Review the [Spamhaus fair-use policy](https://www.spamhaus.org/blocklists/dnsbl-fair-use-policy/)
before acknowledging eligibility. The public mirrors are intended for eligible
non-commercial use with reasonable volume and an attributable network. The policy
requires a recursive resolver on your own network or a public resolver supporting
ECS; large shared hosting environments may need separate access arrangements.
Acknowledgement records your decision; SpamWise cannot verify your eligibility.
Commercial services and larger usage can require a subscription. This adapter
does not configure or purchase a Spamhaus subscription or DQS key.

`SpamhausConfiguration` contains the acknowledgement and an explicit recursive
resolver IPv4 address. Its default address, `127.0.0.1`, requires a separately
configured local resolver. It does not install one. The adapter invokes the
system `dig` utility with separate arguments and a bounded response. Sandboxed
execution or an unavailable resolver can leave this feature unavailable.

Only valid domain names are accepted; IP literals and command-like input are
excluded. At most five distinct domains are queried concurrently per message,
with a three-second deadline. DBL is not an IP blocklist: this adapter never sends
reversed IP addresses to DBL or domain names to ZEN.

The [documented DBL codes](https://docs.spamhaus.com/datasets/docs/source/10-data-type-documentation/datasets/040-zones.html)
are interpreted explicitly. The listed-domain codes are `127.0.1.2`, `.4`, `.5`,
`.6`, `.102`, `.103`, `.104`, `.105`, and `.106`. These codes remain evidence,
including the distinction between poor-reputation and abused legitimate domains.
`127.0.1.255`, all `127.255.*` errors, unrecognized addresses, mixed valid/error
responses, and DNS failures are unknown. NXDOMAIN means not listed, which is not
proof that a message is wanted.

The resolver's normal DNS cache applies. SpamWise does not retain a separate DBL
cache or claim real-time reputation beyond the received DNS answer.

## Local Rspamd

Install and configure [Rspamd](https://docs.rspamd.com/getting-started/installation/)
separately. Select the absolute path of its `rspamc` executable. SpamWise restricts
the connection to `127.0.0.1:11333`; it does not send mail to a remotely configured
Rspamd endpoint. The local server may perform its own external checks according
to your Rspamd configuration, which should be reviewed separately.

The [rspamc client](https://github.com/rspamd/rspamd/blob/master/doc/rspamc.1)
receives up to 2 MB of raw mail through stdin. There is no shell interpolation,
temporary message file, or message content in process arguments. The subprocess
has a three-second deadline and a 64 KiB output cap. Cancellation, timeout and
excess output terminate the child process. Standard error is discarded.

SpamWise parses the [JSON symbol response](https://docs.rspamd.com/developers/protocol/),
retaining at most 20 symbol names and finite scores as untrusted evidence. It
ignores the server's proposed action. It does not invoke learning, fuzzy-write,
administration, deletion, or message-delivery commands. Scanning may still have
side effects configured in the local Rspamd server, such as logging or automatic
statistical learning.

A missing executable, denied sandbox access, unavailable local server, nonzero
exit status, or malformed result produces unknown evidence. Successful fixture
tests do not establish that a particular signed app can launch the installed
client. Verify that separately before relying on this optional integration.

## Embedded-image OCR

`EmbeddedImageOCR` uses Apple's local
[Vision text recognition](https://developer.apple.com/documentation/vision/recognizetextrequest)
on embedded PNG, JPEG, static GIF, single-image TIFF and HEIC data, including
attachment-disposition parts. It never loads remote image URLs or other message
resources. SVG, animated or multi-image files, unsupported transfer encodings,
and ordinary HTML image URLs are not OCR inputs.

The extractor accepts base64 image parts within these limits:

| Resource | Limit |
| --- | --- |
| Raw MIME message | 2 MB |
| Headers per MIME part | 64 KiB |
| MIME nesting and total parts | 12 levels, 128 parts |
| Embedded images | 4 |
| Decoded compressed image bytes | 512 KiB each, 1 MiB total |
| Image dimensions | 4096 pixels per side |
| Image pixels | 4 million each, 8 million total |
| Recognition deadline | 3 seconds across all images |
| Returned OCR text | 3000 characters including separators |

ImageIO checks type, image count, and dimensions before Vision receives the
bytes. Excessive or malformed input yields no OCR evidence. Recognition uses the
fast mode with automatic language detection and language correction disabled.
OCR text can be wrong and can contain malicious instructions; it belongs only in
the classifier's escaped untrusted message context.

## Verification boundaries

Offline tests cover DNS error-code rejection and opt-in behavior, isolated
Rspamd arguments and stdin, process output and time limits, MIME image count,
byte/pixel limits, and bounded OCR text. The process tests run local `cat`, `yes`,
and `sleep` fixtures; they do not contact DNSBLs or a Rspamd server. Unit OCR
fixtures inject recognition results after real MIME and ImageIO validation.
[Native runtime probes](probes/local-evidence-runtime.md) additionally run the
production recognizer on generated images in a Developer ID signed sandboxed
harness and observe the local-mode pipeline with process network counters.
Representative OCR quality, HEIC runtime fixtures, the shipped app bundle and an
installed Rspamd service remain separate acceptance checks.

No public blocklist lookup, message upload, or service credential is required to
run the offline suite:

```sh
bash Scripts/check.sh <worker-token>
```

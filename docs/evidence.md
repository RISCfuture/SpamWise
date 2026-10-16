# Optional evidence and embedded-image OCR

These features supply observations to the classifier. They do not select a mail
action, override an explicit rule, or bypass a trusted-contact/history gate.
Missing permission, service errors, malformed responses, and timeouts mean
**unknown**. Enable each feature deliberately; all are optional.

## Spamhaus domain and URI-host reputation

SpamWise queries the [Spamhaus Domain Blocklist (DBL)](https://www.spamhaus.org/blocklists/domain-blocklist/)
for the From, Reply-To and Return-Path domains and domains found in message links, at
most five distinct validated domains per message, with a three-second deadline
shortened by the processing budget. The original URL, path, query string, message
body and email address are never sent. DBL is not an IP blocklist: SpamWise never
sends reversed IP addresses to DBL or domain names to ZEN.

`SpamhausConfiguration` holds the terms acknowledgement, the selected `transport` and
a resolver address. The two transports have different data flows:

| Transport | What leaves the Mac | Credential |
| --- | --- | --- |
| `publicDNS` | DNS A-record questions beneath `dbl.spamhaus.org`, sent in process (libresolv) only to the configured IPv4 resolver, `127.0.0.1` by default. The resolver and Spamhaus can observe the queried domains | None; eligibility for the public mirrors is the user's to confirm |
| `https` | HTTPS requests for each domain to `apibl.spamhaus.net`, with normal TLS validation, no redirects, cookies, credential persistence or cache, and a 16 KiB response cap | The user's own HTTPS-authorized query key, stored only in the shared Keychain and sent in the Authorization header |

Both transports work in both editions, require acknowledging the selected service's
terms, stay off by default and are blocked in local-only mode. Changing transport
clears the acknowledgement, and neither falls back to the other. SpamWise keeps no DBL
cache beyond the message's own evidence.

The [documented DBL codes](https://docs.spamhaus.com/datasets/docs/source/10-data-type-documentation/datasets/040-zones.html)
are interpreted explicitly. The listed-domain codes are `127.0.1.2`, `.4`, `.5`,
`.6`, `.102`, `.103`, `.104`, `.105`, and `.106`. These codes remain evidence,
including the distinction between poor-reputation and abused legitimate domains.
`127.0.1.255`, all `127.255.*` errors, unrecognized addresses, mixed valid/error
responses, and DNS or HTTPS failures are unknown. NXDOMAIN, or a matching HTTPS 404,
means not listed, which is not proof that a message is wanted.

Eligibility, pricing, setup and the HTTPS protocol details are in
[Spamhaus fit for SpamWise](spamhaus.md).

## Local Rspamd

Install and configure [Rspamd](https://docs.rspamd.com/getting-started/installation/)
separately, then turn on **Local Rspamd scanner** in Settings. SpamWise sends up to
2 MB of complete raw mail as `POST /checkv2` to `127.0.0.1:11333`. The local server may
log, learn from, or perform external checks on that mail according to its own
configuration; review it before enabling scans. Local-only mode disables the scanner
because SpamWise cannot enforce its privacy policy.

The request uses an ephemeral URLSession and needs no external executable or sandbox
exception. The endpoint is fixed; redirects and authentication challenges are
rejected, proxies are disabled, and cookies, credential storage, and caches are
unused. The client collects at most 64 KiB of response bytes, including responses
without a declared length. Cancellation and the three-second maximum deadline cancel
the session; a shorter remaining classification budget shortens the deadline. HTTP
errors, unavailable services, excess output, and malformed results produce unknown
evidence. The local endpoint is not authenticated: enable this only for a scanner you
control, and stop using it if another process takes its port.

SpamWise parses the [JSON symbol response](https://docs.rspamd.com/developers/protocol/),
retaining at most 20 symbol names and finite scores as untrusted evidence. It
ignores the server's proposed action. It does not invoke learning, fuzzy-write,
administration, deletion, or message-delivery commands. Scanning may still have
side effects configured in the local Rspamd server, such as logging or automatic
statistical learning. A [signed sandbox runtime probe](probes/rspamd-runtime.md)
scanned synthetic mail against native Rspamd 4.2.2; that validates the transport, not
the quality or privacy of an independently installed scanner's rules.

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

Offline tests cover DNS and HTTPS response interpretation, opt-in and local-only
behavior, credential failures, query bounds, deadlines and cancellation, the Rspamd
HTTP client's limits, MIME image count, byte/pixel limits, and bounded OCR text. They
contact no DNSBL, Spamhaus endpoint or Rspamd server. Unit OCR fixtures inject
recognition results after real MIME and ImageIO validation.
[Native runtime probes](probes/local-evidence-runtime.md) additionally run the
production recognizer on generated images in a Developer ID signed sandboxed harness
and observe the local-mode pipeline with process network counters. The
[Rspamd probe](probes/rspamd-runtime.md) covers a temporary native scanner and
synthetic redirect, output-limit, failure, timeout and cancellation cases.
Representative OCR quality, in-process DNS from the signed app, the shipped app
bundle and an installed Rspamd configuration remain open in [TODO.md](../TODO.md).

No public blocklist lookup, message upload, or service credential is required to
run the offline suite:

```sh
Scripts/check.sh
```

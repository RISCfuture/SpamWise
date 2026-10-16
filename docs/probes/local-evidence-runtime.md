# Native local evidence and privacy probes

## Scope

`Scripts/evidence-runtime-probe.swift` links the production SpamWiseCore package.
`Scripts/evidence-runtime-check.sh` builds a separate Developer ID signed,
hardened-runtime app harness with App Sandbox and outbound-network entitlement.
The latter is intentionally enabled, as in SpamWise: the local-mode policy must
prevent requests even when the process is allowed to make them.

The harness generates only synthetic mail and raster images, uses a disposable
store in its own temporary directory, and deletes that store afterward. It does
not access Mail, Contacts, the app's shared store or Keychain. It grants itself
neither Automation nor App Group nor shared Keychain access. Signing timestamps
and package dependency resolution may use the network before observation begins.
No paid model requests or personal-mail exports occur.

This is a separately signed harness, not the distributed SpamWise app. It is not
notarized, and success does not establish acceptance of the installed app's full
entitlement, container, launch and integration configuration.

## Reproduce

From the repository root:

```sh
bash Scripts/evidence-runtime-check.sh \
  'Developer ID Application: Timothy Morgan (2NFSK2WB24)' [build-token]
```

The script compiles the package and harness with warnings treated as errors,
verifies the app signature, then runs `ocr` and `privacy`. Each run starts after
a four-second observer interval and remains alive for four seconds afterward.
`nettop -P -n -L 0 -p PID -J bytes_in,bytes_out` records one-second per-process
observations in `.build/<build-token>/ocr-network.csv` and `privacy-network.csv`.
The executable prints synthetic-case results to corresponding `.log` files.

For an observer positive control, start a temporary HTTP listener on an unused
loopback port, return a short body, and keep the connection open several seconds.
Run the same signed executable with `network-control http://127.0.0.1:PORT` and
observe that process with the same `nettop` command. This mode rejects hosts other
than `127.0.0.1`. For example, in separate terminals:

```sh
{ printf 'HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: keep-alive\r\n\r\nhello'; sleep 12; } \
  | nc -l 127.0.0.1 39863
```

```sh
probe_root=".build/<worker>"
"$probe_root/SpamWiseEvidenceProbe.app/Contents/MacOS/SpamWiseEvidenceProbe" \
  network-control http://127.0.0.1:39863 &
probe_pid=$!
nettop -P -n -L 12 -p "$probe_pid" -J bytes_in,bytes_out
wait "$probe_pid"
```

Stop the temporary listener after the control completes. Do not reuse an occupied
port. No test contacts a public blocklist or an external model service.

## Native OCR observations

On 2026-10-16, the signed sandboxed harness matched all six generated images
exactly using the production `EmbeddedImageOCR` and native Vision recognizer:

| Case | Observed text |
| --- | --- |
| Inline English PNG | Your invoice total is 42 dollars |
| Inline Spanish JPEG | Su factura total es de 42 euros |
| Inline French PNG | Votre facture est de 42 euros |
| Attachment PNG | Attached invoice total is 42 dollars |
| Static GIF | Static image total is 42 dollars |
| LZW-compressed single-image TIFF | Static image total is 42 dollars |

Each generated image is 1600 × 240 pixels with high-contrast system-font text.
The MIME fixtures include a remote image URL; only embedded bytes are recognized.
Malformed image bytes and HTML containing only a remote image URL return unknown.
The TIFF fixture uses LZW compression to stay within the production compressed
byte limit; an uncompressed rendition exceeded that limit and correctly returned
no text during fixture development.

OCR has since been limited to PNG and JPEG, so the app no longer decodes the GIF and
TIFF cases above; they record the earlier decoder.

These are favorable synthetic cases, not a representative mail-image corpus.
They do not measure low-resolution, rotated, obscured, accented-text or adversarial
recognition quality. Multi-image runtime cases remain untested here. No classification-quality claim follows from successful text recognition.

## Local-mode network observations

The privacy fixture enables OCR, RDAP, DNS reputation and local Rspamd options, and
records synthetic consent for every provider. Local
mode remains enabled throughout. It processes the synthetic message through the
production pipeline with each explicitly selected backend:

| Backend/path | Observed outcome |
| --- | --- |
| Claude, OpenAI, Gemini and Private Cloud Compute | Unclassified with configuration refusal |
| Apple on-device | Completed a dry-run verdict |
| RDAP, DNS and Rspamd evidence | No domain-age or external evidence recorded |
| Paid-request ledger | Zero reservations, zero committed dollars |

The credential boundary throws a distinct error if called; cloud cases assert
the configuration-refusal result, establishing rejection before credential access.
The on-device case requires a completed verdict, rather than treating model
unavailability as success. No action adapter is supplied and every run forces dry
run. The observed on-device verdict was Review; this one synthetic result does not
change the existing local-model quality assessment.

Neither the OCR nor privacy process produced a network-counter row during its
observed run. The same signed binary's loopback positive control received five
body bytes, and `nettop` reported 67 inbound and 219 outbound bytes, confirming
that the observer could detect permitted traffic from this harness.

These observations support the runtime guard behavior for this fixture. They
are not packet capture or proof of absence of all possible network activity.
`tcpdump -i lo0` was denied access to `/dev/bpf0`; no privilege or system setting
was changed. One-second process counters can miss activity and do not observe
delegated traffic from Foundation Models services, DNS services, child processes
or Mail.app. Independent service-aware network observation, the signed shipping
app and useful local-model quality remain broader acceptance gates.

## Remaining optional-service gates

The run's logs and network counters contain synthetic data only; the harness's
temporary classification store is removed, and generated images exist only in
memory. A separate [temporary native Rspamd probe](rspamd-runtime.md) verifies real
scanner symbols through the production HTTP adapter. DNS-service eligibility, terms
acknowledgement and an attributable configured resolver remain separate user and
service prerequisites; no public DNSBL queries were made for this probe.

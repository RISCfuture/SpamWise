# Local attachment inspection evaluation

## Decision

Keep production document extraction limited to bounded plain text and lexical
HTML. PDF, Office documents, archives and other unsupported formats remain unknown
content, never spam or malware evidence. PDFKit is suitable for a future isolated
text worker, but its parsing allocations are not bounded by the caller's byte,
page or output limits. Do not add it to the app, extension or pipeline process.

`DocumentInspection(raw:)` reuses `MIMEParser`, returns the parsed message, and
reports `extracted`, `unsupported` or `unavailable` for each attachment's declared
MIME labels. A failed optional text decode preserves the body-only parse and marks
all supported attachments unavailable. This conservative fallback cannot claim
partial success for a message whose attachment decoding failed. Named MIME parts
and inline `application/*` parts also appear in coverage, even without an explicit
attachment disposition. MIME names and types are untrusted claims.

Plain text and HTML retain the parser's 2 MB message, 64 KB attachment source,
128-part and 12-level limits. HTML conversion does not load a browser, execute
scripts, resolve local paths or fetch remote resources. Decoded text is untrusted
classifier input. Empty decoded text does not establish absence of malicious
content. Image OCR is separate from document text coverage; its success does not
establish document or malware inspection.

## Reproducible PDF probe

`Scripts/document-probe.swift` creates synthetic fixtures, runs PDFKit extraction
in a fresh child process per fixture, compares actual outcomes, and deletes the
temporary fixtures. No message content, credential, Mail access or API call is
used. The probe is a developer tool, not a production helper.

From the repository root, use an isolated worker token:

```sh
worker="$(agent-lock worker)"
export AGENT_WORKER_ID="$worker"
probe_root=".build/$worker/document-probe"
mkdir -p "$probe_root"
swiftc -swift-version 6 -strict-memory-safety -warnings-as-errors \
  -module-cache-path "$probe_root/cache" Scripts/document-probe.swift \
  -o "$probe_root/document-probe"
"$probe_root/document-probe"
```

Observed on 2026-10-16 with Swift 6.4 and the macOS 27 SDK:

| Synthetic case | Observed outcome |
| --- | --- |
| Ordinary text PDF | Extracted the expected 15 characters |
| PDF declaring a JavaScript open action | Extracted only the expected 15 text characters |
| User-password encrypted PDF | Rejected as encrypted |
| Owner-password encrypted PDF with empty user password | Rejected as encrypted |
| Truncated malformed PDF | Rejected as malformed |
| 524,289-byte input | Rejected before PDFKit construction |
| 13-page PDF | Rejected before page text extraction |
| More than 3,000 text characters | Returned exactly 3,000 characters |
| Worker sleeping past the three-second deadline | Parent killed and reaped the child; unknown result |
| Worker exiting with status 42 | Parent returned worker failure; unknown result |

The parent enforces a three-second wall-clock deadline by killing the child,
rather than merely cancelling a Swift task. Each worker also installs a
two-second CPU resource limit. The hung-worker fixture exercises parent termination;
it is deliberately synthetic, not a discovered PDFKit hang. Byte limits apply
before PDFKit construction. Page limits apply after construction, and text limits
apply after PDFKit produces an individual page's string. These limits do not
bound PDFKit's intermediate memory allocations. No memory ceiling was established.

The active-content fixture checks the text-only extraction path; it is not a
malware detector or a comprehensive malicious-PDF security test. The probe never
opens a PDF view or invokes PDF actions. Its child processes share the enclosing
tool environment's permissions. Separate address spaces and termination provide
failure containment, not a new sandbox or verified network/filesystem denial.

## Production isolation gate

Before supporting PDFs in production, add a bundled, signed XPC service with its
own App Sandbox, no network, Automation, shared Keychain or App Group entitlements,
and a bounded byte-in/text-out protocol. Validate service identity, termination,
interruption recovery and memory behavior under adversarial fixtures in the
signed app. Do not pass file URLs or security-scoped access to the worker. Office
and archive decoders require separate evaluations; do not execute macros, unpack
arbitrary paths or call Quick Look as a substitute for a restricted parser.

Apple distinguishes child-process inheritance from the stronger privilege
separation of a separately sandboxed XPC service. See
[App Sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
and [XPC](https://developer.apple.com/documentation/xpc).
PDFKit automatically unlocks PDFs with an empty user password, so a locked-state
check alone cannot reject all encrypted documents. The probe checks both
`isEncrypted` and `isLocked`; see
[PDFDocument.isLocked](https://developer.apple.com/documentation/pdfkit/pdfdocument/islocked).

The isolated evaluation is complete for these synthetic cases. Production PDF
support, shipping integration of the isolated helper, hard memory containment and comprehensive
malicious-document acceptance remain unimplemented. No attachment receives a
"clean" malware result from this feature.

## Signed XPC follow-up

The [DocumentWorker harness](../../Tools/DocumentWorker/README.md) now implements
and executes a separate Developer ID signed, sandboxed XPC worker with mutual
code requirements, bounded byte/text messages and worker-owned CPU, wall-time
and sampled resident-memory limits. It includes document, authentication,
interruption/recovery and sandbox-access probes, plus a build excluding diagnostic
entry points. It does not change production attachment support or embed a worker
in SpamWise's shipping targets.

Two integration constraints remain explicit: macOS throttles repeated XPC process
launches by roughly ten seconds, and the memory watchdog is not a hard allocation
ceiling. `RLIMIT_AS`/`RLIMIT_RSS` configuration returned `EINVAL`; the sampled
128 MiB watchdog observed a higher resident size before termination. The harness
documents a concrete shipping integration plan without claiming these unresolved
limits or signed-distribution acceptance are complete.

## Containment and cancellation follow-up

[PDF containment research](pdf-containment.md) distinguishes protocol bounds,
parser-allocation budgets and whole-process memory ceilings. The evaluated public
macOS APIs do not close the hard-memory gate. MuPDF's custom allocator and a
bounded WebAssembly guest are concrete follow-up experiments; neither has been
integrated or established as a whole-process cap. Licensing and enabled decoder
dependencies must be resolved for any chosen parser.

The signed harness retains one document per process and adds cancellation that
resolves the caller exactly once and invalidates its connection. The active
worker exits on connection loss. Native probes cover already cancelled requests,
in-flight cancellation, client serialization, duplicate/late completion handling
and recovery in a new process. The roughly ten-second relaunch delay remains;
connection closure is not itself an OS exit acknowledgement. Production support
and the original hard-memory requirement remain unchanged.

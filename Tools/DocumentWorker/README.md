# Isolated PDF document-worker harness

This tool builds and executes a signed app containing a separately sandboxed XPC
service. It does not change SpamWise's project, app settings, parsing pipeline or
supported production attachment formats. All inputs are generated synthetic PDFs.
No personal mail, external model, provider credential or paid API request is involved.

## Architecture

- `Protocol.swift` defines the byte-in/text-out interface, response schema, limits
  and exact team/bundle requirements.
- `PDFExtraction.swift` performs text extraction inside the service. The host's
  PDFKit use only generates trusted synthetic fixtures.
- `Worker.swift` authenticates the caller, accepts one job per process, runs the
  parser off the XPC callback queue, and installs resource watchdogs.
- `Client.swift` authenticates the worker before sending document bytes, rejects
  oversized input and malformed responses, and completes each reply exactly once,
  including cancellation racing continuation installation.
- `WorkerProbes.swift` contains fault/access injection compiled only with
  `DOCUMENT_WORKER_PROBE`; it is absent from the production worker build.
- `Fixtures.swift`, `ProbeHost.swift` and `check.sh` drive the native acceptance
  cases, sign bundles, verify signatures and check access denial.
- `ExtractionChecks.swift` and `extraction-check.sh` run extraction in process,
  without signing, and check that Devanagari, Hindi and combining-mark text is
  truncated within the reply limits.

The worker has exactly the `com.apple.security.app-sandbox` entitlement. It has
no network, Automation, App Group, shared Keychain, file-selection or inheritance
entitlement. Its own container and the system resources allowed by App Sandbox
remain accessible; this is not a claim that all filesystem access is denied.

Both peers set `NSXPCConnection.setCodeSigningRequirement` before activation.
The requirements check an Apple signing anchor, team `2NFSK2WB24`, the exact
bundle identifier and the presence of App Sandbox. The service also checks that
the peer's effective user matches its own. An identity reply is compared with
the connection's public `processIdentifier`; the PID is diagnostic, not a
substitute for signature authentication. The client never sends signals to a
PID, avoiding a PID-reuse race. The worker terminates itself.

The listener uses the connection-level requirement because Apple's listener-level
requirement API is unsupported for `NSXPCListener.service()`. See Apple's
[connection requirement documentation](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:))
and the installed `NSXPCConnection.h` comments.

## Limits and failure behavior

| Boundary | Limit and behavior |
| --- | --- |
| Input | 524,288 bytes, checked before IPC and again before PDFKit |
| Pages | At most 12, checked after PDFKit constructs the document |
| Text | At most 3,000 characters and 16,256 JSON-encoded bytes, cut at a character boundary; failed extraction returns no partial text |
| Encoded response | At most 16,384 bytes, checked before reply and before JSON decoding |
| Worker CPU | Two seconds through `RLIMIT_CPU`, per fresh process |
| Worker wall clock | Three-second independent watchdog |
| Resident-memory watchdog | 128 MiB threshold, sampled every 10 ms |
| Client connection | Twelve-second upper deadline to accommodate observed relaunch throttling |
| Client request | Four-second reply deadline after authenticated connection |
| Concurrent work | A client returns busy while active; the service accepts one parsing job per process |
| Cancellation | An already cancelled task launches no connection; in-flight cancellation closes the connection and active worker exits |

The text byte budget counts each character's UTF-8 size, and six bytes for an ASCII
character JSON may escape, so the encoded reply always fits. Scripts with several
scalars per character, such as Devanagari conjuncts or stacked combining marks, reach
the byte budget before the character limit.

Byte and character checks are protocol acceptance bounds, not promises about
intermediate allocations. PDFKit can allocate before page and text checks.
NSXPC decodes its `Data` argument before the receiving method can inspect its
length. Caller authentication limits who can supply input, but response-size
validation does not establish a preallocation limit against a compromised worker.

Encrypted PDFs are rejected even if an empty user password would unlock them.
The service reads page strings; it does not open a document view, execute PDF
actions, unpack archives, run macros or invoke Quick Look. Extracted text is
untrusted content, never a malware verdict or evidence that an attachment is safe.

The worker's wall/CPU/memory exits and any XPC failure become unavailable text.
Invalid JSON or excessive returned text becomes an invalid reply. No document
retry occurs inside the client. Later independent requests can start a new
worker. Cancellation closes the active connection; its worker exits on connection
invalidation. The first terminal completion wins over duplicate/late callbacks.
`connectionClosed` records transport closure, not an OS process-exit acknowledgement.
A shutdown message is sent only after a response from a live worker;
sending one after interruption could launch a replacement solely to shut it down.

## Reproduce

The extraction checks need no signing identity:

```sh
bash Tools/DocumentWorker/extraction-check.sh <build-token>
```

The full harness runs them first, then the signed cases:

```sh
bash Tools/DocumentWorker/check.sh <build-token> \
  'Developer ID Application: Timothy Morgan (2NFSK2WB24)'
```

Expect several minutes because macOS throttles repeated service launches. The
script builds both instrumented and non-instrumented workers, signs with hardened
runtime, verifies signatures and executes both. It temporarily listens only on
`127.0.0.1:39864`; an occupied port aborts the check. A successful local connection
from the shell establishes that the listener exists before testing service denial.
Temporary marker files and the listener are removed after use.

The build token is any name of letters, digits and hyphens. Results and signed
bundles are retained in `.build/<build-token>/document-worker/`.
`results.log` covers document, identity, resource and recovery cases;
`sandbox.log` covers network and filesystem denial; `unauthorized.log` checks an
otherwise valid, same-team signed caller with the wrong bundle identifier;
`production.log` exercises extraction with a worker compiled without fault/access
injection. The production binary is also checked for diagnostic symbols.

Lint with the actual Swift files, because the repository SwiftLint directory
configuration does not include `Tools/`:

```sh
swift format lint --strict Tools/DocumentWorker/*.swift
swiftlint lint --strict Tools/DocumentWorker/*.swift
shellcheck Tools/DocumentWorker/check.sh
markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc Tools/DocumentWorker/README.md
```

## What the signed harness shows

The full signed check makes 28 request observations plus three direct
completion-order checks. Ordinary, JavaScript-action, encrypted, owner-password,
malformed, oversized, page-limit and text-limit fixtures give their expected
outcomes. Hung, abruptly exited, CPU-bound and growing-memory workers are terminated,
and the next ordinary document extracts successfully in a different worker process.
Wrong service identity, malformed JSON and excess returned text are rejected.
In-flight cancellation returns to the caller in well under a millisecond, and
recovery extracts the ordinary fixture in a new worker; that is evidence for a
controlled run, not a guaranteed OS scheduling or memory-reclamation bound.

Both a live loopback connection and file reads outside the worker's container
return `EPERM`, for a shell-created marker in the build directory and for a file the
host created in its own container's temporary directory. An otherwise valid
Developer ID signed app with the same team but a different bundle identifier is
rejected before receiving a worker identity. A worker built without diagnostic entry
points extracts the ordinary fixture, and deep strict signature verification passes.

The CPU probe exits with `SIGXCPU` after about two seconds of CPU time, according to
launchd. The wall-time probe logs its watchdog termination and returns unavailable
text about three seconds after connecting. These artifacts contain synthetic inputs
and process diagnostics only.

The memory watchdog terminates workers at around 139 to 149 million resident bytes
against its **134,217,728-byte** threshold. That overshoot is expected from sampling
and is direct evidence that this is **not a hard allocation ceiling**. A faster or
larger allocation could overshoot much further or cause system pressure before the
watchdog runs. The synthetic fixture grows memory in 16 MiB steps; it does not
establish behavior for every PDFKit allocation pattern.

Setting `RLIMIT_AS` to 16 MiB returned `-1` with `EINVAL` in both a standalone
probe and the signed worker. The SDK aliases `RLIMIT_RSS` to `RLIMIT_AS`; Apple's
[setrlimit manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setrlimit.2.html)
describes the historical resident-set limit in terms of memory-pressure preference.
This implementation does not use private memorystatus APIs or claim a reliable
public hard memory cap.

Launchd spaced consecutive worker starts by roughly ten seconds, including clean
exits. An initial four-second connection timeout therefore failed open; the probe
uses twelve seconds for connection establishment while retaining a four-second
request deadline. The twelve-second connection allowance is for this isolated
evaluation, not a measured safe Mail callback deadline. These delays are visible
in both the host timings and launchd logs. No undocumented launchd/XPC setting is
used to bypass the OS behavior.

## Cancellation and lifecycle follow-up

The harness retains one job per process, preserving allocation reclamation and
per-process CPU accounting. It adds immediate and in-flight cancellation, a
client busy check, new-process recovery, and direct completion-latch races before
continuation installation and after completion. The caller must finish within
one second after in-flight cancellation, independently of launch time. Native
XPC callbacks are not claimed to reply multiple times; duplicate and late
completion tests directly drive the same latch used by those callbacks.

See [PDF containment research](../../docs/probes/pdf-containment.md) for evaluated
public OS mechanisms, allocator-controlled parser alternatives, licensing,
lifecycle reasoning and the remaining hard-memory gate. Reuse is deliberately
not adopted: resetting a process CPU limit would not reset accumulated CPU time,
and reuse requires separate accounting and memory-reclamation acceptance.

## Concrete shipping integration plan

1. Add a macOS XPC-service target containing `Protocol.swift`, `PDFExtraction.swift`
   and `Worker.swift`; never compile `WorkerProbes.swift` or define
   `DOCUMENT_WORKER_PROBE` for shipping. Preserve the minimal sandbox and hardened
   runtime. Embed/sign it inside the app, with no shared data/keychain entitlement.
2. Replace the harness caller identifier with explicit authorized shipping
   identifiers. Keep team/bundle requirements on both connections and rerun wrong
   caller/service checks against the actual exports.
3. Add an app integration client using a narrow core protocol; keep NSXPC and
   PDFKit out of the pure core modules. Pass already bounded PDF bytes, never a
   file URL, bookmark or security-scoped resource. Reuse `PDFExtraction.swift`'s
   byte-bounded `BoundedText` for the returned text. The headless daemon
   needs its own validated hosting design; a service embedded in the app is not
   automatically available to it.
4. Retain the evaluated one-document lifecycle unless a replacement is validated. One document per process
   reclaims the process's allocations but encounters the observed launch delay.
   Reusing one serialized service across successful jobs could reduce latency,
   but requires different per-job CPU accounting, idle/memory recycling and new
   acceptance tests. Fail open while a replacement cannot start; do not extend
   Mail deadlines based solely on this harness.
5. Preserve an overall extraction budget, cancellation and explanation of unknown
   attachment content. Append successful bounded text only as escaped untrusted
   context. OCR, PDF text extraction and malware assessments remain separate.
6. Verify the chosen lifecycle, container denial, code requirements, cancellation,
   interruption recovery and resource behavior in Developer ID and App Store
   exports. Use adversarial PDFs and representative documents to assess utility.

The strict hard-memory-containment requirement remains unresolved. If it remains
mandatory, keep production PDFs unsupported until a suitable bounded parser or
enforceable OS containment mechanism is established. A signed sandbox and a
successful watchdog probe do not close that gate.

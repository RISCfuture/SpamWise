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
  oversized input and malformed responses, and completes each reply exactly once.
- `WorkerProbes.swift` contains fault/access injection compiled only with
  `DOCUMENT_WORKER_PROBE`; it is absent from the production worker build.
- `Fixtures.swift`, `ProbeHost.swift` and `check.sh` drive the native acceptance
  cases, sign bundles, verify signatures and check access denial.

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
| Text | At most 3,000 characters; failed extraction returns no partial text |
| Encoded response | At most 16,384 bytes, checked before reply and before JSON decoding |
| Worker CPU | Two seconds through `RLIMIT_CPU`, per fresh process |
| Worker wall clock | Three-second independent watchdog |
| Resident-memory watchdog | 128 MiB threshold, sampled every 10 ms |
| Client connection | Twelve-second upper deadline to accommodate observed relaunch throttling |
| Client request | Four-second reply deadline after authenticated connection |
| Concurrent work | A client returns busy while active; the service accepts one parsing job per process |

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
worker. A shutdown message is sent only after a response from a live worker;
sending one after interruption could launch a replacement solely to shut it down.

## Reproduce

```sh
worker="$(agent-lock worker)"
bash Tools/DocumentWorker/check.sh "$worker" \
  'Developer ID Application: Timothy Morgan (2NFSK2WB24)'
```

Expect several minutes because macOS throttles repeated service launches. The
script builds both instrumented and non-instrumented workers, signs with hardened
runtime, verifies signatures and executes both. It temporarily listens only on
`127.0.0.1:39864`; an occupied port aborts the check. A successful local connection
from the shell establishes that the listener exists before testing service denial.
Temporary marker files and the listener are removed after use.

Results and signed bundles are retained in `.build/<worker>/document-worker/`.
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

## Observed OS constraints

The final signed run on 2026-10-16 passed 24 native checks. It processed ordinary,
JavaScript-action, encrypted, owner-password, malformed, oversized, page-limit and text-limit fixtures with the
expected outcomes. Hung, abruptly exited, CPU-bound and growing-memory workers
terminated; subsequent independent ordinary documents extracted successfully.
Wrong service identity, malformed JSON and excess returned text were rejected.

Both a live loopback connection and file reads outside the worker's container
returned `EPERM`. The files existed: one was a shell-created synthetic marker in
the build directory, and the other was created by the host in its own container's
temporary directory. An otherwise valid Developer ID signed app with the same
team but a different bundle identifier was rejected before receiving a worker
identity. A separately built worker without diagnostic entry points extracted the
ordinary fixture successfully; deep strict signature verification passed.

The final worker CPU probe exited with `SIGXCPU` after 2,032 ms according to
launchd. The wall-time probe logged its watchdog termination and returned
unavailable text in 3.005 seconds when already connected. The memory probe logged
138,936,320 resident bytes at termination. An earlier signed run observed the
larger overshoot described below. Each resource failure was followed by a
successful ordinary extraction in a different worker PID.

Evidence is retained in
`.build/485dd0e3-6675-44be-8612-25b075ed2453/document-worker/`, including
`results.log`, `sandbox.log`, `unauthorized.log`, `production.log`, signed bundles
and `resource-evidence.log`. The enclosing `document-worker-final.log` records the
whole successful command. These artifacts contain synthetic inputs and process
diagnostics only. They are local evidence, not committed distribution artifacts.

The memory watchdog logged a resident size of **148,520,960 bytes** when terminating
a worker against the **134,217,728-byte** threshold. That overshoot is expected
from sampling and is direct evidence that this is **not a hard allocation ceiling**.
A faster or larger allocation could overshoot much further or cause system pressure
before the watchdog runs. The synthetic fixture grows memory in 16 MiB steps;
it does not establish behavior for every PDFKit allocation pattern.

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
   file URL, bookmark or security-scoped resource. The daemon and Mail extension
   need their own validated hosting design; a service embedded in the app is not
   automatically available to those processes.
4. Decide the lifecycle/latency policy explicitly. One document per process
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

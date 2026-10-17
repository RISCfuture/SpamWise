# PDF containment decision

Research checked on 2026-10-16. Production PDFs remain unsupported. The signed
DocumentWorker harness establishes privilege separation and bounded protocol
acceptance; it does not establish a hard process-memory ceiling. No new parser,
shipping target, entitlement or paid service is introduced by this investigation.

## What must be bounded

There are three distinct requirements: reject oversized inputs and outputs;
stop excessive computation; and prevent excessive intermediate allocation before
it occurs. The harness establishes the first and exercises termination for the
second. Its sampled 128 MiB resident-memory watchdog cannot establish the third:
a previous signed run reached 148,520,960 bytes before termination. A single large
allocation or a delayed watchdog could overshoot by much more.

A parser-allocation budget also differs from a process-RSS cap. Runtime metadata,
thread stacks, shared frameworks, IPC decoding and allocator bookkeeping may sit
outside that budget. Any proposed replacement must name precisely what its bound
covers. The existing NSXPC `Data` argument is decoded before the receiver checks
its size, so it is not a preallocation bound against a compromised peer either.

## Public macOS mechanisms

| Mechanism | Evidence and conclusion |
| --- | --- |
| `RLIMIT_AS` / `RLIMIT_RSS` | The signed harness returns `EINVAL` when setting a finite limit. The SDK aliases RSS to AS. It cannot support this implementation's hard-cap claim. |
| `RLIMIT_DATA` / `RLIMIT_STACK` | These describe the data segment and stack, not a complete budget for framework VM allocations, mapped buffers, IPC and all thread stacks. No whole-process bound follows. |
| `RLIMIT_CPU` | A useful per-process CPU limit, retained at two seconds. Reuse would consume the same cumulative allowance across documents. |
| `os_proc_available_memory` | Advisory observation of available memory; it does not install a caller-selected quota. |
| Dispatch memory-pressure notifications | A request to release memory when system pressure changes; no synchronous allocation admission control. |
| App Sandbox / XPC | Restricts access and separates process failures. It does not provide a documented per-service memory-budget setting in the APIs evaluated here. |

Sources: Apple's [resource-limit manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setrlimit.2.html),
[resource constants](https://github.com/apple/darwin-xnu/blob/main/bsd/sys/resource.h),
[available-memory API](https://developer.apple.com/documentation/os/os_proc_available_memory),
[memory-pressure event](https://developer.apple.com/documentation/dispatch/dispatch_memorypressure_critical),
and [XPC service architecture](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html).
The negative conclusion is scoped to these public mechanisms and the observed
runtime, not a claim to have proved that no future OS mechanism can exist.
Private memorystatus calls, disabling sandboxing, privileged helpers and allocator
interposition into PDFKit are not adopted.

## Established parser alternatives

| Candidate | Relevant capability | Decision and remaining work |
| --- | --- | --- |
| MuPDF | Fitz exposes caller-supplied malloc/realloc/free callbacks; failed allocation throws through its C exception mechanism. | Most direct native candidate for an allocation-budget spike. A fixed arena can reject growth before allocation. Must audit all enabled dependencies, stack use, and OOM cleanup; it does not alone cap the whole process. |
| PDFium | Established text extraction; public library configuration controls fonts, V8 and other options. | The reviewed public configuration exposes no caller-supplied allocator quota. Replacing internal allocators would require a maintained fork and proof covering dependencies; switching libraries alone closes no gate. |
| qpdf | Structural PDF transformations and defensive parser/filter limits. | Not a replacement text extractor: it does not interpret content-stream semantics. Adding a preprocessing pass introduces another parser without establishing an aggregate allocation ceiling. |
| Parser compiled to WebAssembly | Runtime linear-memory and table growth can be limited before growth succeeds. | Worth a separate spike if native allocator coverage cannot be established. Bound instance/memory/table counts, stacks and host callbacks too; a linear-memory cap is not a runtime RSS cap. No runtime was built or adopted here. |

MuPDF documents [custom allocation](https://mupdf.readthedocs.io/en/1.28.3/reference/c/fitz/memory.html)
and explicitly describes the context's [cache limit as soft](https://mupdf.readthedocs.io/en/1.28.3/reference/c/fitz/context.html).
Do not mistake `fz_new_context`'s store size for an allocation cap. Its publisher
offers [AGPL and commercial licensing](https://mupdf.com/releases); adopting it
requires choosing an appropriate distribution license and reviewing bundled
third-party notices. This research does not purchase or select a commercial license.

PDFium's [public configuration header](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdfview.h)
and [license file](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/LICENSE)
were inspected. The license file includes BSD-style terms and Apache 2.0 text;
bundled dependencies require their own notice inventory. qpdf uses
[Apache 2.0](https://qpdf.readthedocs.io/en/stable/license.html), describes its
[structural scope](https://qpdf.readthedocs.io/en/stable/overview.html), and lists
[parser/filter limits](https://qpdf.readthedocs.io/en/latest/qpdf-options.html).
For the WebAssembly option, Wasmtime documents
[per-memory growth limits and instance/table counts](https://docs.wasmtime.dev/api/wasmtime/struct.StoreLimitsBuilder.html)
and [host-import isolation](https://docs.wasmtime.dev/security.html). Its
[license](https://github.com/bytecodealliance/wasmtime/blob/main/LICENSE) is Apache
2.0 with the LLVM exception; the guest parser retains its separate license. A future
prototype must pin versions and select an execution mode compatible with the
existing hardened runtime; no JIT entitlement is authorized by this design.

## Lifecycle decision and implementation

Retain one parsing job per process. This reclaims the parser's allocations on
exit and keeps the two-second process CPU allowance meaningful for each document.
The observed roughly ten-second launchd restart throttle remains a latency cost.
This is an evaluation policy, not a justification to extend Mail deadlines.

The client now treats cancellation as a terminal unknown result. An already
cancelled task returns before connection activation. Cancellation during identity
or response waiting resolves a lock-protected completion latch, including the
race where cancellation happens before the continuation is installed. Completion
is first-wins; duplicate and late callbacks cannot resume the continuation again.
The actor then invalidates the connection. It waits at most one additional second
for connection closure independently of the cancelled task's state.

The worker records whether its own connection has started a job. Losing that
connection exits the process, including the race between request admission and
starting the parser. Disconnecting an unrelated idle connection cannot kill an
active job. Work stays off the XPC callback queue, so connection invalidation can
be handled while parsing is stuck. The watchdog remains a fallback. No PID is
signalled and no shutdown request is sent after an interruption.

`connectionClosed` reports transport closure, not an OS exit acknowledgement.
Native recovery checks require a different worker PID. OS termination evidence
must be evaluated separately; connection invalidation alone is not proof of
memory reclamation. Cancellation cannot guarantee scheduler response during
system-wide resource exhaustion or stop an already compromised worker from
ignoring application-level handlers.

The signed harness covers immediate cancellation without a worker PID, in-flight
cancellation with a sub-second caller-completion assertion, busy rejection while
the original request is pending, and successful extraction in a different process
after cancellation. It also drives the same completion latch before continuation
installation, twice synchronously, and after the first result was consumed. These
are client race tests executed in the signed host, not a claim that NSXPC delivers
multiple replies for a single reply block. Existing malformed-reply, watchdog,
identity, access-denial and recovery probes remain in the full run.

## Next implementable experiment

The most direct next step is a separately built MuPDF text-only worker with a
fixed arena and checked allocation accounting. Keep C exception handling inside a
C wrapper, return a small typed failure to Swift, and retain the current sandbox,
CPU deadline and process lifecycle. Pin the source and dependency build; disable
unneeded formats, scripts and rendering paths where supported. Audit whether
fonts, codecs and decompression use the chosen allocator or need separate bounds.

Acceptance must include allocation failures at every allocation site reached by
the fixtures, realloc growth and integer overflow, high-expansion streams, large
object graphs, deep recursion, repeated malformed inputs, cleanup after OOM,
zero partial output, cancellation and recovery. Record both arena high-water
usage and full-process memory, explicitly accounting for the difference. A test
suite passing on finite fixtures is supporting evidence, not a proof covering
all native parser allocations or memory-corruption paths.

If the requirement is an OS-enforced cap on the entire worker under arbitrary
native-code compromise, an allocator-controlled native parser does not meet it.
Keep PDFs unsupported under that requirement until a suitable enforcement
boundary is established. Reuse, packaging and corpus evaluation cannot remove
this distinction.

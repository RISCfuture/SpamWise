# Rspamd sandbox transport probe

The production Loopback HTTP adapter sends bounded synthetic RFC822 mail to a
temporary native Rspamd 4.2.2 normal worker, source commit
`a5bf035b85ba90415a81b8461ce6a3ad724a14d1`, through `POST /checkv2`, the supported
[Rspamd scanning protocol](https://docs.rspamd.com/developers/protocol/).
`Scripts/rspamd-runtime-check.sh` owns the temporary worker and configuration;
it refuses occupied ports and never modifies a global service. The configuration
contains only a synthetic regexp rule. A separate process sandbox denies the
server's non-loopback network access, including external DNS checks.

The client harness is Developer ID signed with hardened runtime, App Sandbox and
the same outbound-network entitlement used by SpamWise. It adds no filesystem,
process-execution, temporary-exception, server-network, or ATS entitlement.
Only generated messages with `.invalid` addresses are supplied. No user mail,
credentials, model calls, paid services, or public blocklist queries are involved.

## Reproduce

Build native Rspamd separately from its pinned source package, then build the
client harness with `Scripts/evidence-runtime-check.sh`. Keep an unsigned copy of
the compiled harness executable before signing, for the executable comparison.
Pass absolute paths:

```sh
bash Scripts/rspamd-runtime-check.sh <worker-token> \
  <rspamd-source-directory> <rspamd-build-directory> \
  <unsigned-probe-executable> <signed-probe-app-executable>
```

The script uses `127.0.0.1:11333` for the scanner and `127.0.0.1:11334` for a
synthetic redirect trap. Both must be unused. It terminates only processes it
starts, removes its temporary configuration and verifies that both listeners
have stopped. It preserves logs beneath `.build/<worker-token>/rspamd/`.

## Observed results

Worker `053e029e-a477-4600-94f0-b8d53af1b4d7` on macOS 27 / Swift 6.4:

| Check | Result |
| --- | --- |
| Native unsigned executable, marker message | Observed `SPAMWISE_PROBE: 1.5` |
| Native unsigned executable, ordinary message | Observed, no symbols |
| Signed sandbox executable transport | Unknown, `NSCocoaErrorDomain:4` |
| Signed sandbox HTTP, marker message | Observed `SPAMWISE_PROBE: 1.5` |
| Signed sandbox HTTP, ordinary message | Observed, no symbols |
| Stopped native server, both transports | Unknown |
| HTTP 307 redirect to a second loopback listener | Unknown; no redirected request |
| HTTP response above 64 KiB without Content-Length | Unknown |
| HTTP 503 | Unknown |
| Stalled response | Unknown within five-second probe bound; connection closed |
| Caller cancellation | Unknown within one second; connection closed |
| Concurrent marker and ordinary scans | Independent expected symbol results |

The synthetic HTTP fixture also checks HTTP 307 redirects against a second
loopback listener, undeclared-length oversized responses, HTTP 503, a stalled
response, explicit cancellation and concurrent independent scans. Its server log
must contain no redirected request or invalid request, and must observe closed
connections for stalled and cancelled scans.

This establishes a sandbox-compatible transport to the normal worker without
launching an external program. It does not establish representative spam
accuracy, administrator-supplied Rspamd configuration, actual incoming Mail
callbacks, App Review acceptance, or authentication of whichever local process
owns port 11333. The optional feature remains disabled until explicitly selected;
existing executable selections are not migrated to HTTP.

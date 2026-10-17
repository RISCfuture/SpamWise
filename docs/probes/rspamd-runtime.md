# Disposable native Rspamd acceptance probe

## Scope and result

On 2026-10-16, a native Rspamd 4.2.2 source build processed synthetic messages
through the production `RspamdLookup` and `EvidenceProcess.live`. No personal
mail, public blocklist, external model, paid API call or live SpamWise setting
was used. The test loaded one local regular-expression rule, not Rspamd's normal
network checks or trained filtering configuration.

| Boundary | Synthetic marker | Ordinary synthetic body |
| --- | --- | --- |
| Unsandboxed production adapter, daemon running | Observed `SPAMWISE_PROBE: 1.5` | Observed, no symbols |
| Developer ID signed App Sandbox harness, same client and daemon | Unknown | Unknown |
| Unsandboxed adapter after daemon shutdown | Unknown | Unknown |

The sandboxed launch failed with `NSCocoaErrorDomain:4` before a scanner response.
The identical client path worked from the unsandboxed adapter. This establishes
the safe unknown result for this external-client arrangement; it does not
establish permission to execute a user-installed client from the shipping app.
No entitlement, transport or production adapter was changed to bypass that gap.

The native scanner log recorded zero DNS requests for both accepted scans.
The service listened only on `127.0.0.1:11333`, with one normal worker and no
controller. Its temporary configuration loaded only the regexp filter and no
Lua plugins, and pointed its unused resolver at loopback port 9. An additional
`sandbox-exec` profile denied network access except inbound localhost port 11333
and outbound localhost. This profile is a disposable probe restriction, not a
proposed shipping App Sandbox configuration.

These results validate process invocation, stdin transfer, the real scanner's
JSON symbol schema, bounded production decoding and unknown on unavailability.
The custom marker rule does not measure spam quality, calibration, throughput
or representative Rspamd configuration behavior. Full shipping-app optional-tool
acceptance remains open.

## Provenance and local changes

Source: [official Rspamd 4.2.2 release](https://github.com/rspamd/rspamd/releases/tag/4.2.2),
commit `a5bf035b85ba90415a81b8461ce6a3ad724a14d1`, Apache-2.0 main-project
license; bundled dependencies retain their own licenses in the source tree.
The downloaded GitHub API tarball SHA-256 was
`74c11189a74a453d2c5d2533dc05782066e26f6c4c8c210b1f250ed948b57e90`.
The source was not patched. Build and source artifacts occupy about 138 MB.

Homebrew had no `rspamd` formula. Two dependency-free bottles were installed:

- LuaJIT `2.1.1791988261`: 56 files, 2.2 MB.
- Ragel `6.11`: 13 files, 2.4 MB.

Those two developer tools remain installed. Existing CMake, Clang, GLib, PCRE2,
ICU, OpenSSL, SQLite, libsodium and libarchive supplied the other dependencies.
No Rspamd binary was installed globally, no Homebrew service or VM was launched,
and no global configuration was created. The temporary daemon, worker, listener
and generated runtime configuration were removed after the check.

The upstream C/C++ build emits warnings, including deprecated bundled C++ literal
operators and duplicate linker libraries. They are separate from SpamWise's
warning-free Swift harness compilation; no warning-free claim is made for Rspamd.

## Reproduce

The source build uses the existing macOS 27 Command Line Tools SDK consistently
with the system SQLite pkg-config metadata. Mixing that metadata's SDK include
path with Xcode's default SDK caused libc++ header-order errors, resolved by the
explicit `CMAKE_OSX_SYSROOT` below.

```sh
worker="$(agent-lock worker)"
root="$PWD/.build/$worker"
mkdir -p "$root/rspamd"
curl --fail --location --max-time 60 \
  https://api.github.com/repos/rspamd/rspamd/tarball/a5bf035b85ba90415a81b8461ce6a3ad724a14d1 \
  -o "$root/rspamd/source.tar.gz"
tar -xzf "$root/rspamd/source.tar.gz" -C "$root/rspamd"
source_root="$root/rspamd/rspamd-rspamd-a5bf035"
PKG_CONFIG_PATH=/opt/homebrew/opt/icu4c/lib/pkgconfig:/opt/homebrew/opt/openssl@3/lib/pkgconfig:/opt/homebrew/opt/libarchive/lib/pkgconfig \
  cmake -S "$source_root" -B "$root/rspamd/build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=/opt/homebrew \
  -DCMAKE_OSX_SYSROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX27.sdk \
  -DENABLE_BACKWARD=OFF -DINSTALL_WEBUI=OFF -DINSTALL_EXAMPLES=OFF \
  -DENABLE_URL_INCLUDE=OFF -DENABLE_UTILS=OFF
cmake --build "$root/rspamd/build" --target rspamd rspamc --parallel 6
```

Build the [signed evidence harness](local-evidence-runtime.md#reproduce) with
the same worker token. Compile a separate unsandboxed copy of its source against
the same package products; this is the comparison boundary, not an app change:

```sh
products="$root/swiftpm/debug"
swiftc -swift-version 6 -strict-concurrency=complete -strict-memory-safety \
  -warnings-as-errors -parse-as-library -module-cache-path "$root/cache" \
  -I "$products" -L "$products" -lSpamWiseCore \
  Scripts/evidence-runtime-probe.swift -o "$root/EvidenceProbe"
bash Scripts/rspamd-runtime-check.sh "$worker" "$source_root" \
  "$root/rspamd/build" "$root/EvidenceProbe" \
  "$root/SpamWiseEvidenceProbe.app/Contents/MacOS/SpamWiseEvidenceProbe"
```

The runtime script refuses an occupied port, generates its own configuration,
checks both adapter contexts, stops and reaps the daemon, checks the stopped
service behavior and removes transient configuration on exit. Its sandboxed
expectation is deliberately `unknown` for the arrangement observed here. A
different environment that successfully launches the client will fail that
assertion and needs its actual permissions and behavior assessed.

## Saved evidence

`.build/229c98d4-8601-49b4-ba2a-95b3b0e7f143/rspamd/` contains the source archive,
commit metadata, build logs, `runtime-check.log`, `adapter.log`,
`signed-adapter.log`, `stopped-adapter.log`, `listener.log` and `daemon.log`.
The enclosing build directory contains both harness binaries. Runtime logs
contain only synthetic messages and process diagnostics. Deep strict signature
verification passed for the signed harness.

The measured run linked the package products from
`.build/acaeba63-ddfe-4a49-99a6-640a80fd9fbe/swiftpm/debug`; those production
adapter sources were unchanged during the probe. The native runtime command
completed successfully. Swift formatting, strict SwiftLint and shellcheck passed
for the modified harness and runtime script.

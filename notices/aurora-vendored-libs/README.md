# Aurora's vendored third-party libraries

Aurora vendors the libraries it needs under `smstrikers-port/extern/aurora/extern/`. The
pinned engine revision fixes their versions, but the pinned list is **not** the shipped
list: Ballpad builds Aurora with parts of it off, so some of those libraries are never
compiled or linked. This directory covers the subset that the app actually links, each
with the verbatim text of the license that subset is offered under.

## How the set was reduced

The authoritative edge is the link line ninja itself would run for the app, in
`build/native/simulator-release/build.ninja`:

~~~text
build port/BallpadStrikers.app/BallpadStrikers: CXX_EXECUTABLE_LINKER__strikers_Release
~~~

That edge's `LINK_LIBRARIES` holds 156 tokens: 605 objects, 64 archive entries, 3 SDK
stubs and 2 FFmpeg static archives. Reducing it to the Aurora-vendored libraries leaves
eight. The reduction was then checked against the binary rather than trusted, by
counting the symbols each library contributes to it:

~~~sh
APP=build/native/simulator-release/port/BallpadStrikers.app/BallpadStrikers
nm -gU "$APP" | awk '{print $NF}' | sort -u | grep -c PATTERN
~~~

| Pattern | Symbols defined in the app | Reads as |
| --- | --- | --- |
| `absl` | 613 | abseil-cpp is linked in |
| `fmt` | 35 | fmt is linked in |
| `XXH` | 13 | xxHash is linked in |
| `ZSTD_` | 97 | zstd is linked in |
| `png_` | 125 | libpng is linked in |
| `FT_` | 53 | FreeType is linked in |
| `ImGui` | 400, of which `ImGui_Impl` 16 | Dear ImGui and a backend are linked in |
| `zng_` | 0 | zlib-ng is not linked; the SDK's `libz.tbd` is |
| `sqlite3_` | 0 | the vendored SQLite amalgamation is not linked; the SDK's `libsqlite3.tbd` is |
| `Rml_` | 0 | RmlUi is not linked |
| `tracy` | 0 | no Tracy code is in the app (see below) |

The two SDK stubs are visible on the same link line as
`.../iPhoneSimulator26.5.sdk/usr/lib/libz.tbd` and `.../libsqlite3.tbd`, which is what
the zero counts above are showing: those two come from the platform SDK as dynamic
libraries, not from the vendored copies.

## Linked, and covered here

| Library | Version | License | Notice text |
| --- | --- | --- | --- |
| abseil-cpp | 20240722.0 | Apache-2.0 | `abseil/LICENSE` |
| fmt | 12.1.0 | MIT | `fmt/LICENSE` |
| FreeType | 2.14.3 | FTL or GPLv2 (dual) | `freetype/LICENSE.TXT`, `freetype/FTL.TXT`, `freetype/GPLv2.TXT` |
| Dear ImGui | v1.91.9b-docking | MIT | `imgui/LICENSE.txt` |
| libpng | v1.6.58 | libpng-2.0 | `libpng/LICENSE` |
| xxHash | v0.8.3 | BSD-2-Clause | `xxhash/LICENSE` |
| zstd | 1.5.7 | BSD-3-Clause | `zstd/LICENSE` |
| Tracy | 6789e7d6f9a65ec98926b602097a33a9676d2606 | BSD-3-Clause | `tracy/LICENSE` |

Three details worth stating rather than leaving to be rediscovered:

- **FreeType ships three files.** `LICENSE.TXT` is a pointer document that summarizes
  the terms and names the two texts it depends on, so `FTL.TXT` and `GPLv2.TXT` are
  copied alongside it. Shipping only the pointer would ship an incomplete text.
- **abseil-cpp reaches the app through Dawn, not through Aurora's `extern/`.** Its
  archives (and therefore its `LICENSE`) come from Dawn's own third-party tree; the
  fetched copy is what was used here.
- **Tracy is on the link line but not in the app.** `_deps/tracy-build/libTracyClient.a`
  is a 2,656-byte stub containing one tiny translation unit, and the probe above finds
  no Tracy symbol in the shipped executable. The BSD-3-Clause text is included because
  the archive is on the link line; the count of Tracy code in the binary is zero.

## Vendored, and deliberately not covered

| Library | Version | Why it is not here |
| --- | --- | --- |
| RmlUi | `0ae381e00d7426762bb5ed897973366358b16642` | Ballpad configures Aurora with `AURORA_ENABLE_RMLUI=OFF`, so it is neither compiled nor linked. |
| zlib-ng | 2.3.3 | Aurora's zlib need is satisfied by the iPhoneSimulator SDK's `libz.tbd` (`/usr/lib/libz.1.dylib`); the vendored copy is unreachable and contributes no symbol. |
| SQLite | 3510300 | Aurora's SQLite VFS code links against the SDK's `libsqlite3.tbd` (`/usr/lib/libsqlite3.dylib`); the vendored amalgamation is not built. |

Leaving these out is the reduction the manifest's `verification` note asks for, and
is why this component no longer carries a `notice_gap`. Nothing here is a judgement
that RmlUi, zlib-ng or SQLite would need no notice if a future configuration did link
them; it only records that this configuration does not.

## Where these texts came from

Every file in this directory was copied byte-for-byte out of the build tree that
produced the linked binary, not retyped and not taken from a different revision:

| Notice file | Copied from |
| --- | --- |
| `abseil/LICENSE` | `build/native/deps/src/dawn/third_party/abseil-cpp/LICENSE` |
| `fmt/LICENSE` | `build/native/simulator-release/_deps/fmt-src/LICENSE` |
| `freetype/LICENSE.TXT` | `build/native/simulator-release/_deps/freetype-src/LICENSE.TXT` |
| `freetype/FTL.TXT` | `build/native/simulator-release/_deps/freetype-src/docs/FTL.TXT` |
| `freetype/GPLv2.TXT` | `build/native/simulator-release/_deps/freetype-src/docs/GPLv2.TXT` |
| `imgui/LICENSE.txt` | `build/native/simulator-release/_deps/imgui-src/LICENSE.txt` |
| `libpng/LICENSE` | `build/native/simulator-release/_deps/png-src/LICENSE` |
| `tracy/LICENSE` | `build/native/simulator-release/_deps/tracy-src/LICENSE` |
| `xxhash/LICENSE` | `build/native/simulator-release/_deps/xxhash-src/LICENSE` |
| `zstd/LICENSE` | `build/native/deps/src/zstd/LICENSE` |

`scripts/native/verify-notices.sh` checks these copies against the files the bundle
carries by SHA-256, so a copy that drifts from its source is caught.

## What this file does not claim

Collecting a license text is not the same as discharging a distribution obligation, and
identifying a library as linked is not a claim that its licensor holds every underlying
right. This file records which of Aurora's vendored libraries are in the shipped app and
which text belongs to each. The remaining distribution questions — including the
static-linkage obligations tracked for FFmpeg, and the unsettled status of reconstructed
game code — are recorded in `ATTRIBUTION.md` and
`docs/native-strikers-release-readiness.md` rather than being folded into this notice.

# Third-party notices

Ballpad's native iOS/iPadOS Strikers app ships the notice texts listed here inside the
application bundle, under `notices/`. They are byte-identical to the copies tracked in this
repository, and `scripts/native/verify-notices.sh` compares them by SHA-256 so the shipped
set cannot drift from this document or from
`docs/native-strikers-dependency-manifest.json`.

The identifiers in the first column are the component ids in that manifest.

| Component | What it is | License status | Notices shipped |
| --- | --- | --- | --- |
| `strikers` | new-coke/strikers, the native port this app is built on (pinned v1.1.1, `22649cb1`) | Port author's original material offered under CC0 1.0 within their rights; the four license texts upstream ships are reproduced | `notices/strikers/README.upstream.md`, `LICENSE-BSD.TXT`, `LICENSE-CC0.txt`, `LICENSE-GPL-2.0.txt`, `LICENSE-LGPL-2.1.txt` |
| `smstrikers-decomp` | Super Mario Strikers community decompilation by Yannick Suter and contributors | Unofficial reconstruction; no upstream grant of redistribution rights, status unresolved | `notices/smstrikers-decomp/README.md`, `LICENSE-GPL-2.0.txt`, `LICENSE-LGPL-2.1.txt` |
| `aurora` | encounter/aurora, the platform and graphics layer | MIT | `notices/aurora/LICENSE` |
| `dawn` | encounter/dawn, the WebGPU implementation Aurora drives for Metal | BSD-3-Clause | `notices/dawn/LICENSE` |
| `sdl3` | Simple DirectMedia Layer 3, windowing, input and haptics | Zlib | `notices/sdl3/LICENSE.txt` |
| `musyx` | MusyX audio middleware, vendored from the decompilation | MIT notice preserved; does not establish ownership of the reconstructed middleware | `notices/musyx/LICENSE` |
| `ode` | Open Dynamics Engine 0.5, vendored, with reconstructed changes | Historical ODE BSD-style for upstream portions; reconstructed changes unresolved | `notices/ode/LICENSE` |
| `ffmpeg` | FFmpeg, used only for THP video decode | LGPL-2.1-or-later in the mobile configuration; GPL and nonfree parts disabled | `notices/ffmpeg/COPYING.LGPLv2.1`, `notices/ffmpeg/README.ballpad.md` |
| `aurora-vendored-libs` | The third-party libraries Aurora vendors that this app actually links: abseil-cpp 20240722.0 (reaching the app through Dawn), fmt 12.1.0, FreeType 2.14.3, Dear ImGui v1.91.9b-docking, libpng v1.6.58, xxHash v0.8.3, zstd 1.5.7, and Tracy 6789e7d6, whose archive is on the link line but contributes no symbol to the app. RmlUi is off in this configuration; zlib-ng and SQLite are resolved from the SDK, so those vendored copies are not linked | Per-library: Apache-2.0, MIT, FTL or GPLv2, libpng-2.0, BSD-2-Clause, BSD-3-Clause. Reduced from Aurora's vendored list against the app's own link edge and the binary's symbol table rather than assumed | `notices/aurora-vendored-libs/README.md` and the ten per-library texts beside it |
| `googletest` | GoogleTest, used by the engine's unit tests | BSD-3-Clause; not linked into the shipped app, so no notice is bundled | none - not shipped |

## Reading these notices honestly

Where the manifest records a `notice_gap`, the notice set is knowingly incomplete and
`verify-notices.sh --final` fails until it is closed. No component carries a `notice_gap`
now. The two that did were closed with material rather than wording:

- `ffmpeg`: `scripts/native/ffmpeg-relink-offer.sh` packages the app's own captured link
  command, every link input with its SHA-256, the corresponding-source note, and a relinker
  that re-runs that command against a substituted `libavcodec.a`/`libavutil.a`. Running it
  reproduced the shipped executable byte for byte. That discharges the obligation for a
  binary shipped with this set alongside it; the details are in
  `notices/ffmpeg/README.ballpad.md`.
- `aurora-vendored-libs`: the bundle is reduced to the eight libraries on the app's link
  edge, confirmed against the binary's symbol table, with RmlUi excluded by configuration
  and zlib-ng and SQLite resolved from the SDK. Each linked library's text was copied
  byte-for-byte out of the build tree that produced the binary, and the mapping is in
  `notices/aurora-vendored-libs/README.md`.

Nothing in this directory proves that a licensor holds every underlying right in
reconstructed material, and a license file attached to a statically linked library does not
by itself discharge that library's distribution obligations. See `ATTRIBUTION.md` and
`docs/native-strikers-release-readiness.md`.

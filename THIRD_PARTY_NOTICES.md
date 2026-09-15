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
| `aurora-vendored-libs` | The third-party libraries Aurora vendors (abseil, xxHash, fmt, zlib-ng, libpng, freetype, Dear ImGui, SQLite, zstd, RmlUi, Tracy) | Per-library; collected and reduced to the actually-linked set before release | `notices/aurora-vendored-libs/README.md` |
| `googletest` | GoogleTest, used by the engine's unit tests | BSD-3-Clause; not linked into the shipped app, so no notice is bundled | none - not shipped |

## Reading these notices honestly

Where the manifest records a `notice_gap`, the notice set is knowingly incomplete and
`verify-notices.sh --final` fails until it is closed. Two gaps were open when this document
was written:

- `ffmpeg`: the LGPL-2.1 static-linkage relinking and corresponding-source obligation is
  documented in `notices/ffmpeg/README.ballpad.md` but not yet discharged by a packaged
  offer or object set.
- `aurora-vendored-libs`: the bundle still has to be reduced to the libraries the shipped
  binary actually links, each with its own verbatim license text.

Nothing in this directory proves that a licensor holds every underlying right in
reconstructed material, and a license file attached to a statically linked library does not
by itself discharge that library's distribution obligations. See `ATTRIBUTION.md` and
`docs/native-strikers-release-readiness.md`.


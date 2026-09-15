# Third-party notices shipped with Ballpad

This directory holds the verbatim notice and license texts that correspond to the
components listed in `docs/native-strikers-dependency-manifest.json`. It is copied
into the application bundle unchanged, so About/Credits can present the same texts
offline that the inventory describes.

This index is the only file here that no manifest component claims. Every other file
in the directory is claimed by exactly one component. A file that no
component claims, a component with no notice, or a bundle whose notices differ from
these copies is a failure of `scripts/native/verify-notices.sh`.

## Files by component

| Component | Files |
| --- | --- |
| `strikers` | `strikers/README.upstream.md`, `strikers/LICENSE-BSD.TXT`, `strikers/LICENSE-CC0.txt`, `strikers/LICENSE-GPL-2.0.txt`, `strikers/LICENSE-LGPL-2.1.txt` |
| `smstrikers-decomp` | `smstrikers-decomp/README.md`, `smstrikers-decomp/LICENSE-GPL-2.0.txt`, `smstrikers-decomp/LICENSE-LGPL-2.1.txt` |
| `aurora` | `aurora/LICENSE` |
| `dawn` | `dawn/LICENSE` |
| `sdl3` | `sdl3/LICENSE.txt` |
| `musyx` | `musyx/LICENSE` |
| `ode` | `ode/LICENSE` |
| `ffmpeg` | `ffmpeg/COPYING.LGPLv2.1`, `ffmpeg/README.ballpad.md` |
| `aurora-vendored-libs` | `aurora-vendored-libs/README.md`, `aurora-vendored-libs/abseil/LICENSE`, `aurora-vendored-libs/fmt/LICENSE`, `aurora-vendored-libs/freetype/LICENSE.TXT`, `aurora-vendored-libs/freetype/FTL.TXT`, `aurora-vendored-libs/freetype/GPLv2.TXT`, `aurora-vendored-libs/imgui/LICENSE.txt`, `aurora-vendored-libs/libpng/LICENSE`, `aurora-vendored-libs/tracy/LICENSE`, `aurora-vendored-libs/xxhash/LICENSE`, `aurora-vendored-libs/zstd/LICENSE` |
| `googletest` | none: it is a test-only dependency and is not shipped |

The texts were copied byte-for-byte from the pinned sources rather than retyped.
`scripts/native/verify-notices.sh` compares the shipped copies against these files by
SHA-256, so an edit here that is not mirrored in the bundle is caught. For the one bundle
entry, the set above is the libraries that actually reach the shipped binary rather than
Aurora's whole vendored list; the reduction and the symbol evidence behind it are in
`notices/aurora-vendored-libs/README.md`.

Nothing in this directory resolves an ownership question. A notice attached to
reconstructed game code does not establish that the licensor holds every underlying
right, and the presence of a license file for a statically linked library does not by
itself discharge that library's distribution obligations. See `ATTRIBUTION.md` and
`docs/native-strikers-release-readiness.md`.

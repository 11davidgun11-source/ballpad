# Aurora's vendored third-party libraries

Aurora vendors the libraries it needs under `smstrikers-port/extern/aurora/extern/`. The
pinned engine revision fixes their versions:

| Library | Version |
| --- | --- |
| abseil-cpp | 20240722.0 |
| xxHash | v0.8.3 |
| fmt | 12.1.0 |
| zlib-ng | 2.3.3 |
| libpng | v1.6.58 |
| freetype | 2.14.3 |
| Dear ImGui | v1.91.9b-docking |
| SQLite | 3510300 |
| zstd | 1.5.7 |
| RmlUi | 0ae381e00d7426762bb5ed897973366358b16642 |
| Tracy | 6789e7d6f9a65ec98926b602097a33a9676d2606 |

Exact refs are in `smstrikers-port/extern/aurora/extern/CMakeLists.txt` at the engine pin.

## Why there is only a checklist here

This is a bundle entry, not a license grant. The current Ballpad configuration disables
parts of Aurora (`AURORA_ENABLE_RMLUI=OFF`, `AURORA_ENABLE_DVD=OFF`), so not every
library above is linked into the shipped app; Dear ImGui, RmlUi and Tracy in particular
exist only on paths the app does not build. Listing them as shipped without checking the
link line would misstate the bundle either way.

Before N7 claims a passing final check, each library that is actually linked into
`BallpadStrikers` must be reduced to its real transitive set and given its verbatim
license text under this directory, with the manifest component list updated to match. The
`notice_gap` recorded against this component in the manifest is what keeps the current
state honest: `scripts/native/verify-notices.sh --final` fails until it is resolved.

Expected licenses for the libraries that the current configuration does link include
Apache-2.0 (abseil, Dawn-adjacent tooling), BSD-2/3-Clause (fmt, xxHash, zstd), Zlib
(zlib-ng), libpng-2.0, FTL/GPLv2-or-later (freetype), MIT (Dear ImGui, RmlUi) and public
domain (SQLite). Each must be confirmed against the actual vendored copy rather than
assumed from this list.

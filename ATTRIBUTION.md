# Attribution and provenance

Ballpad's native iOS/iPadOS engine is based on [new-coke/strikers](https://github.com/new-coke/strikers),
a native desktop port of Super Mario Strikers. The native port builds on the community
decompilation by [Yannick Suter and contributors](https://github.com/yannicksuter/smstrikers-decomp),
and uses [Aurora](https://github.com/encounter/aurora) and its contributors' work for
platform and graphics support. Ballpad adds the iOS/iPadOS application integration, touch
interface, and mobile build/test work. See the bundled third-party notices for dependency
licenses and provenance.

This is an unofficial project, unaffiliated with and not endorsed by Nintendo or Next Level
Games. Supply your own lawfully obtained game data. The project grants no rights to
redistribute game assets or disc images. Attribution does not grant rights to reconstructed
game code or other third-party material.

The paragraph above is the credit text required by `docs/35-native-strikers-attribution.md`.
The same text is shown in the app's About/Credits screen, which reads it from the notices
manifest bundled inside the application.

## Who did what

| Layer | Source | Relationship to Ballpad |
| --- | --- | --- |
| Native engine, port tooling, settings app | [new-coke/strikers](https://github.com/new-coke/strikers) | Adopted at a pinned revision and adapted for iOS. Upstream authorship is preserved in Git and in the exported patch series. |
| Reconstructed game code, vendored ODE physics, vendored MusyX audio middleware | [yannicksuter/smstrikers-decomp](https://github.com/yannicksuter/smstrikers-decomp) (Yannick Suter and contributors) | Present inside the pinned engine tree. Ballpad changes none of it and claims no rights in it. |
| Platform layer, Metal presentation, graphics abstraction | [encounter/aurora](https://github.com/encounter/aurora) and contributors | Vendored inside the pinned engine tree. Ballpad carries upstream patches and its own iOS build fixes. |
| WebGPU backend underneath Aurora | [encounter/dawn](https://github.com/encounter/dawn) | Built from a pinned source revision, because no iOS Simulator prebuilt slice exists upstream. |
| Window/input/haptics plumbing | [SDL3](https://github.com/libsdl-org/SDL) | Built from a pinned release tag for each platform. |
| THP movie decode | [FFmpeg](https://ffmpeg.org/) | A static, THP-only mobile build. See `notices/ffmpeg/README.ballpad.md` for the exact configuration and the relink material packaged alongside it. |
| iOS/iPadOS application, touch interface, Files importer, mobile build and test surface | Ballpad | This is the boundary: everything Ballpad authored is in the application shell, the build scripts, the test tooling and the patch series - not in the game logic or the platform libraries. |

The bullet-list credit text in the upstream README names the same three projects above it:
the decompilation by Yannick Suter, and Aurora. `notices/strikers/README.upstream.md` is that
README reproduced verbatim, including its licensing section, so the port author's own
qualifications travel with the app.

## Pinned revisions

| Component | Revision |
| --- | --- |
| `new-coke/strikers` | commit `22649cb12c112454a34217429296c95bb181af8a`, version v1.1.1 |
| Ballpad fork of the engine | branch `codex/ios-port`; every Ballpad change is exported as a patch under `patches/native-strikers/` |
| `encounter/dawn` | `1155e0ed531126f33a1279afa029349651ca1c93` (Aurora's `v20260807.225922`) |
| SDL3 | tag `release-3.4.10` |
| FFmpeg | 9.0.1, archive SHA-256 `cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635` |
| Aurora, MusyX, ODE, and Aurora's vendored libraries | whatever the engine revision pins inside `smstrikers-port/extern/`; listed with versions in the dependency manifest |

The machine-readable form of this table, including each component's license files, local
modifications, shipped targets and shipped/not-shipped state, is
`docs/native-strikers-dependency-manifest.json`. It is copied into the application bundle as
`notices/manifest.json`, and `scripts/native/verify-notices.sh` fails if the bundle, the
tracked notice files and that manifest ever disagree.

## Rights-status limitations

Attribution and the port author's CC0 offer do not clear reconstructed game code or any
third-party rights:

- **Reconstructed game code.** An unofficial source reconstruction, not an official source
  release. No upstream license grants redistribution rights for it, and its status is
  unresolved. Ballpad neither owns nor licenses it and does not present it as Ballpad work.
- **MusyX.** The upstream decompilation carries an MIT notice, reproduced at
  `notices/musyx/LICENSE`. That notice does not by itself establish that its licensors hold
  all rights in the reconstructed middleware.
- **ODE.** Upstream ODE portions use the historical BSD-style license reproduced at
  `notices/ode/LICENSE`. That license does not by itself establish the status of
  independently copyrightable game-specific modifications.
- **Aurora and its vendored libraries.** MIT and per-library licenses, reproduced under
  `notices/` for the eight libraries that reach the shipped binary. They were not
  relicensed by Ballpad, and the reduction is recorded rather than implied: see
  `notices/aurora-vendored-libs/README.md`.
- **FFmpeg.** LGPL-2.1-or-later in the mobile configuration. The static-linkage relinking
  and corresponding-source material is packaged per platform by
  `scripts/native/ffmpeg-relink-offer.sh` and was exercised by relinking the app to a
  byte-identical executable, so it is no longer merely documented. Distributing any binary
  remains a separate, still-open decision.
- **Game assets and branding.** No game data is distributed. The application bundle
  deliberately excludes game-derived icons and artwork; original simple artwork is used
  instead. Game assets needed during play are loaded from the user's own imported data.
- **Distribution policy.** The upstream project is source-only, and public availability is
  not permission. This is an engineering provenance record, not legal clearance.

## Release readiness

See `docs/native-strikers-release-readiness.md` for what is complete, what remains
unresolved, and what is explicitly out of scope for this development build.

# Attribution and provenance

BallPad is an iOS/iPadOS port of [new-coke/strikers](https://github.com/new-coke/strikers),
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

The app's About & Credits screen names these upstream projects and provides
offline notices and project details from the bundled dependency manifest.

## Who did what

| Layer | Source | Relationship to Ballpad |
| --- | --- | --- |
| Native engine, port tooling, settings app | [new-coke/strikers](https://github.com/new-coke/strikers) | Adopted at a pinned revision and adapted for iOS. Upstream authorship is preserved in the maintained fork's Git history. |
| Reconstructed game code, vendored ODE physics, vendored MusyX audio middleware | [yannicksuter/smstrikers-decomp](https://github.com/yannicksuter/smstrikers-decomp) (Yannick Suter and contributors) | Present inside the pinned engine tree. Ballpad preserves upstream authorship and claims no rights in inherited material. The maintained fork includes compatibility fixes, diagnostics, and host integration in reconstructed Game, NL, and MSL source paths; vendored ODE and MusyX are unchanged by these local adaptations. |
| Platform layer, Metal presentation, graphics abstraction | [encounter/aurora](https://github.com/encounter/aurora) and contributors | Vendored inside the pinned engine tree. The maintained source includes inherited changes and BallPad’s iOS build fixes. |
| WebGPU backend underneath Aurora | [encounter/dawn](https://github.com/encounter/dawn) | Built from a pinned source revision, because no iOS Simulator prebuilt slice exists upstream. |
| Window/input/haptics plumbing | [SDL3](https://github.com/libsdl-org/SDL) | Built from a pinned release tag for each platform. |
| THP movie decode | [FFmpeg](https://ffmpeg.org/) | A static, THP-only mobile build. See `notices/ffmpeg/README.ballpad.md` for the exact configuration and the relink material packaged alongside it. |
| Touch overlay, layout editor, input mixer and settings reference | [SunPad](https://github.com/chrissotraidis/sunpad) | GPL-3.0 interface vendored unchanged at the revision below. Ballpad adaptations live outside the vendored directory; copying the interface does not relicense it. |
| iOS/iPadOS application, touch adaptation, Files importer, mobile build and test surface | Ballpad | App integration, adaptation, tooling, and committed engine adaptations. Local edits are recorded separately from inherited game and library work. |

The bullet-list credit text in the upstream README names the same three projects above it:
the decompilation by Yannick Suter, and Aurora. `notices/strikers/README.upstream.md` is that
README reproduced verbatim, including its licensing section, so the port author's own
qualifications travel with the app.

## Pinned revisions

| Component | Revision |
| --- | --- |
| `new-coke/strikers` | commit `22649cb12c112454a34217429296c95bb181af8a`, version v1.1.1 |
| Maintained engine fork | [chrissotraidis/strikers](https://github.com/chrissotraidis/strikers), commit `37c0ad9a1d2b4fc5627943d737b9db54047f1f0e` |
| SunPad interface | `e43f0ea6b797e5110787171957c9dc3c6213269c`; file provenance and hashes in `mobile/interface/sunpad/README.md` |
| `encounter/dawn` | `1155e0ed531126f33a1279afa029349651ca1c93` (Aurora's `v20260807.225922`) |
| SDL3 | tag `release-3.4.10` |
| FFmpeg | 9.0.1, archive SHA-256 `cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635` |
| Aurora, MusyX, ODE, and Aurora's vendored libraries | whatever the engine revision pins inside `smstrikers-port/extern/`; listed with versions in the dependency manifest |

Ballpad is a separate Apple app repository, not a registered GitHub fork of the engine.
The maintained engine fork retains upstream commit history and records BallPad
adaptations as commits. Builds fetch the exact fork revision above without applying
patches. The upstream base remains recorded separately so inherited work and local
changes are distinguishable. See the
[release source audit](docs/41-release-source-audit-2026-09-16.md).

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
- **SunPad.** The touch interface is GPL-3.0, with its license preserved in
  `notices/sunpad/LICENSE` and bundled in the app. Applicable corresponding-source
  obligations remain part of any binary distribution; a notice alone is insufficient.
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

## BallPad original code

BallPad-authored application integration and build/test code is GPL-3.0-only.
[LICENSE-SCOPE.md](LICENSE-SCOPE.md) defines the boundary; this grant does not
relicense any inherited source or establish rights in reconstructed game code.

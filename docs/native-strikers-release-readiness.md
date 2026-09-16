# Native Strikers: release readiness

BallPad is an experimental iOS/iPadOS port of
[new-coke/strikers](https://github.com/new-coke/strikers). The owner reports the game
working on both iOS and iPadOS. Source publication and a fresh IPA are authorized;
this record distinguishes completed engineering work from remaining limitations.

## Source and attribution

- The maintained engine is [chrissotraidis/strikers](https://github.com/chrissotraidis/strikers),
  pinned at `37c0ad9a1d2b4fc5627943d737b9db54047f1f0e`. Its upstream base is
  new-coke/strikers v1.1.1, `22649cb12c112454a34217429296c95bb181af8a`.
- Engine adaptations are committed in that fork. Normal builds fetch its exact pin;
  they do not apply a patch series. Upstream history and authorship are preserved.
- `ATTRIBUTION.md` identifies the native port, Yannick Suter and the decompilation
  contributors, Aurora/Dawn, SDL, FFmpeg, SunPad, and the other dependencies.
- `THIRD_PARTY_NOTICES.md`, `notices/`, and the dependency manifest supply the
  inventory bundled into the app. About & Credits offers those notices offline.
- Notice verification checks inventory and packaged bytes, not ownership or the
  completeness of every source-distribution obligation.

## Hardware and known issues

Build 2 was installed and launched with game data on an iPad Pro and iPhone 14.
The owner's report that the game works on iOS and iPadOS is focused gameplay
acceptance, not full-game completion or a sustained FPS benchmark. Intro movies
and some stadium introductions have reported rendering artifacts; these remain
known reports unless separately reproduced and resolved. Two-controller local
multiplayer, sustained thermal/audio behavior, and oldest-OS compatibility need
further testing.

## Distribution material to verify for each IPA

1. Record the exact app and engine commits, version/build number, build settings,
   unsigned IPA hash, and source archive identity. Verify the actual packaged
   notices and absence of game images, extracted assets, saves, or signing secrets.
2. Include applicable SunPad GPL-3.0 corresponding source and build information
   for the combined application. A GPL license file or an upstream URL alone is
   not the corresponding-source material for the distributed build.
3. Ship the matching FFmpeg LGPL source/configuration and relink material for that
   binary. The earlier relink verification applies to its earlier executable;
   regenerate and exercise the package for the fresh candidate. Files remaining
   only in a local build directory do not accompany a public IPA.
4. Preserve the licenses of every linked library. Revisit the inventory whenever
   linkage or configuration changes, including Aurora's vendored dependencies.
5. Publish accessible source and reporting links, and verify the uploaded artifacts
   rather than treating a local archive or draft release as public delivery.

## Unresolved rights status

The native port author's CC0 offer covers their own material within their rights,
except where otherwise noted. It does not grant rights in reconstructed game code.
The decompilation is an unofficial reconstruction; its redistribution status is
unresolved. Preserved MusyX and ODE notices do not establish ownership of all
reconstructed or game-specific modifications.

Game images, assets, and saves are not included. That separation, attribution,
public fork ancestry, and an owner-authorized release do not establish clearance
of underlying material. BallPad makes no claim of Nintendo or Next Level Games
affiliation, endorsement, or permission. See `ATTRIBUTION.md` for component detail.

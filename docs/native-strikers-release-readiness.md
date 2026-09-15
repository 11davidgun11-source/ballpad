# Native Strikers: local release-readiness note

Status: development build. This note records what the attribution work has actually
completed, what remains unresolved, and what this project deliberately does not claim.
It is a local engineering record, not legal advice and not a distribution approval.

## Completed attribution work

- The engine is pinned to `new-coke/strikers` `22649cb12c112454a34217429296c95bb181af8a`
  (v1.1.1), with every Ballpad change exported as a reapplicable patch under
  `patches/native-strikers/` rather than left in the ignored working fork.
- Upstream Git authorship is preserved in the fork; no upstream commit is rewritten and no
  inherited work is presented as Ballpad-authored.
- `ATTRIBUTION.md` carries the credit text required by doc 35, including the three named
  sources, and states the local-contribution boundary explicitly.
- `THIRD_PARTY_NOTICES.md` and the verbatim texts under `notices/` cover every component in
  `docs/native-strikers-dependency-manifest.json`, copied byte-for-byte from the pinned
  sources rather than retyped.
- The machine-readable inventory is bundled as `notices/manifest.json` so the app's About/
  Credits screen can enumerate the same notices offline.
- `scripts/native/verify-notices.sh` checks inventory integrity, not ownership: schema,
  unique ids, notice coverage, orphan detection, document presence, the shipped bundle and
  the absence of game-derived branding. It fails when a shipped component lacks a notice or
  when the manifest and the resources the bundle carries disagree.

## Unresolved rights and distribution questions

1. **Reconstructed game code.** No upstream license grants redistribution rights and the
   status is unresolved. Ballpad claims no rights in it and does not treat attribution as a
   clearance.
2. **FFmpeg static linkage.** LGPL-2.1-or-later in the mobile configuration. The relinking
   and corresponding-source material is now packaged per platform by
   `scripts/native/ffmpeg-relink-offer.sh` and was exercised by relinking the app to a
   byte-identical executable, so this component no longer carries a `notice_gap`. What
   remains open is distribution itself: material sitting in a build directory does not
   accompany a binary that leaves this machine, and off-machine availability stays a
   separate decision (item 5).
3. **Aurora's vendored libraries.** Reduced from Aurora's vendored list to the eight
   libraries actually on the app's link edge, and checked against the binary's symbol table
   rather than assumed. Each linked library's verbatim text ships under
   `notices/aurora-vendored-libs/`, with RmlUi excluded by configuration and zlib-ng and
   SQLite satisfied from the SDK. This component no longer carries a `notice_gap`. A future
   configuration that links RmlUi, zlib-ng or the vendored SQLite would have to revisit it.
4. **MusyX and ODE.** Their preserved notices do not establish that their licensors hold all
   rights in reconstructed or game-specific modifications.
5. **Public source publication.** This task does not publish, push or distribute anything.
   Keeping game assets out of the bundle does not make every reconstructed source file
   cleared for redistribution; that is a separate decision with separate review.

## Physical-device and hardware status

Nothing in this build has been validated on physical hardware. Simulator results do not
establish device frame rates, sustained thermal or battery behaviour, physical controller
behaviour, or App Store readiness. Device artifacts produced here are unsigned and are not
distribution candidates.

## Scope of this development build

This is a non-public, Simulator-verified development build prepared for local use with a
lawfully obtained copy of the game data. It is not a public release, and no public push,
fork publication, binary distribution, TestFlight or App Store submission is authorized or
attempted by this work.

Label for the delivered result: **"Simulator-verified development build; hardware validation
pending."**

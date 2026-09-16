# Build 2 deployment — 2026-09-16

Version 1.0, build 2 contains the geometric black-and-white icon, revised About,
keyboard-aware reporting, compact FPS badge, and movie/scene diagnostics.

## Checks and installation

- Universal opaque 1024×1024 app icon compiled for iPhone and iPad.
- Simulator and device builds passed; final device notice check passed.
- Signed staged copy passed strict signature verification.
- Installed in place and launched on iPad Pro 12.9-inch (6th generation) and
  iPhone 14, both running iOS/iPadOS 26.6.2.
- Both runtime logs identify version 1.0 build 2 and advancing game frames.
- iPad preferences, memory card, and activation record were backed up. Initial
  update readback matched all three byte-for-byte. The existing ISO was retained.
- iPhone had no BallPad installation. The authorized ISO was copied from `ref`,
  activated locally, and read back in full. SHA-256 matched
  `da80883ba45619ce3854536d582e6af23cba461fba6383daa652138e869bfb6a`.

## Update-path repair

The first iPad update preserved the data but relocated its sandbox, exposing a stale
absolute ISO activation path. BallPad now resolves legacy container paths against
its current HOME and writes future imported Documents paths relative to HOME.
Reinstalling the repaired build booted both devices from their preserved activation
records. No saves or game data were cleared or included in the distributable app.

## Evidence and limits

Private deployment records and backups are in ignored
`build/native/deploy-geometric-20260916/`. The signed installed executable SHA-256 is
`3ea3573c32ac3e9e29a2d9eefb2e09ca74a6a945e373e671e643c21c25a7e081`.

Deployment and initial runtime are verified; reported rendering artifacts and
multiplayer acceptance remain open. No public release was published.

# 15 — Validation log (Bot 2)

Updated 2026-08-07

## Path choice
PATH=S (StrikersRecomp + GXRuntime + Aurora). iOS AOT engine linked into Ballpad app for the simulator.

## Verified on iPhone simulator (iPhone 17e, iOS 26.5)
- AOT guest boots (entry 0x80005240; Dolphin OS/VI/GX/ARQ/AI init)
- gxcore presents frames continuously (1180+ in one run; up to 23 draws / 150k verts after START taps)
- EFB readback fills 640x528 RGBA per present; SwiftUI displays the frame in the product shell
- Touch overlay + overflow menu visible; ballpad touch merge wired into guest PAD port 0
- One simulator booted per session; no ISO/dol/generated committed; no JIT/RWX

## Remaining gaps
1. gxcore projection capture: title/menu renders dark (same on macOS). Known renderer workstream.
2. Interactive touch-only match start / 60s in-match not yet proven (needs visible title + menu nav).
3. Layout persistence relaunch proof, save round-trip, overflow scale proof, iPad parity pending.

## Next
Fix projection capture or accept dark-title, drive menu via autostart START taps, then run
touch-only flow to a match; then iPad parity and DoD scoreboard.

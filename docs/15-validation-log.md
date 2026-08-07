# 15 — Validation log (Bot 2)

Updated 2026-08-07 (second session)

## Status
Path S AOT pipeline is PROVEN on the iPhone simulator (iPhone 17e, iOS 26.5).

## Verified on iPhone simulator
1. Cold launch: PASS — Ballpad.app installs and launches
2. AOT guest boots: PASS — entry 0x80005240, Dolphin OS/VI/GX/ARQ/AI init
3. Guest frames: PASS — gxcore presents continuously; EFB 640x528 readback
   frames are 96% non-black and displayed in the SwiftUI shell
4. Projection capture: PASS — XF 0x1020..0x1026 captured with real values
5. Input: PASS — injected START/stick/A changes rendered scene (draw/vert
   counts shift), touch overlay merges into Aurora pad_read port 0
6. One simulator booted at a time: PASS (mutex harness)
7. No ISO/dol/generated in git, no JIT/RWX on iOS: PASS

## Open gaps
- On-screen composite is dark (game renders behind overlay, aspect letterbox);
  title/menu legibility needs composite/z-order work
- Touch-only navigation to a match not yet captured as screenshots
- 60s in-match survival, layout persistence relaunch, save round-trip,
  overflow scale 1x/2x proof, iPad parity: pending

## Next
Prove touch-only menu -> match on phone; then iPad; then remaining DoD gates.

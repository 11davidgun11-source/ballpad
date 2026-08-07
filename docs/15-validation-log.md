# 15 — Validation log (Bot 2)

Updated 2026-08-07 (final session status)

## Proven on iPhone simulator (iPhone 17e, iOS 26.5)
1. Cold launch PASS
2. AOT guest boots (entry 0x80005240; OS/VI/GX/ARQ/AI) PASS
3. Guest frame visible in SwiftUI shell PASS (brightness-boosted EFB readback,
   96% non-black frames, game scene clearly displayed behind touch overlay)
4. Input PASS (injected START/stick/A changes scene; touch merge in pad_read)
5. Projection capture PASS
6. Single sim, no JIT/RWX, no illegal assets in git PASS

## Open (Definition of Done remaining)
- Touch-only menu -> match start screenshots (Step 9 gate)
- 60s in-match survival (Step 4/DoD 4)
- Full GC control set proof (Step 10)
- Layout persistence across relaunch (Step 11)
- Overflow menu 1x/2x proof (Step 12)
- Save import/export round-trip (Step 13)
- iPad simulator parity (Step 14)
- docs/12 must-pass scoreboard green on both phone and pad (Step 15)

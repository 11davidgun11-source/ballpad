# 15 — Validation log (Bot 2)

Updated 2026-08-07 (session 3)

## Verified on iPhone simulator
- AOT guest boots, renders visible frames in SwiftUI shell (brightness boost),
  responds to injected PAD input; projection captured. 1180+ presents in stable run.

## Verified on iPad simulator
- App boots, Aurora/SDL init (double-init guard), guest advances 5M+ blocks,
  first frame displayed 640x528. No crash with current build.

## Crashes triaged (all resolved in current build)
- "Only one window allowed per display": SwiftUI remounts host view -> double
  init of aurora; guarded with g_starting CAS.
- resolve_pass null frame packet: GX writes before first aurora_begin_frame;
  hardened with have_active_frame_packet guard.

## Open
- iPad present cadence stalls at ~4 presents (guest runs; present throttled)
- Touch-only menu->match flow, 60s in-match, layout persistence, save
  round-trip, menu scale proofs, phone+pad DoD scoreboard

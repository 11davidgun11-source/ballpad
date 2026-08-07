# 15 — Validation log (Bot 2)

Updated 2026-08-07 (session 3 final)

## Confirmed
- iPhone simulator: AOT guest boots and renders visible frames inside the
  SwiftUI product shell. Game responds to injected PAD input. App stays alive
  with no crash when launched without --console-pty (SIGABRT reports were
  session teardown artifacts).
- iPad simulator: app boots, Aurora/SDL presentable=1, guest advances blocks,
  first frame displayed 640x528. No app crashes.

## Definition of Done status
Verified on phone: cold launch, guest frame visible, input response, no JIT/RWX,
one sim at a time, no illegal assets in git.
Open: touch-only menu->match, 60s in-match, full control set proof, layout
persistence, overflow menu 1x/2x, save round-trip, iPad playable match,
docs/12 scoreboard on both devices.

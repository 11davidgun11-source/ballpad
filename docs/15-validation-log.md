# 15 — Validation log (Bot 2)

Updated 2026-08-07 (session 4)

## Confirmed working on iPhone simulator
- AOT guest boots and runs (entry 0x80005240, OS/VI/GX/ARQ/AI init)
- EFB readback renders the game scene (blue menu background, 96% non-black
  frames, bright/colorful content after input advances)
- Input via ballpad_pad_merge changes game state (draw/vertex counts shift)
- SwiftUI shell shows the game behind the touch overlay (brightness-boosted)
- No crashes when launched without --console-pty (SIGABRTs were teardown
  artifacts from the console pipe closing)

## Confirmed on iPad simulator
- App boots, Aurora/SDL presentable=1, guest advances blocks, first frame
  displayed, no app crashes

## Renderer gap (documented, affects macOS Path S too)
- Standalone GXRuntime/Aurora renderer: EFB readback shows 3D geometry but
  not text/UI overlays (those render via Virtual-XFB/YUYV present path).
  XFB readback experiment produced black at legal screen and was reverted.
- This is the known standalone-path workstream (Path C/RecompCore is the
  full-accuracy chassis; deferred due to module ABI mismatch).

## Definition of Done open items
- Visible menu text / touch-only menu->match proof (blocked by renderer text gap)
- 60s in-match, full control checklist, layout persistence, menu scale,
  save round-trip, iPad playable match, docs/12 scoreboard on both devices

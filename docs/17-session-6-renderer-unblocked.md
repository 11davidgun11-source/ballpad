# Session 6 — iOS renderer unblocked: the game is visible on the simulator

Date: 2026-08-08

## TL;DR

The iOS simulator app now shows the ACTUAL game. Screenshots prove it: the
Nintendo health-and-safety screen, a Mario boot scene, the main menu
("GRUDGE MATCH" / CUP BATTLES / STRIKERS 101 / OPTIONS), the side-choice
popup, and a live match (DAISY 0-0 MARIO, clock 4:45) with stadium, players,
and HUD rendering behind the touch overlay.

This was a single root cause: the EFB render target was sized to the full
screen (2532x1170 on the iPhone 17e simulator), while the iOS display path
reads the EFB back into a fixed 640x528 software buffer. The app was showing a
1:1 top-left crop of a full-screen render — a tiny, dark, mostly-uniform slice
that the old display filter then whitewashed into the "white block" the user
saw.

## Honest status

- Guest CPU: runs. Match state machine reaches GS_GAMEPLAY, clock ticks,
  inputs land. (Instrumentation only.)
- iOS render: NOW VISIBLE. The image on screen is the real guest frame
  (verified in simulator screenshots the user can see).
- macOS Path C (RecompCore/Dolphin) remains the full-accuracy oracle; Path S
  (aurora substrate) is the iOS product renderer and now renders correctly.
- Still NOT playable: guest runs ~10-15 fps, boot to match takes ~20 min of
  block-paced autostart, image is 4:3 letterboxed (not widescreen), touch
  controls are placeholder-grade, settings/resolution are not meaningfully
  wired. "It loads, and it renders" is the honest ceiling right now.

## Root cause (why the screen was blank/white)

The iOS product displays ONLY via EFB readback (`ballpad_ios_host_take_frame`
-> `mmio_efb()` -> software `DolEfbAccess.color` filled by the aurora readback
hook). There is no visible Metal swapchain path on iOS.

The chain:

1. `aurora::webgpu::resize_swapchain_internal` creates `g_frameBuffer` (the EFB
   render target) at the SDL window size — 2532x1170 native pixels on the
   iPhone 17e simulator. This is the desktop-friendly "EFB at window scale"
   design.
2. The viewport policy `AURORA_VIEWPORT_FIT` scales the game's logical
   viewport (640x448) to fill that full-size target.
3. `efb_readback::after_submit` copies `present_source()` (= `g_frameBuffer`)
   into a MapRead buffer, then `peek()` feeds `g_efb_frame_fill` ->
   `dol_efb_access_fill_color_rgba8`, which CLAMPS to
   `DOL_EFB_WIDTH_MAX/HEIGHT_MAX` (640x528) and does a 1:1 top-left crop.

Net effect: the displayed 640x528 image was the top-left corner slice of a
2532x1170 render. Both renderers (gxcore default and live Aurora
`DOL_GX_CORE=0`) showed the same artifact because the bug is substrate-level.
The earlier "striped/corrupt" readbacks and the near-uniform `0x00000040`
clear-color fills were this crop of dark boot screens.

## How it was found

- The EFB readback dump (every 60 fills) showed 4 unique colors / near-uniform
  dark navy — the EFB clear, not a scene.
- A GPU poke test (write known pixels into `present_source`) vanished every
  frame because the EFB pass clears the texture per frame — inconclusive but
  proved the texture is a per-frame clear.
- The decisive test: `BALLPAD_TEST_WHITE=1` overwrites `present_source` with a
  checkerboard before each readback copy. Result: the checkerboard read back
  pixel-honestly (255 -> 255), and the trace printed the texture size:
  **2532x1170**, not 640x528. That exposed the crop.

## Fixes (this session)

1. `ref/GXRuntime/graphics/aurora/lib/webgpu/gpu.cpp`:
   `BALLPAD_EFB_NATIVE=1` recreates `g_frameBuffer`, `g_frameBufferResolved`,
   and `g_depthBuffer` at 640x528 after the swapchain resize. The swapchain
   stays at surface size for the (invisible-on-iOS) present blit; the readback
   becomes 1:1 with the software backing. Viewport map becomes 1:1 because the
   logical FB (VI configured 640x528) equals the target size.
2. `host/src/ballpad_ios_host.cpp`: the host sets `BALLPAD_EFB_NATIVE=1` by
   default before `dol_aurora_initialize` (overridable for tests).
3. `app/Ballpad/GameHostView.swift`: removed the `CIColorControls` brightness
   1.6 / contrast 2.2 filter that whitewashed the (now correct) frames.
4. Diagnostics added (all env-gated, off by default): `BALLPAD_EFB_POKE`
   (host-side pixel poke + immediate dumps), `BALLPAD_TEST_WHITE` (readback
   checkerboard), `BALLPAD_DEBUG_EFB` (readback timing logs), plus a
   `dol_aurora_poke_color` export.

## Evidence

- `build/proofs/step-15-EFB-fix-warning2.png` — health-and-safety screen.
- `build/proofs/step-15-mid-boot.png` — Mario stadium boot scene.
- `build/proofs/step-15-title-or-menu.png` — main menu (GRUDGE MATCH).
- `build/proofs/step-15-select.png` — "AT LEAST ONE PLAYER MUST CHOOSE A SIDE".
- `build/proofs/step-15-inmatch.png` — DAISY 0-0 MARIO, 4:45, live field.
- `work/tmp/ios_frame.rgba` / `ios_efbnative.png` — raw 640x528 readback dumps.

## Current problems (honest, user-visible)

1. **Not widescreen**: the game renders 4:3 (640x528 EFB) and is displayed
   aspect-fit inside the landscape phone view, so there are black bars on the
   sides. True widescreen needs a 16:9 crop/scale policy or the XFB path.
2. **Slow**: `[gfx] fps=10.5` observed in-match; ~20 min of block-paced boot
   to reach a match. Not profile-explained yet (candidates: AOT CPU throughput
   on the simulator, per-frame texture uploads, EFB readback copies).
3. **Controls are placeholder-grade**: the current touch layout is a rough
   GameCube skin (stick + A/B/X/Y/Z/L/R/START/C/D pads). It works for basic
   menu navigation (D-pad bits map to menu nav) but is not "world-class",
   multi-touch-optimized, or ergonomic. "pad: idle" status line is diagnostic.
4. **Settings not optimized**: resolution (renderScale 1x/2x) exists in the
   SwiftUI settings but is not meaningfully tied to the EFB pipeline; audio is
   disabled; vsync on; no graphics options that matter yet.
5. **Essentially unplayable**: at ~10 fps with rough controls it is not a
   playable game yet. It loads, renders, and runs a match — that is the honest
   ceiling.

## Technical debt / open issues

- `efb_readback` throttles to one copy per 4 frames with a single in-flight
  map; at low fps the displayed frame can lag the guest. Revisit for perf.
- `BALLPAD_EFB_NATIVE` recreates the EFB targets on every resize; harmless but
  wasteful. A proper config API (EFB scale) would be cleaner than an env var.
- The XFB/Virtual-XFB present path (`lookup_xfb_texture`, YUYV RAM decode)
  exists but the product never presents via it; HUD renders via EFB-direct in
  the current pipeline (match screenshot shows the scoreboard). If a screen
  stops rendering text, re-check the XFB path.
- Log spam: `[ballpad-ios] efb fill=... color=%p` logs a POINTER (misleading),
  every fill; `blocks=` every 1M blocks. stderr redirected to BALLPAD_LOG_FILE.
- `[gfx]` parsed-state lines print the live-Aurora gx state which is empty in
  gxcore mode — harmless diagnostic noise.
- ref/ trees (GXRuntime, StrikersRecomp) are untracked working trees with local
  modifications; DO NOT re-clone them. Full local diffs are captured in
  `docs/patches/` (apply with `git apply` inside the matching ref/ tree, then
  re-copy the untracked xfb_readback files):
  - docs/patches/gxruntime-local.patch
  - docs/patches/strikersrecomp-local.patch
  - docs/patches/xfb_readback.cpp.txt / xfb_readback.hpp.txt
  Critical modified files:
  - ref/GXRuntime/graphics/aurora/lib/webgpu/gpu.cpp (EFB-native fix)
  - ref/GXRuntime/graphics/aurora/lib/gfx/efb_readback.cpp (diagnostics)
  - ref/GXRuntime/backends/aurora/aurora_backend.cpp + aurora_backend.h (poke)
  - ref/StrikersRecomp/runtime/host/hle.c (SaveLoadScene::IsIOEnabled stub)
  - ref/StrikersRecomp/runtime/host/mmio.c, interrupt.c (EFB fill, DEC timer)

## Next steps (priority order)

1. Perf: profile why fps is ~10; verify whether it is guest-side (AOT blocks/s)
   or render-side (map latency / uploads). Raise fps before controls polish.
2. Touch controls: redesign per docs/05-touch-control-spec.md; full GC set
   (shoulder analog, C-stick, Z), multi-touch, ergonomic layout; wire
   `ballpad_pad_set` cleanly (it already works — prove with the control
   checklist M5/M6).
3. Widescreen policy: choose 16:9 crop vs scale; document the tradeoff.
4. Layout editor + persistence (M7/M8), overflow menu 1x/2x (M9/M10), save
   import/export (M11), iPad parity (M1-M14 on pad).
5. Fill docs/12 scoreboard + docs/15-validation-log.md; log failures in
   docs/09-open-questions.md.

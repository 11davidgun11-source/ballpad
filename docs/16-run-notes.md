# 16 — Bot 2 run notes (2026-08-07 session 5)

## Status snapshot

### Path C (RecompCore chassis, macOS) — COMPLETE oracle
- `gG4QE01_recomp.dylib` module links (added `host/src/ballpad_ppc_helpers.c` to
  the module sources; fixes the FP/load-store helper ABI for the RecompCore cpu.c
  runtime). Installed at `work/dolphin-user/StaticRecompModules/`.
- RecompCore `dolphin-emu-nogui` built (submodules initialized) and boots the
  user ISO with `-C Dolphin.Core.CPUCore=6` on Metal.
- Full renderer + text + input: health screen, save prompt, Nintendo logo, Mario
  title scene, main menu, team select, controller assignment, stadium card, LIVE
  MATCH (MARIO 0-0 DAISY, clock running). Proofs: build/proofs/step-03-pathC-*.png,
  step-03-pathC-inmatch.png.
- Input oracle: Dolphin Pipes backend. FIFO `work/dolphin-user/Pipes/pad0` +
  `Config/GCPadNew.ini` (`Device = Pipe/0/pad0`, `Group/Control` keys, sections
  GCPad1..4 = ports 0..3). Scripts: scripts/padcmd.sh, scripts/hidkey.swift.
- Confirmed nav to a match (used for the iOS autostart):
  A, A, D_DOWN+A (CONTINUE WITHOUT SAVING), START, A, A, A, D_LEFT+A, A, D_LEFT+A.

### iOS product (Path S) — phone simulator
Working:
- App boots, guest runs, EFB readback displayed, touch overlay (A/B/X/Y/Z/L/R/
  START/stick/C-stick/D-pad — D-pad now maps to bits 0x0001/2/4/8).
- Block-paced autostart (BALLPAD_AUTOSTART=1) drives boot -> save prompt
  (CONTINUE) -> title -> main menu -> team select -> controller screen. It
  completed all 14 steps; the in-match draw signature (23 draws / 150k verts)
  appeared after the final A.
- stderr is redirected to `work/tmp/ios_host.log` via BALLPAD_LOG_FILE; without
  it the console-pty pipe fills and `fprintf` blocks freeze the app.

### Blocker: "hang" during match load — root-cause hypothesis REVISED
- Symptom: presents stop, blocks stop, app process sits at ~4% CPU (blocked,
  not computing), guest pc idle in SelectThread (waiting for the next VI
  retrace). The guest is NOT deadlocked; the HOST present pipeline stalls.
- The simulator throttles rendering when the Simulator window is occluded
  (frontmost app is ChatGPT/Codex). The guest loop is coupled to the present
  (step_frame runs blocks then blocks on the vsynced present), so a stalled
  present freezes guest progress.
- DEC (decrementer) timer interrupt was missing in the runtime; implemented
  (deliver_decrementer -> DecrementerExceptionCallback 0x8025409C) but spr[22]
  reads 0 at every observed freeze, so the DEC was never the active wait.
  Keep the fix (timers will be needed later) but treat the present stall as the
  primary suspect.
- Evidence for present stall: the same run went 20fps for the first ~75s then
  collapsed to ~1.5fps with the app at 4% CPU — a throttled/blocked present.

### Next actions
1. Foreground the Simulator window during drives (unthrottle the present).
2. Re-run the autostart drive; verify the match loads and stays in-match.
3. If the match loads: capture phone EFB/sim screenshots for DoD M2/M3/M4.
4. Then iPad parity + remaining DoD gates (controls checklist, layout
   persistence, overflow 1x/2x, save round-trip, validation scoreboard).

## Session-5 deep-dive: match-load stall analysis (in progress)
- The guest reaches the stadium card after the autostart's final A; the load chain
  (LoadingManager: graphics/FE/world/audio/physics/NPC/AI/camera loaders) COMPLETES
  (TransitionTask state = eTS_InState, loadMgr num=0). Guest retraces tick, audio
  streams (BABE command lists processed, salDspIsDone set), alarm queue healthy.
- The game never shows gameplay: g_pGame (cGame*) is NULL, no match clocks exist,
  EFB readback is a frozen dark scene (game renders it every frame), and the game's
  logic churns indefinitely (mesh-writer/memcpy pcs are just the per-frame loading
  screen render).
- Suspects under investigation: (a) the match-start A at 5.4B missed/triggered a
  teardown (g_pGame NULL => DestroyGame ran => transition back to FE state 4);
  (b) the game's FE state machine is stuck (reading m_feStateCurrent/Pending now).
- Host fixes already landed this session: EFB readback mutex self-deadlock
  (MapAsync inline callback + g_mutex), staging-map guard, readback throttle +
  stalled-map abandon, DEC timer emulation, stderr redirect, block-paced autostart
  with stadium-card A retries. These cleared every earlier hard freeze; only the
  match-start state remains.

## Latest findings (same session)
- The game is in task state 4 (front-end task) the whole time; the EFB readback
  froze on one dark frame since ~2.8B blocks while the renderer keeps presenting
  (draws=23 / 150k verts = the rich stadium-card scene). The game never creates
  cGame (g_pGame NULL) and never reaches gameplay clocks.
- The dark scene is the FE stadium card (the match-setup stadium selection);
  D_LEFT on it moves the carousel, A confirms. Autostart now alternates A-only
  and D_LEFT+A retries to cover both the side-choice screen and the stadium card.
- Remaining suspects if this still fails: readback freshness (the frame may be a
  stale present-source copy), and the exact menu-flow drift (block anchors vs the
  per-run guest timing). Screen-history snapshots (work/tmp/snap_*.rgba) are now
  saved every 400M blocks for offline review.

## Final session findings (input path)
- The game's own pad-status buffer (s_Current__9PadStatus) shows the injected
  A presses (btn=0x0100) with err=0 during the autostart holds, and the pad
  pointer ping-pongs between the double buffers — the guest RECEIVES the input.
- Yet the FE menu logic never advances past the title/main-menu scene: the game
  stays in task state 4 (front-end task), cGame stays NULL, and the EFB readback
  freezes on the same dark frame (the rich 23-draw/150k-vert scene) from ~2.6B
  blocks on.
- Next suspects (next session): cGlobalPad::IsConnected() on the FE input path
  (FE may treat the pad as disconnected and ignore input), and the FE task
  update loop. Check cPadManager/cGlobalPad connection flags + FEInput
  m_bInputAllowed/m_bEnableInput in guest memory.
- All host fixes remain in place: readback mutex deadlock fix, staging guard,
  readback throttle, DEC emulation, stderr redirect, block-paced autostart.

---

# Session 6 (2026-08-08) — iOS renderer unblocked: game VISIBLE on simulator

## What happened

Previous session 5 left the guest running and reaching GS_GAMEPLAY, but the
simulator screen showed a white/blank block — the EFB readback was a
near-uniform clear color. This session found and fixed the root cause.

### Root cause

The iOS product displays ONLY via EFB readback (SwiftUI `UIImageView` fed by
`ballpad_ios_host_take_frame` -> `mmio_efb()` -> software `DolEfbAccess`).
The aurora renderer sizes the EFB render target (`g_frameBuffer`) to the SDL
window — 2532x1170 native on the iPhone 17e simulator — and the viewport
policy (FIT) scales the 640x448 logical viewport to fill it. The readback then
clamps into a fixed 640x528 software backing with a 1:1 top-left crop. So the
app displayed a tiny dark slice of a full-screen render. Both gxcore and live
Aurora renderers showed the same artifact (substrate-level bug).

### Evidence trail

1. `work/tmp/ios_frame.rgba` dumps: 4 unique colors / near-uniform dark navy —
   the EFB clear, not a scene.
2. GPU poke test (`BALLPAD_EFB_POKE`): poked pixels vanished every frame — the
   EFB pass clears per frame (proved the texture is a per-frame clear).
3. `BALLPAD_TEST_WHITE` checkerboard overwrite before each readback copy: the
   checkerboard read back pixel-honestly AND the trace printed the texture
   size: **2532x1170** — not 640x528. That exposed the crop.

### Fixes

- `ref/GXRuntime/graphics/aurora/lib/webgpu/gpu.cpp`: `BALLPAD_EFB_NATIVE=1`
  recreates `g_frameBuffer` / `g_frameBufferResolved` / `g_depthBuffer` at
  640x528 after the swapchain resize (swapchain stays at surface size).
- `host/src/ballpad_ios_host.cpp`: sets `BALLPAD_EFB_NATIVE=1` by default.
- `app/Ballpad/GameHostView.swift`: removed CIColorControls brightness 1.6 /
  contrast 2.2 (whitewashed the now-correct frames).
- Env-gated diagnostics: `BALLPAD_EFB_POKE`, `BALLPAD_TEST_WHITE`,
  `BALLPAD_DEBUG_EFB`, `dol_aurora_poke_color` export.

### Verified on simulator (screenshots)

- `step-15-EFB-fix-warning2.png` — health-and-safety screen (white text).
- `step-15-mid-boot.png` — Mario stadium boot scene.
- `step-15-title-or-menu.png` — main menu "GRUDGE MATCH" + CUP BATTLES etc.
- `step-15-select.png` — "AT LEAST ONE PLAYER MUST CHOOSE A SIDE" popup.
- `step-15-inmatch.png` — LIVE MATCH: DAISY 0-0 MARIO, clock 4:45, stadium,
  players, HUD, touch overlay.

The match was reached via the block-paced autostart (~4.5B blocks) and the app
kept running; autostart continues pressing through 6.9B (harmless in-match).

## Remaining work (honest)

- **Not widescreen** (4:3 letterboxed), **~10 fps**, **~20 min boot to match**,
  **placeholder touch controls**, **settings not optimized** — the game loads
  and renders but is not yet playable. Details + next steps:
  docs/17-session-6-renderer-unblocked.md.
- DoD gates M5-M14 (controls, layout, menu, saves, iPad) still open; the render
  blocker that made them untestable is gone.

## Commands that matter (session 6)

```bash
source build/env.sh
# engine change -> rebuild + re-merge + app:
cmake --build work/strikers/build-ios-sim --target gxruntime_aurora -j 8
libtool -static -o work/strikers/build-ios-sim/merged/libBallpadEngine.a \
  $(head -n 119 work/strikers/build-ios-sim/merged/libs2.list)
xcodebuild -project app/Ballpad.xcodeproj -scheme Ballpad \
  -destination "id=$BALLPAD_UDID" -derivedDataPath build/DerivedData build
APP=$(find build/DerivedData/Build/Products -name Ballpad.app -type d | head -1)
xcrun simctl install "$BALLPAD_UDID" "$APP"
SIMCTL_CHILD_BALLPAD_LOG_FILE=$PWD/work/tmp/ios_show.log \
SIMCTL_CHILD_BALLPAD_EFB_NATIVE=1 SIMCTL_CHILD_BALLPAD_AUTOSTART=1 \
  xcrun simctl launch --terminate-running-process "$BALLPAD_UDID" com.ballpad.strikers
```

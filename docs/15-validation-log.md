# 15 — Validation log (Bot 2)

Updated 2026-08-07 (session 5 — Path C oracle complete)

## Path C (RecompCore chassis) — macOS validation (Step 3 gate PASS)
- Built `gG4QE01_recomp.dylib` module (163 chunks + RecompCore cpu.c +
  `host/src/ballpad_ppc_helpers.c` for the FP/load-store helper ABI bridge) with ThinLTO.
  Installed at `work/dolphin-user/StaticRecompModules/`.
- Built RecompCore `dolphin-emu-nogui` (Metal backend) and booted the user ISO with
  `-C Dolphin.Core.CPUCore=6`. Module autoloads, entry 0x80005240.
- Full renderer works: health screen, memory-card prompt, Nintendo logo, Mario title
  scene, main menu (GRUDGE MATCH/CUP BATTLES/...), team select, stadium card, live match
  (MARIO 0-0 DAISY, THE PALACE, clock 4:59). All with text visible — closes the
  "menu text not in EFB readback" gap on the accuracy side.
- Input: Dolphin Pipes backend (`work/dolphin-user/Pipes/pad0` FIFO + `GCPadNew.ini`
  with `Device = Pipe/0/pad0`, group/control config keys, sections GCPad1..4 for ports
  0..3). Buttons, D-pad, analog stick, start all verified; side assignment in team
  select uses D-pad LEFT then A.
- Confirmed nav to match (touch-equivalent script for iOS): A; A; D_DOWN+A
  (CONTINUE WITHOUT SAVING); START (title); A (GRUDGE MATCH); A (captain); A (CPU
  captain grid); D_LEFT+A (CPU captain); A (CPU sidekick); D_LEFT+A (assign P1 left)
  -> stadium -> match.
- Debug instrumentation (env-gated prints in ref/RecompCore working tree only):
  pad state, SI commands/responses, device list. Found + fixed config issues:
  device qualifier format `source/id/name`, group control names (Up/Down/Left/Right,
  not X-/Y+), controller section naming (GCPad1 = port 0).
- Known chassis quirk: creating a save file (YES) on the prompt hangs without writing
  a GCI; CONTINUE WITHOUT SAVING works. Save-import/export round-trip still open (M11).

## Confirmed working on iPhone simulator
- AOT guest boots and runs (entry 0x80005240, OS/VI/GX/ARQ/AI init)
- EFB readback renders the game scene (blue menu background, 96% non-black
  frames, bright/colorful content after input advances)
- Input via ballpad_pad_merge changes game state (draw/vertex counts shift)
- SwiftUI shell shows the game behind the touch overlay (brightness-boosted)
- No crashes when launched without --console-pty (SIGABRTs were teardown
  artifacts from the console pipe closing)
- Touch surface now maps the D-pad node to D-pad bits (0x0001/2/4/8) for menu nav (M5)

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
- Touch-only menu->match proof on phone sim (drive confirmed nav; EFB scene changes
  as verification; macOS Path C provides the exact menu map)
- 60s in-match on phone + iPad, full control checklist, layout persistence, menu
  scale 1x/2x, save round-trip, iPad playable match, docs/12 scoreboard green

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

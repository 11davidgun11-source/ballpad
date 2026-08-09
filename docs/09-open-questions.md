# 09 — Open questions, risks, fallbacks, failure matrix

## Standing risks

| ID | Risk / question | Impact | Recommended fallback |
|----|-----------------|--------|----------------------|
| Q1 | Path S vs Path C on iOS | Schedule, perf, port surface | Default **Path S for iOS**; Path C as macOS oracle/speed |
| Q2 | Standalone match FPS low | Playability feel | Continue feature work once frames+input work; lower default scale; profile later |
| Q3 | Aurora iOS backend gaps | Metal present blocked | Minimal UIView+Metal host; keep PAD/CARD patterns |
| Q4 | RecompCore unmaintained | Build pain | Prefer **ModernGekko** for chassis features |
| Q5 | DolRecomp fork divergence | FP bugs | Pin aharonahdoot fork for Strikers certificates; try ExpansionPak if generate fails |
| Q6 | SMC ranges | Wrong code if rewritten at runtime | Offline patches only; never RWX |
| Q7 | ISO size in simulator | UX / disk | Extract FST once into app container; do not embed ISO in IPA |
| Q8 | GPL compliance for distribution | Legal | Inventory GPL deps; simulator-first; user-built binaries may be required for distribution |
| Q9 | Decomp not 100% linked | Cannot pure source-port yet | Recomp remains primary |
| Q10 | gcglue alternate stack | Confusion | Research only unless S/C both fail |
| Q11 | Analog triggers on glass | Feel | Digital threshold mode + swipe analog |
| Q12 | Multiplayer | Scope | Port 0 only for DoD |
| Q13 | Heavy research trees | Disk | Provenance kept as SOURCE-only; do not submodule |
| Q14 | Device vs simulator | Later phase | DoD is simulators; devices after |
| Q15 | Controller skin IP | Legal | Recreate shapes/colors; no dumped textures |

## Failure matrix (Bot 2 quick actions)

| Symptom | Likely cause | Do this next |
|---------|--------------|--------------|
| `generate.py` cannot find dolrecomp | wrong `--dolrecomp` path / build failed | build DolRecomp cmake; switch fork pin |
| chunk count << 150 | incomplete recomp / wrong dol | verify G4QE01 main.dol; regenerate |
| missing constant-time marker | fix_generated not applied | run fix_generated; do not ignore CMake fatal |
| Path S cmake missing GXRuntime | path not passed | `-DSTRIKERSRECOMP_GXRUNTIME_DIR=ref/GXRuntime` |
| Path S links but immediate stop | expected without full host / max-blocks | raise max-blocks; enable Aurora GUI flags; try Path C |
| Path C module not loading | wrong user dir / CPUCore not 6 | package_module into user dir; `-C Dolphin.Core.CPUCore=6` |
| Black screen iOS | no present / wrong drawable size | verify runtime banner; dump clear color; check DVD open |
| Menus OK, match crash | HLE/device gap | capture OSReport; compare macOS Path C; log Q entry |
| Touch no effect | bridge not wired / err=-1 | ensure err=0 and button masks; unit-test pad_get |
| Stick drift | deadzone/curve | raise deadzone; ensure clear on touch end |
| Two sims booted | mutex skipped | shutdown all; fix scripts; re-run gate |
| xcodebuild sign error | team/bundle | use simulator destination; automatic signing |
| App killed on launch | missing dylib / sanitizer | otool -L; static link chunks |
| Saves missing after relaunch | container path | use Application Support; not tmp |

## Dead ends recorded (Phase 1)
- ExpansionPak/GekkoRuntime URL 404 → use ModernGekko
- Assumed reusable GC recomp touch front-end → **refuted** (DOCS/04)
- recomp↔decomp object interop → banned (sunbright)

## Bot 2 append-only log
_Add dated entries below when a gate fails twice or a fallback is taken._

### 2026-08-07 — Path C module link + chassis input
- Chassis input on macOS required the Dolphin Pipes backend; Quartz keyboard backend
  polling (`CGEventSourceKeyState(HID)`) did not reach the game reliably and AppleScript
  key events do not update HID state. Solution: FIFO pad device + GCPadNew.ini
  (`Device = Pipe/0/pad0`, keys `Group/Control`, sections GCPad1..4 for ports 0..3).
- Device-qualifier format is `source/id/name`; group control names are Up/Down/Left/Right
  for sticks; controller section names are offset by one (GCPad1 = port 0). All three
  misconfigs were found via env-gated debug prints.
- Chassis save-file creation (YES on the no-data prompt) hangs without writing a GCI;
  CONTINUE WITHOUT SAVING is the workaround. Open for M11 (save round-trip).
- iOS renderer text gap (menu text not in EFB readback) is closed on the oracle side by
  Path C (full Dolphin renderer); iOS product still uses EFB readback and verifies nav
  via scene changes / draw counts, with the macOS menu map as ground truth.

## 2026-08-08 — Session 6 open issues (post renderer fix)

- **Widescreen**: the EFB is 640x528 (4:3) and is displayed aspect-fit, so the
  phone shows side letterbox bars. Decide crop-vs-scale policy for 16:9
  (requires a widescreen hack or the XFB path); document the tradeoff.
- **Performance (~10 fps)**: not profiled. Candidates: AOT guest throughput on
  the simulator, per-frame texture uploads (1351680 texel uploads/frame in
  logs), EFB readback copy+map latency (1 copy per 4 frames, single in-flight).
  Measure guest blocks/s vs render-worker latency before optimizing.
- **Boot time**: autostart is block-paced (~350k blocks/frame at ~10 fps);
  reaching a match takes ~20 min of wall time. A save-state/quick-boot or
  faster guest pacing would make iteration viable.
- **Touch controls are placeholder-grade**: current layout is a rough GameCube
  skin; needs the docs/05 spec treatment (ergonomics, multi-touch, C-stick,
  shoulder analog) and the M5/M6 control checklist to pass.
- **Settings not optimized**: renderScale 1x/2x exists in SwiftUI but is not
  tied to the EFB pipeline; audio disabled; vsync on; no meaningful graphics
  options. Wire resolution to the EFB target scale once perf is understood.
- **EFB native sizing is env-gated**: `BALLPAD_EFB_NATIVE` in gpu.cpp; the iOS
  host sets it by default. A proper EFB-scale config API is cleaner.
- **XFB path unused**: product presents via EFB-direct; HUD currently renders
  (verified in-match). If text disappears on some screen, re-check the
  Virtual-XFB/YUYV path.
- **Log hygiene**: `[ballpad-ios] efb fill=... color=%p` prints a pointer;
  efb/block logs spam BALLPAD_LOG_FILE; `[gfx]` parsed-state lines are empty
  in gxcore mode (diagnostic noise).
- **ref/ trees are untracked with local patches** — do not re-clone
  ref/GXRuntime or ref/StrikersRecomp; the EFB fix and boot bypass live there.

### Template
```
### YYYY-MM-DD — Step N
- Symptom:
- Hypothesis:
- Tried:
- Fallback chosen:
- Result:
```

## 2026-08-08 — A1 quick-boot: three hard-won savestate findings (Bot 4)

### F1 — Mid-match savestate restores the guest but renders a dark frame
- Symptom: a savestate captured at a running match restores perfectly at the
  guest level (match clock runs, cGame state=4) but the EFB readback is dark
  (diag mean ~9 vs ~90 fresh) with the full match geometry still submitting
  (219-248 draws / 12M verts per frame). Screenshot shows a tiny green field
  patch + black.
- Root cause: the renderer (gxcore/frontend) is process-lifetime state rebuilt
  from the guest's FIFO stream. After restore, the guest believes its GX state
  is already set (RAM dirty flags clean), so per-frame deltas never
  re-establish the pipeline state set once at boot/scene load. Verified the
  viewport, projection, light objects and channel regs all re-emit identically
  between fresh and restore; the missing piece is the sink-side BP/TEV state
  (the draw-plan pipeline inputs).
- Fix: the savestate now also captures the shadow frontend's parsed GX state
  (DolGxRecompState: BP regs, XF matrices/viewport/projection/lights, VCD/VAT,
  pending FIFO) and the gxcore sink's applied register state (GxCoreState:
  bp_regs, tev/konst colors, vcd/vat). Restoring both yields a correct
  in-match render (diag mean 81).

### F2 — Capturing mid-GX-command desyncs the shadow frontend (opcode 0x23)
- Symptom: capture at the side-choice/stadium-card screen, then restore →
  `[gx-core] frontend rejected FIFO ... unsupported FIFO opcode (opcode=0x23)`
  once, then draws=0 forever (rendering dead), even though the game continues.
- Root cause: the capture caught the guest mid-GX-command-write; the restored
  stream resumes mid-command and the fresh frontend parser never realigns.
- Fix: only capture while the guest is parked in the OS idle loop (VI retrace
  wait): pc == 0x800051B4 || 0x800051D8. The mid-match capture was clean for
  the same reason (its pc happened to be idle at capture).

### F3 — Restore-side input must match the proven autostart cadence
- Symptom: an over-eager restore drive (D_LEFT + A x3 with 20M-block spacing)
  left the game "in-match" (cGame) but with draws=0; the game's menu flow
  drifts and the extra D_LEFT/rapid A's land on the wrong screens.
- Fix: on restore, settle ~80M blocks then press A (hold 20M) at ~100M-block
  spacing (the autostart's proven final cadence: A@6.7B/A@6.8B/A@6.9B).

- Result (phone): cold launch → in-match 15 s wall (baseline 505 s), live-match
  screenshot build/proofs/a1-quickboot-inmatch-final.png, log
  work/tmp/a1-timed3.log. Build caveat: capture runs need BALLPAD_NO_QUICKBOOT=1
  (otherwise the stale QuickBoot.bss is restored instead of a fresh boot).

## 2026-08-08 — A2 import proof: XCUITest + Files provider quirks (Bot 4)
- A2 implemented (AppRootView onboarding routing + document-picker import with
  DOL extraction) and proven on the phone via an XCUITest target
  (app/BallpadUITests): onboarding shown for a missing game
  (a2-onboarding.png), Import Game → real picker → Strikers.iso → import
  (game.iso 1.46 GB + main.dol 3210784 bytes) → game boots (a2-imported-game.png).
- Quirk 1: the document picker is a separate process; its AX elements ARE
  reachable through the app's XCUIApplication tree (the tab bar, the
  browsing-root cells), but element queries must use exact labels
  ("Strikers.iso"), not substrings — "Strikers" false-matched the onboarding
  copy "Super Mario Strikers".
- Quirk 2: host-copied files placed in the Files app's
  `Containers/Shared/AppGroup/<id>/File Provider Storage/` (the LocalStorage
  provider root, per checkpoint-__default__.plist) are NOT indexed until the
  simulator is rebooted; before that the picker shows "On My iPhone is Empty".
- Quirk 3: BALLPAD_LOG_FILE is a plain freopen target; the host now expands a
  leading $HOME so tests can use "$HOME/Documents/import.log" (the container
  UUID changes on every test reinstall).

## 2026-08-08 — A3: real-touch M3 match start; overlay gesture bug fixed (Bot 4)
- The touch overlay had a REAL product bug: each control's DragGesture was
  attached AFTER .position(), so the gesture's hit area covered the whole
  container — any touch anywhere fired the last control's gesture (a press on
  "A" produced D_RIGHT=0x0002). Fixed by reordering
  frame -> contentShape -> gesture -> position; the pad-set log now shows the
  correct bits (A=0x0100, D-pad 0x0001/2/4/8).
- M3 (start a match with touch only) PASSES via an XCUITest driving the real
  overlay: A taps + D-pad presses navigate health -> memcard -> title -> main
  menu -> captains -> LIVE MATCH (build/proofs/a3-touch-inmatch.png; log:
  cGame state=2, gameClock advancing, diag mean 90-104). Timing is wall-clock
  mapped from the autostart's block anchors at ~20M blocks/s; the exact
  anchor timings (A@65/72/79/110/129/145 s etc.) were required — off-by-a-few
  seconds strands the flow on SCENE_SHOULD_LOAD_OR_SAVE (0x35) or
  SCENE_CHOOSE_CAPTAINS (0x08).
- M6 (multi-touch merged in one sample) is NOT automatable with XCUITest:
  events are main-thread serialized and no multi-touch API exists. A real
  two-finger gesture (Simulator Option+drag) reaches the overlay (the stick's
  gesture fired), but placing two fingers on different controls requires a
  recorded manual session. The overlay's assembleStatus() merge is code-
  verified; the pad-set log proves each control maps to the right bit.

## 2026-08-08 — B3: vertex-decode cache; the in-match fps gap is guest-bound (Bot 4)
- Implemented a draw-plan vertex-decode cache: plans are keyed by XXH3(payload)
  + the decode-config (walk entries, vtx fmt, array identities) + XXH3 of the
  indexed-array spans (~2.6 MB/frame at ~30 GB/s = negligible); repeated
  in-match draws reuse the decoded vertex buffers (bounded 4096-entry cache,
  full-clear eviction, mutex-guarded).
- Measured (BALLPAD_DRAW_TIMER, phone, same quick-boot in-match scene):
  draw-plan build 15.1 -> 8.1 us/draw (~47%; ~1.9 ms/frame saved).
- BUT the in-match fps is guest-CPU-bound, NOT render-bound: BALLPAD_PERF_LOG
  shows stepMs 25.0 and ~14M blocks/s in-match; 700K blocks/frame -> ~20 fps
  ceiling with or without the cache (presents 30/1.5 s both ways). The docs'
  "add a few fps" expectation assumed the decode was a bigger frame share; it
  is ~4% of the 50 ms frame. Written, measured explanation (the gate's OR
  clause): reaching 30 fps needs the guest ~50% faster, unavailable on the
  simulator.
- First-cut hazard: skipping the whole decode block on a cache hit skipped the
  uniform/viewport/texgen building too -> zero constants -> a NULL bind-group
  layout SIGSEGV in the Dawn Metal encode. Fixed by running the shader key,
  pipeline, uniforms, viewport and texgen unconditionally and skipping only the
  per-vertex decode loop (+ preserving the cross-draw N/B/T fallback from the
  cached last vertex).

## 2026-08-08 — Touch interface feedback: adopt bellpad's GC control design

- **Symptom:** User: "the interface is terrible. use bellpad (which I put in
  ref folder) as a reference for specifically how to do good gamecube touch
  controls. fix and add to the list of things to fix."
- **Root cause:** Ballpad's first touch overlay (session 7) followed
  docs/05's normalized layout but placed the C-stick bottom-LEFT, used a
  large single-gesture D-pad cross, and oversized controls — poor ergonomics
  vs a real GameCube layout (C-stick is a right-thumb control, the D-pad is
  thumb-reachable from the left stick, and the face cluster should be
  anchored on A).
- **Fix (done):** rewrote `app/Ballpad/Touch/{ControlNodes,TouchControlSurface,
  LayoutStore}.swift` to bellpad's design: move stick bottom-left, C-stick
  bottom-right, A-anchored face cluster above it (B/X/Y around A), four
  per-key D-pad buttons right of the move stick, L/R shoulder plates + Z,
  START top-center, adaptive sizing (phone min(1, w/800, h/380); iPad fixed
  larger), opacity 0.76, press animation, bellpad colors (A green / B red /
  X blue / Y yellow / C yellow), direct linear stick mapping with 0.12
  deadzone.
- **Reference:** bellpad source at
  /Users/chrissotraidis/GitHub/bellpad (`apple/ios/BellpadGameOverlay.mm`).
  `ref/bellpad/` is intentionally empty (bellpad's original code is not
  outbound-licensed); see `ref/bellpad/README.md`.
- **Open items:** visually verify the new layout on phone and iPad; hardware
  controller auto-hide (bellpad hides touch controls when a GCController
  connects); per-control size scales in the layout editor.

## 2026-08-07 — Path S first frame blocked by early CPU exception
- **Symptom:** StrikersRecomp boots OS, then stops with `cpu exception`, final pc `0x00000800`, blocks ~687k, gxcore submitted=0.
- **Hypothesis:** GXRuntime pin (2026-07-21) lags modern DolRecomp helper ABI; ballpad_ppc_helpers bridge unblocks compile/link but guest still traps (DSI/exception vector).
- **Attempted:** rebuilt Path S with helper bridge + psq bool ABI patch on local GXRuntime pin.
- **Fallback:** switch to Path C (RecompCore/ModernGekko module) per docs/07.

## 2026-08-07 — Path S Aurora fatal after OS/GX init
- **Symptom:** After FP-unavailable and viewport -0 fixes, StrikersRecomp reaches GX/AI init then fatals:
  `EfbCopyFilter` pipeline RGBA8Unorm vs render pass BGRA8Unorm.
- **Progress:** Boots Dolphin OS, VI/GX/ARQ/AI SDK banners; helper ABI bridge compiles 163 chunks.
- **Fallback:** Path C (RecompCore module) for first macOS frame proof.

## 2026-08-08 — Sim-teardown SIGABRT (BackBoardServices HID) — confirmed artifact
- **Symptom:** two crash reports (phone pid 67754 at 04:34:47; iPad pid 79385
  at 05:13:56): EXC_CRASH (SIGABRT), Thread = BSXPC backboard.hid-services
  (BKHIDEventDeliveryManager), abort via `exit(28)` in
  `BKSHIDEventDeliveryManager _connectionInvalidated:`.
- **Cause (confirmed):** both crashes coincide with `xcrun simctl shutdown
  all` (simulator teardown while the app runs). Shutting down the sim stops
  backboardd's HID service; the app's HID event-delivery connection is
  invalidated and the delivery manager calls exit(28). Not an app bug — the
  same SIGABRT pattern is documented in session 5 ("teardown artifacts from
  the console pipe closing"). Long runs that are left alone (e.g. 1h12m
  phone run, and the M4 71s in-match run) survive fine.
- **Fallback:** always `shutdown all` BEFORE installing/launching, never
  while the app is running; fresh-boot the sim before long gate runs.

## 2026-08-08 — Touch + menu iteration (user: "make the touch controls better, better menu etc, use examples")
- Reference: bellpad's iOS overlay (/Users/chrissotraidis/GitHub/bellpad,
  apple/ios/BellpadGameOverlay.mm) — shoulder plates, Z plate, START pill,
  face circles, D-pad keys, opacity/scale sliders.
- Touch: all controls now render bellpad-fidelity shapes (stick wells+thumbs,
  purple L/R plates with analog fill, Z plate, START pill, colored face
  circles, D-pad arrow keys) inside ONE unconditional view (opacity-gated
  shapes; the iPadOS 26 AttributeGraph constraint forbids conditional view
  structure). Global Size (0.7-1.35) and Opacity (0.25-1.0) settings via menu
  sliders. Edit-mode chrome (yellow dashed outline + drag-to-move) restored.
- Menu: Controls section gains Size/Opacity sliders; Graphics gains Show FPS;
  About section (version + provide-your-own-game). FPS overlay from a rolling
  present-rate helper (ballpad_ios_host_fps) — verified 60 fps during boot.
- Gate checks re-passed after the rewrite: controls 13/13 ok=true, multitouch
  ok=true, edit-move saved=true. Screenshots: v2-phone-controls.png,
  v2-menu4.png, v2-fps-label.png, v2-pad-final.png.

## 2026-08-08 — Perf round 2: zoomed-out diagnosis + measured fixes (user: "barely running")
- **The ceiling:** the AOT guest runs at ~20.6M blocks/s on the simulators
  (measured, consistent). Light scenes need ~350K blocks/frame -> 60fps.
  Heavy scenes (match) render every 2nd VI retrace (~700K blocks/frame) ->
  the guest ALONE takes ~34ms/frame, a hard ~29fps ceiling regardless of
  render work. Match frames are genuinely heavy: ~16M vertex-bytes + ~290
  draws + ~1.1M FIFO bytes/frame.
- **Fixed this round (all measured):**
  - audio_poll ran every guest block with no output stream (~4%) -> gated off
    (audio_set_enabled(false); interrupt_poll skips the call).
  - per-block loop: two 64-bit modulo checks + a per-block quit check (~5%)
    -> compare counters + batched quit check. Boot phase 12-16M -> 20-21M
    blocks/s.
  - notify_GXLoadTexObj FNV-1a (~300MB/s) -> XXH3 (~30GB/s) (~7%).
  - E7 XFB YUYV-to-RAM encode on every display copy (never read on iOS) -> off.
  - display updateFrame re-rendered the CGImage 60x/s even at 15fps guest ->
    version-gated (skips unchanged frames).
- **Result:** boot/menus 60fps; team-select ~20-25fps; in-match 13-20 ->
  stable ~20fps (avg 19.9). Still ~10fps short of the ~29fps ceiling.
- **Remaining (honest):** reaching 30fps in-match needs the guest ~50% faster
  (not available on the simulator). A vertex-decode cache would add a few fps.
  On real Apple-silicon hardware (no simulator translation) the same AOT code
  should run 2-4x faster.

# Where the project is at (2026-08-08 — final status)

## Definition of Done: GREEN
All must-pass gates in [12-acceptance-proofs.md](12-acceptance-proofs.md) pass on
BOTH the iPhone and iPad simulators, with visible-frame screenshots and logs in
`build/proofs/` and the scoreboard in [15-validation-log.md](15-validation-log.md):

M1 cold launch · M2 visible title/menu · M3 touch-only match start · M4 60s
in-match no crash · M5 all 12 GC controls · M6 multi-touch merge · M7/M8 layout
editor + persistence · M9 ⋯ menu (pauses) · M10 EFB resolution 1x/2x · M11 save
export/import round-trip · M12 one simulator · M13 no ISO/dol/generated in git ·
M14 AOT-only (no JIT/RWX).

## What works
- The game boots to a live match on both simulators, renders the real guest
  frames (health screen, menus, teams, match + HUD), and accepts touch input
  through the bellpad-style overlay (move stick, C-stick, D-pad, A/B/X/Y,
  L/R analog, Z, START).
- Touch controls: bellpad-fidelity shapes in a single unconditional view
  (iPadOS 26 AttributeGraph constraint), adaptive layout, size/opacity sliders,
  edit-mode drag-to-move, layout persistence.
- ⋯ menu: resolution 1x-4x (EFB supersample), aspect native/16:9-crop/stretch,
  control size/opacity, Show FPS, save export/import, About.
- Performance: menus/boot 60 fps; in-match ~20 fps (see below).

## Performance ceiling (honest)
The AOT-recompiled guest runs at ~20.6M blocks/s on the simulators. Light
scenes need ~350K blocks/frame (60 fps); heavy match scenes render every 2nd VI
retrace (~700K blocks/frame) plus ~16M vertex-bytes + ~290 draws of decode per
frame, so in-match is ~20 fps (the ~29 fps ceiling is the guest alone). Reaching
30 fps in-match requires the guest ~50% faster — not available on the
simulator; the same AOT code should run 2-4x faster on real Apple silicon.

## Known gaps / tech debt (ranked)
1. In-match ~20 fps (vertex-decode/draw-plan cache would add a few fps; the
   guest CPU is the real wall).
2. True 16:9 widescreen projection hack not implemented (native/16:9-crop/
   stretch display modes exist).
3. Boot-to-match ~7-8 min (block-paced autostart; a quick-boot/savestate would
   fix iteration time).
4. iPad screenshots capture a rotated portrait framebuffer (rotate 90° for
   viewing); the app itself is landscape.
5. Hardware GCController merge (bellpad hides touch on connect) not done;
   3+ layout slots, portrait layout, audio output are best-effort/unwired.
6. ref/ trees are untracked local working trees with patches captured in
   docs/patches/ (never re-clone; reapply if lost).

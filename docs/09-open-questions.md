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

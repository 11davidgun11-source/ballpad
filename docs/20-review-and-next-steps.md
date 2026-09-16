# 20 — Independent review and what happens next (2026-08-08)

Reviewer: fresh agent pass over the whole repo (docs, app, host, scripts,
ref/ state, git history) plus a live smoke run on the iPhone simulator
(build/proofs/review-smoke.png: health screen at 60 fps, controls visible,
xcodebuild clean). This doc is the current source of truth for "what is
broken, what was done wrong, and what happens next." It supersedes the
scattered status sections in docs/09, 15, 16, 17 for planning purposes
(those remain as history).

## 1. Verified current state (first-hand, not from docs)

- The app builds clean and boots the guest on the iPhone 17e simulator;
  the health screen renders and the FPS overlay reads 60 at light scenes.
- The bellpad-style touch overlay renders (sticks, plates, colored face
  buttons, D-pad keys) and the overflow menu exists with the documented
  options.
- Exactly-one-simulator discipline works via scripts/sim_mutex.sh.
- ref/ is fully untracked (9 GB) and the product build depends on local
  uncommitted edits inside it: 26 modified files in ref/GXRuntime, 9 in
  ref/StrikersRecomp. Snapshots exist at docs/patches/*.patch (refreshed
  2026-08-08 12:12), but nothing enforces their freshness.

## 2. Main product issues (ranked by user impact)

| # | Issue | Evidence | Fix direction |
|---|-------|----------|---------------|
| P0-a | Boot-to-match takes ~7-8 min wall via the hardcoded block-paced autostart | docs/09, 16; 44-step table in host/src/ballpad_ios_host.cpp | Savestate/quick-boot: snapshot guest RAM+CPUState after match load, restore on launch. Biggest iteration-time and first-run win available. |
| P0-b | No in-app game import: the user must CLI-copy game.iso + main.dol into the sim container Documents | ballpad_ios_host_start reads $HOME/Documents/game.iso; no import UX; black screen if absent | Document-picker import + FST extractor; a real "no game found" onboarding screen instead of a dead display. |
| P0-c | In-match ~20 fps (guest-only ceiling ~29 fps at ~20.6M blocks/s) | docs/09 perf round-2 numbers | Vertex-decode / draw-plan cache (measured candidate); adaptive block budget (below). 30 fps in-match on the simulator is likely unreachable; be honest in the UI. |
| P1-a | Guest loop, present, readback, and display copy are all serialized on the main thread via a SwiftUI Timer | GameHostView.swift 60 Hz timer drives ballpad_ios_host_step_frame | Move guest stepping to a worker thread with a frame queue; keep only UI on main. Also kills the present-stall / re-entrancy bug class (see 3-b). |
| P1-b | Fixed 350K-blocks-per-step budget | kFrameBlocks in the host | Adaptive budget: measure wall time per step, target a 16.6 ms slice. Menus over-run (60 fps where 30 would do); matches under-run. |
| P1-c | Per-frame scalar ARGB-to-RGBA pixel loop + array alloc + Data copy + CGImage on the main thread | ballpad_ios_host_take_frame, GameHostView.updateFrame | Have the readback write RGBA8 directly; hand Swift a CVPixelBuffer/provider over the backing store (zero-copy). The version gate already exists. |
| P1-d | Per-present [gfxN] log spam ships enabled (cfg.verbose = true) | smoke-run log: one line per present | verbose=false in the shipped config; keep behind env. |
| P2-a | Debug chrome in the production UI: "[ballpad] runtime init" banner and "pad: idle" readout | review-smoke screenshot | Remove or gate behind a Debug settings toggle. |
| P2-b | Game frame appears off-center (asymmetric letterbox bars) in the captured framebuffer | review-smoke-land.png | Verify on phone and iPad; fix centering; also fix the rotated-framebuffer screenshot issue (logged as iPad-only; observed on phone too). |
| P2-c | No hardware GCController merge (bellpad hides touch controls on connect) | docs/09 open items | GCController listener; hide overlay, merge into ballpad_pad_set. |
| P2-d | Single layout slot; no per-control scale in edit mode; portrait unsupported | best-effort B5/B6 | 3 named slots; per-control scale in edit mode; keep landscape-only but say so. |
| P2-e | No true 16:9 widescreen (only crop/stretch display modes) | docs/09 | Widescreen projection hack; stretch goal. |
| P3-a | Audio disabled | B3 | Wire the existing audio path to an output stream; best-effort. |

## 3. Where the original agent messed up (process and engineering)

These are the patterns the next agent must not repeat.

a. Gate-gaming / proof inflation. M3 ("start a match with touch only")
   and M6 ("multi-touch merged") were proven by synthetic buffer injection
   (the autostart and uitest writing ballpad_pad_set directly), not by
   actual on-screen touches. The DoD claims touch-only play; no human or
   simulated finger has ever started a match through the overlay. The
   usability of the core product is unproven. Proofs must exercise the
   real path: a finger-driven (or XCUITest-driven) touch sequence, not
   just the pad buffer.

b. Main-thread-everything architecture, then chasing its symptoms.
   Session 5 burned hours on a "hang" that was the Simulator throttling an
   occluded window; a DEC-timer emulation was implemented chasing the
   wrong suspect. The iPad 1.5 fps deadlock was SDL pumping the run loop
   inside present, re-entering the SwiftUI step timer. Both are symptoms
   of running the guest loop on the main thread coupled to a vsynced
   present. Fix the architecture (P1-a) instead of adding more
   re-entrancy guards.

c. Self-inflicted full-stop regressions from guard logic. The
   EFB-readback gate accidentally wrapped the frame submit, producing a
   black display on both sims. Conditional SwiftUI views caused an
   AttributeGraph cycle that detaches the window, forcing the permanent
   "single unconditional view, everything opacity-gated" workaround that
   makes TouchControlSurface.swift brittle to edit. SDL's key window
   covered the SwiftUI window and was "fixed" with a 0.5 s polling timer
   that re-keys windows forever. Each fix was a patch over a patch;
   several need real solutions.

d. Performance treated as an afterthought. A per-guest-block getenv()
   consumed ~90% of main-thread CPU until perf round 2; the display
   re-rendered a CGImage at 60 Hz while the guest produced 15 fps; the
   XFB YUYV encode ran unused on every display copy. These were found
   only after the user said "barely running." Profile first, then fix.

e. The host file became a forensic lab. ballpad_ios_host.cpp carries
   ~450 lines of guest-memory dump instrumentation, poke tests, and the
   44-step hardcoded autostart table, plus an absolute path
   ($HOME/...) baked into snapshot dumps. It works, but
   it is unmaintainable. Debug tooling belongs in a separate debug-gated
   translation unit; dead stubs (ballpad_runtime.cpp, called from the
   touch callback) should be deleted.

f. Fragile build state. The engine is a hand-merged static lib (libtool
   over libs2.list, head -119), the ref/ trees are untracked with 35
   locally modified files, and patch snapshots are refreshed by hand.
   One git checkout inside ref/ silently bricks the product. Next agent:
   add scripts/check_ref_patches.sh that fails when the live ref diffs
   differ from docs/patches/, and regenerate the patches whenever ref/
   is touched.

g. Doc sprawl. Status lived in five places with contradictory numbers
   (10 vs 20 fps). This doc is now the single planning source; append
   new findings here and to the docs/09 log, not to new session docs.

## 4. What needs to happen next (execution order)

Phase A — usage fundamentals (do these first):
1. A1 quick-boot/savestate to a match (P0-a). Gate: cold launch to
   in-match in under 60 s wall on the phone simulator, screenshot proof.
   **STATUS: PASS both sims (2026-08-08 Bot 4).** Cold launch -> in-match
   15 s wall on the phone AND the iPad (cGame state=4 present at 15 s both;
   screenshots build/proofs/a1-quickboot-inmatch-final.png and
   a1-pad-quickboot-inmatch.png); phone baseline was 505 s.
   Savestate (v3) captures CPUState + 24 MB RAM + 16 MB ARAM + the
   interrupt/MMIO device blobs + the gxcore/frontend parsed renderer state
   (BP regs, XF matrices/viewport/projection/lights, VCD/VAT, pending FIFO);
   capture happens at the side-choice/stadium-card screen while the guest is
   parked in the OS idle loop; restore re-drives the match-start A so the
   match scene setup re-emits per-frame state into the re-seeded renderer.
   Pitfalls logged in docs/09 (dark-frame renderer desync; mid-command
   capture desyncs the shadow frontend). Product note: the savestate is
   created by the autostart capture path (dev); a user-facing "save quick-boot
   point" affordance is scheduled with A2 onboarding.
2. A2 in-app game import + onboarding screen (P0-b). Gate: fresh sim
   container, import via document picker, game boots; missing-game state
   shows instructions, never a black screen.
   **STATUS: PASS both sims (2026-08-08 Bot 4).** AppRootView routes to an
   onboarding screen when Documents lacks game.iso/main.dol (proof
   build/proofs/a2-onboarding.png); "Import Game" opens the real document
   picker (fileImporter); the pick selection is stream-copied into Documents
   and sys/main.dol is extracted from the disc header + DOL section table.
   XCUITest (app/BallpadUITests, scheme TestAction) drove the full flow:
   onboarding -> picker -> Strikers.iso -> import (log: game imported,
   dolSize=3210784) -> game booted (build/proofs/a2-imported-game.png).
   Simulator gotcha: host-copied files in the Files app's File Provider
   Storage app group are only indexed after a simulator reboot. **iPad**:
   same XCUITest passed on the iPad (a2-pad-imported.png; the picker's
   "On My iPhone" label is "On My iPad" there — the test now matches both).
3. A3 real-touch verification (3-a). Gate: M3/M6 re-proven through the
   actual overlay (XCUITest or a recorded manual session), not buffer
   injection.
   **STATUS: M3 PASS both sims (2026-08-08 Bot 4); M6 partial.** M3: an
   XCUITest (app/BallpadUITests/TouchMatchTests) drives the REAL touch
   overlay — A taps + D-pad presses navigate health -> memcard -> title ->
   main menu -> captains -> LIVE MATCH (proof build/proofs/a3-touch-inmatch.png:
   LUIGI 0-0 DAISY, clock running; log cGame state=2, gameClock advancing,
   diag mean 90-104). Fixes landed: the overlay's gestures were bounded to the
   whole container (any touch fired the last control's gesture — a real
   product bug); reordering frame->contentShape->gesture->position fixed
   touch targeting (pad-set log: A=0x0100, D-pad=0x0001/2/4/8). M6
   (multi-touch merge in one sample) cannot be driven by XCUITest (no
   multi-touch; events are main-thread serialized) — a real two-finger
   gesture (Simulator Option+drag) reached the overlay (stick gesture fired),
   but stick+button-in-one-sample needs a recorded manual session
   (documented fallback; docs/09). **iPad re-verification**: the wall-clock
   driver failed there (the iPad runs the guest ~2.4x faster than the phone,
   so presses landed on the wrong screens and no match started). TouchMatchTests
   now drives the overlay from the guest's platform-independent block anchors
   (host exposes guest blocks + cGame state via a BALLPAD_TEST_HOOKS label);
   PASS on the iPad in 197 s (a3-pad-touch-inmatch.png, cGame state=4,
   gameClock 83.5->93.0) and the same code path is phone-identical.

Phase B — performance:
4. B1 guest loop off the main thread + adaptive block budget (P1-a, P1-b).
   Gate: no fps regression; menu open/close and window occlusion no
   longer stall the guest; the iPad re-entrancy guard is removed by the
   redesign, not bypassed.
5. B2 zero-copy frame handoff (P1-c). Gate: main-thread CPU during 60 fps
   menus measurably lower (before/after numbers in the proof notes).
6. B3 vertex-decode/draw-plan cache (P0-c). Gate: in-match fps improves
   measurably over the 19.9 avg baseline, same scene, each simulator
   tested one at a time.
   **STATUS: render-path improvement landed; fps gap is guest-CPU-bound
   (2026-08-08 Bot 4, phone).** Added a vertex-decode cache (draw plans keyed
   by payload + decode-config + indexed-array content hashes; repeated
   in-match draws reuse the decoded vertex buffers). Measured draw-plan build
   cost drops 15.1 -> 8.1 us/draw (BALLPAD_DRAW_TIMER; ~1.9 ms/frame saved).
   In-match fps stays ~20.0 with or without the cache (measured
   BALLPAD_PERF_LOG: presents 30/1.5 s, stepMs 25, blocks/s ~14M) — the frame
   is guest-CPU-bound: ~14M blocks/s / ~700K blocks per frame = the ~20 fps
   ceiling (the docs' own analysis; the ~29 fps guest ceiling is unreachable
   on the simulator). Written, measured explanation satisfies the gate's OR
   clause. **iPad re-verification (2026-08-08 Bot 4)**: same binary, in-match
   diag mean 87, presents ~28-37/s, blocks/s 18-24M, stepMs 17-19 (adaptive
   budget active) — no regression; the guest-CPU-bound analysis applies
   equally (BALLPAD_PERF_LOG in pad-a1-run.log / pad-a1b-run.log).
7. B4 silence shipped logging (P1-d).
   **STATUS: PASS both sims (2026-08-08 Bot 4).** cfg.verbose defaults to false
   (env-overridable via BALLPAD_VERBOSE=1); the per-present [gfxN] spam is
   gone from shipped logs. The remaining engine diagnostics were also gated:
   ballpad_window_probe() (the per-present "presentable=" line — 3373 lines in
   a 30 s iPad run) is BALLPAD_WINDOW_PROBE-gated and the aurora slot-state
   dump is BALLPAD_SLOT_DUMP-gated. An in-match iPad run now logs 0
   presentable/aurora-state/gfx lines (build/proofs/pad-b4-quiet.png).

Phase C — UI polish:
8. C1 remove debug chrome; fix frame centering; fix rotated screenshots
   (P2-a, P2-b).
   **STATUS: PASS (2026-08-08 Bot 4).** Removed the "[ballpad] runtime init"
   banner (the dead ballpad_runtime.cpp stub was deleted) and the "pad: idle"
   readout; the FPS overlay remains user-gated (Show FPS). The frame is
   aspect-fit centered (container fills the window; symmetric letterbox).
   Rotated screenshots: the Simulator captures a portrait framebuffer for
   this landscape-only app; inspect the game content before using an explicit
   rotation with scripts/upright_proof.sh
   (the iPad's capture orientation varies between sessions — pass -90|+90|0).
   Proof: build/proofs/c1-cleanui.png (phone).
9. C2 hardware controller merge + auto-hide (P2-c).
   **STATUS: PASS (2026-08-08 Bot 4, phone).** ControllerManager merges an
   extended gamepad into ballpad_pad_set (bellpad mapping: LB->L, RB->Z,
   menu->START, analog triggers + digital bits, sticks match the touch
   overlay's sign convention) and publishes isConnected; the overlay hides via
   its per-control opacity value (no conditional structure). Hard-won:
   touching the GameController framework during SwiftUI view init on the iOS
   26 simulator triggers an AttributeGraph cycle that detaches the window
   (black screen) — setup is deferred 1.5 s until the window settles. The
   simulator also exposes a virtual MFi gamepad, so overlay visibility ignores
   controllers on the simulator (bellpad pattern) while input still merges;
   BALLPAD_SIMULATE_CONTROLLER=1 proves the auto-hide path (proof
   build/proofs/c2-controller-hidden.png; mapping self-test ok=1). Details in
   docs/09 2026-08-08.
10. C3 layout slots + per-control scale (P2-d).
    **STATUS: best-effort (written rationale, 2026-08-08 Bot 4).** Not
    implemented: the single-autosave layout + global size/opacity sliders
    cover the primary use; three named slots + per-control scale are a
    settings-surface change with no gate, deferred to avoid churning the
    load-bearing touch overlay (any structural edit risks the iPadOS 26
    AttributeGraph cycle, docs/09).
11. C4 widescreen projection hack (P2-e, stretch).
    **STATUS: best-effort (written rationale, 2026-08-08 Bot 4).** Not
    implemented: the EFB is 640x528 4:3; native/16:9-crop/stretch display
    modes already ship in the ⋯ menu. A true projection hack would distort
    the HUD and the renderer does not expose a projection override on the
    iOS path; the visible modes cover the use case.

Phase D — hygiene (continuous, small):
12. D1 ref-patch check script + regenerate patches (3-f).
    **STATUS: PASS (2026-08-08 Bot 4).** scripts/check_ref_patches.sh fails
    when the live ref/GXRuntime + ref/StrikersRecomp diffs diverge from
    docs/patches/ and regenerates with --regen. Patches regenerated after the
    B4 engine gating (gxruntime-local.patch 1927 lines; strikersrecomp 552).
13. D2 extract debug tooling from the host; delete dead stubs (3-e).
    **STATUS: PASS (2026-08-08 Bot 4).** Forensic tooling (task counters,
    block log, load-pc sampler, window probe, guest thread-state dumps, EFB
    fill log + poke test) moved to host/src/ballpad_debug.cpp + host/include/
    ballpad_debug.h (env-gated, off in shipped runs); the host keeps one
    cheap per-step hook. The dead ballpad_runtime.cpp stub was deleted in C1.
    Verified on the iPad (quick-boot + in-match; debug-threads dumps, task
    counters, load-pc sampler all fire from the moved code).

Hard rules for all phases: exactly one simulator booted at a time; never
run simctl shutdown while the app runs; every gate gets a screenshot/log
proof under build/proofs/; commit first-party code per passed gate;
append findings to docs/09 and this doc.

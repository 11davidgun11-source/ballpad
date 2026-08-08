# GOAL-BASED LOOP — Ballpad Bot 4 (Performance, UI, Usability)

Copy everything below the line into a new Codex chat as the first message.

---

You are **Bot 4**, an autonomous **improve-and-validate agent** working in the
local repository:

`/Users/chrissotraidis/GitHub/ballpad`

The game already boots and plays on the iPhone and iPad simulators. Your
mission is to make it **fast, polished, and actually usable**: better
performance, better UI, better first-run experience. You are not porting the
game; you are turning a working tech demo into a product.

You operate as a **goal-based loop**. You do not stop until the exit criteria
below are satisfied.

## Read first (in this order)
1. `docs/20-review-and-next-steps.md` — your work queue. This is law.
2. `docs/09-open-questions.md` — failure matrix and gotchas (read the
   2026-08-08 entries carefully; they encode hard-won simulator knowledge).
3. `docs/15-validation-log.md` — what is proven and how.
4. `docs/10-bot2-operating-manual.md` + `build/env.sh` — build/run commands.

## The one-simulator rule (absolute)
- **Exactly one simulator may be booted at any time.** Before every boot:
  ```bash
  xcrun simctl shutdown all || true
  xcrun simctl boot "$BALLPAD_UDID"
  xcrun simctl bootstatus "$BALLPAD_UDID" -b
  ```
- Use `scripts/sim_mutex.sh` (`sim_boot`, `sim_only_one_booted`). Verify
  `xcrun simctl list devices | grep -c Booted` is 1 before every gate run.
- **Never** run `simctl shutdown` while the app is running: it kills the HID
  connection and the app SIGABRTs (confirmed artifact, docs/09). Terminate
  the app first, then shut down.
- Do phone work first (`BALLPAD_PHONE_UDID`), then shut down fully and repeat
  on iPad (`BALLPAD_PAD_UDID`). Never both.

## Other non-negotiables
1. User-supplied ISO only (`.local-assets/`); never commit ISO/dol/generated/
   saves.
2. AOT guest code only; no JIT/RWX.
3. **Never re-clone or `git checkout` inside `ref/`.** 35 files there carry
   local patches the build depends on. If you touch ref/, regenerate
   `docs/patches/*.patch` in the same commit.
4. **Proofs must exercise the real path.** The previous agent's biggest
   failure was proving touch gates by injecting the pad buffer directly.
   Touch gates are only proven by driving the actual overlay (XCUITest,
   `simctl` input, or a recorded manual session) with screenshots/video.
5. Profile before optimizing. Every perf claim needs before/after numbers
   (`BALLPAD_PERF_LOG=1` gives blocks/s and present counts).
6. Small commits of first-party code per passed gate. Append findings to
   `docs/20-review-and-next-steps.md` and `docs/09-open-questions.md`.

## The loop
1. Select the lowest-numbered unfinished item from the phase list below
   (full detail: docs/20 section 4).
2. Establish the baseline measurement BEFORE changing anything.
3. Make the smallest change that satisfies the item's gate.
4. Build, install, run on ONE simulator, capture proof into
   `build/proofs/` (screenshot + log excerpt + numbers).
5. If the gate fails twice the same way: roll back, log in docs/09, take
   the documented fallback or pick a different approach, retry.
6. Commit. Update docs/20 status. Advance.

Maintain `build/proofs/PROGRESS.md` every loop (current item, baseline,
result, next action).

## Phase list (execute in order; gates in docs/20 section 4)
- **Phase A — usage fundamentals**
  - A1 quick-boot/savestate: cold launch → in-match < 60 s wall.
  - A2 in-app game import (document picker) + onboarding screen; a missing
    game must never show a black screen.
  - A3 re-prove M3/M6 through the real touch overlay.
- **Phase B — performance**
  - B1 guest loop off the main thread + adaptive block budget (replace the
    fixed 350K-blocks step and the SwiftUI-Timer drive).
  - B2 zero-copy frame handoff (kill the scalar ARGB→RGBA loop, the per-frame
    array alloc, and the Data copy; CVPixelBuffer or direct provider).
  - B3 vertex-decode/draw-plan cache; target measurable in-match fps gain
    over the 19.9 avg baseline.
  - B4 ship with `verbose=false`; no per-present logging.
- **Phase C — UI polish**
  - C1 remove debug chrome (runtime banner, pad readout); fix game-frame
    centering; fix rotated screenshot capture.
  - C2 hardware GCController support: merge input, auto-hide touch overlay.
  - C3 three layout slots + per-control scale in edit mode.
  - C4 true 16:9 widescreen projection hack (stretch).
- **Phase D — hygiene (continuous)**
  - D1 `scripts/check_ref_patches.sh`: fail if live ref diffs differ from
    docs/patches/; regenerate patches whenever ref/ changes.
  - D2 move forensic/debug tooling out of `ballpad_ios_host.cpp` into a
    debug-gated file; delete dead stubs (`ballpad_runtime.cpp`).

## Known traps (do not re-learn these the hard way)
- The Simulator throttles rendering when its window is occluded — the guest
  loop is present-coupled until B1 lands, so keep the Simulator window
  visible during gate runs or your fps numbers are garbage.
- ANY conditional view structure in the touch overlay triggers an iPadOS 26
  AttributeGraph cycle that detaches the window. All differentiation must be
  value expressions + `.opacity()` gating in one unconditional view.
- The SDL window steals key status and covers the SwiftUI window; the current
  mitigation is a 0.5 s re-key timer in SceneDelegate. Treat it as load-
  bearing until B1 lets you remove SDL from the UI path entirely.
- stderr without `BALLPAD_LOG_FILE` can block the app when the console pipe
  fills. Always launch with the log file set:
  ```bash
  SIMCTL_CHILD_BALLPAD_LOG_FILE=$PWD/work/tmp/run.log \
    xcrun simctl launch --terminate-running-process "$BALLPAD_UDID" com.ballpad.strikers
  ```
- iPad sim screenshots capture a rotated portrait framebuffer; rotate ±90°
  before judging layout (this affects the phone too — C1).

## Build/run cheat sheet
```bash
source build/env.sh && source scripts/sim_mutex.sh
sim_boot "$BALLPAD_PHONE_UDID"          # or BALLPAD_PAD_UDID, never both
xcodebuild -project app/Ballpad.xcodeproj -scheme Ballpad \
  -destination "id=$BALLPAD_UDID" -derivedDataPath build/DerivedData build
APP=$(find build/DerivedData/Build/Products -name Ballpad.app -type d | head -1)
xcrun simctl install "$BALLPAD_UDID" "$APP"
SIMCTL_CHILD_BALLPAD_LOG_FILE=$PWD/work/tmp/run.log \
  xcrun simctl launch --terminate-running-process "$BALLPAD_UDID" com.ballpad.strikers
xcrun simctl io "$BALLPAD_UDID" screenshot build/proofs/ITEM-screen.png
# Engine changes also need: rebuild gxruntime_aurora, re-merge
# libBallpadEngine.a (see docs/16 "Commands that matter").
```

## Exit criteria (all required)
1. Every Phase A and Phase B gate green, with proofs, on BOTH simulators
   (tested one at a time).
2. In-match fps measurably above the 19.9 baseline, or a written, measured
   explanation of why the remaining gap is guest-CPU-bound.
3. No debug chrome in the default UI; game frame centered; screenshots
   upright.
4. docs/20 updated with final status; docs/09 log appended; patches fresh.
5. `git status` clean except untracked ref/; no simulators left booted.

Phase C is required through C2; C3/C4 are best-effort with written rationale.

**Begin with Phase A1 immediately and continue autonomously.**

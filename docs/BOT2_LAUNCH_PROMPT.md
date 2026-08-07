# GOAL-BASED LOOP — Ballpad Bot 2 (Build + Simulator Validation)

Copy everything below the line into a new Codex chat as the first message.

---

You are **Bot 2**, an autonomous **build-and-validate agent** working in the local repository:

`/Users/chrissotraidis/GitHub/ballpad`

Your mission is to turn the Phase 1 research/plan corpus already in this repo into a **working native Super Mario Strikers (GameCube USA G4QE01) app** for **iOS Simulator and iPadOS Simulator**, with **world-class touch controls** and the **in-app overflow menu**.

You operate as a **goal-based loop**. You do not stop until the Definition of Done is fully satisfied.

## What is already done (do not redo research)
Phase 1 is complete. Treat these as law:

- Research clones: `ref/` + `ref/INDEX.md`
- Plans/specs: `docs/` (same as `DOCS/` on macOS)
- Start-here docs:
  1. `docs/10-bot2-operating-manual.md`
  2. `docs/11-target-repo-layout.md`
  3. `docs/07-build-plan.md`  (execution bible, steps 0-15)
  4. `docs/12-acceptance-proofs.md` (final scoreboard)
  5. `docs/02-native-path.md`, `docs/03-simulator-harness.md`
  6. `docs/05-touch-control-spec.md`, `docs/06-menu-spec.md`
  7. `docs/09-open-questions.md` (risks / failure matrix)

Read those before inventing architecture.

## Non-negotiable constraints
1. **User-supplied ISO only.** Path:
   - `$STRIKERS_ISO` or
   - `.local-assets/Super Mario Strikers.iso`
   Never commit ISO, `main.dol`, `generated/`, saves, or game assets.
2. **AOT guest code only on iOS.** No Dolphin JIT, no RWX, no runtime code generation, no unsigned downloaded executable modules.
3. **Exactly one simulator booted at a time.**
   Always:
   ```bash
   xcrun simctl shutdown all || true
   xcrun simctl boot "$BALLPAD_UDID"
   xcrun simctl bootstatus "$BALLPAD_UDID" -b
   ```
   Never leave iPhone and iPad simulators booted together.
4. **Touch controls are the core product**, not polish. Implement `docs/05-touch-control-spec.md` from scratch.
5. **Self-verify every gate** with proof files under `build/proofs/`. No honor system.
6. Prefer path pins into existing `ref/` clones over re-cloning the internet.

## Architecture decisions (do not re-debate)
- Codegen: DolRecomp from local ISO to generated C chunks
- Game glue: StrikersRecomp + symbols from smstrikers-decomp
- First macOS frame: try **Path S** first (StrikersRecomp + GXRuntime + Aurora)
- If Path S blocked: **Path C** (`gG4QE01_recomp` module + RecompCore/ModernGekko)
- iOS product host: Path-S-shaped AOT host (no JIT required on simulator/device)
- Input ABI: `ballpad_pad_set(port, BallPadStatus*)` compatible with Aurora/Dolphin PAD bits
- UI shell: first-party `app/` + `host/` per `docs/11-target-repo-layout.md`
- Menu: `docs/06-menu-spec.md` (overflow menu, 1x-4x scale, saves, layout editor)

## The loop (repeat until Done)
1. **Select** the lowest unfinished step in `docs/07-build-plan.md` (Steps 0 to 15).
2. **Act** using the step's exact actions/commands.
3. **Build/run/test** as required by that step.
4. **Validate the gate.** If fail: reproduce once, rollback, log `docs/09-open-questions.md`, take fallback, retry.
5. **Record proof** in `build/proofs/step-NN-*` and update `build/proofs/PROGRESS.md`.
6. **Commit** only first-party code (`app/`, `host/`, `scripts/`, docs updates) when a meaningful gate passes.
7. Advance only after the gate is proven.

Maintain `build/proofs/PROGRESS.md` every loop:

```markdown
# Bot 2 progress
- Current step:
- Path choice: S or C
- Last gate:
- Blockers:
- Next action:
```

## Simulator testing mandate
You must actually drive the simulators for iOS work (not just compile).

### Mutex + boot
```bash
source build/env.sh
source scripts/sim_mutex.sh   # create in Step 0/6 per docs/11
sim_boot "$BALLPAD_UDID"      # shuts down all first
```

### Build / install / launch / proof
```bash
xcodebuild -project app/Ballpad.xcodeproj -scheme Ballpad \
  -destination "id=$BALLPAD_UDID" \
  -derivedDataPath build/DerivedData build

APP=$(find build/DerivedData/Build/Products -name "Ballpad.app" -type d | head -1)
xcrun simctl install "$BALLPAD_UDID" "$APP"
xcrun simctl launch --terminate-running-process --console-pty \
  "$BALLPAD_UDID" "${BALLPAD_BUNDLE_ID:-com.ballpad.strikers}" \
  | tee "build/sim-logs/$(date +%Y%m%d-%H%M%S).log"

sleep 5
xcrun simctl io "$BALLPAD_UDID" screenshot "build/proofs/step-XX-screen.png"
```

### Phone then pad (sequential)
- Do iPhone gates first (`BALLPAD_PHONE_UDID`).
- Then shutdown all and repeat on iPad (`BALLPAD_PAD_UDID`).
- Capture separate proofs for both.

Full harness details: `docs/03-simulator-harness.md`.

## Step map (from docs/07 — execute in order)
0. Repo hygiene + skeleton (`app/`, `host/`, `scripts/`, `work/`, `build/proofs/`)
1. Toolchain + resolve phone/pad UDIDs into `build/env.sh`
2. Generate recomp output into `work/strikers/generated/` (chunk count >= 150, dispatch marker, sdk_symbols)
3. First macOS frame (Path S preferred, else Path C) + screenshot proof
4. macOS match smoke (~60s)
5. Freeze PAD injection ABI (`host/include/ballpad_pad.h`) and prove injected A works
6. Empty iOS app shell launches on **iPhone simulator**
7. Link AOT runtime into simulator build (no JIT)
8. First guest frame on **iPhone simulator**
9. Touch MVP (stick, A/B, Start, L/R digital) — playable menus/match start by touch
10. Full GameCube control set + classic skin
11. Layout editor + persistence across relaunch
12. Overflow menu + resolution 1x/2x required (3x/4x best effort)
13. Save import/export round-trip
14. **iPad simulator** parity (mutex switch; playable match + layouts)
15. Fill `docs/15-validation-log.md` from `docs/12-acceptance-proofs.md`

Exact commands, gates, rollbacks, timeboxes: **`docs/07-build-plan.md`**.

## Critical implementation contracts

### PAD bits (port 0)
Use Aurora/Dolphin-compatible masks, including:
- A `0x0100`, B `0x0200`, X `0x0400`, Y `0x0800`, Start `0x1000`
- Z `0x0010`, R digital `0x0020`, L digital `0x0040`
- D-pad L/R/D/U `0x0001/2/4/8`
- sticks `int8` [-127,127], triggers `uint8` 0..255
- virtual controller should present as connected (`err = 0`)

### Frame loop
```
sample touches -> ballpad_pad_set(0, &status) -> runtime.frame()
```

### Generate (Step 2 shape)
Prefer:

```bash
python3 ref/StrikersRecomp/tools/generate.py \
  --iso "$STRIKERS_ISO" \
  --dolrecomp "$REPO_ROOT/ref/DolRecomp-aharonahdoot" \
  --output "$REPO_ROOT/work/strikers/generated" \
  --jobs "$(sysctl -n hw.ncpu)"
```

Fallback DolRecomp: `ref/DolRecomp`.
Also build `sdk_symbols.inc` via `ref/StrikersRecomp/tools/symbols.py` against `ref/smstrikers-decomp`.

## Definition of Done (all required)
Using `docs/12-acceptance-proofs.md` must-pass items on **both** phone and pad simulators:

1. Cold launch works
2. Visible guest frame to title/menu
3. Start a match with **touch only**
4. Survive >= 60s in-match without crash
5. Full GC controls functional
6. Multi-touch stick + face button
7. Layout editor works and **persists after relaunch**
8. Overflow menu works; resolution **1x and 2x** work
9. Save export/import round-trip
10. Only one simulator booted during each test session
11. No ISO/dol/generated in git
12. iOS build does not require JIT/RWX
13. Results written to `docs/15-validation-log.md`
14. Open issues appended to `docs/09-open-questions.md`

Best-effort (waivable with written rationale): 3x/4x scale, audio, hardware controller merge.

## Discipline
- Small commits of first-party code per passed gate.
- Never commit secrets, assets, or generated guest blobs.
- If blocked twice the same way: log failure matrix entry in docs/09 and switch fallback.
- Do not expand scope to netplay, multiplayer ports 1-3, or App Store release engineering.
- Do not rebuild Phase 1 research corpus unless a source is missing from disk.

## First actions right now
1. Read `docs/10-bot2-operating-manual.md` and `docs/11-target-repo-layout.md`.
2. Open `docs/07-build-plan.md` Step 0.
3. Create `build/proofs/PROGRESS.md`.
4. Verify ISO exists and is gitignored.
5. Execute Step 0 -> Step 1 -> ... without skipping gates.
6. When you reach iOS steps, test on simulator with screenshots/logs every gate.
7. Finish only when docs/12 must-pass is green for phone **and** pad.

**Begin Step 0 immediately and continue autonomously until Definition of Done.**

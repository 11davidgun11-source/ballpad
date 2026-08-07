# 07 — Gated build plan (Bot 2 execution bible)

**Rule zero:** Do not advance past a step until its **Gate** passes and a **Proof** artifact is written under `build/proofs/step-NN-*`.
**Rule one:** If a gate fails twice with the same root cause, apply **Rollback**, log in `DOCS/09-open-questions.md`, then take the documented **Fallback**.
**Rule two:** Never commit ISO / `generated/` / saves / DerivedData.

Companion docs: [02](02-native-path.md) · [03](03-simulator-harness.md) · [05](05-touch-control-spec.md) · [06](06-menu-spec.md) · [10-bot2-operating-manual.md](10-bot2-operating-manual.md) · [11-target-repo-layout.md](11-target-repo-layout.md) · [12-acceptance-proofs.md](12-acceptance-proofs.md)

---

## Path selection (read before Step 3)

| Path | When to use | Success signal |
|------|-------------|----------------|
| **C — Chassis** (ModernGekko or RecompCore + `gG4QE01_recomp` module) | First macOS playable / accuracy | Full-speed match on macOS Metal |
| **S — Standalone** (StrikersRecomp + GXRuntime + Aurora) | iOS-bound host; lighter surface | Windowed boot to menu/match (may be slower) |

**Default sequence:** prove Path C or Path S on macOS (whichever builds cleanly first), freeze guest+HLE, then port Path S host into iOS Simulator.
If Path C fails to build, switch to Path S immediately. If Path S match FPS is poor, still proceed to touch/menu on iOS once frames present.

Pinned research clones live under `ref/`. Prefer path references into `ref/` over re-cloning. Workspace layout is in [11](11-target-repo-layout.md).

---

## Environment variables (export every session)

```bash
export REPO_ROOT="$(git rev-parse --show-toplevel)"
export STRIKERS_ISO="${STRIKERS_ISO:-$REPO_ROOT/.local-assets/Super Mario Strikers.iso}"
export BALLPAD_BUNDLE_ID="${BALLPAD_BUNDLE_ID:-com.ballpad.strikers}"
# Resolve once in Step 1; persist to build/env.sh
# export BALLPAD_PHONE_UDID=...
# export BALLPAD_PAD_UDID=...
# export BALLPAD_UDID=$BALLPAD_PHONE_UDID
```

---

### Step 0 — Repo hygiene and skeleton
**Goal:** Safe workspace layout so later steps have homes for code.

**Actions:**
1. Verify `.gitignore` blocks: `.local-assets/`, `*.iso`, `generated/`, `build/`, `DerivedData/`, saves, `.DS_Store`.
2. Create layout from [11-target-repo-layout.md](11-target-repo-layout.md) (`app/`, `host/`, `scripts/`, `build/proofs/`).
3. Write `build/env.sh` template (empty UDIDs OK).
4. Confirm ISO exists and is not tracked:

```bash
test -f "$STRIKERS_ISO"
git check-ignore -v "$STRIKERS_ISO" || true
```

**Gate:**
- Directories exist per layout doc
- `test -f "$STRIKERS_ISO"` succeeds
- ISO is ignored by git

**Proof:** `build/proofs/step-00-layout.txt` listing `find app host scripts -maxdepth 2` and ignore check output.

**Rollback:** delete only empty skeletons you created; never delete `DOCS/` or `ref/`.

**Timebox:** 30 min.

---

### Step 1 — Toolchain and simulators
**Actions:**

```bash
cmake --version
ninja --version || true
python3 --version
xcodebuild -version
xcrun simctl list devices available
```

Install missing pieces with Homebrew: `brew install cmake ninja pkg-config`.

Resolve UDIDs (one iPhone + one iPad; prefer stock names):

```bash
xcrun simctl list devices available -j > build/proofs/step-01-simdevices.json
# set BALLPAD_PHONE_UDID / BALLPAD_PAD_UDID in build/env.sh
```

**Gate:** cmake + python3 + xcodebuild present; JSON contains at least one iPhone and one iPad available.

**Proof:** `build/proofs/step-01-toolchain.txt` with command outputs and chosen UDIDs.

**Rollback:** n/a.

**Timebox:** 30 min.

---

### Step 2 — Offline recomp generation (G4QE01)
**Preferred commands** (using research clones):

```bash
source build/env.sh
mkdir -p work/strikers

python3 ref/StrikersRecomp/tools/generate.py \
  --iso "$STRIKERS_ISO" \
  --dolrecomp "$REPO_ROOT/ref/DolRecomp-aharonahdoot" \
  --output "$REPO_ROOT/work/strikers/generated" \
  --jobs "$(sysctl -n hw.ncpu)"

# Re-run dispatch fix if marker missing
python3 - <<"PY"
from pathlib import Path
import sys
sys.path.insert(0, "ref/StrikersRecomp/tools")
from fix_generated import fix_generated_sources
print("fixes", fix_generated_sources(Path("work/strikers/generated")))
PY

python3 ref/StrikersRecomp/tools/symbols.py \
  --decomp ref/smstrikers-decomp \
  --aurora ref/GXRuntime/graphics/aurora \
  --out work/strikers/generated/sdk_symbols.inc
```

If `DolRecomp-aharonahdoot` fails, retry with `ref/DolRecomp` and note the pin in `DOCS/09`.

**Gate (all must pass):**
- `work/strikers/generated/generated.h` exists
- chunk count `ls work/strikers/generated/chunks/*.c | wc -l` is >= 150 (expect about 163)
- `rg -n "DolRecomp constant-time chunk dispatch" work/strikers/generated/generated.h` matches
- `work/strikers/generated/main.dol` exists (local only)
- `work/strikers/generated/sdk_symbols.inc` is non-empty
- nothing under `work/` is staged for commit

**Proof:** `build/proofs/step-02-generate.txt` with chunk count, marker grep, file sizes. Do not copy `main.dol` into proofs.

**Rollback:** delete `work/strikers/generated/`.

**Fallback:** extract `main.dol` manually then `generate.py --dol path/to/main.dol`.

**Timebox:** 2 h (first DolRecomp build dominates).

---

### Step 3 — First macOS frame (Path C or S)
Try **Path S first** for continuity to iOS. If link/boot fails hard, switch to Path C.

#### Path S

```bash
cmake -S ref/StrikersRecomp -B work/strikers/build-s \
  -DSTRIKERSRECOMP_GXRUNTIME_DIR=$REPO_ROOT/ref/GXRuntime \
  -DSTRIKERSRECOMP_GENERATED_DIR=$REPO_ROOT/work/strikers/generated \
  -DCMAKE_BUILD_TYPE=Debug
cmake --build work/strikers/build-s -j"$(sysctl -n hw.ncpu)"
STRIKERS_ISO="$STRIKERS_ISO" ./work/strikers/build-s/StrikersRecomp \
  --max-blocks 5000000 2>&1 | tee build/proofs/step-03-pathS.log
# Capture GUI screenshot when title/menu is visible:
# build/proofs/step-03-macos-frame.png
```

#### Path C

```bash
ln -sfn "$REPO_ROOT/work/strikers/generated" ref/StrikersRecomp/generated
bash ref/StrikersRecomp/tools/package_module.sh "$REPO_ROOT/work/dolphin-user"

cmake -S ref/RecompCore -B work/recompcore-build -GNinja \
  -DCMAKE_BUILD_TYPE=Release -DENABLE_QT=OFF -DENABLE_NOGUI=ON -DUSE_MGBA=OFF
ninja -C work/recompcore-build dolphin-emu-nogui
./work/recompcore-build/Binaries/dolphin-emu-nogui \
  -e "$STRIKERS_ISO" -u "$REPO_ROOT/work/dolphin-user" -v Metal \
  -C Dolphin.Core.CPUCore=6 \
  2>&1 | tee build/proofs/step-03-pathC.log
```

If RecompCore is painful, use ModernGekko (`ref/ModernGekko` / template flow) as chassis instead and record that choice.

**Gate:** boot past entry with graphics present, or interactive window shows title/menu. Screenshot `build/proofs/step-03-macos-frame.png` is non-black.

**Proof:** log + screenshot + `build/proofs/step-03-path-choice.txt` stating `PATH=S` or `PATH=C` and why.

**Rollback:** wipe build dirs for the failed path; try the other path.

**Timebox:** 4 h.

---

### Step 4 — macOS match smoke
**Actions:** From Step 3 binary, reach in-match gameplay with keyboard/gamepad. Hold about 60s.

Aurora/GXRuntime default keyboard bindings include J/K for A/B and WASD-style stick (see `ref/GXRuntime/backends/aurora/aurora_backend.cpp`).

**Gate:** `build/proofs/step-04-midmatch.png` plus log without crash for >= 60s wall time.

**Proof:** screenshot + `step-04-duration.txt` with timestamps.

**Rollback:** if menus work but match crashes, document HLE gap in DOCS/09. You may still proceed to iOS shell if Step 3 frame gate holds, but playability risk must be marked.

**Timebox:** 2 h.

---

### Step 5 — PAD injection ABI freeze
**Actions:** Implement stable C ABI in `host/include/ballpad_pad.h` and `host/src/ballpad_pad.c` (see layout doc and DOCS/05 section 7). Wire so each frame guest `PADRead` observes injected port 0.

**Acceptance test:**

```c
BallPadStatus s = {0};
s.button = 0x0100; /* PAD_BUTTON_A */
s.err = 0;         /* PAD_ERR_NONE */
ballpad_pad_set(0, &s);
```

Confirm in-game menu accept or pass.

Exact bit values (from Aurora `pad.h`):

| Button | Mask |
|--------|------|
| LEFT | 0x0001 |
| RIGHT | 0x0002 |
| DOWN | 0x0004 |
| UP | 0x0008 |
| Z | 0x0010 |
| R digital | 0x0020 |
| L digital | 0x0040 |
| A | 0x0100 |
| B | 0x0200 |
| X | 0x0400 |
| Y | 0x0800 |
| START | 0x1000 |

Axes: `stickX/Y`, `substickX/Y` as `int8_t` in [-127,127]; triggers `uint8_t` 0..255.

**Gate:** proof that injected A changes game state.

**Proof:** `build/proofs/step-05-pad-a.png` plus short note.

**Rollback:** keep stock SDL path behind `#ifndef BALLPAD_PAD_BRIDGE`.

**Timebox:** 3 h.

---

### Step 6 — iOS app shell (empty)
**Actions:** Create `app/Ballpad.xcodeproj` with bundle ID `$BALLPAD_BUNDLE_ID`, iOS 16+/17+, placeholder host view, debug label `ballpad shell`.

```bash
source build/env.sh
source scripts/sim_mutex.sh
sim_boot "$BALLPAD_PHONE_UDID"
xcodebuild -project app/Ballpad.xcodeproj -scheme Ballpad \
  -destination "id=$BALLPAD_PHONE_UDID" \
  -derivedDataPath build/DerivedData build
APP=$(find build/DerivedData/Build/Products -name "Ballpad.app" -type d | head -1)
xcrun simctl install "$BALLPAD_PHONE_UDID" "$APP"
xcrun simctl launch --terminate-running-process "$BALLPAD_PHONE_UDID" "$BALLPAD_BUNDLE_ID"
sleep 2
xcrun simctl io "$BALLPAD_PHONE_UDID" screenshot build/proofs/step-06-shell.png
sim_shutdown_all
```

**Gate:** launch exit 0; screenshot shows shell UI.

**Proof:** screenshot + xcodebuild log tail.

**Rollback:** recreate project from template.

**Timebox:** 3 h.

---

### Step 7 — Link AOT runtime into simulator binary
**Actions:**
- Compile generated chunks + host runtime for `arm64-apple-ios-simulator`
- Fail the build if JIT-only Dolphin TUs are linked into the iOS target
- Prefer static link of recomp objects into the app binary

**Gate:**
- App launches with runtime log banner such as `[ballpad] runtime init`
- Binary does not require RWX entitlements
- Screenshot captured

**Proof:** `step-07-link.txt` and screenshot.

**Rollback:** feature-flag runtime behind `BALLPAD_ENABLE_RUNTIME=0`.

**Timebox:** 1 day.

---

### Step 8 — First guest frame on iPhone simulator
**Actions:** Disc/asset import into app container. Boot to legal/title/menu. Phone UDID only.

**Gate:** non-black `build/proofs/step-08-iphone-menu.png`; no fatal DVD/missing dol; mutex respected.

**Proof:** screenshot + log excerpt + `simctl list | grep Booted` showing a single device.

**Rollback:** pre-extracted FST in container (user-provided, gitignored).

**Timebox:** 1 day.

---

### Step 9 — Touch MVP
**Actions:** stick + A/B + Start + L/R digital per DOCS/05. Wire to `ballpad_pad_set`.

**Gate:** using only touch, navigate menus and start a match. Multi-touch stick + A works.

**Proof:** at least 3 screenshots (menu, team select, in-match) plus notes.

**Rollback:** temporary huge debug buttons.

**Timebox:** 1 day.

---

### Step 10 — Full GC set + classic skin
**Actions:** C-stick, dpad, X/Y, Z, analog triggers, classic colors/shapes.

**Gate:** `build/proofs/step-10-controls.md` checklist with each control OK/FAIL.

**Proof:** checklist + overlay screenshot.

**Rollback:** hide failing controls temporarily; Definition of Done still requires all controls before finish.

**Timebox:** 1 day.

---

### Step 11 — Layout editor + persistence
**Actions:** Edit mode per DOCS/05; per-deviceClass JSON slots.

**Gate:**
1. Move A button
2. `simctl terminate` app
3. Relaunch — A remains moved

**Proof:** before/after screenshots + JSON copy under `build/proofs/layouts/`.

**Timebox:** 1 day.

---

### Step 12 — Menu + resolution 1x-4x
**Actions:** Implement DOCS/06. Wire `renderScale`.

**Gate:** scales 1 and 2 required; 3 and 4 best effort. Log `[menu] scale=N` and screenshots `step-12-scale-N.png`.

**Proof:** screenshots + settings dump.

**Timebox:** 1 day.

---

### Step 13 — Save management
**Actions:** List/import/export card files.

**Gate:** export then delete then import restores progress or matching card hash.

**Proof:** `step-13-save-roundtrip.md` with hashes/timestamps.

**Timebox:** 4 h.

---

### Step 14 — iPad simulator parity
**Actions:**

```bash
sim_shutdown_all
export BALLPAD_UDID=$BALLPAD_PAD_UDID
# rebuild/install if needed; launch; use iPad layout defaults
```

**Gate:** `step-14-ipad-match.png`; phone not left Booted; playable match with touch; menu scale 1-2 works.

**Proof:** screenshots + mutex verification.

**Timebox:** 4 h.

---

### Step 15 — Validation package and handoff
**Actions:** Execute checklist in [12-acceptance-proofs.md](12-acceptance-proofs.md). Write results to `DOCS/15-validation-log.md`.

**Gate:** all must-pass items green or explicitly waived with rationale in DOCS/09.

**Proof:** validation log + index of all `build/proofs/step-*`.

**Timebox:** 4 h.

---

## Parallelism rules
- Never parallelize simulator boots.
- After Step 2, macOS bring-up and empty iOS shell (Step 6) may proceed in parallel, but Step 7 needs a chosen host approach from Step 3.

## Stop conditions (escalate to human)
- ISO missing or wrong game ID (not G4QE01)
- Apple signing completely broken on the machine
- Both Path C and Path S cannot present any frame after one full day of good-faith attempts
- Legal uncertainty about distributing a GPL binary (document; continue simulator work)

## Definition of Done
Phone sim playable match + iPad sim playable match + editable controls + working menu (scale + saves) + proofs + no illegal assets in git.

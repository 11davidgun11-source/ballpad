# Ballpad

<p align="center">
  <strong>Super Mario Strikers on iPhone and iPad through static recompilation and Metal.</strong><br>
  Full GameCube touch controls, native controller support, local game import, and no bundled game data.
</p>

<p align="center">
  <img alt="Configured iOS target" src="https://img.shields.io/badge/configured%20iOS%20%2F%20iPadOS%20target-17%2B-0A84FF?logo=apple">
  <img alt="Metal renderer" src="https://img.shields.io/badge/renderer-Metal-5E5CE6">
  <img alt="Ahead-of-time static recompilation" src="https://img.shields.io/badge/PowerPC-static%20recompilation-FF9F0A">
  <img alt="Game data not included" src="https://img.shields.io/badge/game%20data-not%20included-FF453A">
</p>

Ballpad is a native Apple app around a DolRecomp-generated Super Mario
Strikers module and the GXRuntime/Aurora compatibility runtime. The original
GameCube PowerPC code runs as ahead-of-time recompiled host code—there is no
runtime PowerPC JIT—while Metal presents the game on iOS and iPadOS.

The app imports a user-provided supported disc image through Files, keeps game
data and saves inside its sandbox, and provides a landscape GameCube control
surface. This repository contains Ballpad's first-party app, host bridge,
patches, tests, and reproducible development commands. It does **not** contain
Super Mario Strikers, a GameCube image, extracted Nintendo assets, user saves,
or a generated game module.

## Current status

| Area | Current result |
|---|---|
| Native app | Universal arm64 iPhone/iPad development target; iPhone 17e and iPad A16 Simulator paths exercised |
| Rendering | The decomp-aligned GXCore path is now the product default: fresh phone/iPad replay EFBs pass the mustard-background regression, while live Aurora remains an explicit diagnostic opt-out (`DOL_GX_CORE=0`). |
| Game setup | Local Files import validates a raw `G4QE01` revision 0 image before staged activation |
| Touch | Move stick, C-stick, D-pad, A/B/X/Y/Z, L/R, Start, editable positions, per-control sizing, global size/opacity |
| Controllers | Thread-safe touch + GameController mixing; touch controls can hide automatically on connection |
| Menu | Persistent Sunpad-style **•••** menu for display, controls, game reimport, memory-card transfer, FPS, and diagnostics |
| Performance | Dedicated guest thread, adaptive work budget, unchanged-frame skipping, draw-plan cache, and memcpy frame staging |
| Saves | Sandboxed Slot A card with native Files import and share-sheet export |
| Audio | Enabled by default; fresh boot playback exercised on iPad A16 Simulator (physical-device audibility/lifecycle still unproven) |
| QuickBoot | Disabled by default: its CPU/RAM restore does not yet restore all live Aurora GX gameplay state. `BALLPAD_ENABLE_QUICKBOOT=1` is diagnostic-only until moving-match parity passes. |
| Decomp integration | The exact game DOL matches the complete function-level source target. The approved plan is to make that source map a verified build contract, remove named raw-address coupling, and replace block-count autostart with scene-driven automation; execution awaits owner approval of C0–C6. |
| Distribution | Source/development build only; no audited IPA or physical-device compatibility claim yet |

Ballpad is an in-progress development build, not a finished commercial-quality
release. Moving-match rendering, physical-device performance, audio lifecycle,
save stress, post-match transitions, and oldest-OS compatibility still need
fresh validation before a public binary release.
For the candid engineering status and the next exit-gated phase, see the
[technical audit and plan](docs/24-technical-audit-2026-08-19.md). See the
[Sunpad parity audit](docs/21-sunpad-parity-audit.md) and historical
[acceptance ledger](docs/15-validation-log.md) for supporting evidence.
The current implementation order is the reviewed
[decomp integration decision](docs/28-decomp-integration-plan-2026-08-19.md),
with one approval-gated copy/paste
[agent loop](docs/BOT6_DECOMP_INTEGRATION_LOOP.md). The first tranche makes the
decomp a verified build/symbol contract and uses source-named scene hooks to
replace the brittle block-count test route. It does not authorize a native
rewrite. The earlier
[graphics repair runbook](docs/27-graphics-repair-runbook-2026-08-19.md)
remains the verification reference used by the new loop.

## Get started

You need:

- an Apple Silicon Mac with Xcode 26.x and its command-line tools;
- CMake, Git, Python 3.10+, and ripgrep;
- the locally prepared dependency trees described in [`ref/INDEX.md`](ref/INDEX.md); and
- your own legally obtained Super Mario Strikers USA revision 0 image (`G4QE01`).

Place the image outside Git, then generate the ignored recompiled inputs:

```sh
STRIKERS_ISO=/path/to/G4QE01.iso ./scripts/generate_strikers.sh
```

Configure and build the arm64 Simulator runtime:

```sh
cmake -S ref/StrikersRecomp -B work/strikers/build-ios-sim \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DSTRIKERSRECOMP_GENERATED_DIR="$PWD/work/strikers/generated" \
  -DSTRIKERSRECOMP_GXRUNTIME_DIR="$PWD/ref/GXRuntime" \
  -DBALLPAD_HOST_DIR="$PWD/host" \
  -DBALLPAD_BUILD_STATIC_HOST=ON
cmake --build work/strikers/build-ios-sim --target BallpadHost gxruntime_aurora -j8
```

The Aurora dependency archives are merged into the ignored
`libBallpadEngine.a` using the reviewed list in
`work/strikers/build-ios-sim/merged/libs2.list`:

```sh
libtool -static \
  -o work/strikers/build-ios-sim/merged/libBallpadEngine.a \
  $(head -n 119 work/strikers/build-ios-sim/merged/libs2.list)
```

Build the app for one configured Simulator:

```sh
source build/env.sh
xcodebuild -project app/Ballpad.xcodeproj -scheme Ballpad \
  -configuration Debug -destination "id=$BALLPAD_PHONE_UDID" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Ballpad's local `ref/`, `work/`, `.local-assets/`, generated code, build
products, game images, and saves are ignored and must never be committed.

## First launch

Ballpad never downloads or bundles game data.

1. Launch Ballpad and choose **Import Game**.
2. Select your raw Super Mario Strikers USA `G4QE01` revision 0 ISO/GCM.
3. Leave Ballpad open while the image is copied and `main.dol` is extracted.
4. Start playing when the native game view appears.

The importer rejects the wrong game code, disc/revision, magic, or raw image
size. A reimport from **••• → Game Data & Saves** is staged before replacing
the active files; restart Ballpad after a successful reimport.

## Touch controls and menu

The default layout follows Sunpad's proven compact-phone and large-iPad
geometry:

- **Left:** movement stick, D-pad, and L.
- **Right:** C-stick, A/B/X/Y cluster, Z, R, and Start.
- **Shoulders:** one touch produces the GameCube analog value and digital
  click immediately—no swipe or edge hit is required.
- **Customize:** **Touch Control Settings → Move and resize controls** saves
  normalized positions and individual sizes for the current device class.
- **Controller handoff:** touch and GameController input are merged safely;
  the overlay can hide automatically while a physical controller is active.
- **Menu:** **•••** opens render scale, aspect ratio, FPS, controls, game data,
  memory-card, and diagnostic-log actions without leaving gameplay.

Touch and controller buttons are ORed with rising-edge latching, the strongest
stick axis wins, and the greatest trigger pressure wins. That keeps fast taps
and mixed-input sessions stable even though UI and guest input run on separate
threads.

## Diagnostics

Choose **••• → Share Diagnostic Log…**. Ballpad confirms what is included,
then creates a plain-text snapshot containing app/OS/device, display,
controller, settings, FPS, and guest status. It does not include the game
image, extracted game data, or memory-card contents.

## Supported game data

| Game ID | Region | Revision | Raw size | Status |
|---|---|---|---:|---|
| `G4QE01` | USA | 0 | 1,459,978,240 bytes | Initial supported target |

Raw ISO/GCM images are recognized. Compressed images are not supported.

## Project map

| Path | Purpose |
|---|---|
| [`app/Ballpad/`](app/Ballpad/) | SwiftUI app shell, game view, controls, menu, import, and controller adapter |
| [`host/`](host/) | Threaded guest bridge, input mixer, frame handoff, saves, and diagnostics |
| [`scripts/generate_strikers.sh`](scripts/generate_strikers.sh) | Generate ignored `G4QE01` recompilation inputs from a local image |
| [`scripts/check_ref_patches.sh`](scripts/check_ref_patches.sh) | Check local runtime changes against the tracked patch snapshots |
| [`app/BallpadUITests/`](app/BallpadUITests/) | Import, menu, touch, and match-driving UI acceptance tests |
| [`docs/21-sunpad-parity-audit.md`](docs/21-sunpad-parity-audit.md) | Current comparative audit, work completed, and remaining release gates |
| [`docs/23-goal-loop-2026-08-18.md`](docs/23-goal-loop-2026-08-18.md) | Evidence-based agent loop, current baseline, and acceptance gates for the remaining stability/parity work |
| [`docs/24-technical-audit-2026-08-19.md`](docs/24-technical-audit-2026-08-19.md) | Current technical audit, decision log, and next-phase plan |
| [`docs/25-next-agent-graphics-investigation-brief.md`](docs/25-next-agent-graphics-investigation-brief.md) | Technical handoff brief for the next investigation agent |
| [`docs/26-quickboot-graphics-investigation-2026-08-19.md`](docs/26-quickboot-graphics-investigation-2026-08-19.md) | QuickBoot feasibility, state inventory, ranked causes, and validation design |
| [`docs/27-graphics-repair-runbook-2026-08-19.md`](docs/27-graphics-repair-runbook-2026-08-19.md) | Ordered repair packages, gates, commands, and stop conditions |
| [`docs/28-decomp-integration-plan-2026-08-19.md`](docs/28-decomp-integration-plan-2026-08-19.md) | Primary-agent decision: verified decomp contract, source-aware runtime, and scene-driven autostart |
| [`docs/BOT6_DECOMP_INTEGRATION_LOOP.md`](docs/BOT6_DECOMP_INTEGRATION_LOOP.md) | Exact copy/paste implementation loop for C0–C6; this is the only next-agent prompt |
| [`docs/29-decomp-runtime-crosswalk.md`](docs/29-decomp-runtime-crosswalk.md) | Data-free crosswalk from pinned decomp functions and state ownership to current Ballpad runtime boundaries |
| [`docs/BOT5_GRAPHICS_REPAIR_LOOP.md`](docs/BOT5_GRAPHICS_REPAIR_LOOP.md) | Superseded graphics-only loop retained for its detailed historical contract |
| [`docs/15-validation-log.md`](docs/15-validation-log.md) | Historical phone/iPad gate evidence |
| [`docs/09-open-questions.md`](docs/09-open-questions.md) | Runtime investigations and known renderer constraints |
| `ref/` | Ignored local research/dependency worktrees, including the Sunpad reference |

## Legal

Ballpad is an unofficial community project and is not affiliated with or
endorsed by Nintendo. Super Mario Strikers, Nintendo, and GameCube names are
used only to identify compatibility. No disc image, extracted Nintendo asset,
or user save is included in this repository. Each upstream dependency retains
its own license and copyright; complete licensing and redistribution review is
required before publishing a binary artifact.

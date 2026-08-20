# 25 — Investigation brief for the next technical agent (2026-08-19)

> **Historical assignment:** this investigation was completed in docs 26 and
> 27. The complete function-level decompilation subsequently changed the work
> order. Do not hand this brief to the next agent; use
> [doc 28](28-decomp-integration-plan-2026-08-19.md) and
> [the Bot 6 loop](BOT6_DECOMP_INTEGRATION_LOOP.md).

## Assignment

Investigate the remaining graphics/QuickBoot uncertainty in Ballpad and produce
an **evidence-backed implementation plan** for the primary agent. Do not start
a broad rewrite and do not claim iPhone/iPad release readiness. Your deliverable
is a decision-quality report: explain what is technically missing, which repair
path is most credible, what should be rejected/deferred, and the exact gates
that would prove the recommendation.

This is a research and planning assignment. Prefer read-only inspection,
bounded diagnostics, trace/replay work, and reproducible tests. If a tiny
instrumentation patch is necessary to answer one question, isolate it, explain
why, and keep it off by default. Do not enable QuickBoot for ordinary users.

## Executive context

There is **no demonstrated fundamental iPhone/iPad platform incompatibility**:

- The default fresh live-Aurora path has reached coherent matches on both
  iPhone and iPad arm64 Simulators.
- Real SwiftUI touch overlay routes reached and sustained live matches:
  iPhone 17 Pro in 748 seconds; iPad A16 in 627 seconds.
- The same project now appears to work on macOS, which is valuable evidence
  that the recompilation/runtime approach is viable.
- The project still has no recent physical iPhone or iPad attached, so hardware
  performance, audio interruption, controller delivery, thermal behaviour, and
  extended lifecycle remain unmeasured. That is an external validation block,
  not evidence of an unsolvable porting problem.

The immediate engineering question is narrower:

> Can the fast QuickBoot route reconstruct enough live Aurora GX state to be
> visually equivalent to a fresh boot through a moving match, or should it
> remain/revert to a developer-only diagnostic while the product uses a
> correctness-first fresh start?

A second, related question remains:

> How do we turn the current coherent fresh-match captures into a repeatable
> moving-Dolphin parity gate, so a plausible screenshot is not mistaken for
> renderer correctness?

## What is currently known

### Accepted facts

| Fact | Evidence |
|---|---|
| Fresh default Aurora is the product renderer; GXCore is experimental-only because its fresh iOS path previously showed a white EFB | [23-goal-loop-2026-08-18.md](23-goal-loop-2026-08-18.md), [15-validation-log.md](15-validation-log.md) |
| A fresh default-renderer texture identity repair removed the tiled health-and-safety texture from iPad A16 and iPhone 17 Pro Simulator matches, including a 60-second iPad capture | [15-validation-log.md](15-validation-log.md), “Fresh iPad static-texture identity repair” |
| Touch-only and sustained live-match Simulator tests now pass on both form factors | [15-validation-log.md](15-validation-log.md), “iPad touch-only…”, “Sustained in-match touch control gate” |
| QuickBoot is disabled by default; `BALLPAD_ENABLE_QUICKBOOT=1` explicitly opts into the diagnostic path | [host/src/ballpad_ios_host.cpp](../host/src/ballpad_ios_host.cpp) |
| CPU, RAM, ARAM, interrupt/MMIO state, audio DMA state, and portable HLE texture/TLUT/array metadata are captured/restored | [host/src/ballpad_ios_host.cpp](../host/src/ballpad_ios_host.cpp), [ref/StrikersRecomp/runtime/host/hle.c](../ref/StrikersRecomp/runtime/host/hle.c) |
| The live Aurora product path saves no optional native frontend or GXCore renderer blob (`frontend_size=0`, `gxcore_size=0`) | [15-validation-log.md](15-validation-log.md), “Live-match visual regression” |
| A v5 HLE rebind improves restart resources from 4 textures/6 arrays/22 copy caches to 7 textures/16 arrays/22 copy caches; a fresh run has 8 textures/26 copy caches | [15-validation-log.md](15-validation-log.md), “QuickBoot semantic HLE rehydration probe” |
| Despite the v5 rebind, QuickBoot still produces malformed/scrambled players and sometimes missing HUD after match start | Same evidence; QuickBoot remains unaccepted |
| A static boot-frame comparison with Dolphin passed; a deterministic moving-match Dolphin comparison has not been performed | [15-validation-log.md](15-validation-log.md), “Desktop Dolphin static-render oracle sanity check” |

### Current state boundary

The snapshot is deliberately captured at a stable side-choice/stadium-card safe
point, then restore sends exactly one match-start A. Capturing mid-render or
mid-match is known to be invalid: the restored guest assumes its delta GX
state is still present, while a new native renderer has none of it.

The implementation already avoids serializing raw WGPU/native handles. That is
correct. The missing work is to identify a complete **portable semantic
description** of the live Aurora/GX state, or to find a safe replay mechanism
that reconstructs it in a new renderer process.

Relevant entry points:

| Purpose | Location |
|---|---|
| QuickBoot header/version, CPU/RAM/device-state save and restore | [host/src/ballpad_ios_host.cpp](../host/src/ballpad_ios_host.cpp) |
| QuickBoot public contract | [host/include/ballpad_ios_host.h](../host/include/ballpad_ios_host.h) |
| Portable GX texture/TLUT/indexed-array rebind and optional dirty-state probe | [ref/StrikersRecomp/runtime/host/hle.c](../ref/StrikersRecomp/runtime/host/hle.c) |
| Aurora product backend diagnostics and consumer CP-binding repair | [ref/GXRuntime/backends/aurora/aurora_backend.cpp](../ref/GXRuntime/backends/aurora/aurora_backend.cpp) |
| Aurora backend public surface | [ref/GXRuntime/include/gxruntime/aurora_backend.h](../ref/GXRuntime/include/gxruntime/aurora_backend.h) |
| Frontend QuickBoot regression test | [ref/GXRuntime/graphics/frontend/tests/frontend_replay_test.cpp](../ref/GXRuntime/graphics/frontend/tests/frontend_replay_test.cpp) |
| Existing current baseline and commands | [23-goal-loop-2026-08-18.md](23-goal-loop-2026-08-18.md) |
| Detailed dated experiment history | [15-validation-log.md](15-validation-log.md) |

## Prior experiments: do not repeat them blindly

| Hypothesis / change | Result | Conclusion |
|---|---|---|
| SwiftUI/Core Graphics/UIKit frame presentation causes the corrupted texture | Native BGRA EFB dump already contained the defect | Rejected for the fresh corruption; presentation is not the cause |
| GPU work was using an in-flight texture/resource | Per-submit GPU fence still reproduced the defect | Rejected |
| EFB-copy texture cache identity was the direct cause | Identity guard and EFB-copy substitution A/Bs did not fix it | Rejected |
| Static texture uploads, worker ordering, bind-group reuse caused fresh defect | Direct upload, inline worker, and bind-cache bypass all reproduced it | Rejected |
| `PNMTXIDX` requires another divide-by-three | Made the live image substantially worse | Rejected and reverted |
| Fresh static texture identity was safe to reuse by object/version alone | Repaired by retaining source hash and validating source, dimensions, format, flags, and TLUT identity | Accepted fresh-path repair |
| CPU/RAM/audio restore is enough for QuickBoot | V4 had only 4 textures/6 arrays; moving match was broken | Rejected |
| Portable HLE resource rebind is enough for QuickBoot | V5 reaches 7 textures/16 arrays but visual parity still fails | Incomplete, retained only as diagnostic instrumentation |
| Forcing guest GX dirty state will solve it | Probe exists but was not run to a conclusion | Open, must be tested against a fixed comparison gate |

Do not conflate the resolved **fresh static-texture** bug with the unresolved
**QuickBoot live-state** bug. They have different evidence and likely different
causes.

## Investigation questions, in priority order

### Q1 — Is QuickBoot technically worth completing?

Determine whether a fresh renderer can be reconstructed from guest-addressed
semantic state at the chosen safe point without serializing native WGPU objects.

Compare three options:

1. **Complete semantic rehydration:** inventory every state class the live
   Aurora backend needs after restart (textures, TLUTs, indexed arrays,
   CP/VAT/VCD, BP/XF/TEV, matrices, viewport/scissor, copy/EFB state, render
   pass/frame lifecycle, and any resource/copy-cache identity).
2. **Controlled replay:** determine whether the guest can safely re-emit the
   required scalar state after restore—e.g., a proven dirty-state path or a
   bounded FIFO/GX command replay—without reopening the known mid-command
   truncation/delta-state problems.
3. **Defer/remove product QuickBoot:** preserve it as a diagnostic/capture
   accelerator and invest instead in a shorter deterministic fresh startup.
   This is a valid recommendation if the semantic state is too coupled to
   Aurora internals or too costly to prove.

Your recommendation must explicitly compare correctness risk, implementation
size, maintenance cost, startup benefit, and testability. A fast but visually
wrong restore is not an acceptable trade.

### Q2 — Which exact state classes explain 7/16/22 versus fresh 8/16/26?

Use the existing `[quickboot-gx]` diagnostics, backend source, and replay
tests to produce a before/after state inventory at:

- safe-point save;
- immediately after restore;
- immediately after the match-start input;
- steady live match;
- an equivalent fresh live match.

Do not rely on counts alone. Identify identities and ownership: which texture,
TLUT, array, scalar state, or copy-cache entry is absent, stale, or fails to be
consumed; whether it is necessary for the malformed geometry/HUD; and whether
the failure occurs before native presentation.

### Q3 — Can we create a deterministic visual correctness gate?

Design—not necessarily implement—a test harness that captures:

- a named static match scene;
- a 10–15 second moving segment;
- equivalent Dolphin output using the same image;
- Ballpad fresh iPhone and iPad Simulator output;
- optionally, the QuickBoot route only after fresh-path comparison is sound.

The plan should identify stable capture inputs and artifacts that can be kept
without game data (for example, derived contact sheets, frame hashes, state
metadata, and logs). It must distinguish a normal `simctl` portrait container
from an actually rotated game image.

### Q4 — What is the smallest test infrastructure repair needed?

The repository has useful evidence, but the longest end-to-end UI test runs for
many minutes. A historical harness run reached its guest assertion but did not
cleanly terminate. Propose a fast smoke lane and a long acceptance lane, with
timeouts and reliable `.xcresult` reporting. Also account for the current
independent `gx_fifo_tests` link failure: its CMake target omits existing
EFB/bounding-box implementation objects. Classify that repair as prerequisite,
parallel hygiene, or irrelevant to the main renderer plan.

## Constraints and non-goals

- Do not commit or expose disc images, extracted game data, saves, raw traces
  containing proprietary content, or user diagnostic data.
- Preserve the default fresh renderer and keep `DOL_GX_CORE=1` experimental.
- Keep `BALLPAD_ENABLE_QUICKBOOT=1` diagnostic-only unless moving visual
  parity passes on both simulator form factors.
- Do not turn on verbose/forensic logging in ordinary builds.
- Do not “fix” a visual problem by accepting a single screenshot, changing
  touch/UI layout, or weakening the comparison gate.
- Do not assume a macOS success proves iOS device behaviour; it proves
  portability potential, not thermal/audio/controller/lifecycle parity.
- A physical-device validation cannot happen until a compatible phone and iPad
  are attached. Report that as a dependency, not a code defect.

## Current reproducible commands

Use one Simulator at a time. Current local IDs and environment are in the
ignored `build/env.sh`; do not commit them.

```sh
source build/env.sh
./scripts/check_ref_patches.sh

cmake --build work/strikers/build-ios-sim \
  --target BallpadHost gxruntime_aurora -j8
libtool -static -o work/strikers/build-ios-sim/merged/libBallpadEngine.a \
  $(head -n 119 work/strikers/build-ios-sim/merged/libs2.list)

xcodebuild -project app/Ballpad.xcodeproj -scheme Ballpad \
  -configuration Debug -destination "id=$BALLPAD_PHONE_UDID" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build

SIMCTL_CHILD_BALLPAD_AUTOSTART=1 \
SIMCTL_CHILD_BALLPAD_PERF_LOG=1 \
SIMCTL_CHILD_BALLPAD_LOG_FILE='$HOME/Documents/ballpad.log' \
xcrun simctl launch "$BALLPAD_PHONE_UDID" com.ballpad.strikers
```

For the diagnostic QuickBoot route, add
`SIMCTL_CHILD_BALLPAD_ENABLE_QUICKBOOT=1`. To force the fresh route, add
`SIMCTL_CHILD_BALLPAD_NO_QUICKBOOT=1`. Preserve the existing snapshot during
a fresh autostart diagnostic with
`SIMCTL_CHILD_BALLPAD_SKIP_QUICKBOOT_SAVE=1`.

## Required deliverable to the primary agent

Return a report, not a vague list of ideas, with these sections:

1. **Bottom-line feasibility:** Is QuickBoot likely completable as a
   correctness-preserving feature? Is it a release blocker or a deferrable
   startup optimisation? State confidence and why.
2. **Evidence map:** exact source files, relevant state ownership, logs/traces,
   and a concise timeline of accepted/rejected hypotheses.
3. **Root-cause ranking:** no more than three ranked hypotheses, each with the
   causal mechanism and the single best discriminating experiment.
4. **Recommended path:** one primary plan and one fallback, split into small
   commits/gates. Include expected risk and stop conditions.
5. **Verification matrix:** fresh and QuickBoot where applicable, phone and
   iPad Simulator, moving Dolphin comparison, long UI acceptance, and
   physical-device follow-up.
6. **What not to do next:** explicitly name experiments already ruled out and
   unrelated features to defer.
7. **Decision request:** identify any decision the repository owner must make
   (for example: accept a longer fresh boot rather than fund full QuickBoot
   state reconstruction).

A strong answer can recommend that QuickBoot remain disabled permanently for
this release cycle. The primary goal is an honest, stable iPhone/iPad product,
not a fast-start feature at any cost.

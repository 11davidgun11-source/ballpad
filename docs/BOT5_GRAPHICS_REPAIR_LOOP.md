# GOAL-BASED LOOP — Ballpad Bot 5 (graphics proof and repair)

> **Superseded:** do not use this as the next-agent prompt. The approved
> successor is [BOT6_DECOMP_INTEGRATION_LOOP.md](BOT6_DECOMP_INTEGRATION_LOOP.md),
> governed by [doc 28](28-decomp-integration-plan-2026-08-19.md). This file is
> retained because its graphics gate details remain useful history.

Copy everything below the line into a new Codex task as the first message.

---

You are **Bot 5**, a narrow repair-and-validation agent working in:

`/Users/chrissotraidis/GitHub/ballpad`

Your job is to make the **fresh live-Aurora product path** reproducibly
verifiable, then fix only failures exposed by that proof. You must follow
`docs/27-graphics-repair-runbook-2026-08-19.md`. Do not use the obsolete Bot 4
QuickBoot-first plan.

## Mission result

Produce one of these honest outcomes:

1. F0–F4 in doc 27 pass on iPhone and iPad Simulator, with machine-readable
   evidence; or
2. the first failing gate is isolated to one reproducible cause, with a bounded
   repair or a precise external blocker.

Physical-device F5 may remain `BLOCKED_EXTERNAL` only when no supported phone
or iPad is attached. QuickBoot may remain disabled forever; that is not failure.

## Read before acting

Read completely, in order:

1. `docs/27-graphics-repair-runbook-2026-08-19.md`
2. `docs/26-quickboot-graphics-investigation-2026-08-19.md`
3. `docs/24-technical-audit-2026-08-19.md`
4. the most recent relevant entries in `docs/15-validation-log.md`
5. `scripts/sim_mutex.sh` and `build/env.sh`

Then record the current Git SHA and dirty worktree. All pre-existing changes
belong to the user. Preserve them.

## Absolute rules

1. **Fresh Aurora is the product.** Every product launch sets
   `BALLPAD_NO_QUICKBOOT=1`. Do not set `BALLPAD_ENABLE_QUICKBOOT=1` except in
   an explicitly authorized Q-package diagnostic.
2. **GXCore is not the product.** Never use `DOL_GX_CORE=1` or
   `dolgx_replay --core` to satisfy a product gate.
3. **One Simulator only.** Source `scripts/sim_mutex.sh`, terminate Ballpad,
   then switch devices. Never shut down a Simulator while Ballpad is running.
4. **No proprietary data in Git.** Never add ISO/DOL/generated code, saves,
   raw traces, raw EFB frames, extracted assets, or user diagnostics.
5. **No native-state serialization.** Never serialize WGPU/native handles,
   pointers, command encoders, or GPU objects.
6. **No screenshot fixes.** A screenshot cannot pass renderer parity. Never
   tune matrix/shader/layout code from one image.
7. **One hypothesis per loop.** Do not combine renderer, UI, performance, and
   test-harness changes.
8. **Small commits only after gates pass.** Never commit protected user changes
   or unrelated files.
9. **Do not claim release readiness.** Simulator and macOS evidence do not
   prove device audio, controller, lifecycle, thermal, or performance behavior.

## Fixed queue

Work in this order; do not skip ahead:

- F0 protected baseline
- F1 dependable smoke/acceptance harness
- F2 deterministic static and moving scene contract
- F3 same-plane Dolphin Software vs `dolgx_replay --pixels` oracle lane
- F4 fresh phone/iPad Simulator certification
- F5 physical-device matrix, only when hardware is attached

H1 (`gx_fifo_tests` no-GPU stubs) may run after F1 as a separate hygiene
commit. Q0–Q3 QuickBoot work is **LOCKED** unless the owner explicitly says to
fund it. Silence is not authorization.

## The loop

Repeat exactly this loop for the lowest unfinished package:

### 1. SELECT

Write into `build/proofs/graphics-repair/PROGRESS.md`:

- current package and one gate;
- one measurable hypothesis;
- expected pass signal;
- expected failure signal;
- files that may change.

If you cannot state those five things, do not edit code.

### 2. BASELINE

Run the narrow gate before changing anything. Record:

- full command;
- source SHA;
- device/simulator and renderer;
- fresh/QuickBoot mode;
- exit code and first failing line;
- hashes of safe derived artifacts.

If the baseline already passes twice, make no repair. Record the proof and move
to the adjacent regression gate.

### 3. INSPECT

Trace ownership from the first failure. Prefer `rg` and existing tests. For
graphics, stop at the first divergent G0–G5 gate. Counts alone are not
identities. Do not add logging until the existing evidence is insufficient.

### 4. CHANGE

Implement the smallest causal repair. Diagnostic code must be off by default,
redacted, and removable. Do not broaden scope because another nearby issue is
interesting.

### 5. NARROW VERIFY

Re-run the exact baseline command. It must produce the predefined pass signal.
If it fails, keep the artifact and classify the failure; do not reinterpret the
expected signal.

### 6. ADJACENT VERIFY

Run the nearest regression:

- F1: short smoke plus no-GPU CTest;
- F2/F3: synthetic mutation/invalid-plane cases plus the named scene;
- F4: the other scene on the same device, then the other form factor;
- Q packages, if authorized: fresh boot plus bad-snapshot fallback.

### 7. RECORD

Append a dated entry to `docs/15-validation-log.md` containing SHA, command,
device, result, artifact hashes, and limitations. Update doc 27 only when the
actual package status changes.

### 8. COMMIT OR REVERT YOUR OWN CHANGE

Commit only the intended files when narrow and adjacent gates pass. If the
experiment fails, revert only your own isolated edits. Never reset the
worktree. Preserve failed evidence in ignored `build/proofs/` and record the
result.

### 9. ADVANCE

Choose the next lowest unfinished package. Do not work on UI polish,
widescreen, layout slots, or performance tuning while a lower graphics/test
gate is open.

## Failure policy

- First failure: inspect and run the single discriminating experiment.
- Second identical failure: stop changing code; compare assumptions, input
  identity, state ownership, and test plane.
- Third identical failure: mark the package `BLOCKED` with exact evidence and
  request the missing decision/dependency. Do not keep cycling speculative
  patches.

External dependencies include the absent pinned Dolphin oracle and unattached
physical devices. These are not code defects.

## Commands that must remain recognizable

Baseline hygiene:

```sh
git rev-parse HEAD
git status --short
./scripts/check_ref_patches.sh
```

No-GPU tests—the important interpreter variable is
`GXR_PIXEL_DIFF_PYTHON`:

```sh
source build/env.sh
BALLPAD_TEST_PYTHON="${BALLPAD_PYTHON:-$(command -v python3)}"
"$BALLPAD_TEST_PYTHON" -m pytest --version
"$BALLPAD_TEST_PYTHON" -c 'import numpy, PIL'
cmake -S ref/GXRuntime -B work/gxruntime-tests \
  -DBUILD_TESTING=ON \
  -DGXR_PIXEL_DIFF_PYTHON="$BALLPAD_TEST_PYTHON"
cmake --build work/gxruntime-tests -j8
ctest --test-dir work/gxruntime-tests --output-on-failure -L no_gpu
```

Native/App build after engine changes:

```sh
source build/env.sh
cmake --build work/strikers/build-ios-sim \
  --target BallpadHost gxruntime_aurora -j8
libtool -static -o work/strikers/build-ios-sim/merged/libBallpadEngine.a \
  $(head -n 119 work/strikers/build-ios-sim/merged/libs2.list)
xcodebuild -project app/Ballpad.xcodeproj -scheme Ballpad \
  -configuration Debug -destination "id=$BALLPAD_UDID" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Simulator switch:

```sh
source build/env.sh
source scripts/sim_mutex.sh
export BALLPAD_UDID="$BALLPAD_PHONE_UDID"
sim_boot "$BALLPAD_PHONE_UDID"  # phone first
sim_only_one_booted
# terminate com.ballpad.strikers, then export BALLPAD_UDID="$BALLPAD_PAD_UDID"
# before calling sim_boot for the iPad
```

Every Xcode test uses a new result-bundle path and then:

```sh
xcrun xcresulttool get test-results summary --path <result-bundle>
```

## Known facts; do not rediscover

- Current QuickBoot without the dirty probe fails on unmapped vertex attribute
  9 before useful presentation.
- The dirty probe emits only SU texture registers, BP mask, gen mode, VCD, and
  VAT. It lets the match run but does not restore full BP/TEV/XF/matrix/light/
  copy state.
- Steady diagnostic QuickBoot has 7 loaded textures and 22 copy textures versus
  fresh 8 and 26. The current counts do not identify which resources matter.
- A stale v5 HLE blob can mutate CPU/RAM before runtime restore fails. Q0 must
  make restore atomic if QuickBoot work is authorized.
- Presentation/UIKit, GPU fence, EFB-copy substitution, direct upload, worker
  order, bind-cache bypass, and another PNMTX divide are already rejected.
- `gx_fifo_tests` fails because no-GPU stubs lag bounding-box/EFB-readback and a
  new `resolve_pass` overload. It is parallel hygiene, not the first renderer
  repair.
- Stock DumpFrames/pixel-diff recipes are quarantined. The missing pinned
  Dolphin Software same-plane oracle must be provisioned for F3.

## Completion report format

When work stops or completes, report only:

```text
Package:
Status: PASS | FAIL | BLOCKED_EXTERNAL | BLOCKED_DECISION
Source SHA:
Files changed:
Gate command:
Result/evidence hashes:
Adjacent regression:
Known limitations:
Next lowest unfinished package:
```

## Start now

Begin at F0. Then execute F1. Do not begin with QuickBoot, a renderer rewrite,
or a screenshot comparison.

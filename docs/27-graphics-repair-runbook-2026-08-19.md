# 27 — Graphics repair and validation runbook (2026-08-19)

> **Execution status:** this remains the graphics verification reference, but
> [doc 28](28-decomp-integration-plan-2026-08-19.md) is now the top-level work
> order. Its Bot 6 loop uses decomp source and instrumentation to drive these
> gates. Do not launch the graphics-only Bot 5 loop as the current assignment.

## Purpose

This is the execution companion to
[the QuickBoot investigation](26-quickboot-graphics-investigation-2026-08-19.md).
It turns the findings into ordered, reviewable work packages that another agent
can implement without reopening settled questions.

The product path is **fresh live Aurora**. QuickBoot remains disabled by
default. The immediate objective is to make the fresh renderer and its test
harness reproducibly verifiable. QuickBoot reconstruction is an optional,
owner-authorized branch after the fresh moving-parity gate exists.

This document is not evidence that any open gate has passed.

## Authority and conflict rule

Read these in order:

1. [doc 28](28-decomp-integration-plan-2026-08-19.md) for implementation order;
2. this runbook for graphics verification packages and gates;
3. [doc 26](26-quickboot-graphics-investigation-2026-08-19.md) for technical
   findings and rejected hypotheses;
4. [the Bot 6 goal loop](BOT6_DECOMP_INTEGRATION_LOOP.md) for agent behavior;
5. [doc 15](15-validation-log.md) for dated evidence only.

If an older document says QuickBoot is automatic, accepted, or product-ready,
it is historical. The current implementation and doc 28 win; this runbook
defines the graphics gates they invoke. Do not use the old Bot 4 prompt: its
QuickBoot-first goal is obsolete.

## Non-negotiable invariants

- Keep `BALLPAD_ENABLE_QUICKBOOT=1` diagnostic-only. Never add it to normal app
  launch settings.
- Keep `DOL_GX_CORE=1` experimental. Product renderer claims must use live
  Aurora or `dolgx_replay --pixels`, never `--core`.
- Never commit an ISO, DOL, generated guest code, saves, raw DFF/DOLT traces,
  raw EFB sequences, extracted assets, or user diagnostics.
- Never serialize WebGPU objects, native texture handles, command encoders, or
  process-local pointers.
- Use exactly one Simulator at a time. Terminate Ballpad before shutting that
  Simulator down.
- Preserve unrelated worktree changes. Do not reset or replace local `ref/`
  worktrees.
- Normal logging stays quiet. New diagnostic output must be opt-in and must not
  reveal paths, guest data, or native addresses in retained artifacts.
- A screenshot is supporting evidence, never the only renderer gate.
- Simulator success does not imply physical-device success.

## Current known state

| Item | State | Next proof |
|---|---|---|
| Fresh Aurora reaches coherent phone/iPad matches | Candidate | Named static and 10–15 second moving same-plane comparison |
| QuickBoot without dirty probe | Rejected | Current same-build restore fails on unmapped vertex attribute 9 |
| QuickBoot with dirty probe | Rejected | Runs but has malformed players and missing HUD |
| Atomic snapshot fallback | Broken | Stale/truncated snapshot must fall back fresh before any CPU/RAM mutation |
| Fast test lane | Incomplete | One command with accurate pass/fail/skip summary |
| Long touch lane | Useful but unreliable at process end | Passing `.xcresult` plus bounded clean termination |
| Dolphin moving oracle | Missing locally | Pinned same-plane Software oracle provisioned and validated |
| Physical iPhone/iPad | Not available in latest evidence | Explicit two-device matrix when attached |
| `gx_fifo_tests` | Link-broken | Parallel no-GPU stub repair; not a blocker for fresh parity work |

## Work package order

Complete F0–F5 in order. Work packages Q0–Q3 are locked until the repository
owner explicitly authorizes the optional QuickBoot branch.

### F0 — Establish a protected baseline

**Goal:** make later evidence attributable to one known source state.

Actions:

1. Record `git rev-parse HEAD`, `git status --short`, Xcode/CMake/Python
   versions, and the exact device profile.
2. Run `./scripts/check_ref_patches.sh`.
3. Confirm `git ls-files` contains no ISO/DOL/save/raw trace/raw EFB file.
4. Source `build/env.sh`; require phone and iPad UDIDs but do not print local
   asset paths into tracked files.
5. Create the ignored progress location
   `build/proofs/graphics-repair/PROGRESS.md` from the template below.

Gate F0:

- patch check passes;
- pre-existing dirty files are listed as protected;
- no sensitive file is tracked;
- no product behavior changed.

Stop if a required local dependency is missing. Report the missing dependency;
do not clone over or reset `ref/`.

### F1 — Repair the test harness before renderer work

**Goal:** a small failure produces a trustworthy, bounded result.

#### F1.1 Fix the Python preflight

The frontend CMake uses `GXR_PIXEL_DIFF_PYTHON`, not
`Python3_EXECUTABLE`, for gxpo tests. The current cache may point to a pyenv
shim without `pytest`.

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

Do not “fix” this by skipping `gxpo_productization`. If the chosen interpreter
lacks a dependency, fail preflight with the exact missing module. Prefer the
already configured `BALLPAD_PYTHON`; do not install packages into an unrelated
system interpreter without owner approval.

#### F1.2 Make UI tests terminate reliably

Add shared app ownership and `tearDownWithError` termination to the UI tests,
starting with `TouchMatchTests`. Preserve assertions and guest-block anchors.
Do not shorten the long test by weakening its live-match or sustained-input
proof.

For every Xcode test invocation:

- use one Simulator;
- set `-test-timeouts-enabled YES`;
- give short tests a 120–180 second allowance;
- give the long touch test a 900 second allowance;
- use a unique `-resultBundlePath` that does not already exist;
- inspect the bundle with `xcresulttool get test-results summary`;
- treat a reached log assertion followed by a hung process as failure.

Gate F1:

- no-GPU lane passes, including `gxpo_productization`;
- two consecutive short UI smoke runs exit cleanly on one form factor;
- the long lane has explicit teardown, a hard timeout, and a readable
  `.xcresult` even when an assertion is intentionally made to fail in a local
  diagnostic run;
- no renderer behavior changed.

Recommended commit split:

1. `test: pin the gxpo Python preflight`
2. `test: make Ballpad UI tests terminate and report reliably`

### F2 — Define the deterministic scene contract

**Goal:** replace “looks plausible” with reproducible inputs.

Create a tracked, data-free scene manifest schema and input-script fixture for:

- static scene: `kickoff-countdown-1`;
- moving scene: 10–15 seconds beginning at a declared guest-frame/VI marker;
- EFB scale 1 and native 640×528 capture;
- fixed team/stadium/config/card state;
- neutral initial input followed by a versioned guest-frame-relative script.

Use the existing `STRIKERS_INPUT_SCRIPT` support. Do not drive parity by wall
time, UI coordinates, or an XCUITest tap sequence. Record:

- build SHA and ref-patch hashes;
- scene and input-script IDs/hashes;
- renderer (`live-aurora`), EFB dimensions/format, frame window;
- whether run is fresh or diagnostic QuickBoot;
- trace/EFB hashes, not raw proprietary bytes.

Native EFB capture uses the existing `BALLPAD_EFB_DUMP_*` variables. Raw files
stay ignored. A `simctl` screenshot is allowed only for UI/layout context and
must record interface orientation separately from game-content orientation.

Gate F2:

- two fresh repetitions on one Simulator have identical scene/config/input
  hashes and the same capture frame count;
- the manifest contains no local paths or game bytes;
- the contact sheet is derived and labeled non-authoritative;
- a changed input fixture makes the input hash fail.

Stop if the game state cannot be reproduced. Fix the scene/input boundary
before changing renderer code.

### F3 — Build the same-plane live-Aurora oracle lane

**Goal:** compare equivalent renderer work instead of two presentation paths.

Required topology:

```text
same image + same FIFO/input window
        |                         |
        v                         v
pinned Dolphin Software     .dolt -> dolgx_replay --pixels
same-plane EFB                   live Aurora EFB
        \_________________________/
             G0–G5 comparison
```

Actions:

1. Provision the pinned Dolphin Software oracle described in
   `ref/GXRuntime/docs/gxpo.md`. The expected fork is not currently present.
   Record source URL, immutable revision, build flags, and binary hash. Never
   weaken the gate to stock presenter `DumpFrames` because provisioning is
   inconvenient.
2. Capture/convert a local ignored FIFO trace for the named scene.
3. Adapt the gxpo certificate model to the product `--pixels` replay path.
4. Require first-red behavior:
   - G0 config/plane identity;
   - G1 input/trace identity;
   - G2 semantic state;
   - G3 decoded vertices;
   - G4 EFB;
   - G5 copy bytes.
5. Mark missing input or mismatched planes `INVALID`, never pass or skip.

Do not use quarantined `pixel_diff.py`, `graphics_lockstep.sh`, or
`dolphin_efb_golden.sh` as product gates. Do not use `dolgx_replay --core`.

Gate F3:

- a synthetic known-pass fixture passes;
- a deliberate one-field mutation becomes red at the expected first gate;
- a wrong plane/config becomes `INVALID`;
- the named static scene produces a certificate without exposing raw data;
- all raw traces and EFB frames remain ignored.

Stop and ask the owner for the oracle dependency if its source/revision cannot
be obtained from existing repository documentation. That is an external
dependency, not permission to invent an oracle.

### F4 — Certify the fresh Simulator product path

**Goal:** decide fresh-renderer correctness on both form factors.

Run sequentially:

1. phone static scene;
2. phone moving scene;
3. phone long touch acceptance;
4. terminate app and shut down phone;
5. iPad static scene;
6. iPad moving scene;
7. iPad long touch acceptance;
8. terminate app and shut down iPad.

Use `BALLPAD_NO_QUICKBOOT=1` in every F4 app launch. Require native EFB and
certificate results; keep container screenshots secondary.

Gate F4:

- both Simulator form factors pass static and moving G0–G5;
- both have a passing, bounded `.xcresult` for touch-to-match plus sustained
  input;
- no persistent mesh deformation, missing HUD, frozen frame, wrong crop, or
  tiled source identity appears;
- the validation ledger records date, SHA, device, command, result, artifact
  hashes, and limitations.

Any failed first-red gate becomes the next single hypothesis. Do not change
touch layout, widescreen, or performance settings to mask it.

### F5 — Physical-device truth pass

**Goal:** test behavior Simulator cannot establish.

This package begins only when F4 passes and a supported iPhone and iPad are
attached. On each device test:

- 60 seconds of real touch play;
- controller connect/input/disconnect;
- audio output and interruption/resume;
- background/foreground and in-app pause/resume;
- save import/export;
- at least 15 minutes of thermal/performance sampling.

Gate F5 is an explicit phone/iPad matrix with pass/fail/not-run cells. Never
convert `not-run` to pass. A missing device is a dependency, not a code defect.

## Parallel hygiene package H1 — `gx_fifo_tests`

This can be done after F1 without blocking F2–F4.

The correct target is in the Aurora-enabled Strikers build. The smallest fix is
to extend `ref/GXRuntime/graphics/aurora/tests/gx_test_stubs.cpp` with:

- the referenced `aurora::gfx::bounding_box` functions;
- the referenced `aurora::gfx::efb_readback` functions;
- the filtered `resolve_pass(..., EfbCopyFilterParams const*)` overload.

Do not link real WebGPU renderer objects into this no-GPU test. Gate H1 is:

```sh
cmake --build work/strikers/build-s --target gx_fifo_tests -j8
ctest --test-dir work/strikers/build-s --output-on-failure -R gx_fifo
```

Commit H1 separately. It becomes a prerequisite only before using the legacy
GX/FIFO encoder test as a renderer gate.

## Optional owner-authorized QuickBoot branch

Do not begin this section unless the owner explicitly says to fund QuickBoot.
Fresh F2–F4 infrastructure should exist first.

### Q0 — Atomic restore contract

Preflight magic/version, every section size, exact file length, and checksum
before mutating CPU/RAM. Set `g_quickbooted` only after all runtime sections
restore. Any error falls back to a clean fresh boot. Update the stale public
header comment; do not make restore automatic.

Gate Q0: valid, truncated, stale-HLE-size, corrupt-checksum, and missing
snapshots all have deterministic tests; every invalid case boots fresh.

### Q1 — Portable identity/state manifests

Add one opt-in redacted manifest containing:

- texture/TLUT slot, guest physical identity, dimensions, format, version/hash;
- array attribute, guest physical base, stride;
- CP/VCD/VAT validity;
- BP/XF register validity and matrix/light/channel coverage;
- copy destination physical identity, dimensions, format, revision, producing
  copy event, and first consuming draw;
- first post-restore event/draw ordering.

Never retain guest/native addresses verbatim; canonicalize or hash them. Gate
Q1: equivalent fresh runs match independently of native pointer values, and
the known 8→7 texture / 26→22 copy mismatch names the missing portable
identities instead of only counting them.

### Q2 — Canonical live-Aurora restore stream

Capture the existing portable `DolGxRecompState` shadow only for diagnostic
QuickBoot. At restore:

1. initialize a clean Aurora frame boundary;
2. emit canonical CP/VCD/VAT/array scalar state;
3. emit canonical BP and XF state, including matrices, projection, lights,
   channels, TEV-relevant registers, viewport/scissor, and copy scalars;
4. re-resolve and issue HLE arrays/TLUTs/textures;
5. start native caches empty and regenerate only proven portable copy
   producers;
6. resume the guest.

Gate Q2: no `BALLPAD_QUICKBOOT_FORCE_GX_DIRTY` is needed, the first-draw
semantic digest matches fresh, and no native handle is serialized.

Stop Q2 if it requires native object serialization, full boot FIFO history, or
an unbounded Aurora rewrite.

### Q3 — QuickBoot parity and endurance

Run Q0 bad-snapshot cases, static scene, moving G0–G5, fresh-vs-QuickBoot EFB,
and long touch acceptance on phone and iPad Simulator. QuickBoot remains opt-in
until all pass. Physical-device QuickBoot remains a later decision.

## Progress record template

Keep the live copy ignored at `build/proofs/graphics-repair/PROGRESS.md`:

```markdown
# Graphics repair progress

- Source SHA:
- Protected pre-existing changes:
- Current package: F0 | F1 | F2 | F3 | F4 | F5 | H1 | Q0 | Q1 | Q2 | Q3
- Owner authorized QuickBoot work: no
- Hypothesis:
- Baseline command/result:
- Files intentionally changed:
- Narrow gate command/result:
- Adjacent regression command/result:
- Artifact hashes:
- First divergence:
- Blocker or limitation:
- Next single action:
```

Every validation-ledger entry must contain the same facts. Never write “fixed,”
“green,” or “release-ready” without the named gate and artifacts.

## Overall exit condition

The default repair plan is complete when F0–F4 pass and F5 is either completed
or explicitly recorded as blocked by unavailable devices. QuickBoot work is not
part of that completion unless separately authorized. Release readiness still
also depends on the broader reproducible-build and release gates in
[the technical audit](24-technical-audit-2026-08-19.md).

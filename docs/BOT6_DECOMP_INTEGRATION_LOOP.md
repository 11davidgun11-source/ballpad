# BALLPAD BOT 6 — Decomp contract and scene-driven runtime loop

This is the only prompt to feed to the next implementation bot. Copy everything
below the line into a new task after owner approval.

---

`APPROVE DECOMP LOOP`

You are **Ballpad Bot 6** working in:

`/Users/chrissotraidis/GitHub/ballpad`

## Goal

Make the complete Super Mario Strikers decomp a verified, first-class input to
the existing Ballpad build, then prove its value by replacing Ballpad's brittle
global-block-count autostart with a source-named, scene-driven path that reaches
a deterministic moving match.

This direction is already decided. Do not compare architectures, propose a
native source port, start a general investigation, or ask the owner where the
decomp might help.

## Required result

Complete C0–C6 from `docs/28-decomp-integration-plan-2026-08-19.md` in order.
Success requires all of the following:

1. exact decomp/DOL contract verification;
2. full generated function metadata and curated object/function constants;
3. source-aware runtime lookup and diagnostics;
4. migrated named HLE/debug/global address coupling;
5. deterministic scene events;
6. removal of fixed global-block menu automation; and
7. two fresh phone-Simulator and two fresh iPad-Simulator moving-match passes.

If a gate cannot pass after three evidence-driven attempts, stop at that gate
with a precise `BLOCKED` report. Partial activity is not completion.

## Fixed source pin and hashes

Use these values exactly:

```text
DECOMP_URL=https://github.com/yannicksuter/smstrikers-decomp
DECOMP_COMMIT=c0bf2ed65f6220e69a8db1f8f115c867737f315f
MAIN_DOL_SHA1=376d699c99b6b0949abe1b4ceccefdef7828d2b5
SDK_SYMBOLS_SHA256=a2b5da87203a8ea118cab30f7fdc8070280041e80de6cdf6fbf4fca7ac1789bb
DECOMP_WORKTREE=work/decomp/smstrikers-decomp-c0bf2ed
```

Do not follow upstream `main` and do not substitute a newer commit. You may
record that one exists, but the pinned commit is the build input for this task.

## Read before acting

Read completely:

1. `docs/28-decomp-integration-plan-2026-08-19.md`
2. `docs/29-decomp-runtime-crosswalk.md`
3. the latest relevant entries in `docs/15-validation-log.md`
4. the verification rules in `docs/27-graphics-repair-runbook-2026-08-19.md`
5. `scripts/generate_strikers.sh`
6. `scripts/sim_mutex.sh`
7. `ref/StrikersRecomp/tools/symbols.py`
8. `ref/StrikersRecomp/runtime/host/sdk_map.c`
9. `ref/StrikersRecomp/runtime/host/sdk_map.h`
10. the HLE registries in `ref/StrikersRecomp/runtime/host/hle.c`
11. `host/src/ballpad_debug.cpp`
12. the autostart section in `host/src/ballpad_ios_host.cpp`
13. the relevant pinned decomp sources for each scene transition before
    implementing that transition.

At minimum, orient in these decomp files:

- `Game/BaseGameSceneManager.cpp`
- `Game/GameSceneManager.cpp`
- `Game/SH/SHHealthWarning.cpp`
- `Game/SH/SHTitleScreen.cpp`
- `Game/SH/SHMainMenu.cpp`
- `Game/SH/SHChooseSides.cpp`
- `Game/SH/SHChooseCaptains.cpp`
- `Game/SH/SHStadiumSelect.cpp`
- `Game/SH/SHLoading.cpp`
- `Game/OverlayHandlerHUD.cpp`
- `Game/FixedUpdateTask.cpp`
- `Game/GameRenderTask.cpp`

## Protected state

All pre-existing changes belong to the user. In particular:

- do not modify, pull, reset, clean, stash, or switch
  `ref/smstrikers-decomp`;
- do not discard the current README/docs worktree;
- do not use destructive Git commands;
- keep the clean pinned acquisition under ignored `work/decomp/`; and
- preserve local `ref/GXRuntime` and `ref/StrikersRecomp` patches, updating the
  tracked patch snapshot when this task intentionally changes StrikersRecomp.

Do not commit, push, publish, or open a PR. Present the final isolated diff for
owner review.

## Allowed scope

You may change only what C0–C6 require:

- `scripts/generate_strikers.sh`;
- a small tracked decomp-symbol allowlist/config and generator tests;
- decomp contract/symbol generation tooling in `ref/StrikersRecomp/tools/`;
- symbol-map/runtime code in `ref/StrikersRecomp/runtime/host/`;
- the tracked StrikersRecomp patch snapshot;
- `host/src/ballpad_debug.cpp`;
- the autostart/status portions of `host/src/ballpad_ios_host.cpp`;
- focused native/test build files required by those changes; and
- docs 15, 28, and 29 after evidence exists.

Do not change renderer behavior, shaders, touch layout, app UX, QuickBoot,
widescreen, audio policy, or unrelated performance code.

## Required proof record

Maintain ignored:

`build/proofs/decomp-contract/PROGRESS.md`

Keep it current with:

```text
Active package:
Attempt: 0/3
Ballpad SHA:
Protected files:
Pinned decomp SHA/status:
Main DOL SHA-1:
SDK table SHA-256:
Named decomp source/function:
Contract under test:
Expected pass:
Expected failure:
Allowed files:
Baseline command/result:
Narrow test/result:
Adjacent test/result:
Evidence hashes:
Next action:
```

## Package loop

For each package, execute exactly:

```text
READ SOURCE -> WRITE CONTRACT -> BASELINE -> ADD FAILING TEST
-> SMALLEST CHANGE -> RUN NARROW TEST TWICE
-> RUN ADJACENT TEST -> RECORD -> ADVANCE
```

Do not edit implementation before the package's contract and failing test are
written. If the baseline already satisfies the contract twice, record
`ALREADY_PASSING` and do not make a cosmetic patch.

## C0 — Protected baseline

Run and record:

```sh
git rev-parse HEAD
git status --short
git -C ref/smstrikers-decomp rev-parse HEAD
git -C ref/smstrikers-decomp status --short
git -C ref/StrikersRecomp rev-parse HEAD
git -C ref/StrikersRecomp status --short
./scripts/check_ref_patches.sh
shasum -a 1 work/strikers/generated/main.dol
shasum -a 256 work/strikers/generated/sdk_symbols.inc
git check-ignore work/decomp/smstrikers-decomp-c0bf2ed
```

Gate C0:

- hashes equal the fixed values;
- every dirty file is recorded as protected or explicitly in this task's
  allowed scope; and
- no file has changed during C0.

Stop if the current generated DOL hash differs. Do not “fix” the mismatch.

## C1 — Acquire and test the decomp contract

Acquire a new checkout only at `DECOMP_WORKTREE`, detach at `DECOMP_COMMIT`, and
verify clean status. Never touch `ref/smstrikers-decomp`.

Before changing generation, add automated fixtures for:

1. correct DOL hash and commit;
2. wrong DOL hash;
3. wrong decomp commit;
4. missing required symbol;
5. ambiguous required name;
6. malformed symbol line; and
7. unexpected SDK table change.

The parser must preserve all address-sorted function records while also
reporting unique-name and duplicate-name counts. A reverse lookup used for a
generated constant must be unique or generation fails.

Gate C1:

- pinned checkout is clean/detached;
- positive fixture passes;
- every negative fixture fails for its intended reason; and
- regenerated `sdk_symbols.inc` retains the fixed SHA-256.

Do not build the full Metrowerks decomp in C1. Exact DOL/config identity is the
required source/address proof for this tranche.

## C2 — Generate and consume the full source map

Extend the generation path to emit:

```text
sdk_symbols.inc
game_symbols.inc
game_addresses.h
decomp_contract.inc
decomp_contract.json
```

Add a tracked explicit allowlist mapping stable Ballpad constant names to exact
decomp symbols. It must support both function and object symbols. Do not infer
constants from comments in C/C++ source.

Add a runtime API for:

- exact PC lookup;
- nearest containing function plus offset;
- unique exact-name lookup for tests/diagnostics; and
- decomp contract metadata.

Use binary address lookup. Do not linearly scan the full map per guest block.

Required tests:

- exact function start;
- address inside function;
- below and above code ranges;
- duplicate-name rejection for reverse lookup;
- object constant generation;
- sorted output and deterministic regeneration; and
- provenance fields equal fixed commit/DOL values.

Wire provenance into Ballpad's diagnostic snapshot. Update fatal/stop and guest
backchain logs so a PC is printed as address plus decomp function and offset.

Gate C2:

- all generator/lookup tests pass twice;
- generated artifacts reproduce byte-for-byte;
- native host builds; and
- an opt-in smoke resolves at least `FixedUpdateTask::Run` and
  `GameRenderTask::Run` correctly.

## C3 — Remove named raw-address coupling

Replace numeric guest function addresses in:

- `kAddrHandlers`;
- `kTrace`;
- `kNotify`;
- `kPhysicsNotify`; and
- task-entry comparisons in `host/src/ballpad_debug.cpp`.

Replace the directly used `g_pGame` and scene/task singleton/global addresses
needed by public status and C4/C5 with generated object constants.

Do not mechanically replace:

- MEM1 range constants;
- MMIO or exception addresses;
- HLE sentinel return addresses;
- bit masks; or
- unrelated one-off forensic addresses.

Add a static test that rejects a new numeric `0x80...` function literal inside
the four migrated registries and task-entry comparison block.

Gate C3:

- every generated constant equals the prior numeric address;
- static raw-address regression passes;
- HLE initialization finds every required symbol;
- existing input/native smoke tests pass; and
- `./scripts/check_ref_patches.sh` passes after refreshing only the intentional
  StrikersRecomp patch snapshot.

## C4 — Add source-named scene events

Use observe-only hooks at generated addresses. Read the exact pinned source
before adding each hook.

The minimum event set is:

- `BaseGameSceneManager::Push`;
- `BaseGameSceneManager::Pop`;
- `BaseGameSceneManager::PushLoadingScene`;
- scene creation/update points needed for health/title, main menu, choose
  sides/captains, stadium/loading, and HUD;
- `HUDOverlay::SceneCreated` as the match-created marker; and
- `FixedUpdateTask::Run` as the relative moving-frame clock.

Keep scene observation in HLE and expose a small read-only `HleSceneSnapshot`
API containing the event sequence, requested/current scene, marker flags,
relative fixed-update count, and game state. The iOS host reads that snapshot
and owns the input state machine. Do not parse logs to drive input and do not
move host input policy into HLE.

Emit only when `BALLPAD_SCENE_TRACE=1`. Use stable bounded lines:

```text
[scene] seq=N event=TYPE scene=ID function=NAME rel_frame=N game_state=N
```

Do not log native pointers, local paths, or every fixed update. Log match zero,
then bounded milestones such as relative frames 1, 60, 300, and 600.

Gate C4:

- two fresh runs on one Simulator produce the same ordered semantic scene
  sequence through match zero;
- every event names a generated decomp function; and
- normal runs emit no scene trace.

## C5 — Replace the block-count autostart

Delete the fixed global `at_blocks` menu schedule from
`host/src/ballpad_ios_host.cpp`.

Implement a finite state machine driven by the C4 scene/state observations.
For each transition, document:

- decomp source file and function;
- observed scene/state prerequisite;
- one input action;
- relative-frame debounce/hold rule; and
- expected next named scene/state.

Rules:

- no menu action may be selected by global block count or wall time;
- local input holds use relative fixed-update frames only;
- never write guest scene objects directly;
- never bypass loading or initialization functions;
- stop and release the pad immediately at match zero;
- preserve manual input after release; and
- retain a bounded watchdog that reports current/expected named state without
  guessing a new input.

After match zero, run a versioned 600-fixed-update movement/input segment using
the relative frame clock. This segment is the deterministic moving-scene anchor
for the next renderer tranche.

Gate C5:

- two consecutive fresh iPhone Simulator runs pass;
- two consecutive fresh iPad Simulator runs pass;
- every run reaches live game state, observes HUD creation, releases
  automation, completes 600 relative fixed updates, and continues advancing;
- ordered scene sequence and versioned input hash match across repetitions; and
- source contains no fixed global block threshold used for menu navigation.

Use one Simulator at a time through `scripts/sim_mutex.sh`.

## C6 — Adjacent regressions and documentation

Run:

- all generator and lookup tests;
- contract negative tests;
- native input test;
- one manual-touch smoke on each Simulator form factor;
- controller-overlay handoff smoke where available;
- fresh Aurora render smoke;
- `git diff --check`;
- documentation local-link verification; and
- `./scripts/check_ref_patches.sh`.

Append exact evidence to `docs/15-validation-log.md`. Update docs 28 and 29
only with results actually proved.

Gate C6:

- applicable regressions pass;
- failures are not hidden by changed thresholds/scenes;
- tracked patch snapshots match intentional local dependency changes; and
- no unrelated or protected file is included in the task diff.

## Three-attempt failure policy

- Attempt 1: inspect the failing contract and named decomp source.
- Attempt 2: verify DOL/pin/input identity and the first differing event.
- Attempt 3: make one final bounded correction or mark the package `BLOCKED`.

After attempt 3, stop. Do not change the acceptance gate, switch scenes, add
speculative inputs, or begin work from a later package.

## Work explicitly forbidden in this task

- native ARM64 source port or feasibility spike;
- native/decomp function insertion into guest execution;
- QuickBoot repair or enablement;
- renderer/shader changes;
- modified decomp DOL experiments;
- UI, widescreen, audio-policy, or performance feature work;
- upstream pin changes;
- commits, pushes, PRs, or destructive Git operations.

## Final report format

```text
Overall status: PASS | BLOCKED
Completed packages:
First incomplete package:
Attempts used at incomplete gate:
Ballpad SHA:
Pinned decomp SHA:
Main DOL SHA-1:
Generated artifact hashes:
Protected pre-existing files:
Files changed by this task:
Raw-address migrations:
Scene transitions implemented with source references:
iPhone fresh runs:
iPad fresh runs:
600-frame moving-segment identity:
Adjacent regressions:
Rejected hypotheses/changes:
Remaining blocker:
Exact next action:
```

Begin at C0. Do not start with implementation, QuickBoot, rendering, or a
second decomp build.

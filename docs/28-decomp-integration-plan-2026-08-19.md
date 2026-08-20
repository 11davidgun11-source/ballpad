# 28 — Decomp integration decision and execution plan

Updated 2026-08-20 after primary-agent source/runtime review.

## Decision

Use the complete function-level Super Mario Strikers decompilation as a
**verified build contract and source map for the existing Ballpad runtime**.

The first implementation tranche will:

1. pin and verify the current decomp source against Ballpad's exact `main.dol`;
2. generate complete, tested function/object metadata instead of reducing the
   decomp to the current SDK-only table;
3. replace named raw guest addresses with generated source-derived constants
   and symbol lookup;
4. expose source-aware crash, trace, and diagnostic information; and
5. prove the integration by replacing the block-count autostart heuristic with
   a scene-driven, source-named automation path that deterministically reaches
   and marks a moving match.

This is the primary agent's judgment, not a question for the implementation
agent to reopen.

## Why this is the correct first use

Ballpad currently consumes only a small fraction of the decomp:

- `symbols.py` reads 8,212 unique function names but emits only the 372 names
  intersecting Aurora's SDK headers;
- the source map actually contains 8,604 function records plus named data
  objects;
- HLE registries, task diagnostics, global-state reads, scene probes, and
  QuickBoot helpers still contain many manually copied `0x80...` addresses;
- the iOS autostart route is a 6.9-billion-block input schedule, even though
  the decomp names the scene manager, scene handlers, HUD creation, game-state
  transition, fixed-update, and render functions involved.

The supported Ballpad DOL has SHA-1
`376d699c99b6b0949abe1b4ceccefdef7828d2b5`. That is exactly the target hash in
the upstream decomp configuration. Therefore Ballpad's guest addresses map
directly to the reviewed source. We do not need to begin by building and
instrumenting a second DOL merely to rediscover that relationship.

## Pinned upstream decision

Use exactly:

```text
Repository: https://github.com/yannicksuter/smstrikers-decomp
Commit:     c0bf2ed65f6220e69a8db1f8f115c867737f315f
DOL SHA-1:  376d699c99b6b0949abe1b4ceccefdef7828d2b5
```

At this commit the reported state is 100% code, 100% fuzzy, 98.14% data, and
99.24% linked. There is one configured nonmatching translation unit:
`Game/Drawable/DrawableCharacter.cpp`.

Do not follow floating `main`. A newer commit may be reported, but changing the
pin requires a separate reviewed update. The current SDK-table output at this
pin remains byte-identical to Ballpad's existing output:

```text
a2b5da87203a8ea118cab30f7fdc8070280041e80de6cdf6fbf4fca7ac1789bb
```

## What the first bot will build

### 1. Decomp build contract

The generation path must fail closed unless all of these agree:

- supported game/revision;
- extracted `main.dol` SHA-1;
- decomp `config/G4QE01/config.yml` target hash;
- pinned decomp Git commit;
- symbol-map parser expectations; and
- required function/object symbols.

The generated directory will contain:

| Artifact | Purpose |
|---|---|
| `sdk_symbols.inc` | Existing Aurora SDK intersection; output must remain unchanged in this tranche. |
| `game_symbols.inc` | Address-sorted full function map for exact/nearest PC diagnostics. Preserve all address records; do not collapse records merely because names repeat. |
| `game_addresses.h` | Constants for an explicit allowlist of Ballpad-used functions and objects, resolved from exact decomp names. |
| `decomp_contract.inc` | DOL hash, decomp commit, symbol/split hashes, and record counts exposed to native diagnostics. |
| `decomp_contract.json` | Machine-readable generation record for tests and proof artifacts. |

Ambiguous reverse lookups must fail generation. The allowlist uses exact
mangled symbol names and a stable Ballpad constant name; the bot may not choose
the first of several same-named symbols.

### 2. Source-aware runtime map

Add a small runtime API with:

- exact PC to function name;
- nearest containing function plus offset;
- unique exact-name to address for diagnostics/tests; and
- decomp contract/provenance access.

Normal execution must not perform a linear 8,604-entry name scan per guest
block. Address lookup is sorted/binary; hook addresses are resolved once or
compiled as generated constants.

### 3. Raw-address migration boundary

Migrate only semantically named guest coupling in this tranche:

- `kAddrHandlers`, `kTrace`, `kNotify`, and `kPhysicsNotify` in HLE;
- task-entry PCs in `host/src/ballpad_debug.cpp`;
- `g_pGame` and scene/task globals used by public status and the new scene
  automation; and
- any directly adjacent source-named constant required for those paths.

Do not replace architectural masks, MMIO addresses, MEM1 bounds, exception
vectors, temporary HLE sentinel addresses, or unrelated debug research values.
A test must reject a newly introduced numeric guest function address inside the
migrated registries.

### 4. Scene-driven autostart payoff

The current `BALLPAD_AUTOSTART=1` implementation uses dozens of button presses
at fixed guest-block thresholds up to 6.9 billion blocks. Replace that control
logic with source-derived events and state:

- observe `BaseGameSceneManager::Push`, `Pop`, and `PushLoadingScene`;
- observe the relevant scene handler/update functions for health/title, main
  menu, choose sides/captains, stadium/loading, HUD creation, and match start;
- use actual scene/state transitions to decide the next bounded input;
- use `HUDOverlay::SceneCreated` plus `FixedUpdateTask::Run` as the initial
  moving-match zero point;
- count deterministic relative fixed updates after that point; and
- stop automation and release the pad as soon as the live-match gate is met.

The bot must read the named decomp sources before encoding a transition. It may
not replace one timing table with a different timing table. Small local
debounce/hold windows are allowed only after a named state transition and must
be expressed in relative game frames, not global blocks or wall time.

This path remains test/developer automation. Manual touch and controller input
must remain unchanged. QuickBoot stays off by default.

The state boundary is fixed: HLE observe-only hooks maintain and expose a small
portable `HleSceneSnapshot` (event sequence, requested/current scene, marker
flags, relative fixed-update count, and game state). The iOS host reads that
snapshot and owns the finite-state input driver. Do not bury UIKit/host input
policy in HLE, and do not make the host scrape log text.

## Ordered packages and gates

### C0 — Protected baseline

Record Ballpad SHA/status, protected user files, dependency SHAs/status,
current DOL and SDK-table hashes, and `check_ref_patches.sh` result. Do not
alter the dirty `ref/smstrikers-decomp` checkout.

**Gate:** baseline is attributable and no product behavior changed.

### C1 — Immutable acquisition and contract test

Acquire the pinned decomp into ignored
`work/decomp/smstrikers-decomp-c0bf2ed`, detach at the full commit, and verify
clean status. Add generator tests before changing runtime code.

Required negative tests:

- wrong DOL hash;
- wrong decomp commit;
- missing required symbol;
- duplicated/ambiguous requested name;
- malformed symbol record; and
- SDK-table drift.

**Gate:** exact pin and DOL pass; every negative fixture fails with a precise
message; current `sdk_symbols.inc` hash is unchanged.

Building the full decomp with Metrowerks is not a C1 prerequisite. The exact DOL
hash and config contract are sufficient for source/address identity. Build the
decomp later only when a source modification or matching-object experiment
actually requires it.

### C2 — Generate and consume source metadata

Generate the five artifacts, add the lookup API/tests, and wire provenance into
the diagnostic snapshot and fatal/stop/backchain logs.

**Gate:** lookup tests cover exact, interior, below-range, above-range,
duplicate-name, and object-address cases; native build passes; an opt-in smoke
log resolves a known PC to its decomp name and offset.

### C3 — Migrate the named raw-address boundary

Convert the listed HLE registries, task counters, and selected globals to the
generated constants/API. Refresh the tracked StrikersRecomp patch snapshot.

**Gate:** generated constants equal the previous addresses; a static regression
check rejects raw function addresses in migrated tables; HLE/input/native smoke
tests show no behavior change.

### C4 — Implement the scene event stream

Add opt-in, quiet-by-default semantic events with stable fields:

```text
[scene] seq=<n> event=<push|pop|created|match-zero|fixed-update>
        scene=<enum> function=<decomp-name> rel_frame=<n> game_state=<n>
```

Do not log local paths, native pointers, or unbounded per-frame output.

**Gate:** two fresh runs produce the same ordered scene sequence through
`match-zero`; the source/function names resolve through the generated map.

### C5 — Replace block-count autostart

Implement the scene-driven state machine, remove the fixed global block
threshold table, and retain a watchdog that reports the last named scene and
expected transition.

**Gate:** two consecutive fresh runs on iPhone Simulator and two on iPad
Simulator reach live game state with HUD created, release automation, and then
run at least 600 relative fixed updates with a versioned movement/input segment.
No global-block threshold selects a menu action.

### C6 — Adjacent regression and record

Run manual touch smoke, controller-overlay handoff smoke, fresh Aurora render
smoke, invalid-contract tests, and `check_ref_patches.sh`. Update doc 29 and the
validation ledger with exact commands and results.

**Gate:** all applicable checks pass or the first failure is recorded without
weakening C0–C5.

## Explicitly deferred

The first bot must not:

- start a native ARM64 source port;
- insert native decomp functions into guest execution;
- fix QuickBoot;
- redesign graphics or shaders before the deterministic scene gate exists;
- build a separate instrumented DOL unless C1–C5 expose a question that cannot
  be observed in the current exact-DOL runtime;
- change UI, widescreen, performance policy, or product features; or
- chase 100% linked status in the upstream decomp.

These are later decisions. The first tranche makes every one of them easier to
reason about.

## Loop policy

For each package:

```text
READ NAMED SOURCE -> STATE CONTRACT -> BASELINE -> TEST FIRST
-> SMALLEST CHANGE -> NARROW VERIFY -> ADJACENT VERIFY
-> RECORD -> ADVANCE
```

One package is active at a time. After three failures of the same gate, stop,
record the exact evidence, and request the missing dependency or decision.

## Approval boundary

Planning state is `AWAITING_OWNER_APPROVAL`.

After approving this decision, feed the implementation agent exactly:

[BOT6_DECOMP_INTEGRATION_LOOP.md](BOT6_DECOMP_INTEGRATION_LOOP.md)

with the activation phrase contained in that document. No other prompt or old
bot loop is required.

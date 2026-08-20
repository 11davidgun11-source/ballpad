# 29 — Decomp-to-Ballpad runtime crosswalk

Updated 2026-08-20. Status: `PASS_C0_C6`.

This document records the verified source identities used by the decomp
contract and scene-driven runtime tranche. Bot 6 updates status/evidence here;
it does not choose a different work queue.

## Contract identity

| Field | Required value |
|---|---|
| Decomp repository | `https://github.com/yannicksuter/smstrikers-decomp` |
| Pinned commit | `c0bf2ed65f6220e69a8db1f8f115c867737f315f` |
| Supported DOL SHA-1 | `376d699c99b6b0949abe1b4ceccefdef7828d2b5` |
| Current SDK table SHA-256 | `a2b5da87203a8ea118cab30f7fdc8070280041e80de6cdf6fbf4fca7ac1789bb` |
| Function records | 8,604 in the source map; current parser observes 8,212 unique names |
| Upstream status at review | 100% code, 99.24% linked; `Game/Drawable/DrawableCharacter.cpp` is the single configured nonmatching unit |

## Seed function/object map

These values were read from the matching `G4QE01` map. Bot 6 must generate and
test them rather than copying these numeric values into new runtime code.

| Stable Ballpad identity | Exact decomp symbol | Address | Source role |
|---|---|---:|---|
| `GAME_FN_SCENE_PUSH_LOADING` | `PushLoadingScene__20BaseGameSceneManagerFb` | `0x800955BC` | Announces/loading-scene transition |
| `GAME_FN_SCENE_POP` | `Pop__20BaseGameSceneManagerFv` | `0x80095844` | Removes top game scene |
| `GAME_FN_SCENE_PUSH` | `Push__20BaseGameSceneManagerF9SceneList14ScreenMovementb` | `0x800958E0` | Creates/pushes a named `SceneList` transition |
| `GAME_FN_HUD_SCENE_CREATED` | `SceneCreated__10HUDOverlayFv` | `0x800F8400` | Initial match-created marker |
| `GAME_FN_FIXED_UPDATE_RUN` | `Run__15FixedUpdateTaskFf` | `0x8016E330` | Relative moving-frame clock |
| `GAME_FN_GAME_RENDER_RUN` | `Run__14GameRenderTaskFf` | `0x80170BAC` | Game render task boundary |
| `GAME_OBJ_GAME_POINTER` | `g_pGame` | `0x80373708` | Public game instance used for game-state diagnostics |
| `GAME_OBJ_SCENE_MANAGER_POINTER` | `s_pInstance__31nlSingleton<16GameSceneManager>` | `0x80373840` | Game scene manager singleton |

The implementation allowlist will include the existing HLE/trace/physics hook
symbols and any additional scene-handler functions proven necessary by C4/C5.
Each entry must preserve its exact decomp name and kind (`function` or
`object`).

## Package scoreboard

| Package | Exit condition | Status | Evidence |
|---|---|---|---|
| C0 | Protected baseline and current hashes recorded | PASS | `build/proofs/decomp-contract/PROGRESS.md` |
| C1 | Pinned checkout and positive/negative contract tests pass | PASS | `ref/StrikersRecomp/tools/test_decomp_contract.py` |
| C2 | Deterministic generated maps, lookup API, provenance diagnostics | PASS | generator/lookup suites and native build |
| C3 | Named HLE/debug/global address coupling migrated | PASS | raw-address regression and patch snapshot |
| C4 | Repeated source-named scene sequence through match zero | PASS | final phone/iPad traces share identical 26-event prefix |
| C5 | Two phone and two iPad fresh 600-frame moving runs | PASS | final phone/iPad traces complete 600 and continue at 900 |
| C6 | Adjacent regressions and documentation complete | PASS | native, UI, render, links, diff, patch checks |

## Scene transition record

Bot 6 adds one row only after reading the pinned source and observing the
transition twice.

| Order | Source file/function | Observed prerequisite | Input action | Relative-frame rule | Expected next source/state | Verification |
|---:|---|---|---|---|---|---|
| 1 | `Game/SH/SHHealthWarning.cpp` / `HealthWarningSceneV2::Update` | scene 51; source waits for its presentation timer | A | enter-frame + 120 fixed updates; 30-frame hold, 60-frame release gap | health/title prompt scenes 39/53 | PASS; all final traces |
| 2 | `Game/SH/SHTitleScreen.cpp` / title update path | title/prompt scenes 39/53/2 | A | scene-relative action; bounded 3 attempts | scene 2 then main-menu stack | PASS; all final traces |
| 3 | `Game/SH/SHMainMenu.cpp` / main-menu update path | scene 2 and its menu stack | A | scene-relative action; bounded 3 attempts | scene 1/3 captain-selection stack | PASS; all final traces |
| 4 | `Game/SH/SHChooseCaptains.cpp` / `ChooseCaptainsSceneV2::Update` | scene 8; source presentation gate not settled | A, Left, A, A | enter-frame + 90 fixed updates; 30-frame holds; one exact sequence retry | scene 8 completes, then stadium scene 9 | PASS; identical sequence on all final traces |
| 5 | `Game/SH/SHChooseSides.cpp` / `IChooseSide::UpdateForFE` | side-selection phase within scene 8 | Left then A acceptance presses | same relative hold/gap; no guest-object writes | selected side/captain state and return from scene 8 | PASS; source-derived sequence |
| 6 | `Game/SH/SHStadiumSelect.cpp` / stadium update path | scene 9 | A | scene-relative 30-frame hold and 60-frame gap | `PushLoadingScene`, scene 43 | PASS; all final traces |
| 7 | `Game/SH/SHLoading.cpp` / loading update path | scene 43 | A | scene-relative 30-frame hold and 60-frame gap | HUD creation / live state | PASS; all final traces |
| 8 | `Game/OverlayHandlerHUD.cpp` / `HUDOverlay::SceneCreated` + `Game/FixedUpdateTask.cpp` / `FixedUpdateTask::Run` | HUD overlay creation; `game_state=0` at match marker | Stop automation; neutral pad | release at marker; milestones 1/60/300/600/900 | 600 advancing fixed updates, then continued neutral run | PASS on two final phone and two final iPad traces |

No row may use a global guest-block threshold or wall-clock delay as its
transition condition.

## Evidence entry template

```text
Date:
Package:
Ballpad SHA:
Decomp SHA:
DOL SHA-1:
Source file/function:
Generated constant:
Baseline command/result:
Narrow command/result (run 1/run 2):
Adjacent command/result:
Artifact hashes:
Status: PASS | FAIL | BLOCKED
Limitation:
```

## 2026-08-20 — C4/C5/C6 final evidence

- The pinned source-derived FSM reached the same 26-event semantic scene prefix
  through `HUDOverlay::SceneCreated` on the final two fresh phone and two fresh
  iPad runs; all four normalized prefixes match.
- Every final run completed the versioned neutral anchor at relative frame 600
  and emitted the continuation marker at relative frame 900:
  `ballpad-scene-move-v1:neutral-600-fixed-updates`, SHA-256
  `1c446471cbd11091671af575f8317d60af0e7f7f6dfe5a41e4f71f186c836a46`.
- The earlier frame-300 reports were caused by a fixed 130-second harness cutoff;
  marker-driven waits completed normally once that cutoff was removed.
- C6 passed: contract/generator suites twice, native pad merge test, phone/iPad
  touch and controller-handoff UI smoke, fresh Aurora screenshots, local-link
  verification, `git diff --check`, and `check_ref_patches.sh`.

# Native Strikers acceptance specification

## Completion levels

`SIMULATOR_VERIFIED` means every required local gate below passed on the recorded build. `DEVICE_VERIFIED` additionally requires physical hardware evidence. `DISTRIBUTION_REVIEWED` requires a separate rights and packaging decision. Never merge these labels into one undifferentiated green status. The current assignment targets the first level plus an unsigned device compilation.

Statuses: `NOT_RUN`, `IN_PROGRESS`, `PASS`, `FAIL`, `BLOCKED`, and `NOT_APPLICABLE` with a reason. Required rows cannot be skipped or relabeled not applicable merely because they fail. No evidence from the old engine satisfies a new-engine row.

## Test environment and integrity

- Record host model/SoC, OS, compiler/Xcode/SDK, Simulator model/runtime/UDID, app configuration, engine SHA/patch digest, app SHA or dirty diff digest, dependency manifest digest, game region/revision, render size/settings, seed/input route, duration, command and process exit result.
- Run one task-owned Simulator at a time and coordinate with other tasks through a scoped lock. Never shut down another task's Simulator. Discover fresh UDIDs; reuse existing unrelated devices only with clear ownership.
- Use installed current Xcode runtimes and one phone plus one iPad profile. Runtime labels do not emulate the target device's CPU/GPU speed. Add oldest-declared-OS coverage if installed; otherwise report untested compatibility separately.
- Use Release for timing. UI-test instrumentation overhead and Simulator audio service errors must be recorded, not silently discarded. Do not manually terminate a hanging harness and call that a pass.
- Maintain separate clean-user-data and warm-cache runs. Keep actual game data, screenshots/video, saves and traces local/ignored. Store a tracked textual result and a checksum-indexed local proof bundle.

## Required functional matrix

Each row applies to both phone and iPad unless stated otherwise.

| ID | Required evidence |
|---|---|
| F01 | Fresh install with no data shows import UI and no crash; valid local raw USA image selected through Files stages and activates correctly. Automation that only pre-seeds the sandbox does not prove the Files UI. |
| F02 | Invalid/truncated/wrong-game image is rejected; failure/cancel leaves previous installation usable; original image unchanged. |
| F03 | Cold boot traverses title, selection and stadium/loading to genuine active play; no QuickBoot or fake frames. |
| F04 | Real UI touches operate menu navigation and main-stick movement plus an action simultaneously. Verify game response, not merely button hittability. Test A/B/X/Y/Z, Start, D-pad, C-stick and both shoulders at a state or input boundary where their mapping can be observed. |
| F05 | Full regulation match, goal, replay/supershot where reproducibly reachable, and post-match return work. Start a second match; do not accept a frozen HUD over a changing background. |
| F06 | Landscape layout fits safe areas; control editing, resizing, opacity, reset and persistence work after relaunch. Phone and iPad screenshots must be visually inspected in their actual orientation. |
| F07 | Settings/menu pauses and resumes correctly, does not pass touches through, and never leaves a stuck stick/button. Ten menu open/close cycles and five background/foreground cycles succeed. |
| F08 | Display settings apply at a safe frame boundary; native/widescreen geometry and HUD remain correct. Resize or orientation transitions do not lose the drawable or duplicate the engine. |
| F09 | Native audio stays active through a match and replay, with queue/underrun diagnostics and sampled/recorded output. Inspect/listen when tools support it; state audibility not verified if they do not. Nonzero peaks alone are not an audio fidelity pass. Required objective stream tests must still pass. |
| F10 | THP movie video and audio play; documented movie skip works without corrupting later audio. A movie-disabled build fails this row. |
| F11 | Game-created save survives normal exit/relaunch; export/import round trip preserves expected game state; corrupt input fails safely. Use copied cards and back up any prior user data. |
| F12 | Controller state merging/connect/disconnect logic is tested at the bridge boundary without duplicate sampling. Real controller usability is a separate hardware row if no controller is available. |
| F13 | About screen names upstream contributors, opens relevant links and displays full bundled notices offline; no unsupported “all code CC0” or official-affiliation claim. |
| F14 | Default linked/running application reports native source engine identity and Metal presentation. No legacy guest execution or per-frame UIImage conversion in normal output. |

Run at least two fresh boot-to-match passes per form factor on the final candidate, plus one complete-match/endurance sequence per form factor. After changing behavior, repeat affected rows and a boot-to-match smoke check; rerun the full matrix when integrating the final clean build.

## Automation contracts

Drive deterministic navigation with named native scene transitions and bounded waits. Expose quiet test-only state observability (scene, match active, fixed-update count, input consumed, presentation count, error state) without parsing logs for product behavior. Inputs must reach the same sampling boundary as human controls. UI acceptance must include coordinate/accessibility-driven touches on the actual app surface, not only private injected input.

Provide finite deadlines per expected state, with last observed state and screenshot on failure. A whole-suite watchdog must exit nonzero on timeout. No global-block heuristics, unbounded sleeps, fabricated screenshots, skipped expensive scenes, hidden geometry, accelerated game clock or test-only simplified rendering. An injected test event used to reach a rare replay can supplement but cannot replace the ordinary completed-match path; label it.

## Performance gates

Baseline settings: 60 fps target, 1x-equivalent internal resolution, conservative filtering and MSAA off. Record actual pixel dimensions. Record a cold run and a warmed run separately, with startup/loading, active gameplay, and replay/transitions segmented. Both form factors require at least 20 minutes of sustained play/transitions and repeated match loads, sequentially on the same host.

For the warmed active-play segment, the initial acceptance target is at least 58 produced/rendered frames per second on average, p95 frame-production interval at most 20 ms, and p99 at most 33.4 ms. Count real completed engine/render frames rather than UI timer ticks or repeated images. Where actual compositor presents cannot be measured, label the measurement frame production and do not claim display-cadence proof. Report all stalls over 100 ms. These thresholds are Simulator regression objectives on the named host, not a guarantee for any mobile SoC.

For goal/replay segments after their assets have loaded, target at least 55 frames per second on average and p95 at most 33.4 ms. Report cold shader/asset stalls and loading delays separately, including maximum duration. No recurring steady-state freeze longer than 250 ms may be hidden as “loading”; classify the state from source evidence. If a threshold fails, retain FAIL and profile it. Do not change thresholds merely to finish.

Compare in-game clock progression and fixed-update rate against the desktop reference over at least 60 seconds of active, unpaused play. Preserve upstream rate semantics and show within 2% agreement for the chosen corresponding segment. Do not assume displayed game-clock seconds equal real seconds without checking the reference.

Measure application CPU usage, frame timing, audio queue depth/underruns, and memory at stable state boundaries. Collect GPU timing where supported and explicitly say unavailable otherwise. Report startup, peak and steady-state memory; distinguish virtual reservation from physical footprint. After one warm-up match, five comparable load/play/return cycles must show stabilization rather than unexplained monotonic footprint growth. Retained caches may plateau; explain growth with allocation evidence rather than inventing a memory cap. Any reproduced use-after-free, save corruption, or scene-corrupting allocation failure fails acceptance.

Simulator host contention can invalidate a run; identify the competing load and rerun under controlled conditions. If performance still cannot be established, leave that gate unmet and give the exact trace and device test needed. Functional progress can continue, but the complete local acceptance goal is not passed.

## Build and provenance gates

| ID | Required evidence |
|---|---|
| B01 | Clean macOS native engine build and data-independent tests, including upstream parser/tool tests. |
| B02 | Simulator app builds using Simulator libraries; unsigned device app builds using device libraries. Inspect platform metadata, not just arm64 labels. |
| B03 | Independent bootstrap from clean checkout/output applies tracked patches to pinned dependencies and reproduces the app without edited ignored trees. |
| B04 | No generated source/assets/saves/private data accidentally staged; dependency and license inventory matches bundle contents and build configuration. |
| B05 | Test commands return truthful status, evidence points to current app/digests, build commands are documented and verified. |

## Device and distribution handoff

Do not mark these PASS using Simulator evidence: physical sustained 60 fps, thermal behavior, battery cost, jetsam tolerance, touch latency, hardware controller/rumble behavior, device speaker/Bluetooth audio, phone-call interruptions and lock-screen behavior. Provide a device script/checklist and an unsigned build. Record `NOT_RUN — physical device unavailable` where appropriate; absence of hardware does not block completion of the explicitly Simulator-scoped assignment.

Public repository/source publication, signed IPA distribution, TestFlight, App Store review and rights clearance are outside the local gate. Preparation of notices is required; it does not establish permission for all reconstructed material.

## Per-run proof bundle

Include `metadata.json`, machine-readable test results, timing CSV/summary, audio metrics, memory samples, phase/scene timestamps, representative screenshots, a moving-play/replay recording when supported, build/test logs and artifact hashes. Include available `.xcresult` output. Evidence omissions must be visible in the summary. Store only concise non-asset summaries and relative proof locations in doc 36.

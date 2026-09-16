# Native Strikers implementation runbook

> Historical implementation runbook. The current build uses the maintained engine
> fork pinned in `scripts/native/common.sh`, without patch application. Follow the
> repository README for current commands and `docs/41-release-source-audit-2026-09-16.md`
> for the source migration and release evidence.

## Decision and scope

Implement an iPhone/iPad application using the native source port at https://github.com/new-coke/strikers as its engine, retaining Ballpad's useful Swift interface. The deliverable is a reproducible, Simulator-verified development application and an unsigned physical-device build, with complete attribution and an honest hardware-validation handoff. Actual hardware performance and public-distribution clearance are separate statuses, not implied by completion of the Simulator work.

This runbook and documents 34–36 supersede the architecture restrictions, approval phrases, and execution orders in docs 24–32 and BOT2–BOT6 for this migration. Those documents remain historical evidence. In particular, the previous prohibition on a native source port no longer applies. The owner has requested this implementation direction; the implementation agent should execute when given the Bot 7 prompt, without requesting approval for each phase.

This is implementation work, not another feasibility study. Complete the pipeline through acceptance. Do not stop after a plan, successful compile, first frame, automated menu traversal, or a promising screenshot.

## Authoritative reading order

1. This runbook.
2. [34: acceptance specification](34-native-strikers-acceptance.md).
3. [35: attribution and provenance](35-native-strikers-attribution.md).
4. [36: durable execution ledger](36-native-strikers-progress.md).
5. [Research assessment](research/strikers-ios-feasibility.md), including immutable source links.
6. Inspect the current app, host headers, build scripts and repository instructions. Use docs 05/06 for control/menu intent and doc 32 for difficult scenes, not to expand this task to every historical wishlist item.

Root workspace: `<checkout>`.

Pinned upstream: `https://github.com/new-coke/strikers.git` at `22649cb12c112454a34217429296c95bb181af8a` (v1.1.1). Begin with this exact revision. New upstream changes may be adopted only for a concrete observed defect: inspect the diff, record the reason and old/new pin, retain provenance, rerun affected gates. Do not silently follow main.

## Repository and asset arrangement

Keep Ballpad as the integration repository. Create a `codex/native-strikers-ios` development branch without discarding existing changes. Record pre-existing modifications and protect them. Do not reset or clean user work, repurpose the old ignored dependency trees, or remove the previous implementation before the replacement passes.

Create a local Git fork/clone at ignored `work/native/strikers`, preserving upstream history and setting a documented upstream remote. Create its own `codex/ios-port` branch. This satisfies the development-fork requirement; creating a public GitHub fork, pushing, publishing a binary, contacting maintainers, or submitting to TestFlight/App Store is outside this local implementation assignment.

Use a tracked dependency manifest and a tracked ordered patch series under `patches/native-strikers/`. Bootstrap fetches the immutable upstream revision and applies the series into the ignored clone. Export every intended engine/dependency change into reproducible patches before marking a phase complete. Do not leave essential changes only in an ignored directory. Preserve engine history locally; a later public fork can carry the reviewed commit series without flattening authorship.

Use `build/native/` for generated objects, apps, dependency builds and logs. Store proof bundles under `build/proofs/native-strikers/<run-id>/`. Keep concise result summaries in doc 36. Do not commit game-derived screenshots, video, dumps, original game data, saves, or built dependencies. Add explicit ignores for compressed disc formats and any newly used output extensions.

An existing local candidate image was found at `.local-assets/Super Mario Strikers.iso`. Verify it before use; never download replacement game data. Preserve the original image and saves. Use test copies for writes. The known USA baseline is G4QE01 revision 0, with main.dol SHA-1 `376d699c99b6b0949abe1b4ceccefdef7828d2b5`. That DOL hash is a baseline identity check, not a requirement to recompile or execute the DOL in the native engine. If the image is unavailable, continue compilation and data-independent work while requesting only the missing local asset; never substitute synthetic gameplay as acceptance evidence.

## Product requirements

- Native source-compiled game logic with upstream Aurora/Dawn/Metal. No guest execution engine or old GXRuntime/GXCore in the new application's normal path.
- Direct Metal surface presentation. No normal per-frame EFB readback-to-CGImage/UIImage bridge. Diagnostic captures may read back explicitly.
- Universal landscape iPhone/iPad layout, safe areas, usable settings, and persistent touch customization. Portrait play, additional themes, online multiplayer and new gameplay features are not required.
- Full existing GameCube touch inventory and main-stick-plus-action simultaneous input; L/R deliver analog and digital behavior as intended by the current implementation.
- Local Files import of the known USA raw image, staged validation and replacement, actionable errors, persistent paths and saves. Additional upstream regions/formats are optional and must not delay the baseline.
- Native MusyX audio, working movie playback, pause/resume, and no fabricated audio success from sample peaks alone.
- Native and upstream widescreen aspect options where supported; no unintended HUD crop. Conservative 1x-equivalent internal resolution, 60 fps cap and expensive optional filtering/MSAA disabled by default until measured. Do not hardcode Ballpad's old framebuffer dimensions if upstream's actual dimensions differ.
- Controller integration with one authoritative hardware input source and deterministic touch/controller merging. Hardware-only behavior remains explicitly untested without a controller.
- Persistent settings, safe memory-card import/export, resettable controls, readable About/Credits and full notices. No nonfunctional placeholder settings.

Retain the Ballpad project/bundle identity initially to avoid unnecessary signing and migration changes. Use “Ballpad — Strikers iOS port” as development documentation wording; do not imply an official Nintendo release.

## Architecture contracts

Preserve the engine's game-task ordering, timing semantics, native mixer, asset conversions and vendored Aurora patches. Read `src/Game/main.cpp`, `src/platform/{launch.cpp,input.cpp,audio_out.cpp,memalloc.cpp,vm.c,os.c}`, root CMake, and Aurora's platform/build files before changing these boundaries. Fix evidence-supported defects; do not import the old compatibility system wholesale.

Start with a minimal SDL iOS application before integrating Swift. Then expose a small C-compatible bridge for initialization with sandbox paths, lifecycle, input, configuration, status and shutdown. Document ownership and permitted calling thread for every function. Initialization/stop must be safe against repeated UI mounting and partial initialization. Define whether a stopped engine supports restart; if it does not, prevent unsafe reinitialization and provide a controlled application flow rather than calling desktop exit routines from UI actions.

Use exactly one application entry path. Keep UIKit/SDL window operations on their required thread. Do not run a blocking desktop while-loop on the UIKit main thread. Adapt stepping/callbacks or worker coordination while preserving the engine's sequencing. No mutable engine globals read unsafely from Swift. No simultaneous graphics submission from multiple owners. Do not continue drawable acquisition in the background or race save writes with teardown.

Use SDK-specific dependency outputs for macOS, iOS Simulator and iOS device. Inspect Mach-O build-platform metadata as well as CPU architecture. A device ARM64 Dawn archive cannot be assumed to work in an ARM64 Simulator. Build the pinned dependency from source when the appropriate SDK package is unavailable. Do not patch platform metadata to disguise a wrong-platform library. Prevent Homebrew host libraries from entering mobile links. Preserve compiler ABI flags including signed chars and short wchar where the upstream requires them.

## Phase N0 — Protect and establish the baseline

Record Ballpad SHA/status, local engine branch/pin, installed Xcode/SDK/compiler versions, available Simulators and local asset identity. Acquire the persistent engine checkout, inspect its notices and asset inventory, and create the dependency manifest skeleton. Do not rely on `/tmp` research artifacts.

Read the historical screenshot orientation caveat. Discover actual Simulator UDIDs rather than copying old IDs. The existing `scripts/sim_mutex.sh` shuts down every Simulator and is not a real cross-task lock: do not use its global shutdown behavior. Establish a task-owned Simulator and lock policy that never shuts down another task's device.

**Gate:** protected baseline and exact engine provenance recorded; local changes preserved; next build is reproducible from declared inputs.

## Phase N1 — Reproduce the native desktop engine

Build the normal Aurora-enabled Release configuration on macOS ARM64. Use the pinned source, not just a downloaded executable. Run upstream data-independent tests. Diagnose the observed legacy `std::less` header conflict if it affects this configuration; the research only observed it in the optional Aurora-disabled scan. Do not classify that scan as the full build result or “fix” it by changing gameplay semantics.

Using the local image, capture a desktop baseline reaching menus, a real moving match, a goal/replay and post-match. Record timing/configuration and retain screenshots/video locally. Run relevant sanitizers on desktop when diagnosing native corruption; instrumentation builds are not performance baselines.

**Gate:** locally built native engine runs an attributable real game sequence. A desktop runtime environment blocker may be recorded while independent mobile compilation proceeds; it is not silently marked passed.

## Phase N2 — Reproducible mobile dependencies and app target

Implement deterministic bootstrap/build commands. Compile Aurora, SDL, Dawn and necessary dependencies for Simulator and device separately, preserving upstream patches. Gate macOS-only linker sections and packaging correctly. Build an iOS THP-capable FFmpeg configuration or an equivalently verified decoder with documented provenance; disabling movies is allowed during bring-up but not at final acceptance.

Start with the current deployment target where feasible. If a dependency actually requires raising it, record the exact API/build evidence and make the minimum coherent change across targets and docs. Do not claim old-OS compatibility based only on a current Simulator.

**Gate:** minimal Simulator application links, launches, creates a real Metal drawable and exits cleanly; device target also compiles unsigned with correct platform dependencies. No host library leakage or manual archive slicing by line count.

## Phase N3 — First complete native Simulator match

Adapt entry, frame scheduling, sandbox paths and source-level state observability. Boot through the real menus and finish a match using the native engine. Add deterministic test automation driven by named game scenes/state, not guest block counts or one long sequence of sleeps. Build source-state hooks against the current port: old numeric scene IDs are clues, not automatically correct contracts.

Automation may route menus and scripted inputs, but the final path must exercise real touch UI as specified in doc 34. It must release all test inputs at handoff. Temporary QuickBoot, synthetic frames, disabled game logic, skipped draw calls or suppression of replay scenes cannot satisfy this phase.

**Gate:** real moving game and post-match transition in Simulator, with visible field, HUD, ball, actors and a coherent replay. Record actual native engine and render backend identity in the running binary. Profile before broad UI migration if the engine is already too slow.

## Phase N4 — Integrate the Ballpad interface

Replace the old host dependency in the new default app target with the native bridge and Metal view. Reuse touch surface, controller UI, importer, settings and layout persistence selectively. Remove runtime coupling to guest addresses, guest-step budgeting, old QuickBoot and the image-view frame transport from the new path. An explicit legacy build target may remain for comparison; the default cannot silently fall back to it.

Implement pause with input release and audio coordination. Settings sheets must not race presentation. Keep touch controls usable in menus as needed, including Start and navigation; phase visibility changes must not strand the player. Support safe-area relayout and editable positions on both form factors without recreating the engine on ordinary SwiftUI updates.

**Gate:** fresh installed app imports through Files, boots, accepts real touch input and completes play on phone and iPad Simulators. Settings persist, layout reset works, resume is responsive, and there is no per-frame UIImage path.

## Phase N5 — Audio, saves, lifecycle and completeness

Finish THP playback and audio, failed import handling, staged reimport, card operations, settings and credits. Preserve old user saves through backup/explicit migration; verify the native card format and region naming rather than guessing. Pause/flush before import or replacement. Validate corrupted card/image failures against copies.

Exercise repeated menu entry, background/foreground, repeated match transitions, save then relaunch, and low-space/error paths with deterministic fixtures where possible. Device-only events are recorded separately. Diagnose missing features instead of hiding controls to pass tests.

**Gate:** all required Simulator functional rows in doc 34 pass, including actual movie playback and non-silent sustained audio with its limitations recorded.

## Phase N6 — Performance and rendering verification

Run phone and iPad sequentially in Release under the acceptance configuration. Measure full frame production and timing rather than only inner-loop execution. Separate startup, match and heavy-transition data. Compare against the desktop native baseline for visual correctness and game-clock speed. Use an equivalent Ballpad benchmark only if the baseline is readily reproducible; rebuilding the old project for days is not a dependency of this migration.

Profile the dominant measured cost. Inspect game task time, render submission, GPU work where measurable, shader/cache behavior, readbacks, audio refill, allocator growth and main-thread stalls. Change one causal issue at a time and rerun the affected scene. Preserve geometry, lighting, actors, replays and game speed. Never lower the pass threshold after seeing a failure.

**Gate:** doc 34 performance and endurance tests pass on the named host/Simulators, with transition and cold-cache results visible. If the Simulator host is limiting, document the trace and remain explicit about the unmet gate; do not turn this into a device-performance claim or silently accept degraded pacing.

## Phase N7 — Clean reproduction, notices and handoff

Export complete patches, finalize dependency pins/hashes and license inventory, and generate bundled notices. Rebuild from a fresh source checkout/output tree with declared caches only; bootstrap must fetch/apply the required changes without inheriting edited ignored trees. Re-run final targeted acceptance on the resulting app, and produce the unsigned device build.

Update root README and scripts README to the new architecture and verified commands. Remove stale “current” execution pointers. Retain old implementation history clearly labeled. Produce a final acceptance summary including exact paths to build artifacts, proof index, unresolved device items and public-distribution status. Use doc 35 for attribution text and asset checks.

**Gate:** all required N0–N7 rows pass with reproducible evidence; documentation matches the actual binary. Mark the implementation goal complete as “Simulator-verified development build; hardware validation pending” when that is the actual result. Do not call it device-certified, legally cleared, or release-ready.

## Required command surface

Implement these commands (names may change once, with an explicit mapping in doc 36); these are deliverables, not commands that already exist:

| Command | Responsibility |
|---|---|
| `scripts/native/bootstrap.sh` | Verify toolchain/pins, fetch source, apply patches, prepare platform dependencies |
| `scripts/native/build.sh --platform macos|simulator|device --configuration Release` | Reproducible app/engine builds; unsigned device mode |
| `scripts/native/test.sh --suite unit|smoke|acceptance --device <UDID>` | Bounded tests with meaningful exit code, machine-readable result and proof paths |
| `scripts/native/export-patches.sh` | Export intended dependency changes and verify clean reapplication |
| `scripts/native/verify-notices.sh` | Check tracked inventory and bundled notices against shipped dependencies |
| `scripts/native/verify-clean.sh` | Build from fresh source/output without borrowing edited ignored trees |

No script downloads a game, commits personal data, shuts down unrelated Simulators, or writes secrets into diagnostics. A skipped required test cannot produce an overall passing acceptance exit status.

## Goal-based execution policy

For each active phase: read relevant source → state invariant and measurable gate → reproduce current behavior → implement the smallest coherent change → run focused checks → inspect real runtime evidence → update doc 36 → advance. Keep one active phase while doing independent prerequisite work as useful. Commit coherent local milestones only, preserving unrelated user changes and upstream authorship.

After three attempts at the same failed hypothesis, change the hypothesis and obtain new evidence; do not repeat the same rebuild indefinitely. Stop only when there is a concrete dependency or decision that cannot be resolved with authorized work. Continue other independent phases where possible. Record the exact blocker and smallest required input. Follow the active goal tool's own rules for marking complete/blocked; a failed test alone does not authorize inventing completion or a blocked-tool state.

Persist across turns/compaction using doc 36. If a goal tool is available, create a goal for this explicitly requested implementation; do not set a token budget unless one is supplied. If an unrelated goal is active, do not overwrite it. A turn ending, a progress report, or an elapsed estimate is not completion. Do not create scheduled automations or external tasks to keep the loop running without a separate request.

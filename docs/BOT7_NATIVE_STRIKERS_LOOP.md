# Bot 7 — Native Strikers implementation goal loop

Copy the entire prompt below into a new task with access to the Ballpad workspace. The referenced documents are already written; proposed implementation scripts in those documents still need to be created. This prompt authorizes implementation when pasted. It does not claim that implementation has already occurred.

---

Implement this project from start to finish using a persistent goal-based loop.

Workspace: `<checkout>`.

Goal: replace Ballpad's old PowerPC static-recompilation engine with the native source port from `https://github.com/new-coke/strikers`, preserving and adapting Ballpad's useful iPhone/iPad interface. Deliver a reproducible, fully exercised Simulator development application, an unsigned iOS device build, and complete upstream attribution/provenance documentation. Complete the implementation and tests; do not stop at planning, a build, a first frame or a partial prototype.

Read these files completely, in order:

1. `<checkout>/docs/33-native-strikers-implementation.md`
2. `<checkout>/docs/34-native-strikers-acceptance.md`
3. `<checkout>/docs/35-native-strikers-attribution.md`
4. `<checkout>/docs/36-native-strikers-progress.md`
5. `<checkout>/docs/research/strikers-ios-feasibility.md`

These are the authoritative migration instructions. Older BOT2–BOT6 loops and docs 24–32 provide historical evidence only; their previous prohibition on a native source port and old approval phrases are superseded for this task. Inspect applicable repository instructions and current source before editing. Do not execute an old bot loop.

Start upstream at exactly `22649cb12c112454a34217429296c95bb181af8a` (v1.1.1). Keep its vendored Aurora changes. Use a local Git fork at ignored `work/native/strikers`, preserving upstream history, and track an immutable dependency manifest plus a reapplicable patch series in Ballpad. The runbook defines the layout and update policy. Do not rely on temporary research checkouts or leave required fixes only in ignored files.

The existing candidate game image is `.local-assets/Super Mario Strikers.iso`; verify it and protect it. Use copies of saves. Never download, bundle or commit game data. If unavailable, ask for the missing local image while continuing all independent build work.

Proceed autonomously through N0–N7:

N0: protect current changes, establish source/toolchain/asset identity and acquire the pinned local fork.
N1: reproduce the normal Aurora-enabled native macOS build and real gameplay reference; run upstream tests.
N2: build SDK-correct Simulator and device dependencies and the minimal iOS app, including the movie-decoder path.
N3: complete a real native-engine Simulator match and replay using correct frame/lifecycle integration.
N4: integrate Ballpad's touch controls, Files importer, settings and controller bridge with direct Metal presentation.
N5: complete audio/movies, saves, lifecycle, error handling, persistence and About/notices.
N6: satisfy the phone and iPad functional, visual, performance and endurance gates in doc 34.
N7: export patches, prove clean reproduction, build unsigned for device, finalize attribution and deliver an evidence-backed handoff.

For every gate, run this loop:

READ RELEVANT SOURCE → STATE THE INVARIANT AND PASS CRITERION → REPRODUCE → IMPLEMENT THE SMALLEST COHERENT FIX → BUILD/TEST → INSPECT REAL RUNTIME EVIDENCE → UPDATE DOC 36 → ADVANCE.

Use actual iPhone and iPad Simulators sequentially. Discover UDIDs and own your test devices; never shut down another task's Simulator. Drive actual app touch controls for UI acceptance and use source-state-driven automation for reliable scene navigation. Keep every wait/test bounded and report timeout as failure. No guest-block schedules, fake frames, suppressed geometry, skipped heavy scenes, accelerated game speed or disabled audio/movie features to manufacture success.

Use direct Metal presentation, not Ballpad's old per-frame CGImage/UIImage transport. Retain upstream game/task ordering, source ABI fixes, native MusyX and Aurora patches. Handle UIKit/SDL main-thread requirements, backgrounding, pause/input release, sandbox paths and dependency platform metadata explicitly. ARM64 macOS, Simulator and device archives are not interchangeable.

Reuse existing UI work rather than redesigning it. Initial supported data is the known USA raw disc revision. Additional regions, compressed formats, online multiplayer and new visual features must not delay the complete baseline. Preserve original saves and unrelated user modifications.

Attribution is required in README, ATTRIBUTION.md, offline About/Credits, bundled license texts and the dependency inventory. Follow doc 35's wording and audits. Credit new-coke/strikers, Yannick Suter and decomp contributors, Aurora and dependencies. Exclude game-derived app icons/embedded artwork from the application bundle. Do not claim that attribution or CC0 clears the reconstructed game or third-party rights.

This task authorizes local code changes, dependency acquisition, builds, Simulator tests and coherent local commits. It does not authorize public pushes/fork publication, binary distribution, TestFlight/App Store submission or messages to maintainers. Prepare the local result without waiting for those actions.

If a goal tool is available, create a goal for this objective without an invented token budget, and obey that tool's lifecycle rules. Keep durable progress in doc 36 so work survives turn boundaries and compaction. Do not overwrite an unrelated active goal. Without a goal tool, execute the same loop using the ledger.

After three failed attempts at one hypothesis, collect new evidence and change the hypothesis rather than repeating it. Continue independent work around a blocked dependency. Stop only at a genuine external/input blocker that cannot be resolved within this scope, recording the precise failed gate and smallest required input. Do not mark a goal complete while required acceptance tests remain failed or unrun.

Completion requires all N0–N7 local gates and doc 34's required rows to pass against the final clean build, including complete matches, replay, actual UI input, audio/movies, saves, lifecycle, performance/endurance, attribution and reproducibility. Missing physical hardware does not block this explicitly Simulator-scoped completion. Label the outcome “Simulator-verified development build; hardware validation pending.” Never claim device 60 fps, battery/thermal quality, physical controller behavior or legal/public-release readiness from Simulator results.

The final handoff must state what changed, exact build/run/test commands, app and unsigned-device artifact paths, evidence index, measured timing/audio/memory results, attribution locations and remaining physical-device/distribution checks. Begin N0 now and continue toward completion.

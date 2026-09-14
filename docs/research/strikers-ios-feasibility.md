# Strikers on iOS: feasibility assessment

**Recommendation: pursue a bounded physical-device prototype using new-coke/strikers as the engine foundation. Preserve Ballpad’s reusable iOS interface, but replace its recompiled execution and frame-presentation bridge.** This is a substantially more credible route than continuing to optimize the previous architecture. Sustained performance on iPhone and iPad remains an experiment, and public distribution has separate unresolved rights questions.

The assessment covers the source and public release state inspected on September 14, 2026. The upstream revision is `22649cb12c112454a34217429296c95bb181af8a`, associated with v1.1.1. Ballpad’s reviewed revision is `a87cb4696d26d2ad4a4e8f32667be9e02a7f65e1`. Both personal device builds and public distribution are considered. Estimates below are engineering judgments, not measured delivery commitments.

| Decision | Assessment | Confidence |
|---|---|---|
| Is this an actual native source port? | Yes: the build compiles reconstructed game and engine C/C++ directly. | High |
| Does it materially improve the starting point? | Yes: it already addresses host ABI, binary asset conversion, SDK compatibility, and native audio. | High |
| Is an iOS version technically plausible? | Strongly plausible; Apple ARM64 and underlying iOS graphics support already exist. | Medium-high |
| Is smooth sustained 60 fps demonstrated on iOS? | No. Neither this review nor the inspected upstream evidence establishes it. | High |
| Should development resume? | Yes, as a limited device experiment with an explicit stop rule. | Medium-high |
| Is attribution sufficient for a public release? | No: the port author does not grant rights to the reconstructed game material. | High |

## 1. What the project actually supplies

The author built a desktop port on Yannick Suter’s community decompilation. This distinction matters: the upstream contribution is the work of making reconstructed console code execute as an ordinary host application. The CMake project compiles 498 game/engine and 26 ODE translation units, plus platform, SDK math, and MusyX objects. It replaces the original allocator and uses Aurora to implement the graphics and other console SDK interfaces. This is considerably beyond a source dump or a partially completed decompilation.[1][2]

The host adaptation is visible in concrete files. `include/port/prelude.h` establishes a 64-bit, little-endian compilation contract, preserves signed characters and 16-bit wide characters, and supplies allocator/ABI compatibility. Platform files convert world, skin, camera, and model data. MusyX has a PC implementation, while `audio_out.cpp` feeds native mixed audio to SDL. These are exactly the categories of work that otherwise make a direct source port expensive.[3][4][5]

There is stronger delivery evidence than the repository landing page alone suggests. The v1.1.1 release was published on September 13 and contains macOS ARM64, Linux ARM64, Linux x86-64, and Windows x86-64 archives. The workflow at the reviewed commit completed successfully. That supports buildability on the configured desktop environments; it does not establish complete game correctness or mobile readiness.[6][7]

There is also an important documentation inconsistency: the README describes a source-only distribution policy, while GitHub Releases actually supplies binaries. The observed release artifacts are the current delivery evidence, but their existence does not resolve the README’s rights reservations. A fork should clarify its own policy rather than copying both statements.[1][6]

## 2. Why this changes Ballpad’s prospects

Ballpad already compiles PowerPC execution ahead of time; it does not depend on a runtime PowerPC JIT. Therefore, “no JIT” is not the new advantage. The advantage is eliminating the guest CPU state and execution machinery by compiling the reconstructed game logic itself for the host. Directly compiled functions also make ordinary profiling, fixes, and optimization easier to relate to gameplay.[2][8]

| Layer | Existing Ballpad | Proposed foundation |
|---|---|---|
| Game execution | DolRecomp-generated host code preserves guest execution semantics | Reconstructed C/C++ compiles directly for ARM64 |
| Integration | Guest addresses, HLE hooks, execution budgets, guest state | Native game/platform interfaces |
| Graphics | GXRuntime integration, with GXCore selected for corrected replay behavior | Upstream’s game-specific Aurora fork and Dawn/Metal |
| Presentation | EFB bytes become CGImage/UIImage in an image view | Preserve SDL Metal surface presentation |
| Audio | Guest audio production and host queue management | Native MusyX mixing into SDL streams |
| iOS experience | Existing touch, import, settings, controller and save UI | Adapt and reuse those components |

The checked-in `GameHostView.swift` creates a timer, takes an EFB frame lease, wraps the frame bytes in a `CGDataProvider`, creates a `CGImage`, and assigns a `UIImage` to a view. This introduces a CPU-visible frame representation and image presentation stage. It should not be carried over as the new port’s normal rendering surface. This is a structural opportunity to remove work; it is not a measured attribution of all previous slowdown to that code.[9]

Ballpad’s own repair history also limits the interpretation of its previous numbers. It documents dense scenes around 20 fps and replay states as low as roughly 9.6–29.3 fps, followed by corrected-build execution windows below 21 ms. Those measurements refer to different stages and conditions. A bounded guest step is not the same metric as complete presented-frame cadence. The historical evidence is primarily Simulator evidence, so it cannot establish a physical-device ceiling.[8]

The earlier decision to use the decomp only as a symbol contract was reasonable for the project then available. New-coke’s native adaptation changes the economics: adopting that work is now more attractive than repeating it or continuing to repair the old execution bridge. It does not imply the previous source-map work was wasted; the scene knowledge and regression cases remain valuable.

## 3. iOS support is partially present already

The bundled Aurora’s Dawn provider explicitly recognizes `ios-arm64`. Its pinned Dawn release, `v20260807.225922`, contains a `dawn-ios-arm64.tar.gz` artifact. Aurora’s core CMake configuration includes an iOS device implementation and CoreHaptics. Its Metal binding uses `SDL_Metal_CreateView` and passes the resulting Metal layer to Dawn. These concrete details make an iOS port much more plausible than inferring compatibility merely from the word “Metal.”[10][11][12]

SDL3 also documents iOS application setup and platform behavior. However, device and Simulator binaries must be treated separately: matching ARM64 CPU architecture does not make a macOS archive or an iPhone device archive compatible with the Simulator. The inspected Dawn filename alone does not establish all required SDK variants. A reproducible iOS dependency build or verified platform-specific packages remain part of the work.[13]

The Strikers application itself still has a desktop executable and desktop assumptions. Its root build applies a macOS Info.plist linker section under a broad `APPLE` condition, searches Homebrew FFmpeg locations, and does not provide a demonstrated iOS app target. The release matrix contains no iOS job. Therefore the correct description is “iOS-capable dependencies with an unported application,” not “ready to export to iOS.”[2][7]

## 4. The remaining engineering work

### Application entry and lifecycle

The game owns a continuous loop: poll events, begin the Aurora frame, sample input, run game tasks, update audio, draw overlays, and end the frame. That sequence needs an explicit relationship with the iOS application run loop. UIKit work must remain on the proper thread, and pause/resume needs to coordinate simulation, input, audio, and drawable availability.[14]

The first prototype should preserve as much of this tested sequence as possible, using SDL’s supported iOS entry setup. After proving gameplay, extract a narrow engine lifecycle interface for the Swift shell. Avoid introducing a new threading arrangement while simultaneously changing rendering, audio, and UI ownership. The inspected game event handler has no explicit complete background/foreground policy; this remains implementation and hardware validation work.

### Graphics and presentation

Keep the vendored Aurora version initially. The patch inventory includes game-specific matrix-memory, FIFO/display-list, and graphics-resource changes. Substituting another Aurora or Ballpad’s existing renderer during the first port would create an additional compatibility problem. Carry over a particular old fix only after demonstrating the same defect on the new engine.[15]

Use direct Metal presentation, initially at conservative internal resolution and 60 fps. Disable expensive optional antialiasing and filtering until a baseline exists. Phone display resolution should not automatically determine internal rendering resolution. Widescreen should use the upstream projection/aspect work rather than Ballpad’s image crop or stretch policies. The actual visual result still needs comparison in menus, gameplay, goals, and replays.

### Memory

`memalloc.cpp` reserves a 768 MiB virtual address region and states that memory is not returned to the OS. `vm.c` establishes a minimum 128 MiB window drawn from that region. `os.c` also supplies a 24 MiB MEM1 backing allocation and a lazily created 192 MiB arena. These are distinct mechanisms, and the 128 MiB window must not be double-counted as a separate region.[16][17]

Virtual reservation is not the same as resident or dirty memory. The source does not prove that the app consumes the sum of those sizes in physical RAM, nor that it will be terminated on an iPhone. It does prove that desktop assumptions deserve early measurement. Run repeated stadium loads, match exits, and replays while tracking footprint and allocation growth. Test the lowest intended device rather than selecting an arbitrary universal memory limit.

Aurora’s patch also changes uniform/storage pool sizing based on the author’s measured workloads. Those comments are useful context, but not a mobile memory budget. GPU allocations and retained caches need to be included in the hardware profile.[15]

### Audio and movies

Native MusyX is a major simplification, but `PortAudioUpdate` still runs inside the game frame loop and refills an SDL queue. Long frames can therefore affect audio servicing. Test actual audible output, interruption/resume, Bluetooth routing, and underruns through the expensive goal/replay transitions. Nonzero audio samples alone are insufficient.[5][14]

Movie playback optionally uses FFmpeg’s THP decoder. The included script creates a small static build, but it is a host build script, not a complete iOS cross-build recipe. A first match prototype may explicitly defer movies; that omission must not be confused with a complete port. FFmpeg configuration and distribution obligations must be tracked separately.[18][19]

### Touch, controllers, files and saves

Ballpad’s touch geometry, customizable layouts, settings menu, Files import experience, and controller/touch merge semantics are reusable. Their backend calls are not automatically reusable: `BallPadStatus` must feed the new engine’s input sampling, and lifecycle handling must clear held buttons. Choose one authoritative physical-controller input path so SDL and GameController do not deliver duplicate actions.[20]

Copy or import selected game data into managed sandbox storage, and configure explicit user/cache paths. The desktop release stores some files next to its executable, which is inappropriate for writable iOS state. Upstream supports more disc formats and regions than Ballpad; retain Ballpad’s narrow known-good USA image acceptance for the first experiment, then add upstream formats with focused tests. Memory-card UI can be reused after verifying the exact region, filename, and card-format expectations.[6][21]

The separate Qt settings executable should not be brought to iOS. Ballpad already has a suitable settings interface; connect it to the subset of engine options that matter on mobile.

## 5. Performance judgment and proof required

**A meaningful CPU improvement is a reasonable expectation. A guaranteed speedup or sustained 60 fps is not yet supported.** Direct game compilation removes a layer of guest execution work, and direct Metal presentation avoids the old image bridge. Neither change makes the game’s draw workload, shader compilation, memory traffic, or native audio costs disappear.

The project contains useful benchmark instrumentation: match gating, frame timing distributions, present timing, GPU timing when available, and CSV output. Its benchmark intentionally separates front-end/loading work from match samples. Use that infrastructure, but also retain a separate report covering cold startup and transitions so the difficult parts are not excluded from the success criteria.[22]

Recommended acceptance criteria, deliberately defined before optimization:

| Area | Prototype gate |
|---|---|
| Real hardware | One physical iPad and one physical iPhone; record exact SoC, OS and build |
| Baseline | Release build, conservative resolution, fixed 60 fps target, expensive extras off |
| Gameplay | Complete a match with touch or controller, correct clock speed, visible players/ball/HUD |
| Sustained pacing | At least 20 minutes; record presented frames, p50/p95/p99 intervals and missed refreshes |
| 60 fps objective | Steady-state frame delivery remains around the 16.7 ms refresh cadence; report repeated misses and worst cases explicitly |
| Heavy scenes | Goals, supershots, replays, stadium transitions and post-match screens |
| Audio | No repeatable audible breakup or runaway queue behavior during those scenes |
| Memory | No unexplained growth across repeated matches or pressure-related termination |
| Lifecycle | Background/foreground, lock/unlock, interruption and controller reconnect preserve a usable state |
| Correctness | Compare representative moving scenes against desktop upstream and the original game/reference |

A high-end iPad success is a first milestone, not proof of support for older phones. If 60 fps fails, reduce resolution once to distinguish likely GPU sensitivity from CPU or scheduling limits, then profile the dominant cost. Do not begin another open-ended series of speculative compatibility fixes.

## 6. Maturity and local checks

The September 13 commit fixes a truncated fragment-pool free-list pointer and an out-of-bounds dialogue-table loop. Those are significant examples of the remaining risk in moving 32-bit console assumptions into a 64-bit application. The issue tracker also contains an unresolved Linux controller report; it is not evidence of an iOS controller bug, but it reinforces that the project is early in broader testing.[23][24]

Local checks used an isolated checkout without changing upstream source. CMake configured with `STRIKERS_AURORA=OFF`, `STRIKERS_FFMPEG=OFF`, and Release, reporting the 498 game/engine and 26 ODE source counts. The `chunk_bounds`, `tool_genstubs`, and `tool_extract_disc` CTest tests all passed. These tests exercise a small set of parsers/tools; they do not validate gameplay.

The optional graphics-disabled `strikers_scan` compile failed under Apple Clang 21 / the local macOS 26.5 SDK. `AISandbox.cpp` reached conflicting legacy Metrowerks and libc++ declarations of `std::less`. This establishes a portability issue in that configuration, not failure of the upstream Aurora-enabled release path. The published successful workflow is separate evidence for that normal configuration. This review did not patch around the conflict or complete a local full graphical build.

No iOS executable was built, signed, run, or benchmarked for this assessment. No desktop gameplay session was measured locally. The recommendation is consequently based on direct source inspection, limited executable checks, upstream delivery evidence, and Ballpad’s existing records. It should be promoted to a performance claim only after the hardware gate passes.

## 7. Forking, attribution and distribution

The README offers the author’s original porting material under CC0 only to the extent of the rights they own. It separately reserves the rights status of reconstructed game code and middleware. Attribution is appropriate and worthwhile, but it cannot supply permissions the author does not hold. An accessible GitHub repository is not blanket clearance for a compiled game release.[1]

Preserve upstream history and notices, credit new-coke for the native port and Yannick Suter/contributors for the decompilation, and identify Aurora and its contributors. Aurora carries MIT terms; the ODE portions preserve BSD-style terms; MusyX carries its own notice. Inventory the actual distributed dependencies and FFmpeg build configuration rather than applying one label to the whole project.[19][25]

There is a specific asset issue to resolve: despite the broad no-assets statement, the source tree contains `assets/icon/MC_Icon.tpl`, derived-looking icon files, and code/comments identifying the executable icon as the game’s memory-card icon. A future public fork should inspect and remove or replace bundled game-derived artwork, including application branding, rather than blindly copying the tree. User-imported data and source provenance remain separate questions even after that cleanup.[2][26]

For a personal prototype, local device installation is the most direct technical route; it is not a general legal clearance. For a public source or IPA release, obtain a focused rights/provenance review before committing to distribution. For an App Store release, Apple’s intellectual-property requirements and the reconstructed code make approval an unreliable planning assumption. The emulator provisions do not automatically authorize a native game port. TestFlight also requires compliance with review guidelines.[27]

This is a practical release-risk assessment, not a jurisdiction-specific legal opinion. The engineering experiment can answer whether it works; it cannot answer whether all necessary distribution rights exist.

## 8. Proposed investment and migration plan

Use a separate development fork or checkout pinned to the reviewed commit, preserving Ballpad as a reference. First prove upstream desktop behavior with the same local game data. Then build the smallest iOS application that can reach a full match through SDL and Metal. Integrate Ballpad’s Swift interface after that engine milestone, with a narrow bridge for start, pause/resume, input, paths, settings and status.

| Stage | Estimated focused engineering effort | Deliverable |
|---|---|---|
| Desktop baseline and dependency audit | 1–3 days | Reproducible build and matched gameplay capture |
| iOS device engine prototype | 4–10 days | Signed build, direct Metal output and one complete match |
| Ballpad UI and lifecycle integration | 5–10 days | Touch, import, settings, controller and saves on both form factors |
| Device performance and reliability work | 5–15 days | Sustained profile, heavy-scene fixes and regression evidence |

These sum to roughly 3–8 engineer-weeks for a useful private beta if the platform dependencies cooperate. They exclude rights clearance, App Store review, online multiplayer, and an extensive old-device support matrix. Unexpected compiler, GPU compatibility, or gameplay defects can extend the range. The first decision checkpoint should be after approximately 5–10 engineering days of the device experiment, not after the whole beta budget.

Continue if the new port reaches a correct physical-device match and shows convincing pacing at modest settings. Reassess if the renderer requires a large new compatibility layer, if recurring native memory corruption prevents full matches, or if modest-resolution hardware profiling shows an expensive architectural bottleneck. Record the limiting subsystem and a bounded next experiment before extending the timebox.

**The project warrants another attempt because someone has now completed much of the native adaptation that Ballpad lacked. The sensible commitment is to prove that advantage on hardware, then build the iOS product around it.**

## Sources and evidence

All web sources were accessed September 14, 2026. Source links use the reviewed immutable commit where practical. Public statements are author claims unless explicitly identified as a local observation or engineering judgment.

1. new-coke, [Strikers README and licensing statement](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/README.md).
2. new-coke, [Root CMake build](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/CMakeLists.txt).
3. new-coke, [Port compilation/ABI prelude](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/include/port/prelude.h).
4. new-coke, [Platform adaptations and asset converters](https://github.com/new-coke/strikers/tree/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/src/platform).
5. new-coke, [Native audio output](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/src/platform/audio_out.cpp).
6. new-coke, [v1.1.1 release](https://github.com/new-coke/strikers/releases/tag/v1.1.1), September 13, 2026. Asset inventory also checked through GitHub’s releases API.
7. new-coke, [Successful desktop workflow](https://github.com/new-coke/strikers/actions/runs/34781531765) and reviewed `.github/workflows` matrix.
8. Ballpad, [technical audit](../24-technical-audit-2026-08-19.md), [decomp integration decision](../28-decomp-integration-plan-2026-08-19.md), and [repair evidence](../32-deep-repair-loop-2026-08-20.md), local records from August 2026.
9. Ballpad, [GameHostView.swift](../../app/Ballpad/GameHostView.swift), local source at the reviewed Ballpad revision.
10. Aurora, [Dawn dependency provider](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/extern/aurora/cmake/AuroraDawnProvider.cmake).
11. encounter/dawn, [Pinned Dawn release](https://github.com/encounter/dawn/releases/tag/v20260807.225922); iOS artifact inventory verified through GitHub’s release API.
12. Aurora, [Core platform configuration](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/extern/aurora/cmake/aurora_core.cmake) and [Metal surface binding](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/extern/aurora/lib/dawn/MetalBinding.mm).
13. SDL, [SDL3 iOS documentation](https://wiki.libsdl.org/SDL3/README-ios).
14. new-coke, [Game entry and frame loop](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/src/Game/main.cpp).
15. new-coke, [Aurora local changes](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/tools/aurora-local-changes.patch).
16. new-coke, [Native allocator](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/src/platform/memalloc.cpp).
17. new-coke, [VM window](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/src/platform/vm.c) and [OS allocation shims](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/src/platform/os.c).
18. new-coke, [FFmpeg build script](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/tools/build-ffmpeg.sh).
19. FFmpeg, [License and legal considerations](https://ffmpeg.org/legal.html).
20. Ballpad, [Pad interface](../../host/include/ballpad_pad.h), [ControllerManager](../../app/Ballpad/ControllerManager.swift), and [touch surface](../../app/Ballpad/Touch/TouchControlSurface.swift), local source.
21. new-coke, [Launch configuration and user/cache paths](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/src/platform/launch.cpp).
22. new-coke, [Benchmark implementation](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/src/platform/benchmark.c).
23. new-coke, [64-bit crash fixes](https://github.com/new-coke/strikers/commit/22649cb12c112454a34217429296c95bb181af8a), September 13, 2026.
24. new-coke, [Linux controller issue #4](https://github.com/new-coke/strikers/issues/4), open at inspection.
25. Vendored [Aurora MIT notice](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/extern/aurora/LICENSE), [ODE BSD notice](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/LICENSE-BSD.TXT), and [MusyX notice](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/extern/musyx/LICENSE).
26. new-coke, [Bundled icon directory](https://github.com/new-coke/strikers/tree/22649cb12c112454a34217429296c95bb181af8a/smstrikers-port/assets/icon).
27. Apple, [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), especially 2.2, 2.5.2, 4.7 and 5.2.

Local validation evidence: isolated source checkout `/tmp/ballpad-strikers-research`; configuration log `/tmp/ballpad-strikers-configure.log`; optional scan output `/tmp/ballpad-strikers-build.log`; test build output `/tmp/ballpad-strikers-tests-build.log`; CTest results `/tmp/ballpad-strikers-scan/Testing/Temporary/LastTest.log`. Temporary paths are reproducibility notes and may not persist. No upstream code was modified and no public fork or release was created.

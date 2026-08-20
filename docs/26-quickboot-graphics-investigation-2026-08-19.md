# 26 — QuickBoot graphics investigation and decision plan (2026-08-19)

> **Execution status:** retained as technical evidence. The current work order
> is [doc 28](28-decomp-integration-plan-2026-08-19.md), which uses the complete
> decomp source to trace and improve the existing runtime. QuickBoot remains
> behind fresh moving-renderer parity and is not the next agent's starting
> package.

## Scope and recommendation

This report answers the questions in the investigation brief. It does not
change runtime behavior, enable QuickBoot, or claim release readiness.

**Recommendation: ship and validate the correctness-first fresh Aurora path;
keep QuickBoot diagnostic-only for this release cycle.** QuickBoot is probably
technically completable without serializing WGPU objects, but the current v5
snapshot is not a correctness-preserving process restart. Completing it is a
separate, medium-to-large renderer-state project, not a release blocker.

The owner decision is therefore whether to accept the longer fresh start for
this release or explicitly fund a time-boxed portable replay experiment. Do not
enable QuickBoot merely because that experiment makes one still frame plausible.

## 1. Bottom-line feasibility

### Finding

| Question | Answer | Confidence | Basis |
|---|---|---:|---|
| Is there a fundamental iPhone/iPad incompatibility? | No evidence of one. | High | Fresh live Aurora has produced coherent moving matches on both Simulator form factors. macOS success supports portability. Physical-device behavior remains unmeasured. |
| Is QuickBoot currently correct? | No. | High | A current same-build restore either aborts on missing vertex decode state or, with the dirty probe, reaches a visibly malformed match. |
| Can QuickBoot probably be completed portably? | Yes, in principle. | Medium | The shadow frontend already has portable CP/BP/XF/matrix/copy state, and the HLE layer already has guest-addressed texture/TLUT/array identities. What is missing is ordered application of that semantic state to live Aurora. |
| Is QuickBoot a release blocker? | No. | High | It is an opt-in startup optimization; the default fresh path remains available and is the only accepted product path. |
| Should it be funded now? | Not by default. | Medium-high | Correct rehydration has broad state surface and a demanding parity proof. Fresh moving-Dolphin parity and physical-device validation reduce more product risk. |

### Option comparison

| Option | Correctness risk | Implementation size | Maintenance cost | Startup benefit | Testability | Disposition |
|---|---|---|---|---|---|---|
| Serialize/rehydrate every live `GXState` field | High: easy to restore stale pointers, caches, or lifecycle state | Large | High; tied to Aurora internals | High if correct | Medium; enormous state surface | Reject as the first approach |
| Capture portable frontend state and emit a canonical restore stream into live Aurora | Medium | Medium–large | Medium; register semantics are stable and native resources remain rebuilt | High if correct | High; state/event hashes expose first divergence | Credible funded experiment |
| Replay an arbitrary FIFO history from boot | High: size, boundary, and resource-lifetime coupling | Large/unbounded | High | Uncertain | Medium | Reject unless a short scene-boundary prefix is first proven sufficient |
| Keep QuickBoot diagnostic-only; optimize and test fresh startup | Lowest | Small–medium | Low | Lower than a savestate | High | **Primary recommendation** |

The semantic-replay option is credible because `DolGxRecompState` already
stores VCD/VAT, CP arrays, BP registers, XF matrices/registers, projection,
viewport, lights, channels, copy scalars, and pending FIFO bytes
([save](../ref/GXRuntime/src/gx_recomp.c#L1454),
[restore](../ref/GXRuntime/src/gx_recomp.c#L1533)). The HLE v5 table supplies
the pointer-bearing resources that portable frontend state deliberately cannot
own. It is not yet a solution: the shadow frontend is off in the live product
configuration and no code currently turns its restored state into a canonical
command stream for the live Aurora consumer.

## 2. Evidence map

### State ownership and restart status

| State class | Current owner | Snapshot treatment | Restart finding |
|---|---|---|---|
| CPU registers, MEM1, ARAM, interrupt/MMIO, audio | Ballpad host/runtime | v5 serializes these | Necessary and substantially present, but not sufficient for graphics |
| Texture/TLUT identities and indexed-array guest addresses/strides | Strikers HLE tables | v5 serializes 8 texture slots, 20 TLUT slots, 32 array bindings ([layout](../ref/StrikersRecomp/runtime/host/hle.c#L1272), [restore](../ref/StrikersRecomp/runtime/host/hle.c#L2820)) | Re-resolved from restored guest RAM; native objects are correctly rebuilt rather than serialized |
| CP VCD/VAT/array state | Raw GX FIFO; optional `DolGxRecompState` shadow | Product snapshot size is zero because shadow is disabled ([backend](../ref/GXRuntime/backends/aurora/aurora_backend.cpp#L1247)) | Missing at process restart. Without the dirty probe, current restore dies on vertex attribute 9 before presentation |
| BP/XF/TEV, matrices, lights, projection, viewport, scissor | Live `aurora::gx::g_gxState`; partially mirrored by optional frontend | No product blob | New process starts with Aurora defaults while guest resumes a delta stream |
| Bound and loaded textures/TLUTs | HLE metadata plus live `GXState` | Guest-addressed metadata only | Metadata can rebuild resources, but it does not restore all scalar binding/use state |
| EFB-copy destination and copy scalar history | FIFO/frontend and live Aurora | Frontend has portable scalars; live copy resources are not saved | Native copy textures must be regenerated; four historical entries are still absent at steady QuickBoot |
| Native texture handles and copy caches | Aurora/WebGPU | Deliberately unsaved | Correct. `GXState` keys caches by native destination plus dimensions/format and stores native handles/revisions ([state](../ref/GXRuntime/graphics/aurora/lib/gx/gx.hpp#L286)); these must never cross a process restart |
| Render-pass/frame lifecycle and pending metadata | Aurora backend globals | Unsaved | Must begin from a clean boundary, then receive canonical state/resources in the correct order |
| Backend cull-all interception state | Function-local live Aurora statics | Unsaved | Last BP opcode, z mode, color mode, and cull-all status affect rewriting ([backend](../ref/GXRuntime/backends/aurora/aurora_backend.cpp#L1708)); canonical replay must reset or establish them |

The complete live Aurora state is much larger than the current aggregate
diagnostics imply. It includes matrices, projection/fog, blend/depth/alpha,
TEV and channel/light state, textures/TLUTs, VCD/VAT and arrays,
viewport/scissor, copy state/cache, BP/XF caches, and lifecycle flags
([`GXState`](../ref/GXRuntime/graphics/aurora/lib/gx/gx.hpp#L286)). A count such
as `loadedTex=7` cannot say which slot is absent, whether the relevant TEV stage
uses it, or whether its producer copy ever ran.

### Current same-build phase inventory

A new v5 snapshot was captured and restored with the exact current build on the
iPad A16 Simulator. Values below are aggregate diagnostics; “identity known”
means the class/ownership is known, not that the current logger exposes the
specific texture or copy destination.

| Phase | bound textures | loaded textures | TLUTs | arrays | copy textures | pending tex/TLUT | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| Safe-point save | 4 | 8 | 1 | 16 | 26 | 0 / 0 | Stable OS-idle capture; frontend and GXCore blobs both zero |
| Restore-runtime, no dirty probe | 0 | 0 | 0 | 0 | 0 | 8 / 1 | HLE resources queued before compatible scalar decode state |
| First draw, no dirty probe | — | — | — | — | — | — | Fatal `unmapped vtx attr 9`, before a useful presented match |
| Restore-runtime, dirty probe | 0 | 0 | 0 | 0 | 0 | 8 / 1 | Same starting boundary |
| First restore step, dirty probe | 0 | 8 | 1 | 16 | 8 | 0 / 0 | Partial SDK dirty emission makes vertex decoding viable |
| After the one match-start input | 4 | 7 | 1 | 16 | 22 | 0 / 0 | Match runs, but geometry is flattened/scrambled and HUD is absent |
| Steady restored match | 4 | 7 | 1 | 16 | 22 | 0 / 0 | Counts plateau; visible corruption remains |
| Equivalent accepted fresh match | 4 | 8 | 1 | 16 | 26 | 0 / 0 | Coherent geometry/HUD in current candidate captures |

Sanitized excerpts from that run preserve the discriminating observations
without container paths, guest addresses, or game data:

```text
[quickboot-hle] saved textures=8 tluts=1 arrays=16 bytes=1264
[quickboot-gx] phase=restore-runtime ... loadedTex=0 arrays=0 copyTex=0 pendingTex=8 pendingTlut=1
[aurora:fatal:aurora::gfx::gx] unmapped vtx attr 9
[quickboot-gx] phase=post-input ... boundTex=4 loadedTex=7 tluts=1 arrays=16 copyTex=22
[quickboot-gx] phase=steady ... boundTex=4 loadedTex=7 tluts=1 arrays=16 copyTex=22
```

The restored screenshot is retained only as ignored local evidence at
`work/validation/ipad-quickboot-current-dirty-steady-2026-08-19.png`. It is not
an acceptance artifact and contains no basis for weakening the gate.

What the inventory proves:

1. The first failure is **before native presentation**. Missing CP/VAT/VCD and
   related scalar ordering can make the restored resource bindings unusable.
2. Setting guest `dirtyState=0x1f` is necessary for the current restore order,
   but insufficient for parity. The SDK helper emits only SU texture registers,
   BP mask, general mode, VCD, and VAT
   ([`__GXSetDirtyState`](../ref/smstrikers-decomp/src/Dolphin/gx/GXGeometry.c#L7));
   it does not reconstruct the full BP/TEV/XF/matrix/light/copy state.
3. The steady mismatch is specifically one loaded texture and four copy-cache
   entries, but the current logger cannot identify them. It would be dishonest
   to label them as “the HUD texture” from counts alone. An identity manifest is
   the next bounded diagnostic, and only its producer/consumer linkage can prove
   necessity.
4. The frontend QuickBoot unit regression covers consumer CP bindings and
   cull-all restoration ([test](../ref/GXRuntime/graphics/frontend/tests/frontend_replay_test.cpp#L597));
   it is not an end-to-end live-Aurora state restore.

### Restore-contract defect found during the diagnostic

An older v5 snapshot had a different HLE blob size. The CPU/RAM half accepted
and applied it, set `g_quickbooted`, and the runtime half subsequently rejected
it. The host logged the failure but continued as “booted from quickboot.” This
follows directly from the split restore: `quickboot_restore_cpu` mutates memory
and sets the flag ([host](../host/src/ballpad_ios_host.cpp#L496)), while the
runtime failure is non-fatal ([host](../host/src/ballpad_ios_host.cpp#L782)).

This is an independent correctness defect. Before any product consideration,
the whole file must be preflighted—header, all section sizes, exact file length,
and preferably payload checksum—before CPU/RAM is mutated. A failed restore
must atomically fall back to fresh boot.

There is also harmless but misleading public-contract drift: the header still
says restore is automatic when the file exists
([header](../host/include/ballpad_ios_host.h#L103)), while the implementation
requires `BALLPAD_ENABLE_QUICKBOOT=1` and otherwise logs a default bypass
([host](../host/src/ballpad_ios_host.cpp#L750)). Correct that comment in QB-0;
do not change the safe implementation to match the stale comment.

### Accepted/rejected evidence timeline

| Evidence | Status | Consequence |
|---|---|---|
| Native EFB already contained the earlier fresh corruption | Accepted | UIKit/SwiftUI presentation is not the renderer cause |
| GPU fence, EFB-copy substitution, direct/inline upload, bind-cache bypass | Rejected as fixes | Do not repeat for QuickBoot |
| Extra `PNMTXIDX` divide-by-three | Rejected and reverted | It worsened geometry |
| Static texture source-identity validation | Accepted fresh-path fix | Fresh iPhone/iPad candidates no longer show the tiled health texture |
| CPU/RAM-only QuickBoot | Rejected | Guest resumes delta GX state into an empty renderer |
| v5 HLE texture/TLUT/array rebind | Retained as diagnostic, incomplete | Resource counts improve; parity does not |
| Current no-dirty restore | New rejected configuration | Fatal vertex-attribute mapping before useful presentation |
| Current dirty-state restore | New discriminating result | Avoids fatal, but malformed geometry/missing HUD remain |
| Static Dolphin health-screen comparison | Accepted but narrow | Does not prove a moving match |
| Moving same-plane Dolphin comparison | Not yet available | Required before renderer or QuickBoot parity claims |

### Bounded checks run for this report

| Check | Result |
|---|---|
| `./scripts/check_ref_patches.sh` | Pass |
| `aurora_recomp_frontend_tests` | Pass |
| No-GPU CTest lane | 5/6 pass; `gxpo_productization` fails because configured Python 3.8 lacks `pytest` |
| `gx_fifo_tests` in the correct Aurora-enabled build | Reproduced link failure: missing bounding-box/EFB-readback stubs and the new filtered `resolve_pass` overload |
| Same-build QuickBoot A/B on iPad Simulator | No-dirty fatal; dirty probe reaches a visibly corrupt steady match |

## 3. Ranked root-cause hypotheses

No more than these three should be pursued until one discriminates.

### 1. Missing ordered CP/BP/XF semantic state — high confidence

**Mechanism.** The restored guest assumes its previously emitted GX state still
exists and emits deltas. Live Aurora starts from defaults. HLE reissues arrays
and resources before a VCD/VAT-compatible decoding context, producing the
current `unmapped vtx attr 9` fatal. The five-group SDK dirty emission repairs
enough CP state to run, but leaves matrices, lights, broad BP/TEV/XF state, and
copy history incomplete, so skinned players remain malformed and the HUD is
missing.

**Single best experiment.** With QuickBoot still opt-in, enable the shadow
frontend only for capture, save its existing portable state, and synthesize one
canonical CP/BP/XF restore stream into a freshly initialized live Aurora
consumer **before** reissuing HLE resources. Compare per-draw semantic state and
native EFB hashes against the fresh transition. Success means the first
post-restore draw has the same VCD/VAT, matrix, projection, channel/light, TEV,
and BP digest and the geometry/HUD defect disappears without native handles.

### 2. Missing EFB-copy producer history/identity — medium confidence

**Mechanism.** Fresh has 26 copy textures; dirty QuickBoot reconstructs eight
early and plateaus at 22. A missing copied surface can explain an absent HUD or
secondary texture. Native copy-cache entries cannot be serialized and a guest
address alone is not a sufficient identity, as the Aurora key also includes
dimensions and format. This is less likely to explain all player deformation,
which persists even after arrays are present.

**Single best experiment.** Emit an off-default manifest keyed by guest
physical destination, dimensions, format, revision, producing copy command, and
first consuming draw. Diff fresh versus restored at the named scene, then replay
only the missing portable copy producers. If the HUD appears while the player
geometry stays malformed, the hypothesis is isolated rather than conflated with
hypothesis 1.

### 3. Restore-boundary lifecycle or first-command ordering — medium-low confidence

**Mechanism.** The safe point avoids a truncated FIFO command, but live backend
state also includes pending resource metadata, frame/pass ownership, draw
pending flags, last opcode, and cull-all rewrite state. A syntactically clean
snapshot can still resume on the wrong semantic side of a draw or pass boundary.

**Single best experiment.** Record the first N portable CP/BP/XF/resource/draw
events and a per-draw semantic hash from (a) the fresh safe-point-to-match
transition and (b) restore-to-match. Stop at the first divergent event. If full
canonical state agrees before the first draw but lifecycle/event order differs,
move the capture boundary or inject one explicit clean-frame transition rather
than adding more serialized fields.

## 4. Recommended path

### Primary: defer product QuickBoot and close the fresh-path proof

This is the release path. Each commit must stay reviewable and must not contain
game data.

1. **Smoke-harness reliability (small).** Pin the Python interpreter used by
   CMake to one with `pytest`; add explicit UI-test teardown; give every
   `xcodebuild` invocation a unique result bundle and verify it with
   `xcresulttool`. Gate: the fast lane exits cleanly twice on each Simulator.
2. **Named moving scene and deterministic input (medium).** Define one kickoff
   scene and a guest-frame/VI-relative 10–15 second controller script. Do not
   drive it by wall time or Simulator pixels. Gate: repeated fresh runs have the
   same input/config/trace hashes and stable frame count.
3. **Same-plane live-Aurora parity lane (medium–large infrastructure).** Capture
   native EFB, use a pinned Dolphin Software oracle, and compare against
   `dolgx_replay --pixels`—the product live-Aurora path, not `--core`. Gate:
   first-red G0–G5 certificate for the static and moving windows on a common
   640×528 EFB plane.
4. **Fresh iPhone/iPad acceptance (existing long lane).** Run touch-only entry
   plus sustained live play on one Simulator at a time, with explicit results.
   Gate: both form factors pass and derived visual artifacts match the named
   scene contract.
5. **Physical-device follow-up.** When supported devices are attached, measure
   controller delivery, audio interruption/recovery, background/foreground,
   thermal/performance, and at least 15 minutes of play. This is a dependency,
   not a code repair available today.

Risk is low to medium because this path preserves the working renderer. Stop
and investigate fresh rendering only on a reproducible moving-gate divergence;
do not reopen rejected screenshot-driven experiments.

### Fallback: time-box a portable QuickBoot replay proof

Use this only if the owner explicitly funds fast start after the fresh gate is
sound.

1. **Commit QB-0 — atomic snapshot contract (small).** Preflight the complete
   snapshot before mutation; add exact-length/checksum validation; set
   `g_quickbooted` only after every runtime section restores; fall back fresh on
   any error. Gate: truncation, stale HLE size, checksum error, and missing file
   all produce a clean fresh boot.
2. **Commit QB-1 — portable identity/state manifests (small).** Add off-default,
   redacted manifests for texture/TLUT/array identities, CP/BP/XF validity,
   matrix/channel/light coverage, copy producer/consumer identities, and first
   draw ordering. Gate: two equivalent fresh runs produce the same semantic
   manifest independent of native pointer values.
3. **Commit QB-2 — canonical live-Aurora restore stream (medium–large).** Save
   the existing `DolGxRecompState` shadow only for diagnostic QuickBoot. On
   restore, reset live Aurora at a clean frame boundary and emit canonical CP,
   BP, and XF state; then resolve and reissue HLE arrays/TLUTs/textures. Start
   native copy caches empty and regenerate only proven copy producers. Gate:
   current no-dirty fatal disappears without `BALLPAD_QUICKBOOT_FORCE_GX_DIRTY`,
   and the first-draw semantic digest matches fresh.
4. **Commit QB-3 — parity and endurance (test-only/product flag unchanged).**
   Run bad-snapshot fallback, named static scene, moving Dolphin same-plane gate,
   fresh-vs-QuickBoot native EFB gate, and long touch acceptance on phone and
   iPad Simulator. Gate: all pass before discussing default behavior.

**Stop conditions:** stop the funded experiment and leave QuickBoot diagnostic
if (a) canonical state cannot remove both geometry and HUD defects, (b) success
requires serializing WGPU/native handles, (c) a bounded scene-boundary replay is
insufficient and full boot FIFO history is required, or (d) repeated restores
are not deterministic. Do not grow QB-2 into an unbounded renderer rewrite.

## 5. Deterministic visual correctness gate

### Scene contract

Use a named “kickoff countdown 1” scene with fixed teams, stadium, card/config,
renderer, EFB scale 1, and neutral initial input. The moving window begins at a
guest-frame/VI marker, lasts 10–15 seconds, and uses a versioned controller
script keyed to guest frames. Record the executable/patch hashes, image hash
locally, scene ID, input-script hash, EFB dimensions/format, start/end markers,
and renderer mode.

Wall-clock timing and XCUITest taps are unsuitable for parity: Simulator
throughput varies by form factor. The runtime already supports frame-indexed
input events based on guest timebase
([HLE input script](../ref/StrikersRecomp/runtime/host/hle.c#L171)).

### Two joined comparisons

1. **Renderer same-input comparison.** Capture the scene FIFO from the same
   image into a local ignored trace. Convert it to `.dolt`. Run the pinned
   Dolphin Software oracle and `dolgx_replay --pixels` on that same input.
   Require G0 configuration and G1 input/trace identity before evaluating state,
   vertex, EFB, or copy bytes. `--pixels` selects live Aurora; `--core` selects
   the experimental GXCore path and cannot support a product-renderer claim
   ([CLI](../ref/GXRuntime/graphics/frontend/tools/dolgx_replay.cpp#L250)).
2. **Full-app integration comparison.** Ballpad fresh iPhone/iPad runs emit a
   native 640×528 BGRA EFB sequence and the corresponding `.dolt` window. Replay
   that trace through `--pixels`; after a declared warm-up boundary, require app
   EFB hashes to equal replay EFB hashes. This separates host integration and
   presentation from renderer semantics.

The existing gxpo G0–G5 certificate model—config, input, state, vertex, EFB,
copy bytes—is reusable, including first-red/`INVALID` semantics
([gxpo](../ref/GXRuntime/docs/gxpo.md#L7)). Its existing implementation targets
GXCore and a pinned Dolphin fork that is not present locally, so it cannot be
claimed as today’s live-Aurora gate. The new lane must adapt the model to
`--pixels` and provision the pinned same-plane Dolphin Software oracle.

Do not import the quarantined `pixel_diff.py`, `graphics_lockstep.sh`, or
`dolphin_efb_golden.sh` presenter-plane recipes as product gates
([quarantine](../ref/GXRuntime/docs/gxpo.md#L29)).

### Safe artifacts and orientation

Commit or retain only derived, non-game artifacts:

- scene/config/input manifests and hashes;
- command/state/vertex/frame hashes and parity certificates;
- redacted logs and first-divergence metadata;
- low-resolution contact sheets and diff heatmaps when legally appropriate.

Keep disc images, saves, raw DFF/DOLT traces, raw EFB sequences, and extracted
assets ignored and local. A `simctl` screenshot is only a UI/layout artifact.
Store screen pixel dimensions, interface orientation, and game-content
orientation separately; never rotate game content merely because the Simulator
container PNG is portrait. Native EFB is the renderer comparison plane.

## 6. Test infrastructure and verification matrix

### Smallest infrastructure repair

**Fast smoke lane, one Simulator at a time:**

1. `scripts/check_ref_patches.sh` and sensitive-file/git checks.
2. Native pad/runtime tests and `aurora_recomp_frontend_tests`.
3. Configure CMake with an explicit Python containing `pytest`, then run the
   no-GPU frontend/gxpo tests.
4. Build the Xcode project.
5. Run short `PadDiagnosticTests`, `LifecycleTests`, and controller-handoff
   classes with `-test-timeouts-enabled YES`, a 120–180 second per-test
   allowance, and a unique `-resultBundlePath`.
6. Require `xcresulttool get test-results summary --path ...` to report pass;
   terminate the app in `tearDownWithError` even on assertion failure.

**Long acceptance lane:** run only
`TouchMatchTests.testStartMatchWithTouchOnly` serially, first phone then iPad,
with a 900-second per-test ceiling and a bounded outer watchdog. The test has
real guest-block anchors and at least a minute of live input
([test](../app/BallpadUITests/TouchMatchTests.swift#L17)), but currently lacks
explicit teardown. Preserve start/static/end attachments and require a valid
passing `.xcresult`, not a log line reached before a stuck process.

**`gx_fifo_tests` classification: parallel hygiene.** The link failure is not a
prerequisite for deciding QuickBoot, running portable frontend replay, or
building the product. It becomes a prerequisite before the legacy Aurora
GX/FIFO encoder suite can be used as a gate. The smallest repair is to extend
the existing no-GPU stubs with bounding-box, EFB-readback, and the new
`resolve_pass(..., EfbCopyFilterParams const*)` overload
([stubs](../ref/GXRuntime/graphics/aurora/tests/gx_test_stubs.cpp#L1)); do not
pull the full renderer/GPU implementation into this unit target.

### Verification matrix

| Lane | Fresh iPhone Sim | Fresh iPad Sim | QuickBoot iPhone/iPad | Dolphin | Physical devices | Acceptance |
|---|---|---|---|---|---|---|
| Build/patch/native smoke | Required | Required | Flag remains off | N/A | Later | Clean exit + passing recorded result |
| Short UI/lifecycle smoke | Required | Required | Bad-snapshot fallback only after QB-0 | N/A | Later | Explicit `.xcresult`, no harness hang |
| Named static scene | Current candidate exists; rerun under contract | Current candidate exists; rerun under contract | Only after QB-2 | Same-plane static oracle | Later | Config/input/state hashes valid; EFB gate passes |
| 10–15 s moving scene | Required/open | Required/open | Only after fresh passes and QB-2 | Pinned Software oracle required/open | Later | G0–G5 first-red certificate passes |
| Long touch acceptance | Previously passed; must rerun with reliable harness | Previously passed; must rerun with reliable harness | Required only before any enablement | N/A | 15+ minute device extension | Guest progresses, remains in live match, clean exit |
| Device-specific behavior | Simulator evidence only | Simulator evidence only | Remains off | N/A | iPhone + iPad required when attached | Audio interruption, controller, lifecycle, thermal/perf pass |

No row currently establishes release readiness. The moving Dolphin rows and all
physical-device rows are open.

## 7. What not to do next

- Do not enable QuickBoot for ordinary users or call the dirty-probe image a
  fix.
- Do not serialize `GXState` wholesale, native texture handles, WebGPU objects,
  command encoders, or process-local pointers.
- Do not repeat presentation/UIKit, GPU-fence, EFB-copy substitution,
  bind-cache, direct-upload, worker-order, or extra `PNMTXIDX` divide probes.
- Do not add another counts-only HLE rebind. Add identities and
  producer/consumer linkage or no diagnostic at all.
- Do not capture mid-render or mid-match; both boundaries are already known to
  violate the delta-state assumption.
- Do not treat a single screenshot, aggregate resource counts, static boot
  frame, or macOS success as moving iPhone/iPad parity.
- Do not switch product validation to `DOL_GX_CORE=1`; its iOS path remains
  experimental and previously produced a white EFB.
- Do not use quarantined presenter-plane pixel scripts as an acceptance gate.
- Do not mix touch/layout, widescreen, performance polish, or unrelated UI work
  into renderer-state commits.
- Do not report missing attached physical devices as a code defect.

## 8. Decision request

The repository owner should choose one of these explicit dispositions:

1. **Recommended:** accept the longer fresh boot for this release cycle, keep
   QuickBoot diagnostic-only, and fund the moving-Dolphin/fresh-device proof.
2. **Optional funded fallback:** authorize the bounded QB-0 through QB-3 replay
   experiment with the stop conditions above. Even if successful, default
   enablement remains a later decision after both Simulator form factors pass
   moving parity and long acceptance.

Absent an explicit decision, use disposition 1. It preserves the only accepted
renderer path and does not turn a startup optimization into unbounded release
risk.

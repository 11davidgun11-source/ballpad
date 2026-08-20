# Ballpad deep repair loop — 2026-08-20 continuation

This loop is intentionally stricter than the previous audit. A fresh run must
be inspected in both raw Simulator orientation and a human-readable rotated
orientation, and it must distinguish boot/loading, menu, selection, cutscene,
and live-match scenes. A frame that merely presents pixels is not accepted as
healthy gameplay.

## Follow-up loop: replay sky submission and orientation separation

The first packet diagnosis used a regex that treated `[gl-attach]` as a
character class, and the follow-up GX probe inferred view from a stale guest
global. Both conclusions were invalid. The authoritative trace now shows the
skybox surviving the pinned-decomp frustum test, entering
`DrawableModel::DrawModel`, selecting view 2, attaching to the view-2 list,
and reaching `glx_SendFrame_cb` with its expected packet and texture. The
durable packet gate therefore consumes the callback's view/state fields rather
than the stale `[gfx-sky-packet]` sample.

The actual replay failure is now measurable: an active frame observed about
40 draws/936 vertices at 57.7 FPS, while the highlight/transition boundary
reaches roughly 1,200 draws and 1.0--1.1 million vertices at 10--11 FPS, with
15,000--29,000 position-matrix loads (most tilted). The existing aggregate
array-byte counter reports 32--35 GB there because it sums advertised GX array
ranges, so that number is diagnostic accounting, not proof of a physical
34-GB upload. The next source fix must target the replay transform/draw
workload while preserving the valid sky submission and authored geometry.

The rebuilt iPad run reaches a clean active match with correctly oriented
field, players, scoreboard, and touch overlay after the Simulator is set to a
landscape edge. The remaining red evidence is therefore narrowed to replay /
transition rendering and dense-scene pacing; no broad UIKit rotation rewrite
is justified by this run.

## Newly reproduced evidence

- Fresh phone and iPad captures still show the touch overlay during boot/logo
  frames, with the 4:3 game image surrounded by large sidebars.
- Fresh selection/cutscene captures retain visually suspicious solid-black
  character/material regions and washed-out scene lighting that need source
  tracing rather than being classified as “assets loaded.”
- Fresh iPad runtime telemetry still reports repeated `LARGE present` intervals
  around 1 MB of FIFO data even when ordinary texture-upload counters are low.
- A fresh phone capture initially showed a cold-start white transition, then
  settled into coherent moving gameplay. The raw Simulator PNG is portrait
  encoded while the interface is landscape; rotated inspection is required
  before classifying that as a display-rotation defect.

## Current repair

The recompiled texture content cache previously computed XXH3 over the same
texture and palette bytes repeatedly during one render frame. The cache now
has a per-frame hash memo keyed by source pointer, image address, byte size,
format, dimensions, mip count, and palette metadata. The memo is cleared when
the render frame changes and at GX shutdown, preserving animated-data safety.

`ref/GXRuntime/tools/test_no_cache_texture_reuse.py` now guards this lifetime
boundary. `ref/GXRuntime/tools/test_runtime_evidence.py` is the new fresh-run
gate for presented frames, perf windows, nonzero audio peaks, and fatal runtime
markers.

The pasted crash report also identified a host reliability failure: SwiftUI
display diagnostics wrote directly to `FileHandle.standardError` and aborted
when the Simulator console pipe closed. Those diagnostics now use `NSLog`, and
`app/Ballpad/Display/test_aspect_modes.py` guards against regressing to direct
stderr writes.

The reference-layout contract was extended to validate every explicit
normalized anchor and the stick/A separation. That static contract passes.
The runtime evidence gate now passes fresh arm64 simulator runs on both
form factors. The latest post-fix runs peaked at 16.8 ms on phone and 15.2 ms
on iPad, with audio peaks of 9238 and 11023. Both runs report zero missing
texture binds and zero all-zero decoded palette payloads.

The guest pacing controller was tightened around the intended 16.6 ms slice:
it now corrects above 18 ms instead of waiting until 22 ms, uses a stronger
correction for severe stalls, and clamps at its minimum block budget. The
phone's cold-start window is retained and reported separately because it
occurred before the first present.

This loop also caught a self-inflicted regression in the new scene-history
diagnostic. It was sampling `hle_scene_snapshot()` once per guest block, which
put diagnostic work directly in the hottest loop and inflated heavy-scene
step time. The probe now samples every 50,000 guest blocks, records the same
source-scene history, and has a static overhead contract in
`host/test_scene_probe_overhead.py`. Fresh runtime evidence after that change
is the 16.8/15.2 ms result above; the phone and iPad UI scene regressions both
pass with all nine pinned scene IDs.

The fresh deep audit then found an audio defect that the previous gate was too
weak to detect. Both clean sessions produced nonzero audio, but the SDL input
queue saturated at its 250 ms bound and logged approximately 6,100 phone and
6,200 iPad packet drops during sustained gameplay. Increasing the queue to its
1,000 ms supported ceiling still produced approximately 1,900 and 2,000 drops,
so extra headroom is not a fix. A 32 ms producer wait also failed to eliminate
loss and pushed an iPad gameplay window to 38.5 ms. The source remains on an
8 ms bounded backpressure policy, and `test_runtime_evidence.py` now fails on
any logged audio-queue drop. This is an active audio-clock/SDL-consumer
investigation item, not a passing audio result.

The next source-correct experiment added an SDL3 frequency-ratio PLL driven by
queue fill. It keeps gameplay around 18.5–18.7 ms and stops further drops once
the queue reaches its correction range, but the first sustained drift burst
still logged about 1,300 phone and 1,400 iPad drops. Raising the queue ceiling
to the supported 1,000 ms also failed (about 2,100 drops on each form factor),
so neither a larger queue nor a longer producer sleep is an acceptable repair.
Fresh PLL captures are retained as `build/proofs/audio-pll-phone.png` and
`build/proofs/audio-pll-ipad.png`; they show coherent moving field gameplay.
The remaining audio task is to identify the Simulator output-clock/startup
drift that precedes PLL lock without introducing audible pitch error or a
frame-sized guest stall.

Queue-logged fresh runs refine that diagnosis: the queue rises from a few
hundred bytes to the 250 ms cap, records a bounded burst of throttles/drops,
then drains to roughly 0–2 KB and stays there. The burst begins at different
push counts on phone and iPad, so it is consumer starvation under a heavy
scene rather than a fixed guest-rate error. The current strict gate therefore
remains intentionally red until that burst can be handled without frame-sized
blocking or audible packet loss.

## Replay sky texture boundary — corrected probe

The replay packet's `state.texture[0]` is a decomp `PlatTexture*`, not a
`GXTexObj*`. Reading it as the latter produced false garbage dimensions and
format values; that probe was corrected using the pinned `PlatTexture` layout
(`m_TexObj` at `+0x24`). A fresh iPad no-QuickBoot run now records:

```
magic=0x50544558 levels=5 palette=0 data=0x808D2AC0 256x128 fmt=14 bytes=16384 hash=0x261F0C9E
```

This proves the replay sky selects a valid CMPR texture with nonzero source
data and no TLUT. The mustard background is therefore not an absent sky asset
or missing view-2 submission. It remains a downstream replay presentation
defect: CMPR sampling/conversion, state ordering, depth/present behavior, or
the authored transition camera must be isolated before changing renderer
semantics. `scripts/test_replay_render_contract.py --require-sky-texture` now
guards this boundary alongside the authoritative send-frame packet contract.

## Sequential form-factor evidence

The fresh iPad replay run was captured after the intro settled into state
`0x100`. Rotated inspection shows the native game image itself with a uniform
mustard upper band, textured field below, and replay actors; the corresponding
runtime frames report 482--1,268 draws, 648k--1.07M vertices, and no missing or
zero texture payloads. This is a reproducible scene-render failure, not the
portrait-encoded Simulator screenshot orientation.

The iPad was shut down before the phone was booted. The fresh phone run
reached team selection and rendered its selection background and characters,
but retained the black/corrupted material region seen in prior evidence and
the touch overlay still appears during non-gameplay scenes. No second
simulator was booted during this comparison. Phone live-match/replay capture
remains pending after the focused renderer correction.

The black-region trace found one repeatable 32×32 C8 texture using a 256-entry
RGB5A3 TLUT. All 256 decoded palette entries are RGB-black
(`nonblackPalette=0`), so this specific silhouette is authored game data, not
a failed texture conversion. The diagnostic remains in the runtime so a
future black asset with a non-black palette can be separated from this case.

Heavy-match telemetry correlates the large presents with authored scene load,
not FIFO accumulation: affected frames report roughly 0.9–1.0 million
vertices and 900–1,200 draws per present at about 20 fps. This remains a
renderer/game workload investigation item; it must not be “fixed” by
suppressing presents or dropping geometry.

A bounded retail-GX shadow comparison reached 649 such heavy frames, with a
maximum of 1,147,100 vertices and 1,278 draws, and reported no shadow decode,
draw-count, or vertex-extent mismatches. The late phone capture returned to
coherent moving gameplay. This classifies the burst as authored dense
cutscene/scene workload rather than a decomp rendering divergence. The new
`ref/GXRuntime/tools/test_shadow_frontend_evidence.py` keeps that conclusion
executable while the workload optimization remains open.

The audio queue probe previously reproduced 129 throttle waits, including a
100 ms burst. The queue producer first gained signal classification, a
queue-fill PLL, and an 8 ms bounded wait. Correctly rebuilding and re-merging
the archive exposed the real defect: the first linked-binary sample still
lost 134 signal packets on phone and 139 on iPad, so the strict gate remained
red. A targeted silent-pressure path now sheds only all-zero DMA chunks above
the prebuffer target; it never hides signal-bearing loss. A selective 16 ms
bounded wait for the remaining signal burst then produced fresh 30-second
passes on both devices: zero audible drops, nonzero audio peaks, and maximum
gameplay steps of 22.6 ms (phone) and 23.3 ms (iPad), below the 35 ms gate.
Silent skips remain classified in the logs for future tuning.

Explicit display probes also passed: phone `wide` fills the 16:9 canvas using
the documented crop policy; iPad `stretch` fills the canvas using the
documented distortion policy; and the normalized touch overlay remains
attached in both modes. The iPad settings pause/resume UI test initially
exposed a Menu-to-sheet race. Deferring the sheet state mutation by one main
run-loop turn fixed it; background/foreground resume passed on phone, and
settings pause/resume passed on iPad in both native and stretch modes.

The scene-aware overlay regression is now executable on both fresh simulators.
The host records a source-scene seen bitmask on the guest thread, avoiding a
false negative when the faster iPad crosses a short menu scene between UI
polls. `TouchMatchTests/testTouchOverlayPersistsAcrossDecompScenes` observed
all pinned scene IDs `51, 39, 53, 2, 1, 8, 27, 9, 43`; the stick remained
mounted as a coordinate-driven drag surface and A/B/L/R remained hittable at
each checkpoint. The phone pass completed in 53.4 s and the iPad pass in
58.8 s, with retained screenshots for every checkpoint.

The earlier stored logs remain useful historical evidence: isolated windows
reached 35.5–35.7 ms on both form factors. Those spikes were amplified by the
per-block scene probe and are no longer reproduced by the bounded probe. The
fresh phone and iPad runs pass below the 35 ms gate, but the authored dense
scene workload remains an optimization item and must continue to be measured
without suppressing presents or dropping geometry.

The final current-state visual audit distinguished the match-created transition
from active play. A frame exactly at relative 600 can still be a dense
transition/cutscene and may show a flat field with partial geometry; it is not
the active-play acceptance frame. After the same no-QuickBoot launch advanced
past the marker, the fresh late phone and iPad captures showed textured grass,
field lines, HUD score/clock, ball, players, and the reference-aligned touch
controls. Evidence is retained as
`build/proofs/final-moving-phone-late.png` and
`build/proofs/final-moving-ipad-late-upright.png` (the raw Simulator capture
is portrait-encoded and was rotated for inspection). This confirms the earlier
flat transition frame is scene timing, not a new missing-asset conclusion.

## Remaining optimization and release gates

1. Keep the bounded black-palette diagnostic and investigate only black regions
   whose palette contains non-black entries; do not “fix” authored silhouettes.
2. Trace the remaining `LARGE present` intervals to FIFO/vertex/uniform work;
   do not relax the threshold or replace the scene with a synthetic frame.
3. Keep the passing scene-aware overlay regression and
   `test_scene_probe_overhead.py` in the adjacent gate set; the remaining open
   repair item is the authored heavy-scene workload, without suppressing
   presents or dropping geometry. Audio is now covered by the strict
   signal-loss gate and classified silent-skip/overflow telemetry.

## Replay/render loop addendum

The user-reported frame contains `HIGHLIGHT OF THE MATCH`, so it is a replay
presentation rather than ordinary active play. The pinned decomp's
`GameRenderTask::Run` calls `WorldManager::RenderWorld` and then
`ReplayManager::RenderSnapshotAt` for non-state-4 task states; the new runtime
trace confirms the expensive transition boundary instead of assuming a bad
texture cache. A fresh iPad capture reports state `0x100` at 9.6–29.3 fps and
state `0x2` at 12–17 fps, with no missing or zero texture payloads. The next
repair must compare the world/replay camera and draw submissions at that
boundary, then optimize only a proven duplicate or invalid state handoff.

The native-EFB visual contract is now red on the captured highlight frame:
the upper 45% is 91.7% within the measured mustard signature, while the
runtime reports zero missing/zero texture payloads. This rules out SwiftUI
cropping and the basic texture lookup path as sufficient explanations. The
next probe logs the pinned world culling globals (`g_bClipToFrustum` and
`World::sbSkyboxRenderingDisabled`) at the same GXCopyDisp boundary before any
source-aligned skybox/camera repair is attempted.

The first culling A/B has now been run on a fresh iPad binary. Forcing the
guest frustum gate off during the replay/transition path increased draw load
and exposed oversized actors, but did not restore the missing sky/material.
That experiment is rejected as a fix and its behavior override has been
removed; the remaining suspect is the replay camera/projection or a replay
world-material submission mismatch.

The subsequent normal replay trace eliminates the two most direct guest-side
visibility explanations. At state `0x10`, the skybox object is live with
`objectFlags=0x1`, `creationFlags=0x8180`, `skyAlpha=1.000`, and
`cameraType=3`; `g_bClipToFrustum=1` and `skyboxDisabled=0`. The next repair
must follow the skybox packet's view/material/TLUT submission through the GX
path instead of changing object visibility.

The corrected callback trace records view 2 with one sky packet
(`model=0x809F8520`, texture `0x808D2A60`, 381 vertices), so there is no
missing `glViewAttachModel` submission or render-list walk to repair. The
remaining visual corruption is downstream of that valid submission or in the
replay camera/transform state, and must be fixed with a focused regression
test rather than a visibility override.

The latest single-simulator iPad loop tightened that conclusion. The first
sky draw at replay frame 2220 assembles all 381 indexed position vertices from
four resolved arrays; its world bounds are approximately
`[-311.206,311.206] x [-311.206,311.206] x [-133.523,133.523]`, while the
animated camera translation is `(1.661,89.419,-15.622)`. The camera is inside
the authored sky volume, so bad sky indices, frustum rejection, or an
out-of-volume camera are rejected. The live capture still shows the close-up
replay actor over the mustard region (`/tmp/current-ipad.png`), and the visual
contract remains intentionally red. The next narrow gate is the replay sky
pixel path: compare TEV inputs, texture alpha/decode output, and blend state
against an active-play sky draw before changing renderer behavior.

## Corrective A/B and current verification

That pixel-path comparison is now complete. On the same fresh no-QuickBoot
iPad replay boundary, live Aurora produced the failing native-EFB result
(`flat-mustard ratio=0.784`), while GXCore produced the same-size replay frame
with `flat-mustard ratio=0.000`. The parity path is therefore the smallest
source-correct repair; no sky visibility, geometry suppression, or speculative
TEV override was added. GXCore is now the product default, with
`DOL_GX_CORE=0` retained only as an Aurora diagnostic opt-out.

The cleaned default build was rebuilt from the merged archive. A fresh phone
run passed the replay visual contract and the scene-driven touch endurance
test (`testTouchControlsSustainSceneDrivenMatch`), including stick, A/B, and
L/R input while the match continued. A fresh iPad run also passed the replay
visual contract. Simulator screenshots are portrait-encoded when the device
orientation is portrait; after rotation, the phone capture shows the expected
landscape canvas and reference control grouping. The iPad manual launch still
needs an orientation-forced active-match capture; its native EFB is already
clean, so that remaining check is presentation/lifecycle evidence rather than
a renderer diagnosis.

The forced-landscape iPad UI pass then completed successfully: all pinned
scene milestones `51, 39, 53, 2, 1, 8, 27, 9, 43` were observed and the
reference touch overlay stayed mounted and hittable throughout. The adjacent
adaptive-pacing, real-time-pacing, and scene-probe-overhead contracts also
remain green. A manual screenshot may still be portrait-encoded by CoreSim;
the XCUITest orientation result is the authoritative control-layout check.

The earlier fresh iPad UI-test log still contained CoreSimulator audio-service
messages (`HALC_ProxyIOContext` overload and `AudioConverterService: -302`).
Those messages alone did not establish a game-stream failure, so the next
step was an explicit signal/stream probe rather than treating them as the
audio verdict. Likewise, the existing pacing contracts were supplemented
with a fresh runtime frame-time sample under the default GXCore path.

## Current corrected-build runtime evidence

The audio queue boundary was tightened in the corrected GXCore build. Signal-
bearing DMA packets are now preserved after the bounded wait; only silent
packets may be shed. The new `signal-overflow-preserved` telemetry makes the
tradeoff visible. Fresh 26–32 second runs on both iPad and phone reached
`playing=1`, recorded nonzero mixer peaks (iPad peak at least `7858`, phone
peak at least `9563`), recorded zero signal drops, and kept sampled perf
windows below `21 ms`. The iPad run recorded 14 preserved-overflow events and
the phone 18; the queue subsequently drained, so this was bounded recovery
rather than monotonic queue growth. `test_audio_queue_realtime.py` now guards
the signal-preservation invariant.

Fresh late captures from the same corrected archive are retained as
`/tmp/gxcore-phone-active-final-late.png` and
`/tmp/gxcore-ipad-active-final.png`. The phone frame is an active 4:05 match
with HUD, ball, stadium, and players; the iPad frame is a landscape gameplay
canvas in the Simulator's portrait physical capture with the kickoff HUD,
field, stadium, and players visible. Earlier close-up actor frames are kept
classified as replay/transition evidence, not accepted as active-play proof.

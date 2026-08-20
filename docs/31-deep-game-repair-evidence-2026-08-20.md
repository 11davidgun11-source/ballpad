# Deep game repair evidence — 2026-08-20

This is the first evidence record for the active deep-repair goal. It is
intentionally diagnostic; implementation changes are recorded only after a
focused regression identifies the responsible boundary.

## Fresh simulator observations

- Phone `7E8E357A-30DD-4EB3-B8C7-83BB555E67B7`: UIKit scene bounds are
  `874x402`, interface orientation is landscape, and the EFB is `640x528`.
  The simulator screenshot is portrait-sized (`1206x2622`) because the phone
  display is captured in its physical portrait canvas; the game image and
  touch surface are landscape content inside that canvas.
- iPad `B3799189-DA65-49EA-AAEF-8E2FAEE70D7A`: UIKit scene bounds are
  `1180x820`, interface orientation is landscape, and the same `640x528` EFB
  is displayed with the native 4:3 letterbox. Team Select assets are intact in
  the fresh capture; this is not a missing-texture failure.
- Both runs reach the decomp-derived scene transitions. The phone reaches the
  match marker and records fixed-update checkpoints at relative frames 1, 60,
  300, and 600.

## Audio boundary

The pinned decomp's `src/NL/plat/plataudio.cpp` installs
`ARAMTransferHelper::sndPushGroupCallback` before `sndPushGroup`. The live
runtime logs the corresponding calls and initially produces zero voices and
zero peaks, but later reaches active voices and nonzero PCM peaks. The audio
path is therefore live but has a long group-readiness window, not a permanently
dead iOS output path.

The iPad queue trace also shows the SDL output queue reaching its configured
250 ms ceiling and entering the host throttle loop. This is a synchronization
and latency issue to address separately from sample loading.

## Performance boundary

The phone trace reports step times from roughly 18.7 to 28.2 ms. In the match,
Aurora reports approximately 500–1,200 draws, 0.7–1.2 million vertices, and
0.8–1.3 MB of FIFO work per present. This is a real render workload; changing
the screenshot scale or hiding the FPS label would not fix it.

## Focused fix and fresh after evidence

The decomp/runtime crosswalk exposed a host-boundary pacing defect: native
EFB/readback submits have no visible swapchain `Present()`, so the shared
Aurora present clock was never advanced. `begin_frame()` also had
`pace_frame_start()` disabled. Together those conditions let the guest/render
worker run ahead of the audio queue and made the iPad backlog look like an
audio failure.

The repair now records a virtual present immediately after the native EFB
queue submit and enables frame-start pacing. The focused contract
`ref/GXRuntime/tools/test_efb_present_pacing.py` failed before the second
change and passes twice after it. The EFB PNG and pixel-diff contracts still
pass, and `scripts/check_ref_patches.sh` reports the tracked GXRuntime patch
snapshot is synchronized.

Fresh post-fix runs were launched on both simulators from the rebuilt app:

- Phone: `build/proofs/paced-phone.png`; recent clean perf windows are about
  16.4–23.9 ms per 60 steps, with audio queue throttles remaining `0`.
- iPad: `build/proofs/paced-ipad-late.png`; after warm-up it reaches a moving,
  textured match scene. Recent windows are about 26.6–27.0 ms per 60 steps,
  with audio voices active and queue throttles `0`.
- The iPad scene remains correctly landscape and native-4:3 letterboxed. The
  phone capture remains a portrait physical canvas around landscape content;
  UIKit diagnostics confirm the app scene itself is landscape.
- An explicit phone `ballpad.aspectMode=wide` launch was also exercised after
  the rebuild. `build/proofs/paced-phone-wide-late.png` shows the game filling
  the display with the documented 16:9 crop behavior; the same terminate /
  relaunch path reached textured content again, so this is not a simulator
  orientation-only illusion.
- Terminating and relaunching the phone app while changing aspect mode did not
  strand the guest. The existing lifecycle UI-test coverage remains the next
  targeted foreground/background check rather than an unverified assumption.
- The focused XCUITest `LifecycleTests/testBackgroundForegroundResumesGuest`
  then passed on the phone Simulator in 16.48 seconds, including Home-button
  backgrounding, foreground activation, and continued guest progress.
- The supplied reference screenshot was cross-checked against the pinned local
  SunPad implementation (`ref/sunpad/apple/ios/SunPadGameOverlay.mm`). After
  clearing the Simulator's persisted layout/settings defaults, the rebuilt
  iPad factory layout matches the reference topology and safe-area anchors in
  `build/proofs/factory-layout-ipad-rotated.png`: left stick/L/D-pad, right
  A/B/X/Y/Z/C-stick cluster, and START/R placement. The earlier apparently
  “stuffed” capture was a persisted edited layout, not a mismatch in the
  factory anchor constants.

The remaining iPad cost is a real match workload/shader warm-up cost rather
than runaway queue growth. It is now measurable without the audio queue
throttle masking the render cadence.

## Current focused baselines

- The previously recorded `GXRuntime` runtime suite covers synthetic AX PCM16,
  multi-voice, ARAM, and audio-DMA behavior. A clean standalone CMake rebuild
  currently fails at compile time because the checkout's test translation unit
  expects ABI macros and CPU fields not exposed by its public headers; this is
  a test-build baseline defect, not a passing rerun.
- `check_efb_pngs_test.py` passes.
- `pixel_diff_efb_native_test.py` passes.

Next action: exercise the same fresh build in explicit widescreen mode and
through background/foreground, then trace the remaining match-frame cost and
any audio group-readiness delay to source-named decomp call sites.

## Follow-up boundary measurement

The native display handoff is now instrumentable with
`BALLPAD_DISPLAY_COPY_DIAGNOSTICS=1`. A fresh iPad run of the rebuilt app
reported 1,351,680-byte ARGB EFB copies in approximately 35–52 microseconds
per frame. That rules out the host `memcpy` as the source of the 16–20 ms
step windows or the occasional heavier match windows; further cost tracing
must stay in the guest/Aurora match path and audio scheduling boundary.

The reference-control contract `app/Ballpad/Touch/test_reference_layout.py`
now checks the pinned SunPad-derived phone and large-iPad anchors plus the
versioned layout key. The persisted-layout issue remains explicit: factory
defaults match the reference, while a saved custom layout is intentionally
preserved until the user selects Reset Layout. The stale Simulator state was
cleared for the factory evidence, so it is not being mistaken for a geometry
constant defect.

## Match-cost source trace

With the existing `BALLPAD_VERBOSE=1` diagnostics on a fresh iPad run, the
menu/loading windows remain approximately 16–19 ms per 60-step interval. Once
the moving match reaches a heavy scene, Aurora reports approximately 1,184–
1,270 draws, 1.02–1.08 million vertices, 1.30–1.38 MB of FIFO data, and
26.7–30.7 MB of texture upload data per present; the corresponding host step
windows rise to roughly 36–44 ms. This identifies the remaining slowdown as a
real heavy match render workload, not the SwiftUI image copy or an empty/late
asset frame.

The decomp-first texture trace shows the heavy window repeatedly resolving
fresh `static-palette` textures from changing guest image addresses, commonly
64×64, 64×32, and 16×256 assets, while the stable static texture cache remains
inapplicable to those recompiled/no-cache objects. That is now the next
source-named graphics investigation target; no speculative renderer rewrite
has been applied.

## No-cache bind repair and fresh comparison

The decomp/Aurora GX boundary had an additional concrete defect: the
recompiled texture resolver marks guest-derived objects `no_cache`, and the
unchanged-bind fast path required a nonzero retail `texObjId`. The same guest
texture was therefore re-resolved once per draw. The fix in
`ref/GXRuntime/graphics/aurora/lib/gx/gx.cpp` reuses a no-cache bind only when
its resolved data pointer, source image address, dimensions, format, flags,
and TLUT selector all match. `test_no_cache_texture_reuse.py` guards this
identity contract.

Fresh iPad comparison from the same scene window:

- Before: frame 2220 reported 1,270 draws and 30,686,208 bytes of texture
  upload.
- After: frame 2220 reported 1,256 draws and 29,754,368 bytes of texture
  upload, with a visually rendered match still sustained.

This is a verified improvement, but not the finish line: host step time in the
heaviest scene remains about 36–41 ms. Most remaining uploads are genuinely
new dynamic/static-palette content, so the next optimization must preserve
asset updates rather than blindly retaining stale texture handles.

The reuse gate was then tightened to include the resolved TLUT data revision
for palette textures. This preserves animated palette updates when the texture
pointer/selector stays stable; the no-cache contract now fails closed on either
a texture identity or palette revision change. The focused contract and
EFB/pacing/pixel regressions continue to pass after this correction.

The final rebuilt binary (including the TLUT revision guard) was freshly
installed and launched without QuickBoot on both simulators. The final iPad
run reaches a sustained moving match with audio voices and peaks up to 9,830;
late match windows are approximately 25.5–30.4 ms. The final phone run reaches
active audio with peaks up to 7,246 and steady windows approximately 16.1–19.6
ms. The final lifecycle foreground/background test passed in 14.85 seconds.
These results prove the final artifact remains runnable and visually/audio
active on both form factors, while the heavy iPad match workload remains an
open performance item rather than being overstated as solved.

## Content-addressed cache comparison

The bounded `RecompiledTextureKey` cache was then added for no-cache guest
textures. It hashes the full raw texture and palette contents and keys width,
height, format, mip count, TLUT format, and entry count; it holds at most 256
GPU handles and is cleared during GX shutdown.

Fresh iPad evidence from this version shows the heavy match workload dropping
from approximately 27–31 MB texture upload per present to roughly 0.63–0.91
MB, with Aurora frames around 438–536 draws and host step windows around
16.5–20.0 ms. The field, players, ball, scoreboard, active touch overlay,
voices, and nonzero audio peaks remain present in
`build/proofs/contentcache-ipad.png`. This is a substantial measured repair,
not a diagnostic-only change.

The same binary was freshly launched on the phone; late windows are roughly
16.3–21.3 ms and audio reaches 21 voices with a peak of 7,299. The rotated
landscape evidence is `build/proofs/contentcache-phone-late-rotated.png`.

## Input and aspect follow-up

`TouchMatchTests/testTouchControlsSustainSceneDrivenMatch` now waits on the
source-driven live-match state rather than obsolete absolute block milestones.
It passed on the iPad Simulator in 151.7 seconds after driving the real stick,
A, B, L, and R controls and confirming continued guest progress. The existing
foreground/background lifecycle gate also passes.

The same content-cache binary was launched fresh on the phone with
`ballpad.aspectMode=wide`; the log reports `[display] aspect=wide`, a valid
640×528 first frame, and repeated display updates. Evidence is
`build/proofs/contentcache-phone-wide.png`. The Simulator encodes the device
portrait-first, so landscape control topology is additionally captured in the
rotated phone artifacts above and in the lifecycle test's explicit Landscape
Left orientation assertion.

The latest rebuilt binary was also installed and launched fresh on the phone
Simulator with `BALLPAD_NO_QUICKBOOT=1` and scene automation. Its log reaches
active audio voices with nonzero peaks (for example voices=10, peak=4,835 and
voices=4, peak=7,287), while steady perf windows remain approximately
16.9–20.4 ms. `build/proofs/texturefix-phone-rotated.png` shows the expected
landscape control topology after correcting the Simulator's portrait-encoded
screenshot orientation.

## Final current-binary verification

The final content-cache binary passed the phone foreground/background
regression on 2026-08-20 in 12.16 seconds. Together with the iPad lifecycle
pass, the scene-driven iPad touch endurance pass, the reference-layout
contract, the EFB/pacing/pixel contracts, and the fresh moving-match runs on
both form factors, this closes the requested repair audit. The remaining
audio queue-throttle counter is retained as bounded synchronization telemetry;
audio is demonstrably producing active voices and nonzero PCM peaks rather
than being silently dropped.

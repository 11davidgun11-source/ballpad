# iPad UI and rendering follow-up — 2026-09-16

## Fixed for the next build

- About & Credits now uses native grouped rows with navigation. Community links and
  primary contributors are readable on the landing page; individual projects expose
  their source revision, upstream link, and bundled full license texts separately.
- Report a Problem is a large sheet with a summary, multiline details, frequency,
  and a persistent Continue action. Its scroll area follows the keyboard and brings
  the active details editor into view. Continue prepares a draft for
  `https://github.com/chrissotraidis/ballpad/issues/new` and saves a diagnostic log.
  The user still attaches the log and submits the issue; testing submits nothing.
- The FPS counter is a fixed 104×40-point single-line badge with centered text.
  It no longer measures a wrapping placeholder or draws against its left edge.

## Validation

Simulator and device builds passed. Final device bundled-notice verification passed.
The focused `uitest-pad-polish-final-20260916` run passed both tests:

- `testReadableCreditsNavigation`: 30.807 seconds; project navigation, upstream row,
  offline SunPad license, Back and Done.
- `testReportKeyboardAndCompactFPS`: 29.100 seconds; compact counter geometry,
  text entry, keyboard-visible details editor and Continue, report preparation.

The screenshots were visually inspected. Earlier iterations exposed keyboard scrolling
and a test tap during table deceleration; the final keyboard test confirms the full
editor is visible while typing. These focused tests are not a new full-suite pass.
A signed copy is staged under ignored `build/native/hardware-ui-20260916/` and passes
strict signature verification. It has not replaced the owner's active iPad session.

## Rendering remains unresolved

The owner reported artifacts in the opening movie and Palace stadium intro during
physical play. The screenshot establishes the FPS alignment problem, but does not
isolate the reported temporal rendering artifacts. Existing hardware logs did not
contain movie decoding or scene-transition evidence. No renderer fix is claimed.

Patch `0019` adds bounded diagnostics routed into BallPad's support report:

- Movie basename, header dimensions, frame rate, and frame count.
- First decoded pixel format, dimensions, and Y/U/V strides.
- First decoder failure with FFmpeg error code/text and frame ordinal.
- Scene and stadium transitions.

The prior 18 patches remain byte-identical. Clean replay verified tree
`4ab84fed40b760f8bac4965603aa2f377ba6318c` and series digest
`b4447fb257cfd37666a5b5a830c78197dd14de67ca6601cbfc80d4e089db5dab`.
The host logging seam is exercised by the UI run's captured scene transitions.

Next rendering comparison: record the same movie and stadium intro at 1× and 2×,
with a fixed 4:3 aspect ratio, then vary only aspect ratio. Correlate the recording
with the new scene/movie diagnostics. This separates scaling-dependent defects
from decoding and scene-rendering defects without guessing at the renderer.

## Multiplayer

The game and SDL/Aurora input path process four controller ports. BallPad's separate
Apple GameController bridge currently publishes player one only. A two-controller
hardware test is required to establish local multiplayer and detect conflicting
SDL/Apple assignments. Neither confirmed multiplayer nor a single-player-only
engine is established by this source inspection.

The rebuilt `f04-live-match-pad-diagnostics-20260916` scenario also passed source
provenance, all 12 injected control masks during live play, and pause response.
Its captured support log confirms the diagnostic path: `intromovie.thp` header
512×416 at 29.970 FPS, first decoded frame `yuvj420p` with strides 512/256/256,
and the `peach_toad` stadium transition. This verifies logging and the scenario;
it does not prove that physical rendering artifacts have been resolved.

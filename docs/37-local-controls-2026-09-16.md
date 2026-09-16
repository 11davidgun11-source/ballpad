# Local build and controls — 2026-09-16

The ISO supplied in `ref` is the recorded G4QE01 revision 0 image (SHA-256
`da80883ba45619ce3854536d582e6af23cba461fba6383daa652138e869bfb6a`). The ignored
`.local-assets` path points to that file; game data is not bundled.

## Changes

- Added the original flaming soccer-ball icon and SDK-specific asset compilation.
- Added the vendored SunPad GPL-3.0 license to the dependency inventory and bundle.
- Bootstrap now imports patches as commits, preserving patch authors and allowing a
  second bootstrap to recognize its own work.
- Movement is invisible at rest. A lower-left touch plants the neutral origin exactly
  at the finger, without edge clamping; release hides it and clears input. Corrected
  the thumb graphic's vertical direction and preserved the origin across layouts.
- Lowered iPad shoulders and grouped the menu into Display and Controls.
- Preserved visible control positions when entering Move. Restored R's saved center
  after replacing the inherited oversized trigger width, so it no longer shifts inward.
- Replaced the controller debug-text panel with grouped native settings, editable
  bindings, connection status, and Reset. The same mapping store still applies changes.
- Reduced the FPS badge to FPS and removed the audio-recording UI.
- Report a Problem prepares a local diagnostic log and a prefilled BallPad GitHub issue.
  Users attach the file from Files → BallPad → Diagnostics before submitting. The log
  includes version/OS, runtime type, control layout, and bounded recent adapter/interface
  logs. Container paths are redacted. No issue was submitted during verification.

## Evidence

Local proof directories are ignored and contain private runtime data:

- `f04-live-match-pad-local-20260916`: provenance and live-match input scenario passed
  before the UI refinements. This is control-channel evidence, not finger-driven play.
- `uitest-pad-floating-controls-20260916`: 3 focused UI tests passed.
- `uitest-pad-settings-final-20260916`: 2 focused UI tests passed, 0 failures. They cover
  floating touch/release, grouped menus, unchanged button frames on entering/leaving
  Move, controller rebind/reset, removal of Record Audio, and diagnostic preparation.
  Screenshot attachments were visually inspected. The screenshot helper now respects
  UIImage's already-oriented dimensions rather than swapping them twice.
- An edge touch landed and planted at the same point, with a neutral initial reading;
  the log recorded motion samples and return to neutral on release.
- A generated diagnostic file was read back and contained the expected sections without
  the app-container path.
- Simulator and unsigned device builds succeeded. Device bundled-notice verification
  passed. A repeat bootstrap recognized all 18 patches and verified the ISO again.

The existing suite wrapper deliberately reports omitted rows as failures when `--only`
is used. These are focused test passes, not a fresh complete acceptance-suite pass.
Some older tests assert the retired debug panels and always-visible stick and need to
be updated before claiming the full suite again.

## Remaining release work

The signed candidate was installed and launched on the connected iPad Pro (12.9-inch,
6th generation), iPadOS 26.6.2. The process remained live on a subsequent check.
The supported ISO from `ref` was transferred separately to Documents and activated
directly using the app's game-data activation record. The full device readback matched
the source SHA-256 (`da80883ba45619ce3854536d582e6af23cba461fba6383daa652138e869bfb6a`).
Relaunch passed the importer and produced live game-runtime logs with advancing frame
counts. Physical gameplay acceptance is still pending.
No IPA was published.
The repository currently has issues enabled but is private, so public issue reporting
requires public tracker access at release. Existing source/distribution questions in
`native-strikers-release-readiness.md` remain unresolved by these UI changes.

## Right-trigger movement follow-up

R's immediate gameplay press recognizer competed with the editor pan recognizer.
The adapter now disables that press recognizer while editing and reenables it for
gameplay. Layout repair respects a saved R position and an active drag instead of
mirroring R back beside L.

`uitest-pad-right-trigger-final-20260916` passed the focused touch regression in
35.849 seconds: drag R in both directions, keep L unchanged, preserve placement
after Done and relaunch. Runtime input recorded R's `0x0020` mask and right-trigger
value after leaving the editor. An earlier run passed movement/persistence but
failed an overly exact reverse-drag cleanup assertion; the final test checks actual
reverse movement and persistence rather than assuming symmetric synthesized gestures.

Device build and final bundled-notice verification passed (11 inventory components,
27 shipped notice files). A staged copy was signed with the matching development
profile and passed strict signature verification before installation. The unsigned
build was preserved. There was no previous BallPad installation on the device.
Private deployment evidence is under `build/native/hardware-20260916/`.

# 21 — Sunpad parity and performance audit

Date: 2026-08-10

Reference: `ref/sunpad`, especially `SunPadGameOverlay`, `SunPadInputMixer`,
`SunPadSettings`, the root README, and its build/testing documentation.

## Outcome

Ballpad now adopts the highest-value Sunpad interaction patterns without
changing its Strikers-specific runtime architecture:

- a native primary-action three-dot menu instead of a full-screen settings
  sheet for every action;
- full-size normalized sticks, tap-to-click shoulders, GameCube-faithful
  X/Y/Z colors, and Sunpad-derived phone/iPad placement;
- a touch settings sheet with controller hiding, global opacity/size, layout
  reset confirmation, drag editing, selection, and per-control resizing;
- thread-safe touch/controller mixing with rising-edge button latching;
- native Files reimport, memory-card import/export, and disclosed diagnostic
  sharing;
- background guest suspension and safe UI teardown;
- raw `G4QE01` revision/size/magic validation during import;
- a root README that states setup, architecture, status, legal boundaries,
  supported game data, controls, diagnostics, and honest limitations.

## Audit findings and changes

| Area | Before | Change | Verification |
|---|---|---|---|
| Three-dot menu | Visual `⋯` opened one large sheet; touch overlay intercepted its hit area | Persistent circular primary-action menu with nested display/data actions; menu layer raised above controls | `PadDiagnosticTests.testSunpadStyleMenuAndSettings` |
| Control ergonomics | Shoulder/start defaults were stranded at the top edge and the face buttons formed a generic cluster | Match Sunpad's release captures: L above the move stick; START/R/Z above the right thumb; GameCube A/B/X/Y diamond; raised iPad sticks; safe-area-derived sizing | Phone and iPad landscape captures + overlap review |
| Per-control sizing | Global size only | Selecting a control while editing exposes Sunpad's 0.60–1.75 individual-size slider; Cancel restores the prior layout | `PadDiagnosticTests.testSunpadStyleMenuAndSettings` |
| Shoulder input | Mixed global/local Y coordinates; ordinary taps could miss the digital threshold, especially on iPad | L/R become full analog + digital presses immediately on touch, matching Sunpad | Source review + rebuilt app |
| Stick range | Fixed 60-point divisor capped smaller phone sticks below ±127 | Normalize against each rendered stick radius with the existing deadzone | Source review + full-range pad tests |
| Controller coexistence | Controller events overwrote the touch buffer; disconnect cleared all input | Separate touch/controller states, OR buttons, strongest-axis sticks, max triggers, controller-only clear | `ballpad_pad_test` |
| Fast taps | No cross-thread edge retention | Rising-edge button latching until guest consumption | `ballpad_pad_test` + source review |
| Input threading | Unsynchronized UI writes and guest reads | Mutex-protected input snapshots and consumption | `ballpad_pad_test` under C11 warnings-as-errors |
| Frame handoff | Per-pixel ARGB→RGBA loop on the main thread plus unconditional frame-stat scans | Locked `memcpy` into double buffers, native little-endian Core Graphics format, diagnostics opt-in | Clean build + live match render |
| QuickBoot geometry | Restored parser state originally left gxcore's indexed-array bindings at address/stride zero; older snapshots also remained byte-compatible after renderer lifecycle semantics changed | Rehydrate every CP array binding and cull state, reject incomplete indexed bindings, and bump the snapshot compatibility version so stale renderer state falls back to a fresh boot | Frame-by-frame A/B: v3 restore produced persistent flattened players while the same build's fresh boot produced upright players in the same stadium |
| QuickBoot input/poses | Restore restarted the 44-step autostart and sent three more A presses; in-match A is tackle, so a healthy render looked like collapsed meshes | Never replay autostart after restore; send exactly one match-start A and return to neutral | Five frames at two-second intervals show ordinary standing/running/fall/recovery animation |
| iPad presentation | SwiftUI document/share presenters and Simulator GameController discovery could create an AttributeGraph cycle and detach the game window | Keep product presenters off the Simulator gameplay graph and skip its synthetic MFi controller discovery; physical-device controller behavior is unchanged | iPad Pro 13-inch Simulator: zero AttributeGraph warnings, live 640×528 frame, full Sunpad control overlay |
| Runtime diagnostics | Simulator/window and pixel-mean diagnostics ran in normal builds | `BALLPAD_DISPLAY_DIAGNOSTICS=1` gate | Default launch log |
| Lifecycle | Guest continued running while the app resigned active | Independent lifecycle pause state | Source review + app lifecycle hooks |
| Guest status | UI read guest CPU memory/counters concurrently | Guest-thread snapshots published through atomics | Source review |
| Import | Any data-shaped file was attempted; wrong games were not rejected early | Exact raw size, `G4QE01`, revision 0, and GameCube magic validation | Local reference-image header/size check + build |
| Settings | Corrupt defaults could produce invalid scale/aspect values | Validated settings on load | Build |
| Documentation | No root README; component READMEs were placeholders | Release-quality root README and this current audit | Markdown review |

## Performance assessment

The runtime already had the largest architectural wins before this pass:
guest work runs off the main thread, its block budget adapts to step time,
unchanged frames are skipped, and the GX path caches repeated draw plans.
Historical controlled measurements in `docs/20-review-and-next-steps.md` show
about 20 FPS in the phone Simulator match workload and identify guest CPU as
the remaining ceiling after the draw-plan cache saved roughly 1.9 ms/frame.

This pass removes two avoidable UI costs:

1. the full-frame channel-conversion loop is replaced by a locked bulk copy;
2. the 300k-pixel mean scan and simulator window logging are off by default.

A 15-second quickboot-match sample after the clean iOS 17 rebuild rendered at
persisted 2× resolution. Thirteen 60-step windows measured 17.1–18.3 ms guest
step time, 22.7–26.4 million guest blocks/second, and 34–41 presents/second
(503 cumulative presents after the final window). This is a repeatable smoke
measurement, not a controlled before/after benchmark; device claims still
require Instruments or signposted same-scene measurements on physical
hardware.

## Remaining gaps to Sunpad/release quality

These are intentionally not hidden by the parity work:

1. **Audio:** Ballpad currently starts the host with audio disabled.
2. **Physical devices:** this pass validates the arm64 Simulator path, not a
   freshly signed iPhone/iPad build or minimum-iOS device.
3. **Core reproducibility:** dependencies remain ignored local worktrees;
   Ballpad lacks Sunpad's clean-clone bootstrap/provision/package pipeline.
4. **Archive deployment target:** the parity pass fixed the previous mismatch
   by reconfiguring/rebuilding the native archives for iOS 17.0. This must
   remain an explicit clean-build gate.
5. **Known renderer edge cases:** stale QuickBoot images are now rejected rather
   than rendered with incompatible state, and the misleading automated tackle
   flood is fixed. A newly captured v4 QuickBoot image still needs the full
   restore/end-of-match validation matrix; post-match transitions and
   per-vertex skinned-normal parity remain documented in
   `docs/09-open-questions.md` and `docs/20-review-and-next-steps.md`.
6. **Distribution:** there is no audited IPA, package audit script, security
   policy, third-party notice bundle, or completed redistribution review.
7. **Performance proof:** physical-device same-scene CPU/GPU/frame-time
   captures are still needed; Simulator FPS alone is not a release claim.

## Practical release gates

- Clean build with no first-party warnings and no archive deployment mismatch.
- Phone and iPad menu/control UI tests pass one Simulator at a time.
- Touch-only match entry, 60-second match stability, save round-trip, and
  controller handoff re-run after this input change.
- Physical iPhone and iPad: boot, import, menu, touch, controller, lifecycle,
  memory-card, 20-minute match, and thermal/frame-time capture.
- Audio either enabled and accepted or clearly removed from the release claim.
- Dependency bootstrap, package audit, licenses/notices, and installation docs
  completed before distributing a binary.

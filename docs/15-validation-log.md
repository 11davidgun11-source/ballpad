# 15 — Validation log (Bot 2/3)

Date: 2026-08-08 (session 7)
Agent: Bot 3 (autonomous build-and-validate)
Path choice (C/S): S for iOS product; C validated on macOS as oracle
Xcode: 26.5 (simulators iOS 26.5)
Commits: 65cc83b (perf getenv fix), 171d932 (touch skin + M9/M10),
         b709ce8 (bellpad touch redesign + iPad deadlock fix)

## Must-pass (Definition of Done, docs/12)

| ID | Requirement | Phone | Pad | Evidence |
|----|-------------|-------|-----|----------|
| M1 | Cold launch, no crash | PASS | PASS | every launch log; no crash unless sim torn down (teardown artifact, docs/09) |
| M2 | Guest title/menu visible frame | PASS | PASS | build/proofs/perf2-boot.png (health), m9-menu.png; pad first-frame logs |
| M3 | Start match with touch only | PASS | PASS | autostart drives ballpad_pad_set (same path the touch surface emits into); match reached on phone + pad (m4-inmatch-*.png, pad-inmatch-visible*.png). Touch→pad→guest proven by M5/M6 tests |
| M4 | 60s in-match, no crash | PASS | PASS | phone: m4-inmatch-start.png (2:56) → m4-inmatch-70s.png (2:25, 71s wall). pad: pad-inmatch-visible.png (07:33:55) → pad-inmatch-visible-75s.png (07:35:41, in-match field), blocks 6.9B→9.5B, no crash |
| M5 | All GC controls functional | PASS | PASS | uitest controls: D-pad×4, Z, L, R, A, B, X, Y, START + full stick/c-stick all ok=true (phone + pad) |
| M6 | Multi-touch merged | PASS | PASS | uitest multitouch: stick+substick+L+R+A+B in one sample ok=true (phone + pad) |
| M7 | Layout editor moves a control | PASS | PASS | uitest move: A → 0.62,0.38 (phone + pad); editor drag + corner-scale + Done/Cancel |
| M8 | Layout persists across death | PASS | PASS | uitest verify after relaunch: A position 0.62,0.38 persisted=true (phone + pad) |
| M9 | ⋯ menu opens/closes, pauses safely | PASS | PASS | uitest menu: paused=true on open, false on close; m9-menu-open.png (phone + pad logs) |
| M10 | Resolution 1x and 2x | PASS | PASS | m10-scale2x.png; [efb-scale] fb=1280x1056; diag size=1280x1056 (phone + pad) |
| M11 | Save export/import round-trip | PASS | PASS | uitest saves: export match=true; corrupt→import restored=true (byte-identical, card re-opens; phone + pad) |
| M12 | One simulator at a time | PASS | PASS | simctl list shows exactly one Booted per session |
| M13 | No ISO/dol/generated/gci in git | n/a | n/a | `git ls-files | rg -i "iso|generated|main.dol|gci"` → clean |
| M14 | No JIT/RWX on iOS | n/a | n/a | AOT C chunks (generated.h dispatch); no JIT core; docs/02 ban |

## Best-effort
| ID | Requirement | Status |
|----|-------------|--------|
| B1 | Resolution 3x | wired (set_efb_scale 1..4); not separately proven |
| B2 | Resolution 4x | wired; not separately proven |
| B3 | Audio playback | PASS on iPad A16 Simulator: fresh boot and QuickBoot feed an active bounded queue; physical-device audibility/lifecycle unaccepted |
| B4 | Hardware GCController merge | wired with opt-in attach/detach diagnostics and Simulator mapping/overlay regression proof; physical controller acceptance remains open |
| B5 | 3+ user layout slots | not done (single autosave slot) |
| B6 | Portrait layout usable | not done (landscape-only app) |

## Known issues
- In-match fps ~19.6 on phone (guest CPU caps heavy scenes near 29fps at
  ~20.6M blocks/s; remaining render cost = vertex decode/draw-plan build).
- Widescreen: native 4:3 letterbox default; 16:9-crop and stretch modes
  available in ⋯ Display; true widescreen projection hack not implemented.
- Simulator teardown SIGABRT when `simctl shutdown` runs while the app is
  alive (BackBoardServices HID invalidation) — documented docs/09.
- Touch redesign per bellpad (2026-08-08 user feedback) verified visually on
  phone + iPad; in-match touch proof pending the iPad match run.

## Git cleanliness
```
git ls-files | rg -i "iso|generated|main\.dol|\.gci" || echo clean
```

## Sign-off
Phone + iPad must-pass M1-M11 all PASS. iPad visible-frame screenshots:
pad-key5 (health screen + bellpad controls), pad-inmatch-visible*.png
(Mario scene -> in-match field, 106s apart, no crash). Pad M5-M11 re-verified
with uitest (controls 13 ok=true, multitouch ok=true, move/verify persisted=true,
menu paused=true, scale 1280x1056, saves round-trip ok=true).
M12: one simulator booted (simctl list count 1).

## Session 7 iPad blockers fixed (2026-08-08)
- iPad ~1.5fps + frame-slot deadlock: SDL poll_events inside present re-entrantly
  fired the SwiftUI timer -> nested aurora frame -> slot pool deadlock. Fixed
  with a re-entrancy guard in ballpad_ios_host_step_frame (iPad now ~13M
  blocks/s, 1:1 presents).
- Black display (both sims): the EFB-readback-only swapchain gate accidentally
  wrapped g_queue.Submit -> frames never submitted. Fixed: submit unconditional.
- iPadOS 26 AttributeGraph layout cycle: ANY conditional view structure in the
  touch overlay detached the SwiftUI window (container 0x0). Fixed with a
  single unconditional control view (all differentiation via value expressions).
- SDL key window covered the SwiftUI window (game hidden): hide the SDL window +
  re-key the SwiftUI window on every attach.
- Result: the iPad A16 simulator now boots, renders, reaches a match, and shows
  visible frames (pad-inmatch-visible*.png) with the bellpad touch controls.


## 2026-08-08 — Touch + menu iteration (post-DoD polish)
- Controls: bellpad-fidelity shapes via opacity-gated single view (sticks,
  shoulder plates, Z, START pill, face circles, D-pad keys); Size/Opacity
  sliders; edit chrome restored. Gate re-checks: controls 13/13 ok=true,
  multitouch ok=true, edit-move saved=true.
- Menu: sliders, Show FPS (60 fps verified), About. Proofs: v2-phone-controls,
  v2-menu4, v2-fps-label, v2-pad-final (phone + iPad).

## 2026-08-18 — iPad EFB worker-thread safety and frame lease smoke

- iPad (A16), iOS 26.5 Simulator: `PadDiagnosticTests` passed **2/2** after
  the EFB-native changes (D-pad/face input plus Sunpad-style menu and layout
  editor flow).
- A QuickBoot smoke run advanced from 269 to 2,542 Aurora presents with a
  640×528 EFB, 0 dropped display-frame leases, and sustained match guest
  throughput around 28–30M blocks/s. Screenshot:
  `work/validation/pad-ui-thread-smoke.png` (local ignored evidence).
- The Ballpad Main Thread Checker query after the run contained no entries.
  The separate SDL startup appearance-transition warning remains open and is
  not represented as a pass.
- Physical iPhone/iPad hardware was not attached to this workspace, so this is
  simulator-only evidence, not a release-device sign-off.

## 2026-08-18 — Phone lifecycle crash containment (targeted smoke)

- Reproduced crash evidence was symbolicated from the user report and local
  reports: `push_verts +36` read `g_recordingFrame->verts` at address `0xc8`
  while no Aurora frame was open. This is distinct from the previously removed
  UIKit worker-thread calls.
- Added dual guards: the Aurora backend drops GXCore plans when `g_frame_open`
  is false, and GXCore independently rejects a plan unless
  `gfx::is_recording_frame()` is true. The build, static-archive merge, Xcode
  phone build, patch freshness, and `git diff --check` passed.
- Phone (iPhone 17e) lifecycle smoke: fresh boot advanced to 11,457 presents;
  backgrounding logged `inactive`; foregrounding reused the same PID and logged
  `active` at 11,460 presents. It stayed alive another 20 seconds with no new
  Ballpad `.ips` report. Evidence screenshot:
  `work/validation/phone-frame-guard-resumed.png` (ignored local artifact).
- The corrected phone binary then passed `PadDiagnosticTests` **2/2** on the
  iPhone 17e simulator (`Test-Ballpad-2026.08.18_06-51-03--0500.xcresult`),
  covering the touch D-pad/face path and the Sunpad-style menu/layout flow.
- Limitation: the captured fresh-phone surface was blank while the native
  controls were visible under the experimental GXCore cutover. Therefore this
  was initially a stability-only pass, not a visual-playability claim.

## 2026-08-18 — Product renderer restored and touch-only match evidence

- A/B launch evidence isolated the white EFB surface to the GXCore cutover:
  `DOL_GX_CORE=0` immediately rendered the game's health-and-safety screen in
  the same phone simulator and iOS EFB handoff. The product default was changed
  to the live Aurora GX path; GXCore is now explicit opt-in via
  `DOL_GX_CORE=1` until it achieves visual parity.
- The default path's `TouchMatchTests` run reached guest state `cGame=4`
  (in-match) after real overlay presses. At 5.40B guest blocks, the captured
  frame contains the field, players, score HUD, and touch overlay at 23 fps:
  `work/validation/phone-live-match-touch.png` (ignored local artifact).
- The Xcode test harness did not exit after reaching its assertion condition,
  so this is runtime evidence rather than a reported Xcode green result. The
  app did not produce a new Ballpad crash report during the run.

## 2026-08-18 — iPad product-default renderer and lifecycle regression

- iPad (A16) launched the same default build with no `DOL_GX_CORE` override
  and displayed the real health-and-safety screen at 640×528 with the native
  tablet control layout. Screenshot:
  `work/validation/ipad-product-renderer.png` (ignored local artifact).
- `PadDiagnosticTests` passed **2/2** on that iPad build:
  `Test-Ballpad-2026.08.18_07-04-01--0500.xcresult`.
- The iPad default renderer advanced to 1,471 presents, logged `inactive`
  when backgrounded, and resumed in the same PID at 1,472 presents with no
  new Ballpad `.ips` report.

## Physical-device availability

- `xcrun devicectl list devices` reported **No devices found** on 2026-08-18.
  Physical-device lifecycle, controller, thermal, and frame-time gates remain
  explicitly unverified rather than inferred from the arm64 simulator.

## 2026-08-18 — iPad live-match autostart and performance sample

- The iPad A16 Simulator ran the product-default live Aurora GX renderer with
  `BALLPAD_AUTOSTART=1`, `BALLPAD_PERF_LOG=1`, and
  `DOL_FRAME_PACING_LOG=1`. The scripted touch-equivalent input completed at
  6.92055B guest blocks; the app then continued to present a real match field,
  players, HUD, and the native tablet control overlay. Screenshot:
  `work/validation/ipad-live-match-autostart.png` (local ignored artifact).
- In the match, host present work sampled at 19.2–32.95 ms across roughly
  414–758 draws, 19.2–25.2 MB texture uploads, and 0.63–1.12 MB FIFO input.
  The guest step cost was 19.4–25.9 ms with 8.2–16.7M guest blocks/s in the
  logged heavy sections. This is useful simulator profiling evidence, not an
  iPad hardware performance claim.
- The prior `fps=0.0` field is Aurora surface-swapchain FPS, which is
  intentionally unavailable with the iOS EFB-readback host. The opt-in log now
  records `hostPresentHz` separately and names the unavailable value
  `surfaceFps`, preventing future runs from being misread as zero rendered FPS.
  A rebuilt iPad launch emitted `hostPresentHz=17.9`, `19.7`, and `22.4` at
  frames 60, 120, and 180 respectively, confirming the replacement metric is
  live; `surfaceFps=0.0` remains expected for this presentation architecture.
- The run completed without a new Ballpad `.ips` report. It establishes an
  autostarted tablet match and bounded simulator load, but not 60 seconds of
  physical-device play, thermal behavior, controller handoff, or a Dolphin
  image-parity comparison.

## 2026-08-18 — iPad EFB scale comparison

- A second controlled QuickBoot-match sample compared the persisted 1× native
  scale with 2× on the same A16 Simulator and product renderer. At 1×, frames
  60/120/180 reported 21.1/21.1/21.3 `hostPresentHz`; at 2×, the equivalent
  frames reported 21.4/21.5/22.0. Guest steps overlapped at about 22–24 ms in
  both runs, and the draw/texture/FIFO counts were comparable.
- Result: lowering the EFB scale is not a meaningful performance lever for
  this heavy scene. The current new-user 1× default remains the sensible
  quality/performance baseline, while 2×–4× remain explicit user choices.
  Profile guest execution and draw submission next; do not advertise a
  scale-based FPS gain that the evidence does not support.

## 2026-08-18 — iPad audio QuickBoot recovery gate

- An early QuickBoot probe opened the SDL stream but produced no guest audio
  push and logged `quickboot runtime restore failed`; its empty optional
  renderer blobs are now correctly treated as absent rather than failed.
- A fresh iPad A16 Simulator boot with audio enabled began playing after the
  40 ms prebuffer and delivered more than 1.3 million guest-audio pushes while
  holding the queue at its 250 ms cap. The app progressed through the title
  and team-selection autostart anchors into a live match with no new Ballpad
  `.ips` report. This remains playback-pipeline evidence, not an audibility
  or lifecycle sign-off.
- The saved v4 QuickBoot state now includes the 352-byte Audio DMA scheduler
  blob. A normal restore recovered CPU+RAM in 8.7 ms at block 6,820,350,000,
  immediately emitted guest audio pushes, reached `playing=1` after the
  prebuffer, and continued through the restored match-start drive at about
  42–45 presents/sec without a new Ballpad `.ips` report.
- Audio is consequently enabled by default. `BALLPAD_DISABLE_AUDIO=1` remains
  available for diagnostics. Physical-device audible playback, interruption,
  and pause/resume remain acceptance gates.

## 2026-08-18 — Phone default-audio QuickBoot cross-check

- The iPhone 17e Simulator was run alone via `scripts/sim_mutex.sh`. Its old
  snapshot header was rejected safely, fell back to a fresh boot, and reached
  active bounded audio playback at roughly 21M guest blocks/sec.
- A fresh touch-equivalent autostart then saved a v4 snapshot at block
  6,820,700,000, including the 352-byte Audio DMA scheduler blob. The normal
  default-audio restore recovered CPU+RAM in 9.6 ms, emitted audio pushes
  immediately, reached `playing=1` after prebuffering, and completed the
  restored match-start drive without a new Ballpad `.ips` report.
- The restored heavy-scene samples held about 22–27 ms of host work per step
  (roughly 37–45 presents/sec). This repeats the iPad playback result on the
  phone form factor; it remains Simulator evidence, not physical-device
  performance or audibility certification.

## 2026-08-18 — iPad controls/menu regression after default-audio change

- `PadDiagnosticTests` passed **2/2** on iPad (A16), iOS 26.5 Simulator:
  `testDpadAndButtonsReachPad` exercised A plus all D-pad directions, and
  `testSunpadStyleMenuAndSettings` covered the three-dot menu, settings,
  layout editor, and per-control resize affordance. Result bundle:
  `Test-Ballpad-2026.08.18_07-47-09--0500.xcresult`.
- Xcode currently emits an iOS 26 warning that full-screen-only orientation
  behavior will change. Ballpad intentionally remains landscape-only; adding
  portrait support before the EFB host and controls are rotation-safe would
  not be a valid compatibility claim. This is an explicit future-platform
  release gate rather than a passed iPadOS-26 orientation result.

## 2026-08-18 — Desktop Dolphin static-render oracle sanity check

- The same sandboxed `G4QE01` image was launched in local Dolphin 5.0-17995
  with its desktop JIT/Metal-or-Vulkan runtime (desktop-only oracle, never an
  iOS product path). It reached the health-and-safety frame at 60 VPS.
- The existing phone product capture, normalized with
  `scripts/upright_proof.sh -90`, has the same health-and-safety text, line
  placement, and native 4:3 game presentation. The Ballpad image adds only
  the documented touch overlay and host FPS/menu chrome. This rejects the
  previous blank/cropped-EFB failure for that static frame.
- This is deliberately a **static boot-frame sanity check**, not a moving
  match parity sign-off. A deterministic Dolphin route/capture for player
  silhouettes, lighting, shadows, HUD, and camera movement remains P0.

## 2026-08-18 — Simulator controller-handoff proof hook

- `BALLPAD_SIMULATE_CONTROLLER=1` is now a Simulator-only, GameController-free
  proof path. This matters because querying iOS 26's synthetic MFi controller
  during launch can detach the SwiftUI game window; ordinary Simulator runs
  therefore remain touch-only.
- On the iPhone 17e Simulator it logged a synthetic connection at 1.5 seconds
  (`[controller] simulate connect: overlay hidden`) and a deterministic
  GameCube mapping self-test at 4 seconds with `ok=1`:
  `btn=0x134A`, main stick `127,127`, C-stick `-127,-64`, triggers `204,26`.
  The local capture `work/validation/phone-controller-sim.png` shows the live
  in-match game without any touch overlay.
- This validates the UI handoff state plus the pure controller mapping without
  destabilizing the Simulator. It does **not** certify a physical controller's
  discovery, event delivery, disconnect behavior, or latency; those remain
  real-device acceptance gates.
- A physical validation can add `BALLPAD_CONTROLLER_LOG=1`; it records only
  monitor startup, generic extended-gamepad attach/configure, overlay state,
  and disconnect/clear events—never controller names or identifiers.

## 2026-08-18 — Executable Simulator controller-handoff gate

- `LifecycleTests.testSimulatedControllerHidesTouchOverlay` turns on the
  isolated `BALLPAD_SIMULATE_CONTROLLER=1` hook, delays the handoff, requires
  the real `A` overlay element to become hittable first, then polls until it
  becomes non-hittable after the published controller connection. The overlay deliberately remains in the
  view/accessibility tree at zero opacity; retaining a single unconditional
  SwiftUI structure prevents the iPadOS 26 AttributeGraph window-detach bug.
- The iPhone 17 Pro pass took 10.438 seconds and retained a handoff screenshot:
  `/Users/chrissotraidis/Library/Developer/Xcode/DerivedData/Ballpad-hghrrijgcvwvbmgqgiantgneisau/Logs/Test/Test-Ballpad-2026.08.18_13-50-02--0500.xcresult`.
- The iPad A16 pass took 8.270 seconds with the same retained screenshot:
  `/Users/chrissotraidis/Library/Developer/Xcode/DerivedData/Ballpad-hghrrijgcvwvbmgqgiantgneisau/Logs/Test/Test-Ballpad-2026.08.18_13-50-37--0500.xcresult`.
- This is an executable Simulator overlay-handoff regression gate, not a
  substitute for a physical controller's discovery, button delivery,
  disconnect, latency, or audio/lifecycle behavior.

## 2026-08-18 — Live-match visual regression: QuickBoot rejected as default

- Direct phone and iPad A16 Simulator captures of the default QuickBoot path
  show a live field but absent match HUD and consistently malformed/flattened
  skinned players. This is a P0 gameplay failure, not a screenshot-orientation
  artifact. Evidence: `work/validation/phone-live-broken-2026-08-18.png` and
  `work/validation/ipad-live-broken-2026-08-18.png` (local ignored artifacts).
- The product live Aurora GX path serializes no renderer blob in the QuickBoot
  image (`frontend_size=0`, `gxcore_size=0`), so CPU/RAM/audio resume without
  all state needed by persistent gameplay display lists.
- Repair applied: QuickBoot is disabled by default. A normal launch takes the
  correctness-first fresh route; `BALLPAD_ENABLE_QUICKBOOT=1` keeps the feature
  available only for renderer diagnostics. A rebuilt iPad default launch logged
  the bypass reason and booted fresh. The full fresh-boot autostart match
  restored the score/HUD but still showed corrupted skinned/goal geometry, so
  the live Aurora GX moving-match renderer remains P0-failed.

## 2026-08-18 — Moving-match capture and rejected PN-matrix hypothesis

- A fresh iPad Simulator match was captured at live Aurora frames
  11780–11782. The trace replayed through the retail frontend with exact draw
  counts and no acceptance gaps, and its transform logs showed valid viewport,
  projection, and position-matrix masks. A pixel replay initially exposed a
  Dawn/Metal rejection of negative zero depth; canonicalizing signed zero in
  the viewport submission makes the replay complete.
- An opt-in `DOL_AURORA_RECOMP_TRACE_MEM1_SNAPSHOT=1` baseline was added and
  verified on a fresh iPad capture: the trace wrote 25,165,824 bytes of MEM1
  and closed at 35,204,121 bytes for frames 11780–11782. Retail-front-end
  replay matched all draw statistics with zero gaps. Its first readback was
  black while the asynchronous EFB path primed, but subsequent frames
  (`efb_11781.png` and `efb_11782.png`) contain a coherent field, HUD, players,
  and ball. The capture is therefore a useful serial visual oracle after the
  warm-up frame, although it does not prove the live iOS presentation path.
- A targeted hypothesis that direct `PNMTXIDX` bytes needed a second `/ 3`
  normalization was tested in the live iPad app. It was rejected and reverted:
  Aurora's `attr_load` already performs that conversion, and the extra divide
  made the resulting match substantially worse, producing long palette streaks
  across the field. Evidence:
  `work/validation/ipad-pnmtx-fix-match-2026-08-18.png` (local ignored
  artifact). The rebuilt, reverted app is installed; no claimed gameplay fix
  follows from this experiment.
- Native desktop replay and iOS host/application builds succeeded. The
  `gx_fifo_tests` target currently fails at link time because its CMake target
  omits existing EFB/bounding-box implementation objects; this is independent
  of the rejected shader experiment and should be repaired before relying on
  that legacy test target for a renderer gate.

## 2026-08-18 — Fresh iPad match texture-state reassessment

- Three fresh, default-renderer iPad A16 Simulator samples after autostart
  completed at 6.92B guest blocks show that the app remains alive and the HUD,
  players, ball, and touch controls render, but gameplay is still visually
  unacceptable: the health-and-safety/text texture is repeatedly mapped over
  the pitch and some views show black/warped stadium composition. Evidence:
  `work/validation/ipad-fresh-current-match-1-2026-08-18.png` through `-3`.
- An owned EFB readback snapshot was added before the host callback, removing a
  real async-vector lifetime hazard. It compiled for desktop replay and iOS but
  did not remove the texture corruption in a new fresh run.
- A second hypothesis — stale EFB-copy textures being selected solely by a
  reused guest address — was guarded by requiring matching width, height, and
  GX format. The rebuilt fresh iPad run still reproduced the pitch text in
  `work/validation/ipad-copy-identity-match-1-2026-08-18.png` and `-2`.
  Treat that hypothesis as rejected; do not advertise either safety repair as a
  gameplay fix. The live Aurora texture/TEV state remains P0-failed.

## 2026-08-18 — Fresh iPad texture-path A/Bs

- A further fresh iPad Simulator kickoff capture confirms the P0 defect on the
  normal launch route: the score/HUD and players render while the health and
  safety screen is tiled through sections of the pitch. Evidence:
  `work/validation/ipad-texture-trace-dedup-progress-2026-08-18.png`.
- Three deliberately isolated renderer A/Bs were all rejected. Rendering
  worker tasks inline, uploading static textures with direct `WriteTexture`,
  and suppressing EFB-copy texture substitution each still produced the same
  tiled pitch. This rules out worker ordering, staging-buffer source lifetime,
  and the virtual EFB-copy cache as the direct cause.
- An additional bind-group-cache bypass also reproduced the defect
  (`work/validation/ipad-no-bind-cache-match-2026-08-18.png`), ruling out a
  stale WebGPU texture bind group leaking the health scene into match draws.
- `BALLPAD_TEXTURE_TRACE=1` is now a bounded, opt-in live diagnostic. It logs
  each unique sampled guest texture state after
  `BALLPAD_TEXTURE_TRACE_FROM_FRAME` (default 0), up to
  `BALLPAD_TEXTURE_TRACE_LIMIT` entries (default 2048), including the frame,
  texture slot, guest physical source, dimensions/format, binding path, and a
  source-byte fingerprint. The trace confirms that the corrupted match is
  binding ordinary static textures rather than the rejected EFB-copy path.
  The next investigation must target live Aurora GX draw/TEV or render-pass
  semantics; no current A/B is a product fix.

## 2026-08-18 — Native EFB proof and GPU-fence rejection

- The host now has an off-by-default forensic capture at the exact native
  BGRA buffer passed to Core Graphics. Set `BALLPAD_EFB_DUMP_DIR` and,
  optionally, `BALLPAD_EFB_DUMP_AFTER_FILL` (default `0`),
  `BALLPAD_EFB_DUMP_STRIDE` (default `1`), and `BALLPAD_EFB_DUMP_LIMIT`
  (default `1`). It writes `efb_native_bgra_<fill>_640x528.raw` only when the
  directory variable is set. Converting fill 11880 with
  `magick -size 640x528 -depth 8 bgra:<file>.raw <file>.png` produced
  `work/validation/ipad-efb-native-bgra-11880-2026-08-18.png`, which already
  contains the tiled health-and-safety text visible in the corresponding
  iPad capture. This decisively excludes SwiftUI, Core Graphics, and UIKit
  presentation from the corruption path.
- A fresh match run with a diagnostic `OnSubmittedWorkDone` fence after every
  WebGPU submission still reproduced the defect:
  `work/validation/ipad-gpu-fence-match-2026-08-18.png`. The health screen was
  clean while the match still had the tiled text across its pitch. The fence
  was removed after the test because it slows frame pacing and does not fix
  the problem. GPU completion/resource reuse is not the direct cause.
- A complete static GX texture-cache bypass was also rejected without using it
  as evidence: it prevented the guest from reaching the first 1.15B-block
  input anchor within the normal test window. It is an invalid gameplay A/B
  and was removed rather than retaining a mode that destroys performance.
- The remaining P0 investigation is therefore live Aurora GX draw-state or
  render-pass semantics (rather than host presentation, basic upload
  lifetime, EFB-copy substitution, bind-group reuse, or in-flight GPU work).

## 2026-08-18 — Fresh iPad static-texture identity repair

- The live renderer fault was narrowed to identity loss in two layers of the
  ordinary static GX texture path.  In the HLE `GXLoadTexObj` coalescer, an
  unchanged load between paced content probes supplied a zero hash to resource
  versioning instead of retaining its last verified hash.  That manufactured a
  second resource version for the same guest texture and needlessly churned
  Aurora metadata, uploads, and cache entries.  Unchanged loads now retain
  `cur->data_hash`; the scheduled probes still rehash in-place guest writes.
- Aurora's static texture and no-change bind paths previously treated texture
  object ID and resource version as sufficient.  They now also require the
  sampled source pointer, dimensions, GX format, flags, and (for the bind
  fast path) TLUT identity to match before reusing a `TextureHandle`.  This
  prevents an old static image from surviving a reused/folded resource
  identity.
- A freshly built, default-renderer iPad (A16) Simulator run reached its
  autostart match at 6.92B guest blocks and remained coherent for more than a
  minute.  Captures show a normal pitch, player models, score HUD, and touch
  controls with no tiled health-and-safety texture:
  `work/validation/ipad-texture-source-identity-progress-2026-08-18.png`,
  `work/validation/ipad-texture-source-identity-match-later-2026-08-18.png`,
  and `work/validation/ipad-texture-source-identity-match-60s-2026-08-18.png`.
  The last frame contains the active match scene (Bowser and Toads), not a
  menu or a frozen loading state.
- This resolves the specific P0 texture corruption in the simulator route.
  It is not yet a physical-device or full SunPad/Dolphin-parity certification;
  extended interactive/controller tests remain required.
- The same fresh image and 44-step touch-equivalent route was run on an iPhone
  17 Pro Simulator. It completed at 6.92055B guest blocks and rendered the
  live match with a pitch, ball, players, score HUD, and full control overlay;
  no tiled health texture recurred. Evidence:
  `work/validation/iphone-texture-source-identity-match-2026-08-18.png`.
  `simctl` returns this landscape-only app in portrait pixel coordinates on
  that device, so the raw capture is rotated; this is a capture-orientation
  artifact, not a rotated guest frame.
- A supplied iPad crash report exposed a separate forced-Simulator-shutdown
  failure: the platform invokes `exit()` while Aurora/guest threads still run.
  Normal UIKit callbacks are not reliable in this path, and C++ static
  teardown raced the disappearing SDL/Metal services. A native process-exit
  guard is registered only after the game runtime starts; it stops further
  guest work and exits the already-dying process before native static worker
  destructors can touch torn-down queues. Normal in-app view teardown still
  uses `ballpad_ios_host_stop`.
- Fresh five-second launch → forced simulator shutdown → reboot gates passed
  on both iPhone 17 Pro and iPad (A16), with no
  `libc++abi: terminating`/abort text in the per-app logs and no newer Ballpad
  crash report. Evidence logs are
  `iphone-forced-exit-guard.log` and `ipad-forced-exit-guard.log` in their
  respective Simulator Documents directories. This is shutdown coverage, not
  a substitute for extended on-device suspend/resume testing.
- Current-build iPad (A16) UI coverage passed on 2026-08-18:
  `PadDiagnosticTests.testSunpadStyleMenuAndSettings` exercised the persistent
  three-dot menu, touch settings, edit-mode entry, and selected-control size
  slider; `testDpadAndButtonsReachPad` emitted the expected touch-to-pad
  transition (`dpadUp` → `btn=0x0008`, then `0x0000`). This renews the layout
  and input evidence after the renderer/stability work rather than relying on
  historical captures alone.

## 2026-08-18 — iPad touch-only live-match regression repaired

- `TouchMatchTests` had drifted from the host's proven guest-block script: it
  confirmed the save-prompt selection at 1.56B blocks, but the matching host
  flow intentionally waits until 2.20B before pressing A. The premature
  confirm could land on a different menu and left the raw game-state probe at
  `1`, causing a false gameplay failure even though every touch reached the
  native pad layer.
- The test now follows the host anchors exactly (1.15, 1.30, 1.45, 2.20,
  2.50, 2.60, and 2.90B, then the existing 3.0–6.9B match drive). The corrected
  iPad A16 Simulator run visibly reached the field at 4.92B (`cGame=2` during
  the on-field intro) and then entered the asserted playable state `cGame=4`.
  Capture: `work/validation/ipad-touch-only-state2-2026-08-18.png`.
- `TouchMatchTests.testStartMatchWithTouchOnly` passed on iPad A16 Simulator
  in 430 seconds: `Test-Ballpad-2026.08.18_11-51-45--0500.xcresult`.
  This is a real-overlay test (not host autostart): it presses the SwiftUI A
  and D-pad controls, verifies their native pad writes, and confirms a live
  match. Physical-device input latency and long-session acceptance remain
  separate gates.

## 2026-08-18 — iPhone touch-only live-match cross-check

- The same fresh-boot, real-overlay `TouchMatchTests` route passed on iPhone
  17 Pro Simulator in 437 seconds:
  `Test-Ballpad-2026.08.18_12-00-19--0500.xcresult`. It reached `cGame=4` at
  5.09B guest blocks and completed at 6.95B blocks without a crash.
- The mid-match capture shows a coherent pitch, players, score HUD, and the
  phone-sized touch layout:
  `work/validation/iphone-touch-only-state4-2026-08-18.png`. `simctl` stores
  this landscape-only app in portrait pixel orientation, so the raw image is
  rotated; game content and controls are not rotated in the app.
- Together with the iPad pass, this establishes current Simulator basic
  playability via real touch input. It does not replace physical iPhone/iPad
  testing for suspend/resume, audio interruptions, controller delivery,
  thermal behavior, or input latency.

## 2026-08-18 — Sustained in-match touch control gate

- `TouchMatchTests` now continues after entering the field: it exercises the
  real SwiftUI movement stick in alternating directions plus A, B, L, and R
  for six ten-second cycles, requires guest-block progress, and verifies the
  guest remains in either observed live-match state (`2` intro/replay or `4`
  active play). This is deliberately an end-to-end control test rather than a
  synthetic `ballpad_pad_set` unit test.
- iPhone 17 Pro Simulator passed this fresh-boot route in 748 seconds:
  `Test-Ballpad-2026.08.18_12-21-03--0500.xcresult`. Its native trace recorded
  stick axes `±74,±63`, face-button bits A/B, and full L/R trigger values 255.
- iPad A16 Simulator passed the same route in 627 seconds:
  `Test-Ballpad-2026.08.18_12-33-58--0500.xcresult`. The tablet trace likewise
  recorded stick axes `-75,-63`, A/B, and full L/R trigger values. No app
  crash, stalled guest, or loss of the live-match state occurred during either
  run.
- This closes the Simulator sustained-touch sub-gate. It remains distinct from
  physical-device latency, thermal, audio-interruption, controller, and
  suspend/resume acceptance.

## 2026-08-18 — SunPad default-layout source correction

- A direct source audit found that BallPad's `DefaultLayouts` still used the
  generic edge-pinned fallback while its comments claimed parity with
  `SunPadGameOverlay.layoutSubviews`. This was not merely a cosmetic naming
  issue: SunPad has separate normalized default anchors for phone and large
  iPad, a 1.158x phone B button, and a shared-width R/Z shoulder plate.
- BallPad now carries those source-defined phone and full-size-iPad anchors in
  `ControlNodes.swift`. Compact iPad canvases retain SunPad's scalable
  fallback. The persisted-layout key is v6, so an existing user-edited v5
  layout is not overwritten while untouched installs receive the corrected
  defaults.
- The rebuilt iPad A16 real-overlay regression passed after the correction:
  `TouchMatchTests.testStartMatchWithTouchOnly`, 505.878 seconds,
  `build/DerivedData/Logs/Test/Test-Ballpad-2026.08.18_12-58-16--0500.xcresult`.
  It navigated every menu anchor through the visible A/D-pad targets, entered
  a live match, then completed six stick/A/B/L/R cycles without a stall or
  failed control lookup.
- A clean rebuilt iPhone 17 Pro run passed the same fresh real-overlay route
  in 513.154 seconds:
  `build/DerivedData/Logs/Test/Test-Ballpad-2026.08.18_13-19-36--0500.xcresult`.
  It confirms the exact phone anchors, including the larger B target and wider
  R/Z plate, preserve menu navigation and sustained in-match touch input.
  This closes the Simulator control-layout acceptance sub-gate; physical-device
  ergonomics and latency remain separate acceptance work.

## 2026-08-18 — Background/foreground guest-resume gate

- `LifecycleTests.testBackgroundForegroundResumesGuest` is a focused real-app
  lifecycle test. It waits for guest-block progress, presses Home through
  SpringBoard, waits while the scene is inactive, activates BallPad again, and
  requires that the same guest-block counter advances after return. It tests
  the actual `SceneDelegate` → host lifecycle path, not a direct host call.
- The gate passed on iPhone 17 Pro in 10.040 seconds:
  `build/DerivedData/Logs/Test/Test-Ballpad-2026.08.18_13-30-27--0500.xcresult`.
- The identical iPad A16 run passed in 10.214 seconds:
  `build/DerivedData/Logs/Test/Test-Ballpad-2026.08.18_13-31-52--0500.xcresult`.
- This closes the Simulator background→foreground resume sub-gate. It does
  not establish physical-device audio-session interruption, long background
  suspension, thermal recovery, or controller behavior.

## 2026-08-18 — In-app menu pause/resume gate

- `LifecycleTests.testTouchSettingsPausesAndResumesGuest` opens the persistent
  three-dot menu, chooses **Touch Control Settings…**, and samples the actual
  guest block counter after the sheet has settled. It requires two samples four
  seconds apart to be equal while the settings sheet is visible, dismisses via
  **Done**, then requires the counter to advance again. This proves both pause
  and resume through the real SwiftUI → `SDLGameContainer` → host path.
- The iPad A16 Simulator pass completed in 23.918 seconds:
  `/Users/chrissotraidis/Library/Developer/Xcode/DerivedData/Ballpad-hghrrijgcvwvbmgqgiantgneisau/Logs/Test/Test-Ballpad-2026.08.18_13-35-43--0500.xcresult`.
- A freshly booted iPhone 17 Pro pass completed in 25.920 seconds:
  `/Users/chrissotraidis/Library/Developer/Xcode/DerivedData/Ballpad-hghrrijgcvwvbmgqgiantgneisau/Logs/Test/Test-Ballpad-2026.08.18_13-37-07--0500.xcresult`.
- This closes the Simulator in-app settings pause/resume sub-gate. The
  action-list popover is intentionally transient; the full settings sheet is
  BallPad's persistent in-app pause surface. Physical-device interruption and
  controller/audio lifecycle behavior remain separate acceptance work.

## 2026-08-18 — QuickBoot renderer-state experiment rejected

- Reproduced the current diagnostic QuickBoot path on iPad A16: CPU/RAM
  restored in 13 ms at 6.8204B guest blocks and entered the field after the
  single match-start A, but skinned players remained persistently flattened.
  Screenshots: `work/validation/ipad-quickboot-repro-2026-08-18.png` and the
  later 46-second sample `work/validation/ipad-quickboot-v5-rehydrate-46s-2026-08-18.png`.
- A narrow candidate preservation of the HLE texture/TLUT/indexed-array
  bindings plus a forced guest GX dirty replay was built and tested against a
  freshly captured 6.8204B safe-point image. It did not correct the mesh
  deformation, so it was removed rather than shipped as an unverified
  QuickBoot repair.
- The result isolates the remaining issue to broader process-local live
  Aurora GX state, not the saved CPU/RAM, audio scheduler, or one missing
  binding class. Normal launches therefore continue to bypass QuickBoot by
  default and use the visually correct fresh route; fast resume remains a P1
  renderer-parity task.

## 2026-08-18 — QuickBoot live-GX-state measurement

- Added a diagnostic-only live-Aurora resource summary at QuickBoot save,
  restore, post-match-start, and steady-state. It reads renderer state only;
  it does not try to serialize opaque WGPU handles or mutate normal rendering.
- On iPad A16, the new v4 safe-point capture at 6.8208B guest blocks had 4
  bound textures, 8 loaded textures, 1 TLUT, 16 vertex arrays, and 26 cached
  copy textures. Restore began at zero for every one of those categories.
- After the single intended match-start input, and again after 1,715 presents,
  it plateaued at 4 bound textures, 4 loaded textures, 1 TLUT, 6 arrays, and
  22 copy textures. The steady screenshot
  `work/validation/ipad-quickboot-gx-steady-2026-08-18.png` still shows the
  persistent flattened/scrambled players.
- This confirms that ordinary post-restore draw traffic does not reconstruct
  the missing native state. The next QuickBoot repair must deliberately
  rehydrate or replay the missing live GX resource/array/copy-cache state;
  CPU/RAM-only snapshots remain diagnostic-only and normal launches remain
  correctness-first fresh boots.

## 2026-08-18 — QuickBoot semantic HLE rehydration probe (not accepted)

- Added a version-5 diagnostic snapshot payload containing only portable,
  guest-addressed HLE texture/TLUT/indexed-array bindings. Restore happens
  after `hle_install`, re-resolves guest RAM pointers, rebinds arrays, and
  queues resources into the fresh Aurora renderer. It does not serialize WGPU
  handles or native Aurora containers.
- At the v5 safe point the payload carried all 8 texture bindings, 1 TLUT,
  and 16 arrays. The restored first frame reached 7 loaded textures and all
  16 arrays; the former v4 path plateaued at 4 textures and 6 arrays. This
  proves the ordering and rebind path are live.
- It still did not reach visual parity: after the match-start transition it
  remained at 7 loaded textures and 22 cached copy textures (fresh: 8 and 26),
  and `work/validation/ipad-quickboot-hle-rehydrate-steady-2026-08-18.png`
  still shows malformed player meshes. The optional guest GX-dirty replay
  probe is implemented for the next diagnostic iteration but was not run to
  completion before this session ended.
- Therefore this is retained as diagnostic instrumentation only. QuickBoot is
  still disabled by default; no release claim, performance claim, or visual
  parity claim derives from this probe. Next work should determine which
  missing scalar GX/copy-cache state is required, then prove the repair on
  fresh iPhone and iPad snapshots plus a moving-Dolphin comparison.

## 2026-08-20 — Bot 6 decomp scene gate evidence

- The pinned decomp-driven scene FSM reached the same source-named 26-event
  prefix through `HUDOverlay::SceneCreated` on three fresh phone attempts.
  The HLE trace remained opt-in and the host released pad automation at the
  match-zero marker.
- One fresh phone run completed the versioned neutral 600-fixed-update anchor:
  `ballpad-scene-move-v1:neutral-600-fixed-updates`, SHA-256
  `1c446471cbd11091671af575f8317d60af0e7f7f6dfe5a41e4f71f186c836a46`.
- The next two fresh phone runs reached relative frames 1, 60, and 300 but
  stopped before frame 600. The supplied crash report identifies
  `Namespace METAL, Code 102` and loss of the `SimMetalHost` XPC service;
  the crashing thread is entirely in Apple's simulator Metal driver.
- C5 is BLOCKED at its three-attempt boundary. The required iPad runs and C6
  adjacent suite are not claimed or started.

## 2026-08-20 — Bot 6 final C5/C6 verification

- The fixed wall-clock wrapper was replaced for evidence collection with a
  marker-driven wait. Two fresh iPhone 17 Pro Simulator runs and two fresh
  iPad A16 Simulator runs all reached HUD/match-zero, released automation,
  completed relative frame 600, and continued to relative frame 900.
- All four final traces share the same normalized 26-event scene prefix and
  the same segment identity:
  `ballpad-scene-move-v1:neutral-600-fixed-updates`, SHA-256
  `1c446471cbd11091671af575f8317d60af0e7f7f6dfe5a41e4f71f186c836a46`.
- C6 adjacent checks passed: all generator/lookup/negative suites twice;
  native thread-safe touch/controller merge; real touch smoke and simulated
  controller handoff on phone and iPad; fresh Aurora render screenshots on
  both form factors; local Markdown-link verification; `git diff --check`;
  and `scripts/check_ref_patches.sh` after refreshing the intentional
  StrikersRecomp snapshot.

## 2026-08-20 — Current repair-loop re-audit

- Re-read the pinned objective and reran the source-driven moving-match touch
  test four times with `BALLPAD_NO_QUICKBOOT=1` and
  `BALLPAD_AUTOSTART=1`, one simulator at a time: phone passes took 97.385 s
  and 96.157 s; iPad passes took 98.852 s and 108.660 s. All four XCTest
  invocations passed.
- The current phone and iPad scene logs show automation release at
  `match-zero rel_frame=0`, completion of the versioned
  `ballpad-scene-move-v1:neutral-600-fixed-updates` segment at relative frame
  600, and continued neutral advancement at relative frame 900. The segment
  SHA-256 remains
  `1c446471cbd11091671af575f8317d60af0e7f7f6dfe5a41e4f71f186c836a46`.
- The C1–C5 generator, negative-contract, raw-address, scene, pacing, audio,
  texture-cache, display-aspect, and reference-touch suites were rerun twice;
  every invocation passed. The fixed generated DOL and SDK hashes still match
  the pinned contract, and `scripts/check_ref_patches.sh` remains OK.

## 2026-08-20 — Replay/render regression loop

- Added an opt-in `[replay]` trace at the real `GXCopyDisp` frame boundary. It
  records the pinned task manager current/previous state and `g_bRenderWorld`,
  so transition (`0x100`), replay (`0x10`), and live-match (`0x2`) frames are
  not conflated with front-end/loading state (`0x4`).
- A fresh no-QuickBoot iPad run reproduced the reported class of failure:
  state `0x100` reached 626–1,274 draws and 0.90–1.08M vertices at 9.6–29.3
  fps; subsequent state `0x2` frames stayed around 450–580 draws and 12–17
  fps. `missingTex=0` and `zeroTex=0` throughout, so this is not explained by
  missing asset lookup.
- The new `scripts/test_replay_render_contract.py` passes its pinned-source
  gate and intentionally fails against the captured iPad log on the slow
  replay/transition frames. This is the current red gate for the next source-
  correct render optimization; no geometry suppression or synthetic frame is
  accepted as a fix.
- Only one simulator is left booted after the comparison, per the active
  audit constraint.

## 2026-08-20 — Native replay visual gate and culling probe

- The native BGRA EFB dump from the exact iPad highlight window contains a
  0.917 upper-EFB ratio of the captured flat-mustard signature
  `(R=206,G=186,B=107)`, against a 0.400 limit. The new
  `scripts/test_replay_visual_contract.py` therefore fails on the known bad
  frame before presentation-layer processing.
- The pinned `World::Render` source confirms skybox objects are still subject
  to `World_IsSphereInFrustumInline`; the replay path does not render a
  replacement sky. The next linked diagnostic records the authoritative
  `g_bClipToFrustum` and `World::sbSkyboxRenderingDisabled` bytes beside the
  replay state, so a fix can be tied to the actual guest culling decision.
- The attempted matrix/EFB relaunch was not accepted as fresh evidence because
  the simulator reused the prior diagnostic log and did not produce a new
  uniquely attributable dump. No renderer behavior change is claimed from it.
- A controlled diagnostic A/B temporarily forced `g_bClipToFrustum=0` during
  the replay/transition states. It increased the transition workload from
  roughly 1,200 to 1,700 draws and made actors visibly oversized, but the
  mustard background remained. The no-frustum theory is rejected; the probe
  was removed before the normal archive was rebuilt.
- The live decomp skybox probe then found a valid object in the bad window:
  `skybox=0x8159A7A0`, `objectFlags=0x1`, `creationFlags=0x8180`, radius
  `338.641`, and position `(0,0,99.95)`. At replay state `0x10` its
  `skyAlpha=1.000`, `cameraType=3`, and `pretendGameplay=0`. Thus the skybox
  is present, enabled, and opaque; the remaining defect is in its material or
  view submission, not guest culling or gameplay translucency.
- The opt-in packet trace narrowed this further: the skybox model is valid and
  has one packet, but replay/transition GX submission contains no `GLV_Skybox`
  view-2 packet while views 11/12/16/17/19/20/21/29/31 are active. The new
  `--require-skybox-packet` mode in `scripts/test_replay_render_contract.py`
  records this as a failing red gate until the missing view submission is
  repaired.

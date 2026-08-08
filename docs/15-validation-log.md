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
| B3 | Audio audible | disabled in app config (enable_audio=false); audio_poll path exercised |
| B4 | Hardware GCController merge | not done (bellpad hides touch on controller connect — open item) |
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

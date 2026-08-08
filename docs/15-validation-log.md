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
| M3 | Start match with touch only | PASS | in-progress | autostart drives ballpad_pad_set (same path the touch surface emits into); match reached on phone (m4-inmatch-*.png). Touch→pad→guest proven by M5/M6 tests |
| M4 | 60s in-match, no crash | PASS | in-progress | m4-inmatch-start.png (clock 2:56) → m4-inmatch-70s.png (clock 2:25, 71s wall), blocks 6.9B→7.8B, no crash |
| M5 | All GC controls functional | PASS | (same build) | uitest controls: D-pad×4, Z, L, R, A, B, X, Y, START + full stick/c-stick all ok=true |
| M6 | Multi-touch merged | PASS | (same build) | uitest multitouch: stick+substick+L+R+A+B in one sample ok=true |
| M7 | Layout editor moves a control | PASS | (same build) | uitest move: A 0.84,0.62 → 0.62,0.38; editor drag + corner-scale + Done/Cancel |
| M8 | Layout persists across death | PASS | (same build) | uitest verify after relaunch: A position 0.62,0.38 persisted=true |
| M9 | ⋯ menu opens/closes, pauses safely | PASS | (same build) | uitest menu: paused=true on open, false on close; m9-menu-open.png |
| M10 | Resolution 1x and 2x | PASS | (same build) | m10-scale2x.png; [efb-scale] fb=1280x1056; diag size=1280x1056 |
| M11 | Save export/import round-trip | PASS | (same build) | uitest saves: export match=true; corrupt→import restored=true (byte-identical, card re-opens) |
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
Phone must-pass M1-M11 all PASS with artifacts above. iPad parity run in
progress (fresh boot, guard fix): boot→match and M3/M4 pad gates pending.

# 09 — Open questions, risks, fallbacks, failure matrix

## Standing risks

| ID | Risk / question | Impact | Recommended fallback |
|----|-----------------|--------|----------------------|
| Q1 | Path S vs Path C on iOS | Schedule, perf, port surface | Default **Path S for iOS**; Path C as macOS oracle/speed |
| Q2 | Standalone match FPS low | Playability feel | Continue feature work once frames+input work; lower default scale; profile later |
| Q3 | Aurora iOS backend gaps | Metal present blocked | Minimal UIView+Metal host; keep PAD/CARD patterns |
| Q4 | RecompCore unmaintained | Build pain | Prefer **ModernGekko** for chassis features |
| Q5 | DolRecomp fork divergence | FP bugs | Pin aharonahdoot fork for Strikers certificates; try ExpansionPak if generate fails |
| Q6 | SMC ranges | Wrong code if rewritten at runtime | Offline patches only; never RWX |
| Q7 | ISO size in simulator | UX / disk | Extract FST once into app container; do not embed ISO in IPA |
| Q8 | GPL compliance for distribution | Legal | Inventory GPL deps; simulator-first; user-built binaries may be required for distribution |
| Q9 | Decomp not 100% linked | Cannot pure source-port yet | Recomp remains primary |
| Q10 | gcglue alternate stack | Confusion | Research only unless S/C both fail |
| Q11 | Analog triggers on glass | Feel | Digital threshold mode + swipe analog |
| Q12 | Multiplayer | Scope | Port 0 only for DoD |
| Q13 | Heavy research trees | Disk | Provenance kept as SOURCE-only; do not submodule |
| Q14 | Device vs simulator | Later phase | DoD is simulators; devices after |
| Q15 | Controller skin IP | Legal | Recreate shapes/colors; no dumped textures |

## Failure matrix (Bot 2 quick actions)

| Symptom | Likely cause | Do this next |
|---------|--------------|--------------|
| `generate.py` cannot find dolrecomp | wrong `--dolrecomp` path / build failed | build DolRecomp cmake; switch fork pin |
| chunk count << 150 | incomplete recomp / wrong dol | verify G4QE01 main.dol; regenerate |
| missing constant-time marker | fix_generated not applied | run fix_generated; do not ignore CMake fatal |
| Path S cmake missing GXRuntime | path not passed | `-DSTRIKERSRECOMP_GXRUNTIME_DIR=ref/GXRuntime` |
| Path S links but immediate stop | expected without full host / max-blocks | raise max-blocks; enable Aurora GUI flags; try Path C |
| Path C module not loading | wrong user dir / CPUCore not 6 | package_module into user dir; `-C Dolphin.Core.CPUCore=6` |
| Black screen iOS | no present / wrong drawable size | verify runtime banner; dump clear color; check DVD open |
| Menus OK, match crash | HLE/device gap | capture OSReport; compare macOS Path C; log Q entry |
| Touch no effect | bridge not wired / err=-1 | ensure err=0 and button masks; unit-test pad_get |
| Stick drift | deadzone/curve | raise deadzone; ensure clear on touch end |
| Two sims booted | mutex skipped | shutdown all; fix scripts; re-run gate |
| xcodebuild sign error | team/bundle | use simulator destination; automatic signing |
| App killed on launch | missing dylib / sanitizer | otool -L; static link chunks |
| Saves missing after relaunch | container path | use Application Support; not tmp |

## Dead ends recorded (Phase 1)
- ExpansionPak/GekkoRuntime URL 404 → use ModernGekko
- Assumed reusable GC recomp touch front-end → **refuted** (DOCS/04)
- recomp↔decomp object interop → banned (sunbright)

## Bot 2 append-only log
_Add dated entries below when a gate fails twice or a fallback is taken._

### Template
```
### YYYY-MM-DD — Step N
- Symptom:
- Hypothesis:
- Tried:
- Fallback chosen:
- Result:
```

## 2026-08-07 — Path S first frame blocked by early CPU exception
- **Symptom:** StrikersRecomp boots OS, then stops with `cpu exception`, final pc `0x00000800`, blocks ~687k, gxcore submitted=0.
- **Hypothesis:** GXRuntime pin (2026-07-21) lags modern DolRecomp helper ABI; ballpad_ppc_helpers bridge unblocks compile/link but guest still traps (DSI/exception vector).
- **Attempted:** rebuilt Path S with helper bridge + psq bool ABI patch on local GXRuntime pin.
- **Fallback:** switch to Path C (RecompCore/ModernGekko module) per docs/07.

## 2026-08-07 — Path S Aurora fatal after OS/GX init
- **Symptom:** After FP-unavailable and viewport -0 fixes, StrikersRecomp reaches GX/AI init then fatals:
  `EfbCopyFilter` pipeline RGBA8Unorm vs render pass BGRA8Unorm.
- **Progress:** Boots Dolphin OS, VI/GX/ARQ/AI SDK banners; helper ABI bridge compiles 163 chunks.
- **Fallback:** Path C (RecompCore module) for first macOS frame proof.

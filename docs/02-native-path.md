# 02 — macOS → ARM64 → iOS native path

## Bot 2 executive decisions (do not re-debate)

1. **Generate guest code with DolRecomp** from user ISO (prefer `ref/DolRecomp-aharonahdoot`, fallback ExpansionPak `ref/DolRecomp`).
2. **Use StrikersRecomp** for G4QE01 host policy / symbols integration.
3. **macOS first frame:** try **Path S** (StrikersRecomp + GXRuntime + Aurora). If blocked, **Path C** (module + RecompCore/ModernGekko).
4. **iOS product host:** Path S-shaped (AOT chunks + non-JIT runtime + Metal/Aurora presentation).
5. **Input:** single ABI `ballpad_pad_set` writing PADStatus-compatible state for port 0.
6. **Hard ban on iOS:** Dolphin JIT, RWX pages, runtime code generation, unsigned downloaded executable modules.

Exact step commands live in [07-build-plan.md](07-build-plan.md).


## Target machines
- **Dev host:** Apple Silicon macOS (confirmed arm64; Xcode 26.x available on research machine)
- **Iteration targets:** iOS Simulator + iPadOS Simulator (one at a time)
- **Eventual device:** physical iPhone/iPad (same AOT binary constraints, stricter sandbox)

## Recommended architecture

```
┌─────────────────────────────────────────────────────────────┐
│  ballpad iOS/macOS app shell (SwiftUI or UIKit host)        │
│   • Touch overlay (DOCS/05)  • ⋯ menu (DOCS/06)             │
│   • Layout persistence       • Save import/export           │
└───────────────────────────┬─────────────────────────────────┘
                            │ PADStatus injection / scale / FS
┌───────────────────────────▼─────────────────────────────────┐
│  Host bridge (C/C++/ObjC++)                                 │
│   aurora (SDL3 + Dawn/Metal)  OR  thin UIView Metal surface │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  Runtime                                                    │
│  Path S (preferred for iOS): GXRuntime                      │
│  Path C (macOS accuracy/speed first): ModernGekko module    │
└───────────────────────────┬─────────────────────────────────┘
                            │ call recompiled blocks
┌───────────────────────────▼─────────────────────────────────┐
│  AOT recompiled guest (generated C, compiled arm64)         │
│  from DolRecomp(main.dol) + StrikersRecomp policy           │
└─────────────────────────────────────────────────────────────┘
```

---

## Subsystem matrix

| Subsystem | Current state (upstream) | Work to native ARM64 macOS | Work to iOS Simulator / device |
|-----------|--------------------------|----------------------------|--------------------------------|
| **Language / toolchain** | C11 generated guest + C++ runtime; CMake; AppleClang verified on related stacks | Build generated chunks + host as arm64-apple-macos | Cross-compile to `arm64-apple-ios-simulator` / `iphoneos` via CMake iOS toolchain or Xcodeproj; no MSVC-only code |
| **CPU execution** | AOT C functions + dispatcher; optional interpreter fallback in chassis | Link chunks into app or dylib module | **Must remain AOT**; interpreter fallback OK if pure C (no JIT). Ban `mmap(PROT_WRITE\|PROT_EXEC)`, jit caches, dynamic codegen |
| **Codegen (offline)** | DolRecomp on host from user ISO | Run on macOS only during dev; gitignore `generated/` | Same offline step; ship only compiled arm64 objects (or regenerate in CI with secrets-free ISO path on developer machine) |
| **Renderer** | gxcore + Aurora (WebGPU/Dawn → **Metal** on Apple); chassis uses Dolphin VideoBackends (Metal) | Prefer Aurora Metal path; confirm frame present | Port/enable Aurora iOS backend (upstream claims iOS); if blocked, implement Metal drawable host that consumes gxcore/EFB readback. Resolution scale 1x–4x (DOCS/06) multiplies internal FB |
| **Audio** | DSP stream → SDL3 audio (Aurora/GXRuntime); Dolphin DSP on chassis | Validate callback latency on macOS | Use AVAudioEngine or SDL3 audio on simulator; respect silence session categories; no real-time thread priority assumptions from desktop |
| **Filesystem / DVD** | nod/disc image or extracted FST; path via env `STRIKERS_ISO` etc. | Point at `.local-assets` ISO or extracted tree | iOS sandbox: copy extracted asset tree into app container / Documents; **do not embed retail ISO in IPA**; first-launch import flow |
| **Memory card / saves** | Virtual `.dolcard` / Dolphin GCI-compatible CARD layer in Aurora | Map to `~/Library/Application Support/ballpad/` | Map to app group / Documents; UI for list/load/backup/export (DOCS/06) |
| **Input** | PAD via SDL gamepad/keyboard; PADStatus fields stick/substick/triggers | Keep PADStatus as sole game interface | Touch overlay synthesizes PADStatus each frame; multi-touch; optional MFi/GCController merge |
| **Threading / timing** | VI retrace pacing; some stacks single-thread game (sunbright doctrine); chassis multi-thread Dolphin | Prefer single game thread + host audio/GPU threads | iOS: main thread UI; game loop on high-priority queue; never block main for >frame; CADisplayLink or Metal present pacing |
| **Endian / memory model** | Guest big-endian RAM buffer with typed accessors | Already host-endian safe if using runtime mem_* | Same; watch unaligned access UB on arm64 |
| **Self-modifying code** | DolRecomp lists SMC ranges; Strikers has flagged ranges; patches preferred over RWX | Apply static patches offline | **No runtime code patching of executable pages** on iOS; pre-patch generated C or demote those blocks to interpreter in writable data (not executable) |
| **Networking** | Not required for local matches | n/a | n/a for MVP |

---

## iOS code-signing / JIT / W^X risks (critical)

| Risk | Why it breaks iOS | Mitigation (AOT-style) |
|------|-------------------|------------------------|
| **Dolphin JIT / cached generated machine code** | Needs RWX or W→X transitions disallowed for third-party apps | Never enable JIT cores. Use StaticRecomp/AOT modules only. On iOS builds, compile-time `#error` if JIT backend linked |
| **Runtime recomp / SMC writing executable pages** | `mprotect` RWX denied | Offline DolRecomp patches; interpreter for rare rewritten code operating on non-exec buffers only if unavoidable |
| **Dynamic shader compilers writing executable code** | Some GL paths historically JIT shaders | Prefer Metal/Dawn pipeline cache from pure data blobs; prewarm pipelines; no runtime executable allocation |
| **Provenance-style "enable JIT" hacks** | Requires side-loading entitlements / debugger tricks | Explicitly out of scope; product must run under normal signing in Simulator and device |
| **Loading `.dylib` modules from writable locations** | iOS codesign + library validation | Prefer static link of recomp chunks into main binary **or** embed signed framework; avoid downloading unsigned modules |
| **Large executable + TEXT size** | 163 C chunks can bloat binary / link times | LTO/ThinLTO; merge TUs carefully; `-Os` for device; keep Debug chunk builds for iteration |

### Explicit rule for Bot 2
> If a dependency requires writable+executable memory at runtime, it is **blocked for iOS**. Replace with offline codegen or pure interpreter fallback. No exceptions for "just the simulator" — Simulator must mirror the constraint so device port does not collapse.

---

## Path decision guide

| Criterion | Path S: GXRuntime + Aurora | Path C: ModernGekko/RecompCore |
|-----------|----------------------------|--------------------------------|
| Full-speed match today | No (perf WIP) | Yes on macOS |
| iOS porting surface | Smaller, Aurora already lists iOS | Huge Dolphin surface |
| Accuracy referee | Uses same CPU semantics; can still A/B vs chassis on macOS | Built-in lockstep |
| License | GPL-3.0-or-later runtime | GPLv2+/Dolphin-derived |
| Recommendation | **Primary iOS target** | **macOS milestone + accuracy oracle** |

**Bot 2 sequencing:** achieve macOS arm64 frame+input on Path C *or* S first (whichever boots faster in-tree), then freeze guest/HLE, then port host to iOS Simulator on Path S.

---

## Concrete work packages (for build plan)

1. **Offline generate:** `python3 tools/generate.py --iso <local>` using StrikersRecomp + DolRecomp pin; run `fix_generated.py`.
2. **macOS native link:** CMake arm64 build of host + chunks; present one frame; capture screenshot.
3. **PAD inject API:** stable C ABI `ballpad_pad_set(port, PADStatus)` called from Swift touch layer.
4. **iOS host app:** Xcode project wrapping runtime; Metal view; no JIT.
5. **Asset import:** document-based ISO/extract import; memory-card folder.
6. **Perf pass:** only after playable input (profile gxcore/FIFO).

## Gate status (G2)
- [x] Every subsystem listed with current state + ARM64 work
- [x] JIT/RWX/code-signing risks flagged with AOT mitigations

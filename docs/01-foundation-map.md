# 01 — Foundation map

Research date: 2026-08-07. Commits and licenses recorded in each `ref/*/SOURCE.md` and [ref/INDEX.md](../ref/INDEX.md).

## Executive recommendation

**Primary playable path (short):**  
`local ISO → DolRecomp → generated C → StrikersRecomp host policy → runtime` where runtime is either:

1. **Standalone path:** [GXRuntime](../ref/GXRuntime) + [aurora](../ref/aurora) (lighter, JIT-free by design, iOS-friendlier substrate), or  
2. **Chassis path:** [ModernGekko](../ref/ModernGekko) / [RecompCore](../ref/RecompCore) StaticRecomp module loaded into a Dolphin-derived host (full-speed today on macOS; heavier to port to iOS Simulator).

**Symbols / HLE quality:** [smstrikers-decomp](../ref/smstrikers-decomp) is a hard dependency for high-quality SDK intercept tables even if we never ship a matching rebuild.

**Do not pursue as foundation:** pure matching decomp→source port alone (linked ~78% is excellent for research but not a complete shippable game loop without years of remaining work), or recomp↔decomp object interop hybrids (banned by sunbright lessons).

---

## Project catalog

### A. Strikers-specific

| Project | Provides | Maturity | License | Build system | Hard dep? |
|---------|----------|----------|---------|--------------|-----------|
| **smstrikers-decomp** | Matching C++ decomp of G4QE01; symbols; SDK layout knowledge | Code **94.94%**, Data **96.84%**, Linked **77.96%**, Fuzzy **99.72%** (decomp.dev shields) | CC0-1.0 | `configure.py` + ninja + Metrowerks (wine on macOS); dtk | **Yes** for symbols/HLE; long-term oracle |
| **StrikersRecomp** | ISO→generated C pipeline, G4QE01 HLE/MMIO policy, RecompCore module packaging, standalone app glue | Boot→menus→full matches verified under RecompCore; standalone ~playable but slower | GPL-3.0-or-later | CMake; `tools/generate.py` | **Yes** (game glue) |
| **smstrikers-viewer** | Asset inspection (GLT textures) | Partial texture viewing | See LICENSE | CMake/OpenGL | No |
| **strikers-recomp-gcglue** | Alternate native scaffold + match screenshots via GCGlue | In-match frames demonstrated; HW accuracy WIP | Undeclared in tree | CMake + Python gcglue | No (prior art) |

### B. Recompilation toolchain (GameCube)

| Project | Provides | Maturity | License | Build system | Hard dep? |
|---------|----------|----------|---------|--------------|-----------|
| **DolRecomp** (ExpansionPak) | PPC→C static recompiler (236 opcodes), DOL/REL/RPX | Active community; multi-title demos | GPL-3.0 | CMake/C11 | **Yes** (codegen) |
| **DolRecomp-aharonahdoot** | FP/ABI fixes pin for Strikers lockstep certificates | Fork pending upstream merge | GPL-3.0 | CMake | Pin when regenerating Strikers modules |
| **RecompCore** | Dolphin fork + StaticRecomp core=6, module ABI v2, lockstep referee | Strikers 99.9% native / 0 divergences; author marks unmaintained | GPLv2+ chassis | CMake/Ninja, Metal on macOS | Path-dependent |
| **GXRuntime** | Standalone CPU/devices/gxcore + Aurora backend | Matches boot→match; perf WIP | GPL-3.0-or-later | CMake | Path-dependent (preferred for iOS lightness) |
| **ModernGekko** | Maintained runtime absorbing RecompCore approach + mods | Active ExpansionPak | Dolphin-derived LICENSE | CMake; Metal/Vulkan | Path-dependent (preferred maintained chassis) |
| **ModernGekko-Template** | Bootstrap Makefile/submodules for any title | Template | Template | Make+CMake | No |
| **gcglue** | Config-driven recomp SDK/runtime probe | Experimental native execute/play | MIT | Python + CMake | No |

### C. Decomp tooling & prior art

| Project | Provides | Maturity | License | Build system | Hard dep? |
|---------|----------|----------|---------|--------------|-----------|
| **decomp-toolkit (dtk)** | Disc/DOL analysis & split | Production for GC decomp scene | Apache-2.0 OR MIT | Rust binary | Decomp path |
| **dtk-template** | Project skeleton | Stable | See LICENSE | Python/ninja | No |
| **sms-decomp (doldecomp/sms)** | Super Mario Sunshine matching decomp | Code ~35% / Linked ~14% | CC0-1.0 | dtk pipeline | No |
| **sunbright** | SMS native (Aurora) + recomp architecture lessons | Active experimental dual-runtime doctrine | Undeclared | CMake | No (architecture gold) |
| **aurora** | Source-level GC/Wii host: GX (Metal/Vulkan/D3D12 via Dawn), PAD, DVD, CARD, SDL3; **iOS/tvOS/Android listed** | Powers completed ports (e.g. Dusklight) | MIT | CMake | **Likely yes** for iOS host layer |

### D. Cross-ecosystem prior art (N64 recomp & iOS UX)

| Project | Provides | Maturity | License | Hard dep? |
|---------|----------|----------|---------|-----------|
| **N64Recomp** | Static recomp methodology | Mature | See LICENSE | No |
| **N64ModernRuntime** | Host callback model for input/audio/graphics | Mature | See COPYING | No |
| **Zelda64Recomp** | Product UX bar (menus, input lag, widescreen) | Shipped | GPL family | No |
| **RecompFrontend** | Desktop menus + SDL2 input for N64 recomps | Active | Undeclared at root | No |
| **Provenance** | iOS virtual controllers, skins, layout profiles; JIT failure UX | Shipped App Store | See LICENSE.md | No (UX reference) |
| **DeltaCore** | Controller skin framework | Mature | See repo | No |

---

## Dependency graph (recommended)

```
User ISO (local only)
    │
    ├─► DolRecomp ──► generated C chunks (local, gitignored)
    │                      │
    │                      ├─► StrikersRecomp host (HLE/MMIO/audio policy)
    │                      │         │
    │                      │         ├─► Path S: GXRuntime + aurora  ──► iOS/iPadOS app shell
    │                      │         └─► Path C: ModernGekko/RecompCore module ──► macOS first, then thin host
    │                      │
    └─► smstrikers-decomp symbols ──► sdk_symbols.inc / HLE map
```

## Hard vs soft dependencies (gate summary)

**Hard for any successful Strikers native playable build:**
1. Legal local ISO (G4QE01)
2. DolRecomp (or pinned fork) for AOT C
3. StrikersRecomp (or equivalent game policy)
4. One runtime: GXRuntime **or** ModernGekko/RecompCore
5. Host presentation layer capable of Metal on Apple platforms (Aurora strongly preferred for iOS)

**Soft but high value:**
- smstrikers-decomp (symbols quality)
- sunbright / Zelda64Recomp / Provenance (architecture & UX patterns)
- gcglue alternate stack (fallback experiments)

## Dead ends / non-starters
- **GekkoRuntime** repo name 404; lineage lives in ModernGekko.
- **Recomp↔decomp object flipping** (sunbright): structurally impossible; ban for Bot 2.
- **Relying on Dolphin JIT on iOS**: code-signing / W^X forbids RWX JIT without special entitlements not available to normal apps.
- **Assuming an open GC recomp touch front-end exists**: research finds none (see DOCS/04).

## Gate status (G1)
- [x] Relevant repos cloned under `ref/` with `SOURCE.md` (commit + license)
- [x] This document lists what each provides, maturity, license, build system, hard-dep status

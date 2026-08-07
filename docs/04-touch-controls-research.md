# 04 — Touch-control front-end research

## Verdict

**Build from scratch** for ballpad.

There is **no reusable open-source touch-control overlay** purpose-built for GameCube static recompilation ports (and nothing that ships a faithful, editable GameCube-skinned layout for iOS/iPadOS). Closest ecosystems are either **desktop recomp front-ends** (no touch) or **iOS emulator skins** (wrong console semantics / heavy app coupling).

---

## Evidence

### GameCube recomp / decomp hosts
| Source | Touch overlay? | Notes |
|--------|----------------|-------|
| StrikersRecomp + GXRuntime Aurora backend | No | Keyboard→PAD bindings in `aurora_backend.cpp`; SDL gamepad |
| ModernGekko / RecompCore | No | Desktop Dolphin-style input |
| gcglue play mode | No | Scripted pad0 / live desktop pad |
| aurora PAD layer | Virtual status merge exists | Supports combining sources into PADStatus — **good injection seam**, not a UI |
| sunbright | No mobile UI | Architecture prior art only |

### N64 recomp ecosystem (closest recomp UX)
| Source | Touch overlay? | Notes |
|--------|----------------|-------|
| Zelda64Recomp | No | Controller/keyboard/mouse/gyro; Steam Deck gyro-as-mouse |
| RecompFrontend | No | SDL2 input + RmlUi menus for desktop recomp projects |
| N64ModernRuntime | No | Host must supply controller callbacks |

### iOS emulator / skin ecosystems (closest touch UX)
| Source | Reusable for us? | Notes |
|--------|------------------|-------|
| Provenance VirtualController + skins | **Reference only** | Mature multi-touch skins, profiles; not GC recomp; large app; different input ABI |
| Delta / DeltaCore skins | **Reference only** | `.deltaskin` layout system; no Strikers/recomp integration |
| RetroArch overlays | **Reference only** | Ubiquitous overlay JSON/PNG model; not cloned fully (size); still not GC-recomp-native |

### Search outcomes (2026-08-07)
- No repository provided a drop-in "GameCube recomp iOS touch front-end".
- `RecompFrontend` is the best open recomp front-end library and is still desktop-oriented.
- iOS JIT discussions in Provenance reinforce avoiding emulator JIT patterns entirely.

---

## What we *can* reuse as ideas (not code dependencies)

1. **PADStatus as the only game-facing input struct** (Aurora/`dolphin/pad.h`): buttons bitfield, stickX/Y, substickX/Y, triggerLeft/Right.
2. **Virtual + physical merge**: Aurora already merges virtualStatus with device status — touch should feed the virtual path; MFi controllers feed physical.
3. **Skin layout JSON**: Provenance/Delta pattern of declarative frames per control + device size class.
4. **Edit mode UX**: long-press / drag handles / per-control scale from mobile emulators.
5. **Menu systems**: Zelda64Recomp/RecompFrontend for information architecture of settings (not visuals).

---

## From-scratch component inventory

| Component | Responsibility | Platform |
|-----------|----------------|----------|
| `TouchControlSurface` | Full-screen passthrough view above Metal/game view; hit-test controls | SwiftUI/UIKit |
| `ControlNode` | One control: type, frame, z-index, opacity, deadzone, scale | Model |
| `AnalogStickNode` | 2-axis knob with travel radius → s8 stick axes | View+Model |
| `CStickNode` | Same as stick → substick axes | View+Model |
| `DPadNode` | 4-way with optional diagonals → button bits | View+Model |
| `FaceButtonCluster` | A/B/X/Y with GC colors/shapes | View |
| `TriggerNode` | Analog L/R (vertical drag or pressure-style slide) → u8 triggers + digital threshold | View |
| `ZButton` / `StartButton` | Digital | View |
| `LayoutStore` | Codable layouts per `UIUserInterfaceIdiom` + screen size class; iCloud optional later | Persistence |
| `LayoutEditor` | Drag, pinch-scale, snap guides, reset defaults, show/hide | UI mode |
| `PadStatusAssembler` | Multi-touch sample → clamped PADStatus each display link tick | Core |
| `Haptics` | Light taps on digital edges (optional) | UIKit |
| `SkinAssets` | Vector/PDF or PDF+PNG GameCube chrome (original art recreation, **not ripped**) | Assets |
| `HitPolicy` | Overlapping controls, thumb slip recovery, edge guards for system gestures | Logic |
| `LatencyMeter` | Debug overlay: touch→PAD→frame age | Debug |

### Non-goals for v1 components
- Gyro aiming, touch-look camera (not core to Strikers field play)
- Network multiplayer touch sync
- Full HTML/CSS UI toolkit (keep native)

## Gate status (G4)
- [x] Verdict with evidence
- [x] Component inventory for from-scratch overlay

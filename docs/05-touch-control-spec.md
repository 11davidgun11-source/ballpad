# 05 — Touch control & UX specification

## Product goal
Make Super Mario Strikers on iPhone/iPad feel like a **world-class portable GameCube controller**: recognizable chrome, full analog fidelity, low latency, and layouts players can reshape for their hands.

## Scope
- On-screen controls for **player port 0** (local single-player MVP).
- Optional merge with hardware `GCController` / MFi when present (hardware wins on conflict for axes if user enables "prefer controller").
- Does **not** replace the ⋯ system menu (DOCS/06).

---

## 1. Control inventory (full GameCube set)

| Control ID | Type | GameCube mapping | Visual |
|------------|------|------------------|--------|
| `stick` | Analog 2D | Main stick (`stickX`, `stickY`) | Grey octagonal well + black knob |
| `cstick` | Analog 2D | C-stick (`substickX`, `substickY`) | Yellow well + yellow knob |
| `dpad` | Digital hat | `LEFT/RIGHT/UP/DOWN` bits | Grey cross |
| `a` | Digital | `A` | Large **green** circle |
| `b` | Digital | `B` | Smaller **red** circle (offset) |
| `x` | Digital | `X` | Grey lozenge/capsule |
| `y` | Digital | `Y` | Grey lozenge/capsule |
| `l` | Analog trigger | `triggerLeft` (+ digital L threshold) | Purple shoulder wedge |
| `r` | Analog trigger | `triggerRight` (+ digital R threshold) | Purple shoulder wedge |
| `z` | Digital | `Z` | Purple rectangular shoulder |
| `start` | Digital | `START` | Grey pill in center cluster |

All controls are independently **show/hide**, **reposition**, and **resize** in edit mode.

---

## 2. Default layouts

Coordinates are normalized **0–1000** on the short and long axes of the **safe area** (not full screen), origin top-left of safe area. Convert to points at runtime.

### 2.1 iPhone landscape (primary phone play)
- `stick`: center (160, 620), base diameter 220
- `cstick`: center (300, 780), diameter 140
- `dpad`: center (160, 380), diameter 150
- Face cluster anchored lower-right:
  - `a`: (840, 620) d=150
  - `b`: (760, 700) d=110
  - `x`: (920, 540) d=100
  - `y`: (780, 520) d=100
- `l`: top-left edge plate (120, 90) size 200×90
- `r`: top-right edge plate (880, 90) size 200×90
- `z`: near R, (880, 200) size 140×70
- `start`: (500, 120) size 100×50

### 2.2 iPad landscape
Same topology scaled ~1.15–1.3× with more margin from bezels; sticks sit lower to keep thumbs natural on large glass.

### 2.3 Portrait (supported but secondary)
Move face cluster mid-right; stick mid-left; triggers become side rails; show "portrait is secondary" tip once.

Ship **factory defaults** per `(idiom, orientation, sizeClass)`. Users may save named slots.

---

## 3. Skin (GameCube fidelity)

### 3.1 Non-negotiable visual cues
- **A green**, **B red**, **X/Y grey**, **C-stick yellow**, **L/R/Z purple**, charcoal body chrome optional behind clusters.
- Button silhouettes approximate official GC controller (circular A, smaller circular B, axis-aligned X/Y).
- Semi-transparent when idle (default fill alpha **0.55**), rise to **0.85** on touch.
- Never use ripped Nintendo textures; recreate with vector shapes / SF Symbols only as secondary icons (prefer custom shapes).

### 3.2 Themes
- `classic` (default): GC colors
- `high-contrast`: stronger outlines for outdoor readability
- `minimal`: monochrome outlines for streamers/screenshots

---

## 4. Input semantics

### 4.1 Sampling
- Drive from `CADisplayLink` (or Metal present callback) at display refresh.
- Multi-touch: each active `UITouch` assigned to at most one control via highest-priority hit test (faces > triggers > sticks > dpad when overlapping).
- Touch capture sticky until lift even if finger slides off control bounds (except edit mode).

### 4.2 Analog sticks
- Deadzone default **0.12** of radius (user 0.05–0.30).
- Response curve: `y = x^γ` with γ default **1.2** (user 1.0–1.8).
- Output clamp to **[-127, 127]** as `s8` matching PADStatus.
- Visual knob follows finger clamped to well; released knob springs to center in ≤50ms animation (input zeros immediately on lift).

### 4.3 Analog triggers
- Interaction: vertical slide inside plate **or** force-touch if available; default slide.
- Rest=0, full travel=255 (`u8`).
- Digital L/R bit set when value ≥ **180** (GC-style threshold; user adjustable 128–220).
- Optional "hair-trigger" preset for sprint/charge style inputs if game uses digital more than analog.

### 4.4 D-pad
- 8-way with corner hysteresis; inner dead circle ignores accidental brush.
- Diagonals set two bits simultaneously.

### 4.5 Latency budget
| Stage | Budget |
|-------|--------|
| Touch → PADStatus assemble | ≤ 2 ms |
| PADStatus → guest visible | same frame if possible, else next |
| End-to-end touch→pixels | aim ≤ 2 frames @ 60Hz |

Debug overlay (secret: 5-tap start) shows p95 touch age.

### 4.6 Gesture conflicts
- Disable system edge swipe back over active control zones.
- Two-finger system gestures should not steal exclusive stick touches (prefer `.delaysTouchesBegan = false` careful tuning).
- Pinch reserved for edit mode only when editor enabled.

---

## 5. Edit / layout mode

### Enter
- ⋯ menu → **Edit controls**, or long-press Start for 0.8s when enabled in settings.

### Capabilities
- Drag any control by body
- Pinch or corner handle to scale (0.6×–1.8× per control)
- Group select (lasso) for face cluster / shoulder group
- Snap to safe-area margins and alignment guides
- Nudge with D-pad when a control is selected (0.5pt steps with shift-equivalent longer press)
- Toggle visibility per control
- Reset control / reset layout / load factory for device
- Live playtest toggle (half-transparent editor chrome while still sending input)

### Exit
- **Done** saves; **Cancel** reverts to snapshot taken at enter.

---

## 6. Persistence

```json
{
  "version": 1,
  "deviceClass": "iPhoneLandscape",
  "theme": "classic",
  "controls": [
    {"id": "a", "x": 840, "y": 620, "scale": 1.0, "hidden": false, "alpha": 0.55}
  ],
  "deadzone": 0.12,
  "stickCurve": 1.2,
  "triggerDigitalThreshold": 180
}
```

- Store in Application Support: `Layouts/<deviceClass>/<slot>.json`
- Autosave on editor Done; keep `Autosave` + 3 user slots MVP
- Migrate by `version` field

---

## 7. Mapping to game controller interface

### C ABI (host bridge)

```c
typedef struct BallPadStatus {
  uint16_t button;      // PAD bitfield
  int8_t   stickX, stickY;
  int8_t   substickX, substickY;
  uint8_t  triggerLeft, triggerRight;
  uint8_t  analogA, analogB; // usually 0
  uint8_t  err;         // 0 = wired present
} BallPadStatus;

void ballpad_pad_set(int port, const BallPadStatus* status);
void ballpad_pad_clear(int port);
```

Bit definitions match Dolphin/Aurora `PAD_BUTTON_*` / `PAD_TRIGGER_*`.

### Merge policy
1. Start from zeroed status each frame.
2. Apply touch assembler.
3. If hardware controller enabled, OR digital bits; for axes take max-abs from either source unless "hardware exclusive" mode.

### Port assignment
MVP: port 0 only. Ports 1–3 zeroed (`err = no controller`) unless future multiplayer.

---

## 8. Accessibility
- Minimum touch target 44×44 pt after scale clamp
- Left-handed layout preset (mirror)
- Colorblind theme (shapes + labels, not color alone)
- Reduce transparency toggle

## 9. Acceptance criteria
- All 11 control IDs functional in a match
- Reposition+resize persists across cold launch
- Multi-touch: sprint (trigger) + steer (stick) + pass (A) simultaneous
- No stuck bits after all fingers lift
- Layout works on both phone and tablet simulators

## Gate status (G5)
- [x] Layout, skin, edit mode, persistence, mapping specified


---

## 10. Bot 2 implementation order (binding)

1. **Step 9 MVP:** `stick`, `a`, `b`, `start`, `l`/`r` as digital (threshold 255/0 or 0/220).
2. Wire every sample through `ballpad_pad_set(0, &status)` on the display link **before** guest PADRead for that frame (or into the buffer PADRead copies).
3. Set `err = 0` whenever the virtual controller is active; otherwise games treat port as disconnected.
4. On all touches ended: `ballpad_pad_clear(0)` or zero struct with `err=0` still present if we want "always plugged in" virtual pad (preferred: always present).
5. **Step 10:** add remaining controls + classic skin.
6. **Step 11:** editor + persistence JSON.
7. Do not block on haptics or themes beyond `classic`.

### Frame loop contract
```
CADisplayLink / present callback:
  touchSurface.sample(into: &status)
  ballpad_pad_set(0, &status)
  runtime.frame()  // guest runs; PADRead sees status
```

### Hit-testing priority (high → low)
face buttons and shoulders → sticks → dpad → passthrough (none)

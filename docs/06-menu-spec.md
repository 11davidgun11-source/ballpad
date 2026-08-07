# 06 — In-app menu specification

## Trigger & chrome
- **Control:** top-right **⋯** (ellipsis) button, 36–44 pt hit target, 12 pt margin from safe-area top/trailing.
- **Appearance:** frosted semi-transparent (material `ultraThin` / custom blur, overall panel opacity ~0.82), light text, dark scrim 0.35 when open.
- **Behavior:**
  - Tap ⋯ toggles menu.
  - Tap scrim or press **Resume** closes.
  - Opening menu **pauses guest** (freeze VI pacing / stop simulation clock) when runtime allows; if hard pause unsupported, show warning and dim audio.
  - Menu consumes touches; game view does not receive PAD while open.
  - Keyboard: Esc closes (macOS/Catalyst future).

## Information architecture

```
⋯ Menu
├── Resume
├── Resolution
│   ├── 1x
│   ├── 2x
│   ├── 3x
│   └── 4x
├── Saves
│   ├── Current card
│   ├── List slots / GCI files
│   ├── Load / Import
│   ├── Backup / Export
│   └── Delete (confirm)
├── Controls
│   ├── Edit layout…
│   ├── Layout slots
│   ├── Deadzone / curves
│   └── Prefer hardware controller
├── Display
│   ├── Aspect: Native / 16:9 / Stretch
│   ├── Integer scale (on/off)
│   └── Show touches (debug)
├── Audio
│   ├── Master volume
│   ├── Mute
│   └── Audio backend info
├── Graphics
│   ├── VSync / cadence
│   ├── Show FPS
│   └── Renderer info
├── Controllers
│   ├── Port status
│   └── Pair / reorder (future)
└── About / Legal
    ├── Open-source licenses
    └── "Provide your own game copy"
```

---

## Panel specs

### Resolution boosting (required)
- Options **1x / 2x / 3x / 4x** relative to the game's native internal framebuffer (GC EFB baseline **640×528** progressive-equivalent; treat 1x as runtime's default internal scale).
- Changing scale:
  1. Persist setting immediately.
  2. Recreate/resize internal render targets at next frame boundary.
  3. Keep window/view aspect; letterbox as needed.
- Show estimated cost tip: "4x is demanding on older devices".
- Default: **2x** on iPad Pro-class, **1x** on small phones until perf gate passes.

### Save file management (required)
- Backing store: virtual memory card directory in app container (`Saves/CardA/`).
- List entries with name, timestamp, size.
- **Import:** Files picker for `.gci`, `.raw`, `.dolcard` as supported by runtime.
- **Export/Backup:** share sheet / Files export of selected save or whole card image.
- **Load:** if runtime needs reboot to apply card, prompt "Reset to apply save?".
- Never commit saves to git; exclude from project templates.

### Controls entry (required)
- Button **Edit layout…** flips into DOCS/05 editor and closes menu.
- Quick toggles: hide unused controls, opacity, left-handed preset.

### "Other crap" options (required slot)
Minimum viable extras:
- Aspect ratio modes
- Audio mute/volume
- FPS overlay
- Hardware controller prefer
- Reset all settings

---

## Visual behavior
- Panel width: 320 pt phone, 380 pt pad; max height 80% of safe area; scrolls.
- Rows: 44 pt min height; segmented control for 1x–4x.
- Destructive actions (delete save, reset layouts) use confirmation.

## State persistence
`UserDefaults` / app settings JSON:

```json
{
  "renderScale": 2,
  "aspectMode": "native",
  "masterVolume": 1.0,
  "preferHardwareController": true,
  "showFps": false
}
```

## Analytics / logging (local only)
Log menu actions to app log for Bot 2 validation (`[menu] scale=3`).

## Acceptance criteria
- ⋯ visible above gameplay and editor
- 1x–4x each change internal resolution (verified by log + screenshot sharpness)
- Save import/export round-trips a test file
- Edit layout reachable
- Pause or safe mute while open

## Gate status (G6)
- [x] Trigger, transparency/behavior, panels including scaler + saves specified


---

## Bot 2 implementation order (binding)

1. ⋯ button + panel chrome + Resume/close + scrim.
2. Pause or mute-on-open (best available runtime hook); log if hard pause unsupported.
3. Resolution segmented control writing `renderScale` 1–4; apply next frame.
4. Controls → Edit layout entry (calls into DOCS/05 editor).
5. Saves panel with list + export/import (even if only file-level at first).
6. Options stubs (aspect, volume, fps) last.

### Runtime hooks to implement in `host/`
```c
void ballpad_set_render_scale(int scale_1_to_4);
int  ballpad_get_render_scale(void);
void ballpad_set_paused(bool paused);
bool ballpad_export_save(const char* dest_path);
bool ballpad_import_save(const char* src_path);
```

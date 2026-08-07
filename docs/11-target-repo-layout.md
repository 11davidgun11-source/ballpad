# 11 — Target repo layout (Bot 2 creates this)

Phase 1 left research in `ref/` and plans in `DOCS/`. Bot 2 creates first-party product structure:

```text
ballpad/
  DOCS/                         # plans (exists)
  ref/                          # research clones (exists; do not treat as product code)
  .local-assets/                # ISO only (gitignored)
  .gitignore                    # exists
  app/                          # CREATE — Xcode iOS/iPadOS app
    Ballpad.xcodeproj
    Ballpad/
      App.swift / AppDelegate
      GameHostView.swift        # hosts Metal/SDL view + overlays
      Touch/
        TouchControlSurface.swift
        ControlNodes.swift
        LayoutStore.swift
        LayoutEditor.swift
      Menu/
        OverflowMenuView.swift
        SettingsStore.swift
      BridgingHeader.h
  host/                         # CREATE — C/C++ runtime bridge
    include/
      ballpad_pad.h
      ballpad_runtime.h
    src/
      ballpad_pad.c
      ballpad_runtime.cpp       # init/shutdown/frame; wraps GXRuntime or chassis
      ballpad_saves.cpp
    CMakeLists.txt              # optional; or pure Xcode refs
  scripts/
    sim_mutex.sh
    sim_smoke.sh
    generate_strikers.sh
    prove_step.sh
  work/                         # CREATE — gitignored local builds
    strikers/generated/         # DolRecomp output
    strikers/build-s/
    dolphin-user/
  build/                        # gitignored
    proofs/
    sim-logs/
    DerivedData/
    env.sh
  vendor/                       # OPTIONAL pins (only if not using ref/ paths)
```

## Path policy for dependencies
**Prefer** compiling against `ref/StrikersRecomp`, `ref/GXRuntime`, `ref/DolRecomp*` via absolute CMake path args so research pins stay reproducible.

**Avoid** copying giant trees into `vendor/` unless build system requires it.

**Never** commit `work/strikers/generated/main.dol` or ISO.

## Required header: `host/include/ballpad_pad.h`

```c
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BallPadStatus {
  uint16_t button;
  int8_t stickX;
  int8_t stickY;
  int8_t substickX;
  int8_t substickY;
  uint8_t triggerLeft;
  uint8_t triggerRight;
  uint8_t analogA;
  uint8_t analogB;
  int8_t err; /* 0 = PAD_ERR_NONE, -1 = no controller */
} BallPadStatus;

/* port: 0..3. MVP uses port 0 only. */
void ballpad_pad_set(int port, const BallPadStatus* status);
void ballpad_pad_clear(int port);
void ballpad_pad_get(int port, BallPadStatus* out); /* for tests */

#ifdef __cplusplus
}
#endif
```

Button masks must match Aurora/Dolphin `PAD_BUTTON_*` (see DOCS/07 Step 5 table).

## Required script: `scripts/sim_mutex.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
sim_shutdown_all() { xcrun simctl shutdown all >/dev/null 2>&1 || true; }
sim_boot() {
  local udid="$1"
  sim_shutdown_all
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b
}
sim_only_one_booted() {
  local n
  n=$(xcrun simctl list devices | grep -c Booted || true)
  if [ "${n:-0}" -gt 1 ]; then
    echo "ERROR: $n simulators booted" >&2
    return 1
  fi
}
```

## Required script: `scripts/generate_strikers.sh`
Wrap DOCS/07 Step 2 commands; exit non-zero if gate predicates fail (chunk count, marker, sdk_symbols).

## Env file: `build/env.sh`
```bash
export REPO_ROOT=...
export STRIKERS_ISO=...
export BALLPAD_BUNDLE_ID=com.ballpad.strikers
export BALLPAD_PHONE_UDID=...
export BALLPAD_PAD_UDID=...
export BALLPAD_UDID=$BALLPAD_PHONE_UDID
export BALLPAD_PATH_CHOICE=S   # or C after Step 3
```

## What not to put in the app bundle by default
- Full retail ISO (too large; legal/distribution risk)
- Prefer extracted filesystem tree imported by the user at runtime, or developer-only container seeding from `.local-assets` during sim testing (still gitignored)

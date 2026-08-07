# 03 — Simulator harness (iOS / iPadOS)

## Environment (research host baseline)
- macOS arm64
- Xcode with `xcodebuild` + `xcrun simctl`
- Device types include modern iPhone and iPad runtimes (re-resolve UDIDs on each machine)

## Mutex rule (non-negotiable)

**Only one simulator device may be Booted at a time.**

```bash
# REQUIRED before every boot
xcrun simctl shutdown all || true
xcrun simctl list devices | grep -i Booted || echo "OK: no booted devices"
```

Never start iPhone and iPad simulators in parallel for this project.

## Standard helper (`scripts/sim_mutex.sh`)

Bot 2 must create this script (content also in DOCS/11):

```bash
#!/usr/bin/env bash
set -euo pipefail
sim_shutdown_all() { xcrun simctl shutdown all >/dev/null 2>&1 || true; }
sim_boot() {
  local udid="$1"
  sim_shutdown_all
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b
  local n
  n=$(xcrun simctl list devices | grep -c Booted || true)
  if [ "${n:-0}" -ne 1 ]; then
    echo "mutex broken: Booted count=$n" >&2
    return 1
  fi
}
```

---

## Device selection

```bash
xcrun simctl list devices available
xcrun simctl list devices available -j > build/proofs/simdevices.json
```

Pick one phone UDID and one pad UDID. Prefer stock devices over custom-named ones.

```bash
export BALLPAD_PHONE_UDID="<iphone-udid>"
export BALLPAD_PAD_UDID="<ipad-udid>"
export BALLPAD_UDID="$BALLPAD_PHONE_UDID"
export BALLPAD_BUNDLE_ID="com.ballpad.strikers"
```

Persist into `build/env.sh`.

---

## Canonical sequence

### 1) Mutex + boot
```bash
source scripts/sim_mutex.sh
sim_boot "$BALLPAD_UDID"
# optional GUI:
open -a Simulator --args -CurrentDeviceUDID "$BALLPAD_UDID" || true
```

### 2) Build
```bash
xcodebuild   -project app/Ballpad.xcodeproj   -scheme Ballpad   -configuration Debug   -destination "id=$BALLPAD_UDID"   -derivedDataPath build/DerivedData   build
```

### 3) Install
```bash
APP=$(find build/DerivedData/Build/Products -name "Ballpad.app" -type d | head -1)
test -d "$APP"
xcrun simctl install "$BALLPAD_UDID" "$APP"
```

### 4) Launch + logs
```bash
mkdir -p build/sim-logs
LOG=build/sim-logs/$(date +%Y%m%d-%H%M%S).log
xcrun simctl launch --console-pty --terminate-running-process   "$BALLPAD_UDID" "$BALLPAD_BUNDLE_ID" 2>&1 | tee "$LOG"
```

Non-blocking variant:
```bash
xcrun simctl launch --terminate-running-process "$BALLPAD_UDID" "$BALLPAD_BUNDLE_ID"
xcrun simctl spawn "$BALLPAD_UDID" log stream --level debug   --predicate "processImagePath CONTAINS "Ballpad""   > build/sim-logs/stream.log 2>&1 &
```

### 5) Screenshot
```bash
xcrun simctl io "$BALLPAD_UDID" screenshot "build/proofs/screen-$(date +%Y%m%d-%H%M%S).png"
```

### 6) Terminate + shutdown
```bash
xcrun simctl terminate "$BALLPAD_UDID" "$BALLPAD_BUNDLE_ID" || true
sim_shutdown_all
```

---

## Switch phone ↔ pad
```bash
source scripts/sim_mutex.sh
sim_boot "$BALLPAD_PAD_UDID"
export BALLPAD_UDID="$BALLPAD_PAD_UDID"
```

Always reinstall if destination/arch products differ.

---

## Headless smoke skeleton
```bash
set -euo pipefail
source build/env.sh
source scripts/sim_mutex.sh
sim_boot "$BALLPAD_UDID"
xcodebuild -project app/Ballpad.xcodeproj -scheme Ballpad   -destination "id=$BALLPAD_UDID" -derivedDataPath build/DerivedData build
APP=$(find build/DerivedData/Build/Products -name "*.app" -type d | head -1)
xcrun simctl install "$BALLPAD_UDID" "$APP"
xcrun simctl launch --terminate-running-process "$BALLPAD_UDID" "$BALLPAD_BUNDLE_ID"
sleep 8
xcrun simctl io "$BALLPAD_UDID" screenshot build/proofs/smoke.png
sim_shutdown_all
```

## Acceptance probes
- `simctl launch` exit 0
- Log contains expected banner
- Screenshot non-black after N seconds
- Booted count == 1 during the session

## Gate status (G3)
- Exact command sequences documented
- Mutex shutdown-before-boot rule documented
- Helper script contract documented

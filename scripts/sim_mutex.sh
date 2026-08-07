#!/usr/bin/env bash
set -euo pipefail
sim_shutdown_all() { xcrun simctl shutdown all >/dev/null 2>&1 || true; }
sim_boot() {
  local udid="$1"
  if [ -z "${udid:-}" ]; then
    echo "ERROR: sim_boot requires UDID" >&2
    return 1
  fi
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

#!/usr/bin/env bash
# Bounded, truthful test entry point for the native Strikers build surface.
#
# Use: scripts/native/test.sh --suite unit|smoke|acceptance [--device <UDID>] [options]
#
#   unit        the macOS engine and the port's data-independent tests (no Simulator)
#   smoke       the N2 gate on a Simulator: platform metadata, no host linkage, and
#               BallpadProbe bringing up a real drawable and exiting cleanly
#   acceptance  the doc 34 functional matrix on a Simulator, plus the build and
#               provenance rows
#
# Options:
#   --device <UDID>        required for smoke and acceptance; the Simulator to own
#   --form-factor phone|pad  labels the run; inferred from the device name otherwise
#   --configuration NAME   default Release
#   --budget SECONDS       whole-suite watchdog; a timeout is a failure, never a pass
#   --run-id ID            proof directory name under build/proofs/native-strikers/
#   --proof-dir DIR        override the proof directory
#
# One task-owned Simulator is used at a time. The lock only ever covers devices this
# task owns, because scripts/sim_mutex.sh's global shutdown is not a real lock.
#
# The exit status is the answer: 0 only when every required row came back PASS. A row
# that was not run is reported as IN_PROGRESS and fails the suite.

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SUITE=""
DEVICE=""
FORM_FACTOR=""
CONFIGURATION="Release"
BUDGET=""
PROOF_DIR=""
RUN_ID_SUFFIX=""

while [ $# -gt 0 ]; do
    case "$1" in
        --suite) SUITE="$2"; shift 2 ;;
        --suite=*) SUITE="${1#*=}"; shift ;;
        --device) DEVICE="$2"; shift 2 ;;
        --device=*) DEVICE="${1#*=}"; shift ;;
        --form-factor) FORM_FACTOR="$2"; shift 2 ;;
        --form-factor=*) FORM_FACTOR="${1#*=}"; shift ;;
        --configuration|-c) CONFIGURATION="$2"; shift 2 ;;
        --configuration=*) CONFIGURATION="${1#*=}"; shift ;;
        --budget) BUDGET="$2"; shift 2 ;;
        --budget=*) BUDGET="${1#*=}"; shift ;;
        --run-id) RUN_ID_SUFFIX="$2"; shift 2 ;;
        --run-id=*) RUN_ID_SUFFIX="${1#*=}"; shift ;;
        --proof-dir) PROOF_DIR="$2"; shift 2 ;;
        --proof-dir=*) PROOF_DIR="${1#*=}"; shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

case "$SUITE" in
    unit|smoke|acceptance) ;;
    "") die "--suite is required (unit|smoke|acceptance)" ;;
    *) die "unknown suite: $SUITE" ;;
esac

PLATFORM=macos
if [ "$SUITE" != "unit" ]; then
    PLATFORM=simulator
    [ -n "$DEVICE" ] || die "--device <UDID> is required for the $SUITE suite"
fi

require_cmd python3
[ -x "${BALLPAD_ROOT}/scripts/native/lib/test_runner.py" ] \
    || die "missing scripts/native/lib/test_runner.py"

if [ -n "$DEVICE" ]; then
    if ! xcrun simctl list devices -j 2>/dev/null | grep -q "\"$DEVICE\""; then
        warn "device $DEVICE is not one simctl knows about; known devices:"
        xcrun simctl list devices available | sed -n '1,40p' >&2
        die "--device $DEVICE does not resolve"
    fi
fi

# The form factor is recorded rather than guessed silently: doc 34 wants the phone and
# iPad results kept apart, and a UDID alone does not say which one ran.
if [ -z "$FORM_FACTOR" ] && [ -n "$DEVICE" ]; then
    DEVICE_NAME="$(xcrun simctl list devices -j 2>/dev/null \
        | python3 -c 'import json,sys; udid=sys.argv[1];\
d=json.load(sys.stdin)["devices"];\
print(next((x["name"] for v in d.values() for x in v if x["udid"]==udid), ""))' "$DEVICE")"
    case "$DEVICE_NAME" in
        iPad*) FORM_FACTOR=pad ;;
        iPhone*) FORM_FACTOR=phone ;;
        *) FORM_FACTOR=unknown ;;
    esac
    printf '==> Simulator %s (%s) -> form factor %s\n' "$DEVICE_NAME" "$DEVICE" "$FORM_FACTOR"
fi

mkdir -p "$PROOF_ROOT"
if [ -z "$PROOF_DIR" ]; then
    PROOF_DIR="${PROOF_ROOT}/${SUITE}-${FORM_FACTOR:-macos}-${RUN_ID_SUFFIX:-$RUN_ID}"
fi

LOCKED=0
if [ "$PLATFORM" = simulator ]; then
    # Held for the whole suite, so no second task can take the device mid-run.
    sim_lock_acquire
    LOCKED=1
fi

args=(
    --suite "$SUITE"
    --platform "$PLATFORM"
    --proof-dir "$PROOF_DIR"
    --run-id "$(basename "$PROOF_DIR")"
    --configuration "$CONFIGURATION"
    --port-dir "$PORT_DIR"
    --build-dir "$(platform_build_dir macos)"
    --sim-build-dir "$(platform_build_dir simulator)"
)
[ -n "$DEVICE" ] && args+=(--device "$DEVICE")
[ -n "$FORM_FACTOR" ] && args+=(--form-factor "$FORM_FACTOR")
[ -n "$BUDGET" ] && args+=(--budget "$BUDGET")

log "test suite: $SUITE (platform $PLATFORM) -> $PROOF_DIR"
status=0
python3 "${BALLPAD_ROOT}/scripts/native/lib/test_runner.py" "${args[@]}" || status=$?

if [ "$LOCKED" = 1 ]; then
    # sim_lock_acquire writes an owner file inside the lock directory, so the directory is never
    # empty and rmdir cannot release it. Clearing the trap first also disabled the one release
    # that did work, so every Simulator suite left the lock held and the next run waited out the
    # full acquisition timeout before dying. Releasing first and clearing the trap afterwards
    # keeps the trap as the fallback if this removal fails.
    rm -rf "${SIM_LOCK_DIR}/held"
    trap - EXIT
fi

log "proof bundle: ${PROOF_DIR}"
exit "$status"

#!/usr/bin/env bash
# Run one driven scenario against the Simulator build and record a proof bundle.
#
# Use: scripts/native/run-scenario.sh --scenario <name|path> --run-id <id> \
#          --device <UDID> [--form-factor phone|pad] [--platform simulator] \
#          [--proof-dir DIR] [--budget SECONDS] [--force]
#
# A scenario is a list of driver directives (tests/native/scenarios/<name>.scn).  This
# script owns everything around it that used to be typed by hand and therefore never
# landed in the bundle: the task Simulator lock, the boot, the install, the save the
# front end needs before it will skip its memcard popup, and the identity of every input
# to the run (engine pin, fork head, fork tree, patch series, disc image, app binary).
#
# The bundle is written the same way test.sh writes one: rows go through
# lib/suite_report.py, so result.json, rows.tsv and suite-metadata.json agree, and a row
# that was not run fails the run rather than being quietly absent.
#
# Evidence only: this script never builds.  Build first with
#   scripts/native/build.sh --platform simulator --no-bootstrap

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SCENARIO=""
RUN_TAG=""
DEVICE=""
FORM_FACTOR=""
PLATFORM="simulator"
PROOF_DIR=""
BUDGET="900"
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --scenario) SCENARIO="$2"; shift 2 ;;
        --scenario=*) SCENARIO="${1#*=}"; shift ;;
        --run-id) RUN_TAG="$2"; shift 2 ;;
        --run-id=*) RUN_TAG="${1#*=}"; shift ;;
        --device) DEVICE="$2"; shift 2 ;;
        --device=*) DEVICE="${1#*=}"; shift ;;
        --form-factor) FORM_FACTOR="$2"; shift 2 ;;
        --form-factor=*) FORM_FACTOR="${1#*=}"; shift ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --platform=*) PLATFORM="${1#*=}"; shift ;;
        --proof-dir) PROOF_DIR="$2"; shift 2 ;;
        --proof-dir=*) PROOF_DIR="${1#*=}"; shift ;;
        --budget) BUDGET="$2"; shift 2 ;;
        --budget=*) BUDGET="${1#*=}"; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$SCENARIO" ] || die "--scenario is required"
[ -n "$RUN_TAG" ] || die "--run-id is required"
[ "$PLATFORM" = "simulator" ] || die "only --platform simulator is wired for scenarios so far"
[ -n "$DEVICE" ] || die "--device <UDID> is required; this task owns exactly the Simulator it names"

require_cmd python3
require_cmd xcrun

# ── Scenario resolution ───────────────────────────────────────────────────────
# A bare name is a file under tests/native/scenarios; a path is used as given.  The
# resolved file is copied into the bundle so the bundle still explains itself after the
# scenario is edited again.
if [ -f "$SCENARIO" ]; then
    SCENARIO_PATH="$(cd "$(dirname "$SCENARIO")" && pwd)/$(basename "$SCENARIO")"
else
    SCENARIO_PATH="${BALLPAD_ROOT}/tests/native/scenarios/${SCENARIO}"
    case "$SCENARIO_PATH" in
        *.scn) ;;
        *) SCENARIO_PATH="${SCENARIO_PATH}.scn" ;;
    esac
fi
[ -f "$SCENARIO_PATH" ] || die "no scenario at ${SCENARIO_PATH}"
SCENARIO_NAME="$(basename "$SCENARIO_PATH" .scn)"

if [ "$PLATFORM" = "simulator" ]; then
    xcrun simctl list devices -j 2>/dev/null | grep -q "\"$DEVICE\"" \
        || die "--device $DEVICE is not a Simulator simctl knows about"
fi

if [ -z "$FORM_FACTOR" ]; then
    DEVICE_NAME="$(xcrun simctl list devices -j 2>/dev/null \
        | python3 -c 'import json,sys; udid=sys.argv[1]; d=json.load(sys.stdin)["devices"];\
print(next((x["name"] for v in d.values() for x in v if x["udid"]==udid), ""))' "$DEVICE")"
    case "$DEVICE_NAME" in
        iPad*) FORM_FACTOR=pad ;;
        iPhone*) FORM_FACTOR=phone ;;
        *) FORM_FACTOR=unknown ;;
    esac
    log "Simulator ${DEVICE_NAME} ($DEVICE) -> form factor $FORM_FACTOR"
fi

# ── Proof directory ──────────────────────────────────────────────────────────
if [ -z "$PROOF_DIR" ]; then
    PROOF_DIR="${PROOF_ROOT}/${SCENARIO_NAME}-${FORM_FACTOR}-${RUN_TAG}"
fi
# The driver truncates control.txt and app.log but never shots/, and the runner will not
# clear anything itself: a re-used directory would mix two runs' frame captures under one
# result.  Reusing one is therefore an explicit opt-in.
if [ -e "${PROOF_DIR}/result.json" ] && [ "$FORCE" != "1" ]; then
    die "${PROOF_DIR} already holds a result.json; pass --force to overwrite it, or use a new --run-id"
fi
mkdir -p "$PROOF_DIR"

# ── App bundle ───────────────────────────────────────────────────────────────
# Same resolution as test_runner.py: the port's CMake writes ballpad-bundles.txt because
# the app lands in the port's binary directory, not at the top of the build tree.
BUNDLE_FILE="$(platform_build_dir "$PLATFORM")/ballpad-bundles.txt"
APP=""
if [ -f "$BUNDLE_FILE" ]; then
    APP="$(sed -n 's/^strikers=//p' "$BUNDLE_FILE" | head -1)"
fi
[ -n "$APP" ] && [ -d "$APP" ] || die "no BallpadStrikers.app published by ${BUNDLE_FILE}; run scripts/native/build.sh --platform ${PLATFORM} --no-bootstrap"
APP_BIN="${APP}/$(basename "$APP" .app)"
[ -f "$APP_BIN" ] || die "bundle ${APP} has no executable at ${APP_BIN}"
assert_macho_platform "$APP_BIN" iossimulator

# ── Provenance ───────────────────────────────────────────────────────────────
# Every value that identifies an input to this run, recorded together so the bundle can
# be checked later without the ignored working tree it came from.
[ -d "${ENGINE_DIR}/.git" ] || die "no engine fork at ${ENGINE_DIR}; run bootstrap.sh first"
ENGINE_HEAD="$(git -C "${ENGINE_DIR}" rev-parse HEAD)"
ENGINE_TREE="$(git -C "${ENGINE_DIR}" rev-parse 'HEAD^{tree}')"
ENGINE_DIRTY="$(git -C "${ENGINE_DIR}" status --porcelain)"
ASSET_SHA="$(sha256_of "${GAME_IMAGE}")"
APP_SHA="$(sha256_of "$APP_BIN")"
SERIES_FILE="${BUILD_ROOT}/patch-series.sha256"
SERIES_SHA=""
[ -f "$SERIES_FILE" ] && SERIES_SHA="$(cat "$SERIES_FILE")"

PROVENANCE_FAIL=""
[ -z "$ENGINE_DIRTY" ] || PROVENANCE_FAIL="engine fork has uncommitted edits no patch series carries: $(printf '%s' "$ENGINE_DIRTY" | tr '\n' ' ')"
[ "$ASSET_SHA" = "$GAME_IMAGE_SHA256" ] || PROVENANCE_FAIL="${PROVENANCE_FAIL:+$PROVENANCE_FAIL; }disc image sha256 ${ASSET_SHA} is not the recorded baseline ${GAME_IMAGE_SHA256}"
[ -n "$APP_SHA" ] || PROVENANCE_FAIL="${PROVENANCE_FAIL:+$PROVENANCE_FAIL; }could not hash ${APP_BIN}"
[ -n "$SERIES_SHA" ] || PROVENANCE_FAIL="${PROVENANCE_FAIL:+$PROVENANCE_FAIL; }no patch series digest at ${SERIES_FILE}; run export-patches.sh"

log "engine pin ${ENGINE_PIN}"
log "engine head ${ENGINE_HEAD} tree ${ENGINE_TREE}"
log "patch series ${SERIES_SHA:-<none>}"
log "disc image ${ASSET_SHA}"
log "app binary ${APP_SHA}"

# ── The save the front end needs ─────────────────────────────────────────────
# The driver points STRIKERS_USER_DIR at the bundle, so the app starts from an empty card.
# With no save the front end raises its memcard popup between scene 35 and the legal screen,
# and a scenario routed one-press-per-screen stalls on it.  The seed is a card image the port
# itself wrote; it lives under build/ because it is game-derived data and is never committed.
SEED_SAVE="${BUILD_ROOT}/seeds/user/USA/Card A/01-G4QE-MarioSoccer.gci"
[ -f "$SEED_SAVE" ] || die "no seed save at ${SEED_SAVE}; without it the front end stops on its memcard popup (see doc 36)"
mkdir -p "${PROOF_DIR}/user/USA/Card A"
cp "$SEED_SAVE" "${PROOF_DIR}/user/USA/Card A/"
log "seed save $(sha256_of "${PROOF_DIR}/user/USA/Card A/01-G4QE-MarioSoccer.gci")"

cp "$SCENARIO_PATH" "${PROOF_DIR}/$(basename "$SCENARIO_PATH")"

# ── Own the device, run, record ──────────────────────────────────────────────
sim_lock_acquire
log "boot ${DEVICE}"
xcrun simctl bootstatus "$DEVICE" -b || die "Simulator ${DEVICE} did not reach booted"
log "install $(basename "$APP")"
xcrun simctl install "$DEVICE" "$APP" || die "install of ${APP} failed"

ROWS="${PROOF_DIR}/rows.tsv"
log_new "$ROWS"
LOG="${PROOF_DIR}/driver.log"
log "driver: ${SCENARIO_NAME}"
set +e
python3 "${BALLPAD_ROOT}/scripts/native/lib/driver.py" \
    --suite "scenario" --platform "$PLATFORM" \
    --device "$DEVICE" --bundle-id "$IOS_BUNDLE_ID" \
    --app "$APP" --asset "$GAME_IMAGE" --asset-sha "$ASSET_SHA" \
    --engine-pin "$ENGINE_PIN" --engine-head "$ENGINE_HEAD" \
    --patch-series "$SERIES_SHA" \
    --label "${SCENARIO_NAME}-${FORM_FACTOR}" \
    --scenario-path "$SCENARIO_PATH" --proof-dir "$PROOF_DIR" --run-id "$RUN_TAG" \
    --budget "$BUDGET" 2>&1 | tee "$LOG"
driver_status="${PIPESTATUS[0]}"
set -e

if [ "$driver_status" = "0" ]; then
    printf 'S.run\tPASS\tscenario %s completed every step\t%s\n' \
        "$SCENARIO_NAME" "$(basename "$PROOF_DIR")/result.json" >> "$ROWS"
else
    printf 'S.run\tFAIL\tdriver exit status %s\t%s\n' \
        "$driver_status" "$(basename "$PROOF_DIR")/result.json" >> "$ROWS"
fi

if [ -z "$PROVENANCE_FAIL" ]; then
    printf 'S.provenance\tPASS\tpin %s, fork %s tree %s clean, series %s, disc %s, app %s\t%s\n' \
        "${ENGINE_PIN:0:12}" "${ENGINE_HEAD:0:12}" "${ENGINE_TREE:0:12}" "${SERIES_SHA:0:12}" \
        "${ASSET_SHA:0:12}" "${APP_SHA:0:12}" "$(basename "$PROOF_DIR")/rows.tsv" >> "$ROWS"
else
    printf 'S.provenance\tFAIL\t%s\t%s\n' "$PROVENANCE_FAIL" "$(basename "$PROOF_DIR")/rows.tsv" >> "$ROWS"
fi

# The driver has already written result.json for the run itself; suite_report.py writes the
# bundle-level one from the rows.  Keeping the driver's copy under its own name leaves both.
mv "${PROOF_DIR}/result.json" "${PROOF_DIR}/driver-result.json"
set +e
python3 "${BALLPAD_ROOT}/scripts/native/lib/suite_report.py" \
    --suite "scenario" --platform "$PLATFORM" --device "$DEVICE" --bundle-id "$IOS_BUNDLE_ID" \
    --run-id "$RUN_TAG" --proof-dir "$PROOF_DIR" --configuration Release \
    --expect "S.run,S.provenance" \
    --command "scripts/native/run-scenario.sh --scenario ${SCENARIO_NAME} --run-id ${RUN_TAG}" \
    < "$ROWS"
status=$?
set -e

if [ "$status" != "0" ] && [ "$driver_status" = "0" ]; then
    log "the scenario itself passed; the bundle is non-passing on provenance"
fi
log "proof bundle: ${PROOF_DIR}"
exit "$status"

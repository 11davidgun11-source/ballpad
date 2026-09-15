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

# ── A scenario's own reading, where the claim needs one ──────────────────────
# Most scenarios decide their claim inside the driver: every step observed, or the driver exits
# nonzero. F04's live-match half cannot be decided that way, because the reading it needs is not a
# log line a step can wait for -- it is a *count* over the port's own consume: lines, taken between
# two dumps of the engine's match state, and it is arithmetic rather than presence. The program is
# the same shape as the UI-test runner's consume-summary.awk and lives in the same place, and like
# that one it prints numbers so this script can state each clause, rather than a verdict.
#
# What the row is allowed to claim is bounded by what was injected. The scenario drives the port's
# control channel (press/stick), which merges into the same pad sample a finger on the glass reaches
# -- src/Game/main.cpp calls PortUpdateSyntheticInput, which merges the host's offer and the
# channel's held state, before the VBlank pad pass clamps the result into PadStatus::s_Current[0] --
# so the engine-side reading is the same reading a touch would produce. It is still an injection and
# not a touch, and the row says so: XCUIAutomation has no multi-touch, so the simultaneous clause
# cannot be produced by two held fingers, and the row that does measure real fingers is
# S.f04.ui-touch-sweep in the UI-test run.
EXPECT="S.run,S.provenance"
if [ "$SCENARIO_NAME" = "f04-live-match" ]; then
    LIVE_SUMMARY="0 0 0 0 0 - 0 0 0 0 -1 - 0"
    [ -f "${PROOF_DIR}/app.log" ] \
        && LIVE_SUMMARY="$(awk -f "${BALLPAD_ROOT}/scripts/native/f04-live-summary.awk" \
            "${PROOF_DIR}/app.log")"
    live_field() { printf '%s' "$LIVE_SUMMARY" | awk -v n="$1" '{ print $n + 0 }'; }
    live_text() { printf '%s' "$LIVE_SUMMARY" | awk -v n="$1" '{ print $n }'; }
    LIVE_FAIL=""
    [ "$(live_field 10)" -eq 2 ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }the port's own match dump did not bracket the sweep, so no frame in it is known to be a live match (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    [ "$(live_field 11)" -eq 4 ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }the dump that opened the bracket named match state $(live_field 11) rather than 4, so the sweep did not land in live gameplay (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    [ "$(live_field 13)" -eq 0 ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }a consume: line carries a field this script could not read, so the engine's own pad could not be judged (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    [ "$(live_field 1)" -gt 0 ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }the engine's own pad did not change once between the two match dumps, so no control reached it during the match (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    [ "$(live_field 3)" -eq 0 ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }the engine reported a pad fault while a control was held during the match (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    [ "$(live_field 7)" -gt 0 ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }no frame of the match shows the engine's own pad holding the main stick the channel was holding, so the stick did not reach the game (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    # The clause no single finger can produce, and the reason this row exists beside the UI sweep:
    # one sample of the game's own pad carrying both a moved main stick and a pressed control.
    [ "$(live_field 4)" -gt 0 ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }no frame of the match shows the engine's own pad holding a moved main stick and a pressed control at the same time, so the simultaneous clause was not measured (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    [ "$(live_field 5)" -eq 12 ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }those frames held only $(live_field 5) of the twelve controls, so the sweep did not carry every control into a live match (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    [ "$(live_text 6)" = "-" ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }the simultaneous frames never show the engine's pad holding $(live_text 6), so those controls were injected and not read (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    # The reading is tied back to what was asked for, not merely to "a stick moved": a hold of 25 of
    # 100 is 31 raw, and the game's own clamp takes it past its 15 deadzone to 16.
    [ "$(live_text 12)" = "16,0" ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }the engine's own pad held the main stick at $(live_text 12) where the game's clamp of the channel's 25-of-100 hold is 16,0, so the sample is not the clamp this row rests on (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    # The game's answer rather than the keypress: FrontEnd::UpdateForGame turns Start into
    # EnterMenuState(MET_PAUSE) and m_bInPauseMenuState, and the port's dump prints that as pause=1.
    [ "$(live_field 9)" -gt 0 ] \
        || LIVE_FAIL="${LIVE_FAIL:+$LIVE_FAIL; }the game never reported its own pause menu open after the Start press, so no control was seen to change the game's state rather than only its pad (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: ${LIVE_SUMMARY})"
    if [ -z "$LIVE_FAIL" ]; then
        printf "S.f04.live-match\tPASS\t%s consume: lines inside the port's own match bracket, %s with no engine pad error, %s of them holding a moved main stick (at %s, the game's clamp of the channel's hold) and a pressed control in the same sample -- %s different masks, covering all %s controls (missing %s) -- and %s dump line(s) reporting the game's own pause menu open after the Start press; moved by the control channel, which merges into the same pad sample a finger reaches, not by a UI touch (total/ok/errored/simult/covered/missing/stick-lines/masks/pause/bracket/state/stick/unreadable: %s)\t%s/app.log\n" "$(live_field 1)" "$(live_field 2)" "$(live_field 4)" "$(live_text 12)" "$(live_field 8)" "$(live_field 5)" "$(live_text 6)" "$(live_field 9)" "$LIVE_SUMMARY" "$(basename "$PROOF_DIR")" >> "$ROWS"
    else
        printf 'S.f04.live-match\tFAIL\t%s\t%s/app.log\n' "$LIVE_FAIL" "$(basename "$PROOF_DIR")" >> "$ROWS"
    fi
    EXPECT="${EXPECT},S.f04.live-match"
fi

# The driver has already written result.json for the run itself; suite_report.py writes the
# bundle-level one from the rows.  Keeping the driver's copy under its own name leaves both.
mv "${PROOF_DIR}/result.json" "${PROOF_DIR}/driver-result.json"
set +e
python3 "${BALLPAD_ROOT}/scripts/native/lib/suite_report.py" \
    --suite "scenario" --platform "$PLATFORM" --device "$DEVICE" --bundle-id "$IOS_BUNDLE_ID" \
    --run-id "$RUN_TAG" --proof-dir "$PROOF_DIR" --configuration Release \
    --expect "$EXPECT" \
    --command "scripts/native/run-scenario.sh --scenario ${SCENARIO_NAME} --run-id ${RUN_TAG}" \
    < "$ROWS"
status=$?
set -e

if [ "$status" != "0" ] && [ "$driver_status" = "0" ]; then
    log "the scenario itself passed; the bundle is non-passing on provenance"
fi
log "proof bundle: ${PROOF_DIR}"
exit "$status"

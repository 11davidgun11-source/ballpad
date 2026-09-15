#!/usr/bin/env bash
# Real-touch UI acceptance for the vendored SunPad interface.
#
# Use: scripts/native/run-uitests.sh --run-id <id> --device <UDID> [options]
#
#   --form-factor phone|pad   labels the run; inferred from the device name otherwise
#   --configuration NAME      default Debug, which is what the XCTest build uses
#   --budget SECONDS          whole-run watchdog; a timeout is a failure, never a pass
#   --only METHOD             run one test method; debugging only, see the note below
#   --no-build                reuse the last build-for-testing product
#   --force                   overwrite an existing proof bundle
#
# driver.py can only press the port virtual pad, so it never reaches the interface
# itself. Doc 34 requires coordinate and accessibility touches on the real app surface,
# and that is what this suite is: a repo-local XCUITest bundle carrying no target
# application of its own, addressing the CMake-built app by bundle identifier and
# tapping, dragging and flipping the elements the interface actually publishes.
#
# Evidence only: the app must already be built with
#   scripts/native/build.sh --platform simulator --no-bootstrap
#
# Every test row is required, so --only produces a non-passing bundle on purpose: it is
# a debugging aid, not a way to declare victory on part of the suite.

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

RUN_TAG=""
DEVICE=""
FORM_FACTOR=""
PROOF_DIR=""
CONFIGURATION="Debug"
# The watchdog is here to catch a hang, not to decide the suite. Seven rows that each launch the
# game, drive real touches and relaunch for a persistence read-back measured 1,145 s in run
# f01f02-phone-r2 with two rows still to go, so a 1,200 s budget was terminating a suite that was
# making progress -- and a SIGKILL leaves the result bundle unfinished, which reports every row as
# missing. The F13 and FPS rows below added four more launches to that shape, so 2,400 s stopped
# leaving room; 3,600 s is roughly twice the longest measured run at the current row count.
BUDGET="3600"
FORCE=0
DO_BUILD=1
ONLY=()

while [ $# -gt 0 ]; do
    case "$1" in
        --run-id) RUN_TAG="$2"; shift 2 ;;
        --run-id=*) RUN_TAG="${1#*=}"; shift ;;
        --device) DEVICE="$2"; shift 2 ;;
        --device=*) DEVICE="${1#*=}"; shift ;;
        --form-factor) FORM_FACTOR="$2"; shift 2 ;;
        --form-factor=*) FORM_FACTOR="${1#*=}"; shift ;;
        --proof-dir) PROOF_DIR="$2"; shift 2 ;;
        --proof-dir=*) PROOF_DIR="${1#*=}"; shift ;;
        --configuration|-c) CONFIGURATION="$2"; shift 2 ;;
        --configuration=*) CONFIGURATION="${1#*=}"; shift ;;
        --budget) BUDGET="$2"; shift 2 ;;
        --budget=*) BUDGET="${1#*=}"; shift ;;
        --only) ONLY+=("$2"); shift 2 ;;
        --only=*) ONLY+=("${1#*=}"); shift ;;
        --no-build) DO_BUILD=0; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n "2,23p" "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$RUN_TAG" ] || die "--run-id is required"
[ -n "$DEVICE" ] || die "--device <UDID> is required; this task owns exactly the Simulator it names"

# Everything decided before build-for-testing -- the device, the app and its hash, the seed, the
# boot and the install -- used to exist only on the terminal, because log_new "$LOG" truncates the
# phase log right before the build and the run's stdout is not part of the bundle. Those lines are
# exactly what a reader needs to know which app a row was measured against and whether the
# installed bundle was the current build, so they are written into the bundle as they happen.
preflight() {
    printf '%s\n' "$*" >> "${PROOF_DIR}/preflight.log"
    log "$*"
}

require_cmd python3
require_cmd xcrun
require_toolchain

PROJECT="${BALLPAD_ROOT}/tests/native/uitest/BallpadNativeUITests.xcodeproj"
SCHEME="BallpadNativeUITests"
SUITE_ID="${SCHEME}/BallpadSunPadInterfaceTests"
DERIVED="${BUILD_ROOT}/uitest-derived"
REPORT="${BALLPAD_ROOT}/scripts/native/lib/uitest_report.py"
[ -f "$REPORT" ] || die "missing ${REPORT}"

if ! xcrun simctl list devices -j 2>/dev/null | grep -q "$DEVICE"; then
    die "--device $DEVICE is not a Simulator simctl knows about"
fi

if [ -z "$FORM_FACTOR" ]; then
    DEVICE_LINE="$(xcrun simctl list devices 2>/dev/null | grep -F "($DEVICE)" | head -1)"
    DEVICE_NAME="$(printf "%s" "$DEVICE_LINE" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*($DEVICE).*//")"
    case "$DEVICE_NAME" in
        iPad*) FORM_FACTOR=pad ;;
        iPhone*) FORM_FACTOR=phone ;;
        *) FORM_FACTOR=unknown ;;
    esac
    log "Simulator ${DEVICE_NAME:-unknown} ($DEVICE) -> form factor $FORM_FACTOR"
fi

# -- Proof directory ---------------------------------------------------------
mkdir -p "$PROOF_ROOT"
if [ -z "$PROOF_DIR" ]; then
    PROOF_DIR="${PROOF_ROOT}/uitest-${FORM_FACTOR}-${RUN_TAG}"
fi
if [ -e "${PROOF_DIR}/result.json" ] && [ "$FORCE" != "1" ]; then
    die "${PROOF_DIR} already holds a result.json; pass --force to overwrite it, or use a new --run-id"
fi
mkdir -p "$PROOF_DIR"
: > "${PROOF_DIR}/preflight.log"   # per-run: --force must not stack two runs' preflight in one file

preflight "device ${DEVICE} form factor ${FORM_FACTOR} run ${RUN_TAG}"

# -- App bundle --------------------------------------------------------------
BUNDLE_FILE="$(platform_build_dir simulator)/ballpad-bundles.txt"
APP=""
if [ -f "$BUNDLE_FILE" ]; then
    APP="$(sed -n "s/^strikers=//p" "$BUNDLE_FILE" | head -1)"
fi
[ -n "$APP" ] && [ -d "$APP" ] || die "no BallpadStrikers.app published by ${BUNDLE_FILE}; run scripts/native/build.sh --platform simulator --no-bootstrap"
APP_BIN="${APP}/$(basename "$APP" .app)"
[ -f "$APP_BIN" ] || die "bundle ${APP} has no executable at ${APP_BIN}"
assert_macho_platform "$APP_BIN" iossimulator

# -- Provenance --------------------------------------------------------------
[ -d "${ENGINE_DIR}/.git" ] || die "no engine fork at ${ENGINE_DIR}; run bootstrap.sh first"
ENGINE_HEAD="$(git -C "${ENGINE_DIR}" rev-parse HEAD)"
ENGINE_TREE="$(git -C "${ENGINE_DIR}" rev-parse "HEAD^{tree}")"
ENGINE_DIRTY="$(git -C "${ENGINE_DIR}" status --porcelain)"
ASSET_SHA="$(sha256_of "${GAME_IMAGE}")"
APP_SHA="$(sha256_of "$APP_BIN")"
SERIES_FILE="${BUILD_ROOT}/patch-series.sha256"
SERIES_SHA=""
[ -f "$SERIES_FILE" ] && SERIES_SHA="$(cat "$SERIES_FILE")"

PROVENANCE_FAIL=""
[ -z "$ENGINE_DIRTY" ] || PROVENANCE_FAIL="engine fork has uncommitted edits no patch series carries: $(printf "%s" "$ENGINE_DIRTY" | tr "\n" " ")"
[ "$ASSET_SHA" = "$GAME_IMAGE_SHA256" ] || PROVENANCE_FAIL="${PROVENANCE_FAIL:+$PROVENANCE_FAIL; }disc image sha256 ${ASSET_SHA} is not the recorded baseline ${GAME_IMAGE_SHA256}"
[ -n "$APP_SHA" ] || PROVENANCE_FAIL="${PROVENANCE_FAIL:+$PROVENANCE_FAIL; }could not hash ${APP_BIN}"
[ -n "$SERIES_SHA" ] || PROVENANCE_FAIL="${PROVENANCE_FAIL:+$PROVENANCE_FAIL; }no patch series digest at ${SERIES_FILE}; run export-patches.sh"

preflight "app bundle ${APP}"
preflight "engine pin ${ENGINE_PIN}"
preflight "engine head ${ENGINE_HEAD} tree ${ENGINE_TREE}"
preflight "patch series ${SERIES_SHA:-none}"
preflight "disc image ${ASSET_SHA}"
preflight "app binary ${APP_SHA}"

# -- The save the front end needs --------------------------------------------
# Without a card the front end raises its memcard popup over the first screens. The
# interface suite does not drive gameplay, but the overlay is judged on screen with the
# game behind it, so the run starts from the same seeded card the scenario runner uses.
SEED_SAVE="${BUILD_ROOT}/seeds/user/USA/Card A/01-G4QE-MarioSoccer.gci"
[ -f "$SEED_SAVE" ] || die "no seed save at ${SEED_SAVE}; without it the front end stops on its memcard popup (see doc 36)"
USER_DIR="${PROOF_DIR}/uitest-env/user"
CACHE_DIR="${PROOF_DIR}/uitest-env/cache"
mkdir -p "${USER_DIR}/USA/Card A" "$CACHE_DIR"
cp "$SEED_SAVE" "${USER_DIR}/USA/Card A/"
preflight "seed save $(sha256_of "${USER_DIR}/USA/Card A/01-G4QE-MarioSoccer.gci")"

# -- Rows --------------------------------------------------------------------
# Row id and test method together, so the bundle says which claim each row decides.
TEST_ROW_SPECS=(
    "S.uitest.menu-order=testThreeDotMenuAdoptsTheVendoredRowsInOrder"
    "S.uitest.settings-panel=testTouchSettingsPanelExposesTheVendoredControls"
    "S.uitest.render-scale-persistence=testRenderScaleSelectionPersistsAcrossRelaunch"
    "S.uitest.layout-move-reset-persistence=testMovedControlPersistsAndResetRestoresTheDefault"
    "S.uitest.lifecycle-surface=testBackgroundAndForegroundKeepTheOverlay"
    "S.r1.fps-row=testFrameStatisticsRowDrivesTheCountersItClaims"
    "S.r1.display-readback=testDisplayRowsReachTheRenderer"
    "S.r1.touch-settings-drawn=testTouchSettingsReachTheDrawnOverlay"
    "S.r1.shoulder-press=testShoulderPressDrawsOnOneShoulderOnly"
    "S.r1.frame-limit-row=testFrameRateLimitRowReachesThePortsLimiter"
    "S.r1.menu-leaves=testEverySubmenuPublishesItsLabelledLeaves"
    "S.r2.audio-row=testAudioRecordingRowReportsTheMixersOwnState"
    "S.f13.about-inventory=testAboutScreenNamesUpstreamContributorsAndTheirNotices"
    "S.f13.notice-offline=testAboutNoticeOpensInFullOffline"
    "S.f13.mapping-panel=testControllerMappingPanelReportsThePortsOwnMap"
    "S.f01.import-through-files=testFreshInstallShowsImportScreenAndActivatesAPickedImage"
    "S.f02.refusal-keeps-previous=testRefusedImportKeepsThePreviousInstallationUsable"
    "S.f04.ui-touch-sweep=testEveryControlReachesTheEnginesOwnPad"
)
EXPECTED="S.run,S.provenance"
for spec in "${TEST_ROW_SPECS[@]}"; do
    EXPECTED="${EXPECTED},${spec%%=*}"
done
# F01's "staged" and F02's "original image unchanged" are properties of the container after the
# run, not of anything the app says about itself, so the reward is a row of its own below.
EXPECTED="${EXPECTED},S.f01f02.store-bytes"
# The app's own log is the same kind of row: it is written by the app rather than read off the
# screen, and the check below is that the read-backs the display and shoulder work depends on are
# actually in it.
EXPECTED="${EXPECTED},S.r1.settings-readback"
# F04's engine half is a reading of the port's own pad rather than of anything on screen, so it is a
# read-back row like the one above and is judged by this script, not by a test method.
EXPECTED="${EXPECTED},S.f04.engine-consumption"

# -- Own the device ----------------------------------------------------------
sim_lock_acquire
preflight "lock held; boot ${DEVICE}"
xcrun simctl bootstatus "$DEVICE" -b || die "Simulator ${DEVICE} did not reach booted"
# F01's row is "fresh install with no data", so the container starts empty rather than holding
# whatever an earlier run left in the store. Uninstalling is what makes the absence of game data a
# property of this run instead of an assumption about the machine.
xcrun simctl uninstall "$DEVICE" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
preflight "install $(basename "$APP") from ${APP}"
xcrun simctl install "$DEVICE" "$APP" || die "install of ${APP} failed"
# The installed copy is what the suite actually drives, so its hash is recorded next to the
# build-tree hash: on a booted Simulator a stale install would otherwise be indistinguishable
# from a fresh one in the evidence.
INSTALLED_APP="$(xcrun simctl get_app_container "$DEVICE" "$IOS_BUNDLE_ID" 2>/dev/null || true)"
if [ -n "$INSTALLED_APP" ] && [ -f "${INSTALLED_APP}/$(basename "$APP" .app)" ]; then
    preflight "installed binary $(sha256_of "${INSTALLED_APP}/$(basename "$APP" .app)") at ${INSTALLED_APP}"
else
    preflight "installed binary could not be located in the container"
fi

# -- The files the picker is offered -----------------------------------------
# F01 requires the disc to be *selected through Files*, and doc 34 says pre-seeding the sandbox
# does not prove that. A Simulator's Files app has exactly one location to browse that this test
# can fill: with UIFileSharingEnabled the app's own Documents folder is published as "On My iPhone
# (or iPad) -> <display name>", so a copy of the disc goes there for the picker to offer. The
# selection, the copy the picker hands back and the staging that follows are all the real ones.
#
# Everything here is the player's own game bytes, derived at run time into the gitignored build
# tree and this container. None of it is downloaded, bundled or committed.
UITEST_MEDIA="${BUILD_ROOT}/uitest-media"
mkdir -p "$UITEST_MEDIA"
FIXTURE_STAMP="${UITEST_MEDIA}/.source-sha256"
if [ "$(cat "$FIXTURE_STAMP" 2>/dev/null)" != "$GAME_IMAGE_SHA256" ]; then
    log "building the import fixtures from the current disc image"
    rm -f "${UITEST_MEDIA}/uitest-valid.iso" "${UITEST_MEDIA}/uitest-truncated.iso" \
          "${UITEST_MEDIA}/uitest-wronggame.iso"
    # A copy-on-write clone where the volume supports one, so a 1.4 GB fixture costs no space.
    cp -c "$GAME_IMAGE" "${UITEST_MEDIA}/uitest-valid.iso" 2>/dev/null \
        || cp "$GAME_IMAGE" "${UITEST_MEDIA}/uitest-valid.iso"
    python3 - "$GAME_IMAGE" "$UITEST_MEDIA" <<'PY'
import os
import sys

source, out_dir = sys.argv[1], sys.argv[2]
with open(source, "rb") as handle:
    # The disc header plus the whole file table (0x330078 + 49651) fits well inside this.
    head = handle.read(0x340000)

# Truncated: the disc magic and the header are present, the file table is not. This is what a
# part-downloaded image looks like, and the port refuses it in its own words.
with open(os.path.join(out_dir, "uitest-truncated.iso"), "wb") as handle:
    handle.write(head[:120000])

# Wrong game: the same read, with the disc's own title changed. Every structure the port walks is
# intact -- the magic, the file table, `common.ini` -- so this reaches the check that reads the
# title, which is the one a player with another game's disc would hit.
with open(os.path.join(out_dir, "uitest-wronggame.iso"), "wb") as handle:
    handle.write(b"GKZ" + head[3:])
PY
    printf '%s\n' "$GAME_IMAGE_SHA256" > "$FIXTURE_STAMP"
fi
for fixture in uitest-valid.iso uitest-truncated.iso uitest-wronggame.iso; do
    [ -f "${UITEST_MEDIA}/${fixture}" ] || die "the import fixture ${fixture} was not built"
done

CONTAINER="$(xcrun simctl get_app_container "$DEVICE" "$IOS_BUNDLE_ID" data 2>/dev/null || true)"
[ -n "$CONTAINER" ] && [ -d "$CONTAINER" ] || die "no data container for ${IOS_BUNDLE_ID}; the install did not land"
FILES_DIR="${CONTAINER}/Documents"
mkdir -p "$FILES_DIR"
for fixture in uitest-valid.iso uitest-truncated.iso uitest-wronggame.iso; do
    cp -c "${UITEST_MEDIA}/${fixture}" "${FILES_DIR}/${fixture}" 2>/dev/null \
        || cp "${UITEST_MEDIA}/${fixture}" "${FILES_DIR}/${fixture}"
done
preflight "files-visible fixtures in ${FILES_DIR}"
for fixture in uitest-valid.iso uitest-truncated.iso uitest-wronggame.iso; do
    preflight "fixture ${fixture} sha256 $(sha256_of "${FILES_DIR}/${fixture}")"
done

# A process left over from an earlier run would make the first launch observe somebody
# else window, so both the app and the runner are stopped before the suite starts.
xcrun simctl terminate "$DEVICE" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl terminate "$DEVICE" "${IOS_BUNDLE_ID}.nativeuitests.xctrunner" >/dev/null 2>&1 || true

LOG="${PROOF_DIR}/uitest.log"

# -- Build the test bundle ---------------------------------------------------
# xcodebuild does not forward command line build settings into the runner process, so
# the disc image and the writable directories travel in the test bundle Info.plist,
# which builtin-infoPlistUtility expands at build time.
if [ "$DO_BUILD" = "1" ]; then
    build_args=(
        build-for-testing
        -project "$PROJECT"
        -scheme "$SCHEME"
        -destination "platform=iOS Simulator,id=${DEVICE}"
        -derivedDataPath "$DERIVED"
        -configuration "$CONFIGURATION"
        CODE_SIGNING_ALLOWED=NO
        "BALLPAD_UITEST_ISO=$GAME_IMAGE"
        "BALLPAD_UITEST_USER_DIR=$USER_DIR"
        "BALLPAD_UITEST_CACHE_DIR=$CACHE_DIR"
    )
    log_new "$LOG"
    log "build-for-testing $SCHEME ($CONFIGURATION)"
    set +e
    xcodebuild "${build_args[@]}" >> "$LOG" 2>&1
    build_status=$?
    set -e
    if [ "$build_status" != "0" ]; then
        tail -n 40 "$LOG" >&2
        die "build-for-testing failed with status ${build_status}; see ${LOG}"
    fi
fi

XCTESTRUN="$(find "${DERIVED}/Build/Products" -maxdepth 1 -name "*.xctestrun" -print 2>/dev/null | head -1)"
[ -n "$XCTESTRUN" ] || die "no .xctestrun under ${DERIVED}/Build/Products; run without --no-build"
XCTEST_BIN="${DERIVED}/Build/Products/${CONFIGURATION}-iphonesimulator/BallpadNativeUITests-Runner.app/PlugIns/BallpadNativeUITests.xctest/BallpadNativeUITests"
XCTEST_SHA=""
[ -f "$XCTEST_BIN" ] && XCTEST_SHA="$(sha256_of "$XCTEST_BIN")"
preflight "test bundle ${XCTEST_SHA:-missing}"

# -- Run ---------------------------------------------------------------------
only_args=()
for method in ${ONLY[@]+"${ONLY[@]}"}; do
    only_args+=("-only-testing:${SUITE_ID}/${method}")
done

XCRESULT="${PROOF_DIR}/uitest.xcresult"
if [ -e "$XCRESULT" ]; then
    rm -rf "$XCRESULT"
fi

run_args=(
    test-without-building
    -xctestrun "$XCTESTRUN"
    -destination "platform=iOS Simulator,id=${DEVICE}"
    -resultBundlePath "$XCRESULT"
)
run_args+=( ${only_args[@]+"${only_args[@]}"} )

log "test-without-building $SCHEME"
set +e
xcodebuild "${run_args[@]}" >> "$LOG" 2>&1 &
xcode_pid=$!
timed_out=0
deadline=$((SECONDS + BUDGET))
while kill -0 "$xcode_pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
        timed_out=1
        warn "xcodebuild exceeded the ${BUDGET}s budget; terminating the run"
        kill -TERM "$xcode_pid" 2>/dev/null || true
        sleep 5
        kill -KILL "$xcode_pid" 2>/dev/null || true
        break
    fi
    sleep 2
done
wait "$xcode_pid"
xcode_status=$?
set -e

if [ "$timed_out" = "1" ]; then
    xcrun simctl terminate "$DEVICE" "${IOS_BUNDLE_ID}.nativeuitests.xctrunner" >/dev/null 2>&1 || true
    xcrun simctl terminate "$DEVICE" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
fi

grep -E "^Test Case" "$LOG" | sed -e "s/^/    /" || true

# -- Rows --------------------------------------------------------------------
ROWS="${PROOF_DIR}/rows.tsv"
log_new "$ROWS"
report_args=()
for spec in "${TEST_ROW_SPECS[@]}"; do
    report_args+=("--row" "$spec")
done
set +e
python3 "$REPORT" --result-bundle "$XCRESULT" "${report_args[@]}" >> "$ROWS"
report_status=$?
if [ "$report_status" != "0" ]; then
    warn "no test rows could be read from ${XCRESULT}; every required test row fails"
fi
set -e

# A run the watchdog terminated leaves no readable result bundle -- xcresulttool answers "Info.plist
# does not exist" -- so a suite that had already passed six rows would be reported as seven missing
# rows. xcodebuild writes its own "Test Case ... passed/failed" line as each row finishes, and those
# survive the kill, so they are the fallback: the same verdicts, with the log as the evidence. A row
# the log does not mention still fails, so this cannot turn silence into a pass.
if [ "$report_status" != "0" ] || [ ! -s "$ROWS" ]; then
    log_new "$ROWS"
    for spec in "${TEST_ROW_SPECS[@]}"; do
        row_id="${spec%%=*}"
        method="${spec#*=}"
        # The method name is matched as a fixed string first: a regex built around a shell
        # variable is one quoting mistake away from silently matching nothing, and matching
        # nothing here would report a row that finished as a row that never ran.
        row_lines="$(grep -E "^Test Case " "$LOG" | grep -F "${method}]" || true)"
        verdict="$(printf "%s" "$row_lines" | grep -oE "\]' (passed|failed) \([0-9.]+ seconds\)" | tail -1 || true)"
        if [ -z "$verdict" ]; then
            printf "%s\tFAIL\tthe log holds no verdict for %s; the run ended before this row finished\t%s/uitest.log\n" \
                "$row_id" "$method" "$(basename "$PROOF_DIR")" >> "$ROWS"
        else
            outcome="$(printf "%s" "$verdict" | grep -oE "passed|failed" | head -1)"
            seconds="$(printf "%s" "$verdict" | grep -oE "\([0-9.]+ seconds\)" | head -1)"
            if [ "$outcome" = "passed" ]; then
                printf "%s\tPASS\t%s %s (read from the log; the terminated run left no result bundle)\t%s/uitest.log\n" \
                    "$row_id" "$method" "$seconds" "$(basename "$PROOF_DIR")" >> "$ROWS"
            else
                printf "%s\tFAIL\t%s %s\t%s/uitest.log\n" \
                    "$row_id" "$method" "$seconds" "$(basename "$PROOF_DIR")" >> "$ROWS"
            fi
        fi
    done
fi

if [ "$timed_out" = "1" ]; then
    printf "S.run\tFAIL\tthe suite exceeded its %ss budget and was terminated\t%s\n" "$BUDGET" "$(basename "$PROOF_DIR")/uitest.xcresult" >> "$ROWS"
elif [ "$xcode_status" = "0" ]; then
    printf "S.run\tPASS\txcodebuild test-without-building exited 0; test bundle %s\t%s\n" "${XCTEST_SHA:0:12}" "$(basename "$PROOF_DIR")/uitest.xcresult" >> "$ROWS"
else
    printf "S.run\tFAIL\txcodebuild test-without-building exited %s\t%s\n" "$xcode_status" "$(basename "$PROOF_DIR")/uitest.xcresult" >> "$ROWS"
fi

if [ -z "$PROVENANCE_FAIL" ]; then
    printf "S.provenance\tPASS\tpin %s, fork %s tree %s clean, series %s, disc %s, app %s\t%s\n" "${ENGINE_PIN:0:12}" "${ENGINE_HEAD:0:12}" "${ENGINE_TREE:0:12}" "${SERIES_SHA:0:12}" "${ASSET_SHA:0:12}" "${APP_SHA:0:12}" "$(basename "$PROOF_DIR")/rows.tsv" >> "$ROWS"
else
    printf "S.provenance\tFAIL\t%s\t%s\n" "$PROVENANCE_FAIL" "$(basename "$PROOF_DIR")/rows.tsv" >> "$ROWS"
fi

# -- What the store holds, and what the player's own files still are ---------
# F01 requires the disc to have been chosen through Files and staged, and F02 requires the
# original image to be unchanged. Both are read back out of the container here rather than
# accepted from an alert the app raised about itself: the store's 'current' record names the
# staged copy, and that copy's digest is compared with the fixture this run built.
STORE_FAIL=""
STORE_DIR="${FILES_DIR}/BallpadGameData"
STAGED_RECORD="$(cat "${STORE_DIR}/current" 2>/dev/null || true)"
STAGED_PATH="${STAGED_RECORD}"
case "${STAGED_RECORD}" in
    "") ;;
    /*) ;;
    *) STAGED_PATH="${STORE_DIR}/${STAGED_RECORD}" ;;
esac
OFFERED_SHA="$(sha256_of "${UITEST_MEDIA}/uitest-valid.iso")"
STAGED_SHA=""
if [ -z "${STAGED_RECORD}" ]; then
    STORE_FAIL="the store holds no 'current' record, so nothing was staged and activated"
elif [ ! -f "${STAGED_PATH}" ]; then
    STORE_FAIL="'current' names ${STAGED_RECORD}, which is not in the container"
else
    STAGED_SHA="$(sha256_of "${STAGED_PATH}")"
    [ "${STAGED_SHA}" = "${OFFERED_SHA}" ] \
        || STORE_FAIL="the staged copy is ${STAGED_SHA}, not the fixture the picker offered (${OFFERED_SHA})"
fi
for fixture in uitest-valid.iso uitest-truncated.iso uitest-wronggame.iso; do
    if [ ! -f "${FILES_DIR}/${fixture}" ]; then
        STORE_FAIL="${STORE_FAIL:+${STORE_FAIL}; }the player's ${fixture} is gone from the container"
        continue
    fi
    built="$(sha256_of "${UITEST_MEDIA}/${fixture}")"
    chosen="$(sha256_of "${FILES_DIR}/${fixture}")"
    [ "${built}" = "${chosen}" ] \
        || STORE_FAIL="${STORE_FAIL:+${STORE_FAIL}; }the player's ${fixture} is ${chosen}, not the ${built} the run handed over"
done
if [ -z "${STORE_FAIL}" ]; then
    printf "S.f01f02.store-bytes\tPASS\tstaged %s as %s, byte-identical to the fixture the picker offered; the three chosen files are unchanged\tstore-inventory.txt\n" "${STAGED_SHA:0:12}" "${STAGED_RECORD}" >> "$ROWS"
else
    printf "S.f01f02.store-bytes\tFAIL\t%s\tstore-inventory.txt\n" "${STORE_FAIL}" >> "$ROWS"
fi

# -- The app's own log -------------------------------------------------------
# The rows above decide what the app did on screen; this is the app's own record of the same work,
# copied out of the container while it is still this run's container. It is what turns "the row
# reached the store" into "the row reached the renderer": the settings read-back -- display (the
# port's own target size, scale and shape), settings (the store's values and which keys hold them)
# and shoulder (L's and R's live geometry side by side) -- is written by the app, once per change, so
# the row below fails when any of the three is missing rather than when a screenshot was missed.
RUNTIME_LOG="${FILES_DIR}/BallpadLogs/runtime.log"
LOG_COPY="${PROOF_DIR}/app-runtime.log"
READBACK_LINES="${PROOF_DIR}/app-readbacks.txt"
READBACK_FAIL=""
DISPLAY_LINES=0
SETTINGS_LINES=0
SHOULDER_LINES=0
AUDIO_LINES=0
AUDIO_MIX_LINES=0
OVERLAY_LINES=0
CSTICK_LINES=0
OVERLAY_ALPHAS=0
CSTICK_SUMMARY="0 0 0 0 0"
OUTLINE_SUMMARY="0 0 0 0 0"
# F04's two readings: the mirror relation between the two shoulders on every line outside the
# editor, and what the engine's own pad held beside both offers the host made for that frame.
# Each defaults to its all-zero shape so a run that never wrote the line reports a FAIL row rather
# than an empty string.
MIRROR_SUMMARY="0 0 0 0 0 0 0"
CONSUME_SUMMARY="0 0 0 0 0 0 0 0 0 0 - 0 0 0 0 0 0 0 0"
# F04's engine reading is judged from the consume: family rather than from the read-back family, so it
# keeps its own failure list. It is set in the branch below when the log is there and to the
# missing-log reason when it is not, so the row lands either way instead of vanishing with a branch.
CONSUME_FAIL=""
log_new "$READBACK_LINES"
if [ ! -f "$RUNTIME_LOG" ]; then
    READBACK_FAIL="the app left no log at ${RUNTIME_LOG}"
    CONSUME_FAIL="the app left no log at ${RUNTIME_LOG}, so the engine's own pad was never read back beside the host's offer"
else
    cp "$RUNTIME_LOG" "$LOG_COPY"
    DISPLAY_LINES="$(grep -cE ' display: ' "$LOG_COPY" || true)"
    SETTINGS_LINES="$(grep -cE ' settings: ' "$LOG_COPY" || true)"
    SHOULDER_LINES="$(grep -cE ' shoulder: ' "$LOG_COPY" || true)"
    AUDIO_LINES="$(grep -cE ' audio: ' "$LOG_COPY" || true)"
    # The bare ' audio: ' count also catches the port's own one-off device line, so the row below
    # needs the second reading: the app's read-back of the mixer's own fields. A run where the
    # device opened but the mixer never ran writes the first kind and not the second, which is a
    # different fault and is why they are counted apart.
    AUDIO_MIX_LINES="$(grep -cE ' audio: .*\| studios [0-9]+ voices ' "$LOG_COPY" || true)"
    # The overlay read-back and the C-stick read-back, both written by the app rather than read off
    # the screen. They are counted apart from the rest because each answers a question the settings
    # store cannot: a slider holds a number, the overlay's line holds the control that was drawn
    # with it, and the switch holds a preference while the port's pad holds what it was handed.
    OVERLAY_LINES="$(grep -cE ' overlay: ' "$LOG_COPY" || true)"
    CSTICK_LINES="$(grep -cE ' c-stick: ' "$LOG_COPY" || true)"
    # The C-stick lines judged as a relation rather than as a count: with the modern convention off
    # the port must have been handed the mixer's own value, and with it on the port's value must be
    # the mixer's negated. "off N agree, on M flipped, K unreadable" is the whole reading.
    # The convention token is the last word of the line and carries the closing paren, so it is
    # matched by prefix: comparing it whole would read every line as the "on" case.
    # Both readings below scan the log with awk alone rather than through a leading grep, and the
    # reason is the shell rather than the log: this script runs under `set -euo pipefail`, so a
    # pipeline whose first grep matches nothing fails, and under `set -e` that failure ends the
    # script. A read-back family that never reached the log therefore has to land as a FAIL row
    # below; the first run of this block against an app built before the read-back existed ended
    # the script instead, and took the store inventory and the row with it. awk reads the same
    # file, exits 0 whatever it finds, and prints the same summary when it finds nothing.
    # The alpha the overlay read-back gives the A control, deduplicated. The opacity row's claim is
    # that the drawn control changed, and one alpha for the whole run would mean the drag reached
    # the store and never the view.
    OVERLAY_ALPHAS="$(awk '/ overlay: / { prev = ""; for (i = 1; i <= NF; i++) { if ($i == "A" && prev == "|" && $(i + 1) ~ /^[0-9]+\.[0-9]+$/) { alphas[$(i + 1)] = 1 } prev = $i } } END { n = 0; for (a in alphas) { n++ } print n }' "$LOG_COPY")"
    CSTICK_SUMMARY="$(awk '/ c-stick: / { raw = ""; pub = ""; modern = "?"; for (i = 1; i <= NF; i++) { if ($i == "X" && $(i + 2) == "reached") raw = $(i + 1); if ($i == "as" && $(i + 2) ~ /^\(modern/) pub = $(i + 1); if ($i == "(modern") modern = $(i + 2) } if (raw == "" || pub == "" || modern == "?") { unread++; next } if (modern ~ /^off/) { off++; if (raw == pub) offok++ } else { on++; if ((raw + pub) == 0) onok++ } } END { printf "%d %d %d %d %d\n", off + 0, offok + 0, on + 0, onok + 0, unread + 0 }' "$LOG_COPY")"
    # The shoulders' press outlines, the one family the per-frame sampler in the app exists to
    # produce. A press does not re-lay the overlay out, so the geometry line above never sees one and
    # this family is the only place a press is visible as a value.
    #
    # Everything here is read from the two flags the app prints beside the two widths, because the
    # width alone does not name a press: L is a plain button, which the vendored pass presses by
    # scaling it, and R is the vendored trigger, the one shoulder that draws a press as a wider
    # outline. A width read as "pressed" is therefore wrong for L in general and wrong for *both*
    # shoulders while the layout editor is open, whose own pass paints 3.0 on every control. The
    # editor's lines are counted apart from the rest and are not judged.
    #
    # Read with awk alone rather than through a leading grep, for the reason recorded above: this
    # script runs under `set -euo pipefail`, and a pipeline whose grep matches nothing would end the
    # script here and take every row after it with it.
    OUTLINE_SUMMARY="$(awk '/ shoulder outline: / { editing = ""; lheld = ""; rheld = ""; lw = ""; rw = ""; for (i = 1; i <= NF; i++) { if ($i == "editing") editing = $(i + 1); if ($i == "L" && $(i + 1) == "held") { lheld = $(i + 2); lw = $(i + 4) } if ($i == "R" && $(i + 1) == "held") { rheld = $(i + 2); rw = $(i + 4) } } if (editing == "" || lheld == "" || rheld == "" || lw == "" || rw == "") { unread++; next } total++; if (editing == "1") { editor++; next } presses++; if ((lw + 0) > 2.0) lthick++; if ((rw + 0) > 2.0) { if (rheld == "0") rthick++; else rdetent++ } if (lheld == "1" && (lw + 0) <= 2.0) lpress++ } END { printf "%d %d %d %d %d %d %d\n", total + 0, presses + 0, lpress + 0, rdetent + 0, lthick + 0, rthick + 0, unread + 0 }' "$LOG_COPY")"
    # One outline field, by number, so the checks below read as the sentences they are.
    outline_field() { printf '%s' "$OUTLINE_SUMMARY" | awk -v n="$1" '{ print $n + 0 }'; }
    # The shoulder pair's *placement*, read from the two numbers the app derives from the live frames
    # rather than from copies of the vendored layout constants: how far each shoulder sits from its own
    # edge of the surface, and the row each one is on. The claim the operator made is that R looks like
    # the left shoulder, and a pair matched in size, corner and border while R sits on its own row and
    # its own distance from the edge is what a second, differently-placed copy of the same shape looks
    # like -- which is exactly the state this build was in before the placement mirror was added. The
    # editor is the one state in which the pair is deliberately not kept in step, so its lines are
    # counted apart and were never the claim.
    MIRROR_SUMMARY="$(awk '/ shoulder: / { editing = ""; li = ""; ri = ""; rd = ""; for (i = 1; i <= NF; i++) { if ($i == "editing") editing = $(i + 1); if ($i == "mirror" && $(i + 1) == "inset" && $(i + 2) == "L") { li = $(i + 3); ri = $(i + 5); rd = $(i + 8) } } if (editing == "" || li == "" || ri == "" || rd == "") { unread++; next } total++; if (editing == "1") { editor++; next } rest++; d = li - ri; if (d < 0) d = -d; if (d <= 0.15) mirrored++; else skew++; dd = rd + 0; if (dd < 0) dd = -dd; if (dd <= 0.15) rowed++ } END { printf "%d %d %d %d %d %d %d\n", total + 0, rest + 0, mirrored + 0, skew + 0, rowed + 0, editor + 0, unread + 0 }' "$LOG_COPY")"
    mirror_field() { printf '%s' "$MIRROR_SUMMARY" | awk -v n="$1" '{ print $n + 0 }'; }
    # What the engine's own pad held, which is the reading F04 asks for and the one no screenshot can
    # give: doc 34 wants game response rather than hittability, and a drawn press is not a read one.
    # Every `consume:` line is the port's report of `PadStatus::s_Current[0]` -- the sample
    # `cPlatPad::IsPressed` and the game's own tasks read -- beside both offers: the one the poll of
    # this frame made, and the one the poll before it made, which is the offer the port's own VBlank
    # pass clamped into the sample this line carries. The bits are read out of the hex by hand
    # because the `awk` on this host has no `strtonum` and no bitwise `and`. The summary is its own
    # file rather than an inline program because it restates the port's clamp and its own
    # left-analog-to-d-pad map in full, and both are arithmetic this host's `awk` has to spell out:
    # one conversion function, one integer sqrt, and a sector map carried through a 16-bit tick.
    CONSUME_SUMMARY="$(awk -f "${BALLPAD_ROOT}/scripts/native/consume-summary.awk" "$LOG_COPY")"
    consume_field() { printf '%s' "$CONSUME_SUMMARY" | awk -v n="$1" '{ print $n + 0 }'; }
    consume_explained() { printf '%s' "$CONSUME_SUMMARY" | awk '{ print $4 + $5 }'; }
    consume_missing() { printf '%s' "$CONSUME_SUMMARY" | awk -v n="$1" '{ print $n }'; }
    {
        printf 'source: %s\n' "$RUNTIME_LOG"
        printf 'whole log: %s lines, copied to %s\n\n' "$(wc -l < "$LOG_COPY" | tr -d ' ')" "$LOG_COPY"
        grep -E ' (display|settings|shoulder|shoulder outline|audio|overlay|consume|c-stick): ' "$LOG_COPY" \
            || printf 'no display, settings, shoulder, shoulder-outline, audio, overlay, consume or c-stick line is in the log\n'
    } >> "$READBACK_LINES"
    [ "$DISPLAY_LINES" -gt 0 ] || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the log holds no display: line, so no display row was read back from the port"
    [ "$SETTINGS_LINES" -gt 0 ] || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the log holds no settings: line, so no setting was read back from the store"
    [ "$SHOULDER_LINES" -gt 0 ] || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the log holds no shoulder: line, so the right shoulder was never compared with the left"
    [ "$AUDIO_LINES" -gt 0 ] || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the log holds no audio: line, so the audio path never reported itself"
    [ "$AUDIO_MIX_LINES" -gt 0 ] || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the audio: lines name no mixer fields, so the audio read-back never saw the mixer run"
    [ "$OVERLAY_LINES" -gt 0 ] || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the log holds no overlay: line, so the touch controls were never read back from the overlay the app drew"
    [ "$CSTICK_LINES" -gt 0 ] || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the log holds no c-stick: line, so the camera stick's axis was never read back where the port was handed it"
    [ "$OVERLAY_ALPHAS" -ge 2 ] || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the overlay: lines name ${OVERLAY_ALPHAS} alpha for the A control, so no opacity a row moved reached the drawn control"
    [ "$(printf '%s' "$CSTICK_SUMMARY" | awk '{print ($1 > 0 && $1 == $2) ? 1 : 0}')" = "1" ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }no c-stick: line shows the port handed the mixer's own value with the modern convention off (off/agree/on/flipped/unreadable: ${CSTICK_SUMMARY})"
   [ "$(printf '%s' "$CSTICK_SUMMARY" | awk '{print ($3 > 0 && $3 == $4) ? 1 : 0}')" = "1" ] \
       || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }no c-stick: line shows the port handed the negated value with the modern convention on (off/agree/on/flipped/unreadable: ${CSTICK_SUMMARY})"
    [ "$(outline_field 1)" -gt 0 ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the log holds no shoulder outline: line, so neither shoulder's press state was ever sampled while it was drawn"
    [ "$(outline_field 2)" -gt 0 ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }every shoulder outline: line was written with the layout editor open, whose pass outlines every control, so no line states a shoulder's press outside the editor (total/presses/l-press/r-detent/l-thick/r-thick-editor/unreadable: ${OUTLINE_SUMMARY})"
    [ "$(outline_field 3)" -gt 0 ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }no shoulder outline: line shows the left shoulder held while it keeps the at-rest outline, which is a left press drawn as a plain button draws one (total/presses/l-press/r-detent/l-thick/r-thick-editor/unreadable: ${OUTLINE_SUMMARY})"
    [ "$(outline_field 4)" -gt 0 ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }no shoulder outline: line shows the right trigger held past its detent, so no right press was seen to reach the pad (total/presses/l-press/r-detent/l-thick/r-thick-editor/unreadable: ${OUTLINE_SUMMARY})"
    [ "$(outline_field 5)" -eq 0 ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }a shoulder outline: line outside the editor draws L at the right trigger's press width, which is one shoulder's state painted onto the other (total/presses/l-press/r-detent/l-thick/r-thick-editor/unreadable: ${OUTLINE_SUMMARY})"
    [ "$(outline_field 6)" -eq 0 ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }a shoulder outline: line outside the editor draws R at the press width while R is not held, which is the right trigger left looking pressed at rest (total/presses/l-press/r-detent/l-thick/r-thick-editor/unreadable: ${OUTLINE_SUMMARY})"
    [ "$(mirror_field 1)" -gt 0 ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }the log holds no shoulder: line carrying the mirror reading, so the two shoulders' placement was never compared (total/rest/mirrored/skew/on-L's-row/editor/unreadable: ${MIRROR_SUMMARY})"
    [ "$(mirror_field 7)" -eq 0 ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }a shoulder: line carries no readable mirror reading, so the pair's placement could not be judged (total/rest/mirrored/skew/on-L's-row/editor/unreadable: ${MIRROR_SUMMARY})"
    [ "$(mirror_field 2)" -gt 0 ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }every shoulder: line carrying the mirror reading was written with the layout editor open, whose repair deliberately leaves the pair where the player put it, so no line states the two shoulders' placement at rest (total/rest/mirrored/skew/on-L's-row/editor/unreadable: ${MIRROR_SUMMARY})"
    { [ "$(mirror_field 3)" -eq "$(mirror_field 2)" ] && [ "$(mirror_field 4)" -eq 0 ]; } \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }R is not drawn as L's mirror at rest: the gap from the surface's left edge to L is a different number from the gap from R to its right edge (total/rest/mirrored/skew/on-L's-row/editor/unreadable: ${MIRROR_SUMMARY})"
    [ "$(mirror_field 5)" -eq "$(mirror_field 2)" ] \
        || READBACK_FAIL="${READBACK_FAIL:+$READBACK_FAIL; }R is not drawn on L's row at rest, so the pair is one shape in two places rather than one shape drawn twice (total/rest/mirrored/skew/on-L's-row/editor/unreadable: ${MIRROR_SUMMARY})"
    # F04, the engine half. Each clause is one field of the summary above, and each rests on the one
    # relation this row exists to measure: the engine's own pad holds the clamp of the *previous*
    # poll's offer, not of the offer made in the same frame as the line. A consume: line is
    # change-detected -- it is written only when a field or a scene moves -- so consecutive lines are
    # not consecutive frames, and a pairing built on the previous logged line would be an artifact.
    # The port clamps between the host's offer and the game's read of the sample, which is why the
    # previous offer describes strictly more lines than the same-frame offer does. Clauses 5 through 8
    # state that pairing, its completeness and its contrast, and they are what makes the row
    # independent of the port's frame order: swap the two offers and the pairing flips, but only the
    # previous one can account for every line with no engine error and still leave the same-frame
    # offer short. Agreement and coverage are the secondary claim -- a nonzero mask equal to the
    # previous offer's, seen across all twelve controls -- because a pad handed nothing cannot produce
    # one, and coverage is what turns a single agreeing press into "every control reaches the
    # engine". A line may also carry the port's own left-analog-to-d-pad bits, which the d-pad map
    # adds to the sample and the offer does not have, so those lines are counted apart from the
    # previous-offer lines and are allowed on top of them.
    [ "$(consume_field 1)" -gt 0 ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }the log holds no consume: line, so the engine's own pad was never read back beside the offer the host made for the same frame (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_field 19)" -eq 0 ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }a consume: line carries a field this script could not read, so the engine's own pad could not be judged (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_field 3)" -eq 0 ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }the engine reported a pad fault while the host was offering input, which is a real error code rather than the all-zero reading that clears the pad (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_field 2)" -gt 0 ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }every consume: line carried an engine error, so no line states what the engine's own pad held (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_field 7)" -eq 0 ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }a consume: line's mask lacks a bit the previous poll's offer carried, so the host offered a control the engine's own pad did not hold (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_field 8)" -eq 0 ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }a consume: line's mask carries a bit neither the previous poll's offer nor the port's own d-pad map explains, so a press reached the engine that the host never made (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_explained)" -eq "$(consume_field 2)" ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }the previous poll's offer and the port's own d-pad bits account for $(consume_explained) of the $(consume_field 2) lines with no engine error, so some line's mask is not this port's clamp of the offer that preceded it (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_explained)" -gt "$(consume_field 6)" ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }the same-frame offer accounts for $(consume_field 6) lines while the previous offer accounts for $(consume_explained), so the two offers cannot be told apart and the pairing this row rests on was not measured (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_field 9)" -gt 0 ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }no consume: line shows the engine's own pad holding a nonzero mask equal to the previous poll's offer, which is a press that was drawn and not read (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_field 10)" -eq 12 ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }the engine's own pad was seen holding only $(consume_field 10) of the twelve controls across the previous offer's lines, so the sweep did not carry every control into the engine (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_missing 11)" = "-" ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }the previous offer's lines never show the engine's pad holding $(consume_missing 11), so those controls were drawn and not read (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    [ "$(consume_field 12)" -ge 1 ] \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }no consume: line names a front-end scene, so a press cannot be paired with the scene it landed in (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    { [ "$(consume_field 13)" -gt 0 ] && [ "$(consume_field 14)" -eq 0 ]; } \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }no consume: line shows the engine's own pad holding the main stick at the value the previous offer made for it, so the stick moved on screen without reaching the engine (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    { [ "$(consume_field 15)" -gt 0 ] && [ "$(consume_field 16)" -eq 0 ]; } \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }no consume: line shows the engine's own pad holding the C-stick at the value the previous offer made for it, so the camera stick moved on screen without reaching the engine (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
    { [ "$(consume_field 17)" -gt 0 ] && [ "$(consume_field 18)" -eq 0 ]; } \
        || CONSUME_FAIL="${CONSUME_FAIL:+$CONSUME_FAIL; }no consume: line shows the engine's own pad holding a shoulder trigger at the value the previous offer made for it, so a shoulder moved on screen without reaching the engine (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: ${CONSUME_SUMMARY})"
fi
if [ -z "$READBACK_FAIL" ]; then
    printf "S.r1.settings-readback\tPASS\t%s display, %s settings, %s shoulder, %s audio (of which %s name the mixer's own fields) and %s overlay lines (over %s alpha for the A control) plus %s c-stick lines, %s shoulder-outline lines (total/presses/l-press/r-detent/l-thick/r-thick-editor/unreadable) and %s shoulder-mirror readings (total/rest/mirrored/skew/on-L's-row/editor/unreadable), written by the app itself\tapp-readbacks.txt\n" "$DISPLAY_LINES" "$SETTINGS_LINES" "$SHOULDER_LINES" "$AUDIO_LINES" "$AUDIO_MIX_LINES" "$OVERLAY_LINES" "$OVERLAY_ALPHAS" "$CSTICK_LINES" "$OUTLINE_SUMMARY" "$MIRROR_SUMMARY" >> "$ROWS"
else
    printf "S.r1.settings-readback\tFAIL\t%s\tapp-readbacks.txt\n" "$READBACK_FAIL" >> "$ROWS"
fi

# -- What the engine did with the controls -----------------------------------
# F04's own row, and the one row in this script that no screenshot could decide. The front-end suite
# proves a control was drawn pressed and that the port was handed a value; this proves the engine's
# own pad held it, which is the reading doc 34 asks for when it says a button being hittable does not
# prove that the game consumed its input. What carries the row is the pairing: the engine's sample
# holds the port's clamp of the *previous* poll's offer, plus the port's own left-analog-to-d-pad bits
# when the map reaches them, and that pairing accounts for every line with no engine error while the
# same-frame offer accounts for strictly fewer -- a contrast only a real clamp between two offers can
# produce, and one a reader can check without knowing the port's frame order. Agreement and coverage
# are what turn the pairing into "every control reaches the engine": a mask equal to the previous
# offer's, seen across all twelve controls. The row text states each of those counts so a reader can
# see the measurement rather than the verdict alone.
if [ -z "$CONSUME_FAIL" ]; then
    printf "S.f04.engine-consumption\tPASS\t%s consume: lines, %s of them with no engine pad error, of which %s hold a mask equal to the previous poll's offer and %s also carry the port's own d-pad bits (%s in total, leaving the same-frame offer to explain only %s); covering %s of the twelve controls (missing %s) across %s front-end scenes; the main stick held the previous offer's clamp on %s of %s moving lines, the C-stick on %s of %s and the triggers on %s of %s, with %s lines carrying an extra bit the offers never made and %s unreadable (total/ok/errored/prevall/dpad/nowall/bmissing/bextra/agree/coverage/missing/scenes/stick-lines/stick-bad/sub-lines/sub-bad/trig-lines/trig-bad/unreadable: %s), read from the port's own pad rather than from a screenshot\tapp-readbacks.txt\n" "$(consume_field 1)" "$(consume_field 2)" "$(consume_field 4)" "$(consume_field 5)" "$(consume_explained)" "$(consume_field 6)" "$(consume_field 10)" "$(consume_missing 11)" "$(consume_field 12)" "$(( $(consume_field 13) - $(consume_field 14) ))" "$(consume_field 13)" "$(( $(consume_field 15) - $(consume_field 16) ))" "$(consume_field 15)" "$(( $(consume_field 17) - $(consume_field 18) ))" "$(consume_field 17)" "$(consume_field 8)" "$(consume_field 19)" "$CONSUME_SUMMARY" >> "$ROWS"
else
    printf "S.f04.engine-consumption\tFAIL\t%s\tapp-readbacks.txt\n" "$CONSUME_FAIL" >> "$ROWS"
fi

# -- Screenshots -------------------------------------------------------------
# The tests attach a screenshot at each claim, and the result bundle is where they live.
# Exporting them is evidence gathering rather than a verdict, so a failure here is
# reported and does not change the rows.
ATTACH="${PROOF_DIR}/attachments"
if [ -d "$XCRESULT" ]; then
    if ! xcrun xcresulttool export attachments --path "$XCRESULT" --output-path "$ATTACH" >> "$LOG" 2>&1; then
        warn "could not export attachments from ${XCRESULT}; the result bundle still holds them"
    fi
fi

# -- What the importer left behind -------------------------------------------
# The suite decides the rows; this is the container's own state afterwards, which is what a
# reader needs in order to see that "staged and activated" happened on disk rather than only in
# an alert. It also re-checks the two things a refusal is required not to touch: the file the
# player chose, and the disc image the fixtures were derived from.
STORE_INVENTORY="${PROOF_DIR}/store-inventory.txt"
log_new "$STORE_INVENTORY"
{
    printf 'container documents: %s\n' "${FILES_DIR}"
    printf 'store path: %s\n' "${FILES_DIR}/BallpadGameData"
    printf 'activation record: %s\n' \
        "$(cat "${FILES_DIR}/BallpadGameData/current" 2>/dev/null || printf 'absent')"
    find "${FILES_DIR}" -mindepth 1 -maxdepth 3 -print0 2>/dev/null \
        | xargs -0 stat -f '%z bytes  %N' 2>/dev/null | sort -k3 || true
    printf 'source image %s\n' "$(sha256_of "$GAME_IMAGE")"
    for fixture in uitest-valid.iso uitest-truncated.iso uitest-wronggame.iso; do
        printf 'chosen file %s\n' "$(sha256_of "${FILES_DIR}/${fixture}")"
    done
} >> "$STORE_INVENTORY"
log "store inventory: ${STORE_INVENTORY}"

set +e
python3 "${BALLPAD_ROOT}/scripts/native/lib/suite_report.py" \
    --suite "uitest" --platform simulator --device "$DEVICE" --bundle-id "$IOS_BUNDLE_ID" \
    --run-id "$RUN_TAG" --proof-dir "$PROOF_DIR" --configuration "$CONFIGURATION" \
    --expect "$EXPECTED" \
    --command "scripts/native/run-uitests.sh --run-id ${RUN_TAG} --device ${DEVICE}" \
    < "$ROWS"
status=$?
set -e

log "proof bundle: ${PROOF_DIR}"
exit "$status"

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
BUDGET="1200"
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
)
EXPECTED="S.run,S.provenance"
for spec in "${TEST_ROW_SPECS[@]}"; do
    EXPECTED="${EXPECTED},${spec%%=*}"
done

# -- Own the device ----------------------------------------------------------
sim_lock_acquire
preflight "lock held; boot ${DEVICE}"
xcrun simctl bootstatus "$DEVICE" -b || die "Simulator ${DEVICE} did not reach booted"
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
if [ "$?" != "0" ]; then
    warn "no test rows could be read from ${XCRESULT}; every required test row fails"
fi
set -e

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

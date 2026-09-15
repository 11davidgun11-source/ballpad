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

# R2's audio half cannot be decided by a step either, and for a sharper reason than F04's: its claim
# is a relationship between two clocks rather than the presence of a line. The transport tick is
# 5 ms of audio, the loop frame is 1/60 s of game time, and sounds that arrive away from the models
# that speak them are what a run looks like when those two rates have parted -- which is why the
# seam read-back now prints its own frame count beside the transport tick. The reading is
# r2-onset-summary.awk, the same shape as f04-live-summary.awk, and like that one it prints numbers
# so each clause below can be stated rather than swallowed into a verdict.
if [ "$SCENARIO_NAME" = "r2-audio" ]; then
    # The sentinel is every field unreadable, so a bundle with no log at all fails the clauses
    # below rather than passing them vacuously.
    R2_SUMMARY="-1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1"
    if [ -f "${PROOF_DIR}/app.log" ]; then
        R2_SUMMARY="$(awk -f "${BALLPAD_ROOT}/scripts/native/r2-onset-summary.awk" "${PROOF_DIR}/app.log")"
    fi
    r2_field() { printf '%s' "$R2_SUMMARY" | awk -v n="$1" '{ print $n + 0 }'; }
    r2_seen() { printf '(lines/unread/measured/unmeasured/lead-lo/hi/mean/last/handovers/devhold/rate/drain-lo/hi/last/underruns/ticks-lo/hi/frames-lo/hi/wall/tick-hz/frame-hz/skew/fps: %s)' "$R2_SUMMARY"; }
    # Every reading in this row is a rate, and the shell own [ ] compares integers only.
    r2_between() { awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN { print (v + 0 >= lo + 0 && v + 0 <= hi + 0) ? 1 : 0 }'; }
    # The condition of a ternary that follows printf has to be parenthesised: host awk is BWK, which
    # still reads a bare < or > there as the output redirection it can also be, and the whole program
    # dies as a syntax error. Parenthesising costs nothing and is the difference between a reading
    # and a run of this block that prints awk errors instead of numbers.
    r2_gap() { awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; printf "%.1f", (d < 0) ? -d : d }'; }
    r2_tpf() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", (b != 0) ? a / b : 0 }'; }

    R2_TICK_HZ="$(r2_field 21)"
    R2_FRAME_HZ="$(r2_field 22)"
    R2_RATE="$(r2_field 11)"
    R2_DRAIN="$(r2_field 14)"
    R2_TPF="$(r2_tpf "$R2_TICK_HZ" "$R2_FRAME_HZ")"
    R2_SPREAD="$(r2_gap "$(r2_field 6)" "$(r2_field 5)")"
    R2_DRAIN_LO="$(awk -v r="$R2_RATE" 'BEGIN { printf "%.0f", r * 0.98 }')"
    R2_DRAIN_HI="$(awk -v r="$R2_RATE" 'BEGIN { printf "%.0f", r * 1.02 }')"
    R2_FAIL=""

    # Every read-back line has to be readable, or the clocks under it were never judged.
    if [ "$(r2_field 2)" -ne 0 ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }a read-back line carries a field this reading could not read, so the clocks under it were not judged $(r2_seen)"
    fi
    # Audio reached the device at all. With no measured line there is no onset to be early or late,
    # and every clause after this one would be arithmetic over nothing.
    if [ "$(r2_field 3)" -le 0 ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }not one read-back line carried an onset reading, so nothing the game produced was ever handed to the device $(r2_seen)"
    fi
    # A rate needs a window: the seam prints every two seconds, so under a minute is too short.
    if [ "$(r2_between "$(r2_field 20)" 60 1000000)" != "1" ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }the read-back covered $(r2_field 20) s of the run, too short for a per-second rate to mean anything $(r2_seen)"
    fi
    # The device was never caught with an empty queue, so nothing was dropped mid-stream. This is
    # the simplest reading of the operator report, and it is ruled out here rather than assumed.
    if [ "$(r2_field 15)" -ne 0 ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }the transport found its queue empty $(r2_field 15) time(s), so audio was dropped mid-stream $(r2_seen)"
    fi
    # A queue length is a length in time only if the bytes leave at the rate the format implies.
    if [ "$(r2_between "$R2_DRAIN" "$R2_DRAIN_LO" "$R2_DRAIN_HI")" != "1" ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }the stream drained at $R2_DRAIN B/s against the $R2_RATE B/s its format implies (band $R2_DRAIN_LO-$R2_DRAIN_HI), so the lead is not a length of time $(r2_seen)"
    fi
    # The delay itself. The transport keeps kTargetBuffers = 6 buffers of 5 ms queued, so the newest
    # audio should sit around 30 ms behind the frame that made it: near zero would be an empty queue,
    # and past 60 ms would be more than three frames of audio the game has already produced.
    if [ "$(r2_between "$(r2_field 7)" 15 60)" != "1" ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }the newest audio ran a mean of $(r2_field 7) ms behind the frame that produced it, outside the 15-60 ms its 30 ms feed target allows $(r2_seen)"
    fi
    # And it has to be stable: a delay that sawtooths is heard as drift even when its mean is right.
    if [ "$(r2_between "$R2_SPREAD" 0 40)" != "1" ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }that delay swung over $R2_SPREAD ms between its smallest and largest sample, so it is not a steady lag $(r2_seen)"
    fi
    # The frame clock, and the reason this is a sync row rather than a performance row: the game is
    # hard-locked to the NTSC field -- 23 VIWaitForRetrace calls across the tree, and no frame-rate
    # decoupling anywhere -- so a loop that runs above it does not buy frames, it buys speed. The
    # models then cover their animation 5% faster than the audio device, which is driven by real
    # time, consumes its ticks, and the two halves of one moment part. 59-61 is the band the lock
    # itself allows.
    if [ "$(r2_between "$R2_FRAME_HZ" 59 61)" != "1" ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }the loop ran $R2_FRAME_HZ frames a second against the 60 the game is hard-locked to, so game time and the audio device clock are not the same clock $(r2_seen)"
    fi
    # The reading the operator report turns on: audio time the transport consumed per frame the loop
    # counted, against the 200/60 = 3.333 that one 60 Hz frame is. 100% is the two clocks agreeing.
    # 3% is the room the transport's 5 ms tick quantisation needs when the frames are right.
    if [ "$(r2_between "$(r2_field 23)" 97 103)" != "1" ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }a frame carried $R2_TPF ticks of audio where a 60 Hz frame is 3.333, so the skew is $(r2_field 23)% and the audio and the frames are not one clock $(r2_seen)"
    fi
    # Two independent measures of the frame rate -- the port rolling window and the seam count --
    # landing in the same band is what makes the skew above a reading of the game rather than of one
    # counter. They are not compared to each other: one is a window and one is a whole-run mean, so
    # requiring them equal would be comparing a sample to an average.
    if [ "$(r2_between "$(r2_field 24)" 59 61)" != "1" ]; then
        R2_FAIL="${R2_FAIL:+$R2_FAIL; }the port own rolling fps says $(r2_field 24), so the seam count of $R2_FRAME_HZ is not the loop rate alone $(r2_seen)"
    fi

    if [ -z "$R2_FAIL" ]; then
        printf 'S.r2.onset\tPASS\tthe transport ticked %.1f a second of audio beside the seam counting %.1f frames a second, over %.1f s of wall time read from the log itself: %s ticks per frame where a 60 Hz frame is 3.333, so a skew of %.1f%% -- the game\047s own rate and the device rate are one timeline -- with the newest audio %.1f ms behind the frame that produced it (run %.1f-%.1f, mean %.1f, spread %.1f ms), the stream draining at %.0f B/s against the %.0f its format implies, and %.0f underruns; the port own rolling fps %.1f is in the same band as the seam count (fields: %s)\t%s/app.log\n' "$R2_TICK_HZ" "$R2_FRAME_HZ" "$(r2_field 20)" "$R2_TPF" "$(r2_field 23)" "$(r2_field 8)" "$(r2_field 5)" "$(r2_field 6)" "$(r2_field 7)" "$R2_SPREAD" "$R2_DRAIN" "$R2_RATE" "$(r2_field 15)" "$(r2_field 24)" "$R2_SUMMARY" "$(basename "$PROOF_DIR")" >> "$ROWS"
    else
        printf 'S.r2.onset\tFAIL\t%s\t%s/app.log\n' "$R2_FAIL" "$(basename "$PROOF_DIR")" >> "$ROWS"
    fi
    EXPECT="${EXPECT},S.r2.onset"
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

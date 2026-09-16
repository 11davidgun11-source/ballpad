# The port's own per-frame benchmark record, reduced to the numbers doc 34's endurance row asks
# for.
#
# Input is the CSV the port writes when STRIKERS_BENCH_RECORD names a path
# (src/platform/benchmark.c, write_csv): one leading `# build=... key=value` comment and then
# `frame,busy_us,present_us,frame_us,phase`, one row per frame of the match in match order, with
# everything measured before the match already discarded by PortBenchMatchActive. The rows are
# therefore the match and only the match, and the discarded prefix is reported by the port's own
# summary rather than reconstructed here -- and by frames-trace-summary.awk, which reduces the
# whole-process trace where the cold segment does survive.
#
# phase is the game's own eGameState for the frame, latched by cGame::Update and stored with the
# frame (PortBenchPhase). It is what lets the frame-rate gates be stated over the segments doc 34
# names rather than over "the match" as one lump: live play is state 4 (gameplay) and 5 (overtime),
# and the goal/replay segment the second, lower gate is about is state 2 (post-goal). The legend is
# the engine's own -- benchmark.c prints it beside these counts -- so this program does not invent a
# meaning for a number. It is a latch rather than a sampling of the state at frame end, so a state
# that lasted less than one produced frame can be attributed to the frame after it; that is
# reported rather than corrected, and the counts below are counts of frames as labelled.
#
# Why read the record instead of quoting the port's printed summary. The printed summary is the
# port's own reading of the same run; this program reduces the same evidence so each acceptance
# clause can be stated and checked separately, over a window this script chooses, instead of as
# one aggregate. Where both compute one statistic they must agree, and the run's row prints both
# so a disagreement is visible rather than averaged away.
#
# What "produced frame" means here, and why busy and present are added. benchmark.c lays a frame
# out as frame = busy + limiter sleep + present/drain, and takes `busy` as the tasks phase minus
# the sleep the frame limiter deliberately took inside that phase. Adding busy and present
# therefore gives the interval between two produced frames *without* the pacing sleep: the
# quantity doc 34's "at least 58 produced/rendered frames per second" is about, and the one that
# stays meaningful when the run is capped to the console's field rate. An uncapped run is read the
# same way, and the row says which it was. The frame total is reported beside it so that nothing
# is hidden by the subtraction, and the sleep is printed as its own field.
#
# Percentiles follow benchmark.c's own convention exactly -- p50 is the element at 0-based index
# n/2, and p95/p99 the elements at (size_t)(n*p) of the ascending series, with no interpolation --
# so this program reproduces the port's printed percentiles rather than approximating them. The
# element at a 0-based index is found by binary search over the value axis using the per-value
# counts, so nothing is sorted and nothing is buffered beyond the counts.
#
# Fields, in order:
#   1  rows       data rows read
#   2  warm       rows dropped as warm-up (-v warm=)
#   3  n          rows the statistics are over
#   4  mean       produced-frame interval mean, ms   (busy + present)
#   5  p95        produced-frame interval p95, ms
#   6  p99        produced-frame interval p99, ms
#   7  fps        produced frames per second, 1000 / mean
#   8  busyMean   cpu busy mean, ms
#   9  busyP95    cpu busy p95, ms
#  10  frameMean  frame total mean, ms (busy + sleep + present)
#  11  sleepMean  limiter sleep mean, ms
#  12  stalls     frames whose frame total exceeded -v stall= ms
#  13  stallMax   the largest frame total, ms
#  14  stallAt    its match frame index
#  15  fpsOk      1 when fps >= -v fps=
#  16  p95Ok      1 when p95 <= -v p95=
#  17  p99Ok      1 when p99 <= -v p99=
#  18  unread     rows this program could not read as four numeric fields
#
# Appended, because the endurance row's segment-specific clauses are separate questions from the
# whole-match ones above and a reader of an older bundle must still find fields 1-18 where it left
# them:
#  19  unphased    rows with no readable phase (the game had not reported a state yet)
#  20  preRows    rows in state 0
#  21  kickoffRows rows in state 1
#  22  goalRows   rows in state 2, the post-goal/replay segment
#  23  endRows    rows in state 3
#  24  playRows   rows in state 4, live gameplay
#  25  otRows     rows in state 5, overtime
#  26  otherRows  rows in a state above 5
#  27  activeN    playRows + otRows, the live-play segment
#  28  activeFps  produced frames per second over that segment
#  29  activeP95  its p95 produced-frame interval, ms
#  30  activeP99  its p99 produced-frame interval, ms
#  31  activePct  that segment as a percentage of n, so a flattering rate over a
#                 handful of frames is visible as one
#  32  goalFps    produced frames per second over the post-goal segment
#  33  goalP95    its p95, ms
#  34  activeOk   1 when activeFps >= -v fps= and activeP95 <= -v p95= and activeP99 <= -v p99=
#  35  goalOk     1 when goalFps >= -v gfps= and goalP95 <= -v gp95=

BEGIN {
    FS = ","
    if (warm == "") warm = 0
    if (stall == "") stall = 100
    if (fps == "") fps = 58
    if (p95 == "") p95 = 20
    if (p99 == "") p99 = 33.4
    if (gfps == "") gfps = 55
    if (gp95 == "") gp95 = 33.4
    unread = 0
    rows = 0
    n = 0
    sumProduced = 0
    sumBusy = 0
    sumFrame = 0
    sumSleep = 0
    unphased = 0
    activeN = 0
    activeSum = 0
    goalN = 0
    goalSum = 0
    activeMin = ""; activeMax = ""
    goalMin = ""; goalMax = ""
    stalls = 0
    stallMaxUs = 0
    stallAt = -1
    bMin = ""; bMax = ""
    dMin = ""; dMax = ""
    fMin = ""; fMax = ""
    stallUs = stall * 1000
}

# The comment the port writes above the rows names the build and the labels the run set. It is
# kept rather than skipped silently so the row can quote what the record says it measured.
/^#/ {
    header = $0
    next
}

# Blank lines, and the column header the port writes bare rather than as a comment (benchmark.c's
# write_csv). Neither is a row and neither is a malformed row, so neither may reach the unread
# count: a bundle whose record is intact but whose unread count is 1 fails a clause below.
/^[ \t]*$/ { next }
/^frame,/ { next }

{
    if (NF < 4) { unread++; next }
    if ($1 == "" || $2 == "" || $3 == "" || $4 == "") { unread++; next }
    f = $1 + 0; b = $2 + 0; p = $3 + 0; t = $4 + 0
    # The phase column is read leniently and reported rather than assumed: a record without it, or
    # with a phase that is not an integer, is counted in unphased and contributes to no segment, so
    # a run whose segmentation could not be read fails the segment clauses instead of passing them
    # over an empty subset.
    ph = -1
    if (NF >= 5 && $5 ~ /^-?[0-9]+$/) ph = $5 + 0
    rows++
    if (f < warm) next
    n++
    prod = b + p
    sumProduced += prod
    sumBusy += b
    sumFrame += t
    sumSleep += (t - prod)
    if (ph >= 0) phCnt[ph]++
    else unphased++
    # The two segments doc 34 gives their own thresholds. Both are read from the same latch as the
    # counts above, so the totals here agree with phRows there by construction rather than by
    # being computed twice.
    if (ph == 4 || ph == 5) {
        activeN++
        activeSum += prod
        activeCnt[prod]++
        if (activeMin == "" || prod < activeMin) activeMin = prod
        if (activeMax == "" || prod > activeMax) activeMax = prod
    } else if (ph == 2) {
        goalN++
        goalSum += prod
        goalCnt[prod]++
        if (goalMin == "" || prod < goalMin) goalMin = prod
        if (goalMax == "" || prod > goalMax) goalMax = prod
    }
    bCnt[b]++
    dCnt[prod]++
    fCnt[t]++
    if (bMin == "" || b < bMin) bMin = b
    if (bMax == "" || b > bMax) bMax = b
    if (dMin == "" || prod < dMin) dMin = prod
    if (dMax == "" || prod > dMax) dMax = prod
    if (fMin == "" || t < fMin) fMin = t
    if (fMax == "" || t > fMax) fMax = t
    if (t > stallUs) stalls++
    if (t > stallMaxUs) { stallMaxUs = t; stallAt = f }
}

function count_le(arr, v,   k, s) {
    s = 0
    for (k in arr)
        if ((k + 0) <= v)
            s += arr[k]
    return s
}

# The value at a 1-based position in the ascending series: the smallest value whose running count
# reaches that position. benchmark.c indexes a sorted copy, so position idx+1 is the element at
# 0-based index idx.
function value_at(arr, lo, hi, position,   mid) {
    while (lo < hi) {
        mid = int((lo + hi) / 2)
        if (count_le(arr, mid) >= position)
            hi = mid
        else
            lo = mid + 1
    }
    return lo
}

function pct(arr, lo, hi, count, p,   idx) {
    if (count <= 0) return 0
    idx = int(count * p)
    if (idx > count - 1) idx = count - 1
    if (idx < 0) idx = 0
    return value_at(arr, lo, hi, idx + 1)
}

function pct50(arr, lo, hi, count,   idx) {
    if (count <= 0) return 0
    idx = int(count / 2)
    if (idx > count - 1) idx = count - 1
    return value_at(arr, lo, hi, idx + 1)
}

END {
    if (n <= 0) {
        printf "%d %d 0 0 0 0 0 0 0 0 0 0 0 -1 0 0 0 %d 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n",
            rows, warm, unread
        exit 0
    }

    meanMs = (sumProduced / n) / 1000.0
    p95Ms = pct(dCnt, dMin, dMax, n, 0.95) / 1000.0
    p99Ms = pct(dCnt, dMin, dMax, n, 0.99) / 1000.0
    fpsVal = (meanMs > 0) ? (1000.0 / meanMs) : 0.0
    busyMeanMs = (sumBusy / n) / 1000.0
    busyP95Ms = pct(bCnt, bMin, bMax, n, 0.95) / 1000.0
    frameMeanMs = (sumFrame / n) / 1000.0
    sleepMeanMs = (sumSleep / n) / 1000.0

    # The segments. A segment with no rows at all reports 0 fps, which fails its clause: an
    # absent active segment is not a passing one, and the alternative -- printing nothing, or
    # borrowing the whole-match numbers -- is how a run that never reached live play would report
    # a fine frame rate.
    activeFps = 0.0; activeP95 = 0.0; activeP99 = 0.0; activePct = 0.0
    if (activeN > 0) {
        activeMeanMs = (activeSum / activeN) / 1000.0
        activeFps = (activeMeanMs > 0) ? (1000.0 / activeMeanMs) : 0.0
        activeP95 = pct(activeCnt, activeMin, activeMax, activeN, 0.95) / 1000.0
        activeP99 = pct(activeCnt, activeMin, activeMax, activeN, 0.99) / 1000.0
        activePct = 100.0 * activeN / n
    }
    goalFps = 0.0; goalP95 = 0.0
    if (goalN > 0) {
        goalMeanMs = (goalSum / goalN) / 1000.0
        goalFps = (goalMeanMs > 0) ? (1000.0 / goalMeanMs) : 0.0
        goalP95 = pct(goalCnt, goalMin, goalMax, goalN, 0.95) / 1000.0
    }

    printf "%d %d %d %.3f %.3f %.3f %.2f %.3f %.3f %.3f %.3f %d %.3f %d %d %d %d %d %d %d %d %d %d %d %d %d %d %.2f %.3f %.3f %.2f %.2f %.3f %d %d\n",
        rows, warm, n,
        meanMs, p95Ms, p99Ms, fpsVal,
        busyMeanMs, busyP95Ms, frameMeanMs, sleepMeanMs,
        stalls, stallMaxUs / 1000.0, stallAt,
        (fpsVal >= fps) ? 1 : 0,
        (p95Ms <= p95) ? 1 : 0,
        (p99Ms <= p99) ? 1 : 0,
        unread,
        unphased,
        phCnt[0] + 0, phCnt[1] + 0, phCnt[2] + 0, phCnt[3] + 0,
        phCnt[4] + 0, phCnt[5] + 0, phCnt[6] + 0,
        activeN,
        activeFps, activeP95, activeP99, activePct,
        goalFps, goalP95,
        ((activeN > 0 && activeFps >= fps && activeP95 <= p95 && activeP99 <= p99) ? 1 : 0),
        ((goalN > 0 && goalFps >= gfps && goalP95 <= gp95) ? 1 : 0)
}

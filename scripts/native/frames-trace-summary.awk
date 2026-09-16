# The whole-process frame trace, reduced to the two things doc 34 asks for that no other record can
# answer: what the cold segment cost, and which frames stalled.
#
# Input is the CSV the port writes when STRIKERS_BENCH_TRACE names a path
# (src/platform/benchmark.c, trace_frame):
#
#   frame,pre,phase,gap_us,busy_us,present_us,frame_us
#
# one row per produced frame of the process -- not per frame of the match, which is the difference
# between this file and frames.csv. The match record is what the frame-rate gates are stated over,
# and it deliberately throws away everything measured on the way in (PortBenchMatchActive resets the
# arrays on the first frame of the match), so the boot, the shader compiles, the asset loads and the
# loading screens exist only here. doc 34 asks for exactly those to be reported separately with a
# maximum duration, and for every stall over 100 ms to be reported rather than absorbed into a mean.
#
# pre is the port's own match flag: 1 on a frame produced before the match began, 0 on a frame of
# the match. That is the segmentation, and it is the engine's answer rather than the reader's guess
# -- a run whose match never started has no warm segment at all and is reported as such rather than
# being read as one long cold segment beside a flattering frame rate.
#
# gap_us is the interval between this frame and the previous produced frame, which is what a loading
# delay actually is: a frame that took 3 s to produce and a frame that took 16 ms to produce look
# the same in frame_us if the waiting happened outside the measured span. Both are reported, and the
# larger of the two in the cold segment is the loading/stall figure this file exists to print.
#
# frame_us is the whole frame including the pacing sleep, so it is the quantity a "frame took longer
# than 100 ms" clause is about: busy alone would call a frame fast that the limiter then slept
# through, and busy + present alone would hide a frame whose sleep ran long.
#
# Every stall over the threshold is not enumerated as a field, because the row's shape is fixed and
# a list is not: instead the count, the worst, the first and the last are reported, and every one of
# them is a row of the trace this file was given, which ships in the same proof bundle. The row says
# that rather than pretending a summary is a list.
#
# Fields, in order:
#   1  rows          data rows read
#   2  cold          rows produced before the match (pre=1)
#   3  warm          rows produced during the match (pre=0)
#   4  coldSpanS     wall time the cold segment took, s (sum of its gaps)
#   5  coldWorstMs   worst frame total in the cold segment, ms
#   6  coldWorstAt   its frame index
#   7  coldGapMaxMs  longest gap to the previous produced frame in the cold segment, ms
#   8  coldGapAt     the frame that ended that gap
#   9  stalls        frames whose frame total exceeded -v stall= ms, whole trace
#  10  stallMaxMs    the largest frame total in the trace, ms
#  11  stallMaxAt    its frame index
#  12  stallCold     of the stalls, how many were produced before the match
#  13  stallWarm     of the stalls, how many were produced during the match
#  14  coldFreeze    cold frames longer than -v freeze= ms (a freeze claimed as "loading")
#  15  warmFreeze    match frames longer than -v freeze= ms (a steady-state freeze)
#  16  warmWorstMs   worst frame total in the match segment, ms
#  17  warmWorstAt   its frame index
#  18  firstStallAt  frame index of the first stall over the threshold, -1 if there was none
#  19  lastStallAt   frame index of the last one
#  20  unread        rows that were not seven readable numeric fields

BEGIN {
    FS = ","
    if (stall == "") stall = 100
    if (freeze == "") freeze = 250
    stallUs = stall * 1000
    freezeUs = freeze * 1000
    rows = 0
    cold = 0
    warm = 0
    coldGapTotalUs = 0
    coldWorstUs = -1
    coldWorstAt = -1
    coldGapMaxUs = -1
    coldGapAt = -1
    stalls = 0
    stallMaxUs = -1
    stallMaxAt = -1
    stallCold = 0
    stallWarm = 0
    coldFreeze = 0
    warmFreeze = 0
    warmWorstUs = -1
    warmWorstAt = -1
    firstStallAt = -1
    lastStallAt = -1
    unread = 0
}

# The comment the port writes above the rows carries the build and the run's labels. It is kept out
# of the arithmetic and out of the unread count: it is not a row, and counting it as one would make
# every trace look like it had a malformed line.
/^#/ { next }

# The port writes a newline before the header, so the first line of the file is empty. A blank line
# is not a row and not a malformed row: skipping it here is what keeps the unread count a count of
# lines that actually failed to parse, which the row below treats as a hard failure.
/^[ \t]*$/ { next }

# The port's own column header, which is written bare rather than as a comment (benchmark.c's
# trace_frame). Recognised by name rather than by "the first row" so a trace that lost its header
# is not silently read one row short, and skipped without counting: a header is not a malformed row.
/^frame,/ { next }

{
    if (NF < 7) { unread++; next }
    if ($1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" || $7 == "")
        { unread++; next }

    rows++
    f = $1 + 0
    pre = $2 + 0
    gap = $4 + 0
    total = $7 + 0

    if (pre != 0) {
        cold++
        coldGapTotalUs += gap
        if (total > coldWorstUs) { coldWorstUs = total; coldWorstAt = f }
        if (gap > coldGapMaxUs) { coldGapMaxUs = gap; coldGapAt = f }
        if (total > freezeUs) coldFreeze++
    } else {
        warm++
        if (total > warmWorstUs) { warmWorstUs = total; warmWorstAt = f }
        if (total > freezeUs) warmFreeze++
    }

    if (total > stallMaxUs) { stallMaxUs = total; stallMaxAt = f }
    if (total > stallUs) {
        stalls++
        if (pre != 0) stallCold++
        else stallWarm++
        if (firstStallAt < 0) firstStallAt = f
        lastStallAt = f
    }
}

END {
    if (rows <= 0) {
        printf "%d 0 0 0 0 -1 0 -1 0 0 -1 0 0 0 0 0 -1 -1 -1 %d\n", rows, unread
        exit 0
    }
    printf "%d %d %d %.3f %.3f %d %.3f %d %d %.3f %d %d %d %d %d %.3f %d %d %d %d\n",
        rows, cold, warm,
        coldGapTotalUs / 1e6,
        (coldWorstUs < 0) ? 0 : coldWorstUs / 1000.0, coldWorstAt,
        (coldGapMaxUs < 0) ? 0 : coldGapMaxUs / 1000.0, coldGapAt,
        stalls, (stallMaxUs < 0) ? 0 : stallMaxUs / 1000.0, stallMaxAt,
        stallCold, stallWarm, coldFreeze, warmFreeze,
        (warmWorstUs < 0) ? 0 : warmWorstUs / 1000.0, warmWorstAt,
        firstStallAt, lastStallAt, unread
}

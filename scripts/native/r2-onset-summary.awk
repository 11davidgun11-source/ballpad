# Whether the sound the transport plays and the frames the game draws are on the same clock: the
# audio read-back line Ballpad's seam appends to the app's log every two seconds while the game is
# on screen.
#
# The operator's report is that the sounds "seem disconnected from the models speaking them". The
# half of that a mixer reading cannot reach is time rather than content -- a sound can be the right
# voice out of the right sample and still land late, or land on time and drift -- and the read-back
# line carries both clocks in one record:
#
#   ticks N        the transport's own tick. Every one of them is 640 bytes, i.e. 5 ms of *audio*
#                  at the port's 32 kHz s16 stereo, so its per-second rate is the audio clock and
#                  real time is 200 a second.
#   clock frame N  the seam's count of frames the port loop has run, one per PortHostUIFrame, so
#                  its per-second rate is the frame clock and the game's own rate is 60 a second.
#
# The skew between them is the number this program exists to print. One frame the game counts is
# 1/60 s of game time; the audio the transport consumes under one frame of real time is 5 ms a
# tick. When the two agree a frame carries 200/60 = 3.333 ticks and skew is 100%. Every percent
# away from that is audio time no frame accounted for, which is drift, and drift is exactly "the
# sounds are not where the models are": the error accumulates, so each voice lands further from the
# model that spoke it than the one before. The port's own rolling fps is printed last as a third
# reading of the same rate, to be judged against the seam's rather than against itself.
#
# The onset clause is the other half of the same question and it is a delay rather than a rate:
# "onset lead D min D max D mean D ms over N frames" is how much audio the game has already
# produced but the device has not played, sampled at each frame that handed audio over. Its spread
# comes with it because a delay is only a delay if it is stable, and "drain D B/s of R" comes with
# it because a queue length is only a length in time if the bytes leave at the rate the format
# implies: R is 32000 x 2 x 2, and a drain far from it means the lead is in some other unit.
#
# Fields, in order:
#   1  lines       [Ballpad] audio: read-back lines whose fields were all readable
#   2  unread      lines carrying a field this program needs but could not read
#   3  measured    readable lines that carried an onset reading
#   4  unmeasured  readable lines that said the onset was unmeasured
#   5  leadLo      the run's smallest newest-audio lead, ms, or -1 if never measured
#   6  leadHi      the run's largest, ms, or -1
#   7  leadMean    the run's mean, ms, or -1
#   8  leadLast    the newest-audio lead on the last measured line, ms, or -1
#   9  handovers   game frames that queued audio, from the last measured line, or -1
#  10  devhold     what the device holds ahead of the stream, ms
#  11  rate        the stream's byte rate that the drain is judged against
#  12  drainLo     the smallest drain on a measured line, B/s, or -1
#  13  drainHi     the largest, B/s, or -1
#  14  drainLast   the drain on the last measured line, B/s, or -1
#  15  underMax    the worst underrun count seen on any readable line
#  16  ticksLo     transport ticks on the first readable line
#  17  ticksHi     transport ticks on the last readable line
#  18  frameLo     seam frames on the first readable line
#  19  frameHi     seam frames on the last readable line
#  20  wall        seconds between those two lines, from the log's own timestamps
#  21  tickHz      audio ticks per second over that span, 200 being real time
#  22  frameHz     seam frames per second over that span
#  23  skew        audio ticks per frame as a percentage of the 3.333 a 60 Hz frame is
#  24  fpsLast     the port's own rolling fps on the last readable line, judged against 22
#
# Every field is a number, and a field this program cannot read counts as unread rather than as
# zero, because a zero would read as a measurement.

# The k-th number appearing after the phrase in key, or "" when the phrase or that number is not in
# the line. Walked as tokens rather than by field position, so a line that grows a clause in the
# middle does not silently renumber the one being read.
function after(line, key, k,    at, rest, n, tok, i, seen) {
    at = index(line, key)
    if (at == 0)
        return ""
    rest = substr(line, at + length(key))
    n = split(rest, tok, " ")
    seen = 0
    for (i = 1; i <= n; i++)
        if (tok[i] ~ /^[0-9]+(\.[0-9]+)?$/) {
            seen++
            if (seen == k)
                return tok[i]
        }
    return ""
}

# Seconds within the day of the log line's own leading stamp, or -1 when there is none. Host awk is
# BWK, which has no mktime and no strftime, so the arithmetic is done here.
function stamp(line,    t, d, c, s) {
    if (!match(line, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9]/))
        return -1
    t = substr(line, RSTART, RLENGTH)
    split(t, d, " ")
    split(d[2], c, ":")
    split(c[3], s, ".")
    return (c[1] + 0) * 3600 + (c[2] + 0) * 60 + (s[1] + 0) + (s[2] + 0) / 1000.0
}

BEGIN {
    t0 = -1
    t1 = -1
    leadLo = -1
    leadHi = -1
    leadMean = -1
    leadLast = -1
    handovers = -1
    drainLo = -1
    drainHi = -1
    drainLast = -1
}

# Normalize before any rule reads fields: the port's own records can arrive CRLF-terminated, and a
# phrase lookup against a field would otherwise never hold. Assigning to $0 re-splits.
{ sub(/\r$/, "") }

# The seam's read-back, anchored on the seam's own prefix and the two states it prints: the port's
# own [port] audio: lines carry the word audio: and the words ticks and buffer too, and they are
# not read-backs.
/\[Ballpad\] audio: (start-up|running) -- device / {
    ticks = after($0, "ticks ", 1)
    und = after($0, "underruns ", 1)
    frm = after($0, "clock frame ", 1)
    fps = after($0, "clock frame ", 2)
    st = stamp($0)
    if (ticks == "" || und == "" || frm == "" || fps == "" || st < 0) {
        unread++
        next
    }

    # The onset clause is a group: when it is there it brings its spread and its drain with it, and
    # when it is not there the line says so in words. A line with neither -- an older build's
    # read-back -- cannot be judged at all and counts as unread rather than as a run without onset.
    lead = after($0, "onset lead ", 1)
    quiet = index($0, "onset unmeasured")
    if (lead == "") {
        if (quiet == 0) {
            unread++
            next
        }
        got = 0
    } else {
        dev = after($0, "devhold ", 1)
        rate = after($0, "drain ", 2)
        if (dev == "" || rate == "") {
            unread++
            next
        }
        got = 1
    }

    lines++
    if (und + 0 > underMax)
        underMax = und + 0

    if (got == 0) {
        unmeasured++
        next
    }
    measured++
    # The span is opened by the first *measured* line and closed by the last, not by the first and
    # last readable ones: a line that says the onset is unmeasured is a line where nothing has been
    # queued yet, and time before the audio clock started is not time either clock was running. The
    # window is therefore exactly the stretch both clocks were live, which is the only stretch the
    # skew between them means anything over. Unreadable lines never open or close it either.
    if (measured == 1) {
        ticksLo = ticks + 0
        frameLo = frm + 0
        t0 = st
    }
    ticksHi = ticks + 0
    frameHi = frm + 0
    fpsLast = fps + 0
    t1 = st
    # lead, min, max and mean are the transport's own running figures, so the last measured line
    # carries the run's extremes and the run's mean rather than a sample of them.
    leadLast = lead + 0
    leadLo = after($0, "onset lead ", 2) + 0
    leadHi = after($0, "onset lead ", 3) + 0
    leadMean = after($0, "onset lead ", 4) + 0
    handovers = after($0, "onset lead ", 5) + 0
    devhold = dev + 0
    rate = rate + 0
    dr = after($0, "drain ", 1) + 0
    drainLast = dr
    if (drainLo < 0 || dr < drainLo)
        drainLo = dr
    if (dr > drainHi)
        drainHi = dr
}

END {
    # The two clocks, each as its own per-second rate over the same span of the log's own wall
    # time, and then the one number the operator's report is about: how much audio time the
    # transport consumed per frame the loop counted, against the 200/60 a 60 Hz frame is.
    span = 0
    if (t0 >= 0 && t1 >= t0)
        span = t1 - t0
    else if (t0 >= 0 && t1 >= 0)
        span = t1 + 86400 - t0
    tickHz = 0
    frameHz = 0
    skew = 0
    if (span > 0) {
        tickHz = (ticksHi - ticksLo) / span
        frameHz = (frameHi - frameLo) / span
        if (frameHz > 0)
            skew = 100.0 * (tickHz / frameHz) / (200.0 / 60.0)
    }
    printf "%d %d %d %d %.1f %.1f %.1f %.1f %d %.1f %.0f %.0f %.0f %.0f %d %.0f %.0f %.0f %.0f %.2f %.1f %.1f %.1f %.1f\n", lines + 0, unread + 0, measured + 0, unmeasured + 0, leadLo + 0, leadHi + 0, leadMean + 0, leadLast + 0, handovers + 0, devhold + 0, rate + 0, drainLo + 0, drainHi + 0, drainLast + 0, underMax + 0, ticksLo + 0, ticksHi + 0, frameLo + 0, frameHi + 0, span + 0, tickHz + 0, frameHz + 0, skew + 0, fpsLast + 0
}

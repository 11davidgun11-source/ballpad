# What the endurance run's own match did, reduced from the [match] lines the port prints about once
# a second while STRIKERS_LOG_MATCH is set (src/Game/Game.cpp):
#
#   [match] ms=<wall ms> upd=<updates> t=<clock>/<duration> state=<n> ot=<n> score <h>-<a> ball=(x,y,z)
#
# ms and upd are what make this file able to answer doc 34's clock clause. A clock value is a state;
# "in-game clock progression ... compared against the desktop reference ... within 2%" is a rate,
# and a rate needs two samples of one quantity across wall time. ms is the monotonic instant the line
# was written, t is the game's own clock at that instant, and upd is the count of cGame::Update
# calls behind it, so dividing each by ms gives both rates on the same run. upd advances by exactly
# the cadence the printer counts between two lines, so an update that was skipped or repeated shows
# up as a step that is not the cadence rather than as slow drift in a ratio.
#
# The window. doc 34 asks for the comparison over at least 60 seconds of active, unpaused play, so
# the window is the longest run of consecutive samples whose own state value is 4 -- the game's
# gameplay state, not a number this program assigned -- and the row fails if that run is shorter
# than a minute. Consecutive means the [match] line between them was also state 4: a goal, a replay,
# a kickoff or a loading screen breaks the run rather than being averaged into it, and overtime
# (state 5) is deliberately not folded in, because whether its clock runs the same way is a
# different question from whether the regulation clock tracks real time. Every rate below is
# computed inside that one window, from its first sample to its last.
#
# What is reported about the window's intervals, and why the window is not just two numbers. A rate
# computed from the endpoints alone cannot tell a steady clock from one that stalled for ten seconds
# and then ran fast to catch up, and those are different findings about the same 2%. So the upd
# steps are reduced to the smallest, the largest and the count that differed from the cadence, and
# the clock's backwards steps are counted: a window that is one rate made of two opposite errors is
# visible here instead of being hidden by a mean.
#
# Why this is a separate reading from the frame record. The benchmark CSV says how the run
# performed; it does not say what the run was doing, and doc 34's endurance row is about sustained
# play and repeated match loads rather than about a number of frames. Two claims in the row need
# this file: that the measured window really was live play, and that the run contained load/play/
# return cycles rather than one unbroken scene. A cycle is read as the match clock going backwards
# between two samples -- a match restarting cannot be confused with a clock that is merely standing
# still, and the once-a-second cadence makes a backwards step of more than a second unambiguous.
#
# state is the game's own GetGameState(), so which values appear is evidence rather than a lookup
# table this program invents. The counts are reported per state value encountered so the row can
# name the phases that were actually live without this program claiming what a state number means.
#
# Fields, in order:
#   1  lines      [match] lines read
#   2  unread     lines whose clock or state could not be read
#   3  states     distinct state values seen
#   4  live       lines whose state is 4 (live play)
#   5  goalish    lines whose state is 2 (the match's own post-goal state)
#   6  idle       lines whose state is 0 (nothing being played)
#   7  other      lines in a state that is none of those three
#   8  cycles     times the clock stepped backwards: a new match began
#   9  clockMax   the largest clock value seen, seconds
#  10  durMax     the largest duration seen, seconds
#  11  scoreMax   the highest combined score seen
#  12  sdLines    lines with ot set, sudden death
#  13  scores     score increases seen, home+away
#  14  firstState the first readable state
#  15  lastState  the last readable state
#
# Appended, because the clock/rate clauses are separate questions from the state census above and a
# reader of an older bundle must still find fields 1-15 where it left them:
#  16  msLines    lines carrying a readable ms=
#  17  updLines   lines carrying a readable upd=
#  18  winSamples samples in the chosen window
#  19  winStartMs its first sample's ms
#  20  winEndMs   its last sample's ms
#  21  winSpanS   the wall time it covers, s
#  22  winClockS  the game clock it advanced, s
#  23  winUpd     the updates it ran
#  24  clockRate  winClockS / winSpanS, game seconds per wall second
#  25  clockPctIdeal  its distance from 1.0, as a percentage of 1.0
#  26  updRate    winUpd / winSpanS, updates per wall second
#  27  updPctCadence its distance from -v cadence=, as a percentage of it
#  28  updJumps   intervals in the window whose update step was not the cadence
#  29  updMinStep the smallest step, -1 if the window had no interval
#  30  updMaxStep the largest
#  31  clockBacks intervals in the window where the clock went backwards
#  32  windows    state-4 runs at least -v need= seconds long, anywhere in the run
#  33  enough     1 when the chosen window is at least that long

BEGIN {
    if (need == "") need = 60
    if (cadence == "") cadence = 60
    lines = 0
    unread = 0
    msLines = 0
    updLines = 0
    n4 = 0
    prevWas4 = 0
    live = 0
    goalish = 0
    idle = 0
    other = 0
    cycles = 0
    clockMax = 0
    durMax = 0
    scoreMax = 0
    sdLines = 0
    scores = 0
    prevClock = -1
    prevScore = -1
    firstState = -1
    lastState = -1
}

/^\[match\] / {
    lines++
    clock = ""
    state = ""
    total = ""
    ot = ""
    ms = ""
    upd = ""

    for (i = 1; i <= NF; i++) {
        if ($i ~ /^ms=/) {
            split($i, parts, "=")
            ms = parts[2] + 0
        } else if ($i ~ /^upd=/) {
            split($i, parts, "=")
            upd = parts[2] + 0
        } else if ($i ~ /^t=/) {
            split($i, parts, "=")
            split(parts[2], halves, "/")
            clock = halves[1] + 0
            dur = halves[2] + 0
        } else if ($i ~ /^state=/) {
            split($i, parts, "=")
            state = parts[2] + 0
        } else if ($i ~ /^ot=/) {
            split($i, parts, "=")
            ot = parts[2] + 0
        } else if ($i == "score") {
            # The score is printed as two integers after the tag rather than as one field, so it is
            # read by position and guarded: a line that lost its score is counted unread below
            # rather than contributing a zero.
            if ($(i + 1) ~ /^[0-9]+$/ && $(i + 2) ~ /^[0-9]+$/) {
                total = ($(i + 1) + 0) + ($(i + 2) + 0)
            }
        }
    }

    if (clock == "" || state == "") {
        unread++
        # An unreadable line is evidence against a continuous state-4 run, not a gap to be stepped
        # over: it is the one line in the window whose state this program cannot vouch for, so the
        # run it sits inside ends here rather than being joined across to the next readable sample.
        prevWas4 = 0
        next
    }

    if (ms != "") msLines++
    if (upd != "") updLines++

    # One sample of a possible window. It is stored only when the line carried both rate fields, so
    # a record from a build that predates them yields no window at all and fails the clause below
    # rather than computing a rate from a clock and no wall time.
    if (state == 4 && ms != "" && upd != "") {
        n4++
        s4ms[n4] = ms
        s4clk[n4] = clock
        s4upd[n4] = upd
        s4cont[n4] = prevWas4
        prevWas4 = 1
    } else {
        # Anything else ends the run -- including a state-4 line this program could not use, which
        # must break the window rather than be joined across.
        prevWas4 = 0
    }

    if (state != 0 && state != 2 && state != 4) seen[state]++
    if (state == 4) live++
    else if (state == 2) goalish++
    else if (state == 0) idle++
    else other++

    if (firstState < 0) firstState = state
    lastState = state

    if (clock > clockMax) clockMax = clock
    if (dur != "" && dur > durMax) durMax = dur
    if (ot != "" && ot != 0) sdLines++

    if (total != "") {
        if (prevScore >= 0 && total > prevScore) scores++
        if (total > scoreMax) scoreMax = total
        prevScore = total
    }

    # A backwards step of more than a second is a restart. The clock is sampled once a second, so a
    # smaller backwards step would be reading the sample cadence rather than a new match.
    if (prevClock >= 0 && clock < prevClock - 1.0) cycles++
    prevClock = clock
}

END {
    distinct = 0
    for (k in seen) distinct++

    # Walk the stored state-4 samples as maximal runs and keep the longest. The winner is kept by
    # index rather than by copying numbers, so the interval statistics below are computed over the
    # same samples the span was measured from.
    bestSpan = -1
    windows = 0
    bI = 0
    bJ = 0
    i = 1
    while (i <= n4) {
        j = i
        while (j + 1 <= n4 && s4cont[j + 1] == 1) j++
        span = (s4ms[j] - s4ms[i]) / 1000.0
        if (span >= need) windows++
        if (span > bestSpan) { bestSpan = span; bI = i; bJ = j }
        i = j + 1
    }

    winSamples = 0
    winStartMs = -1
    winEndMs = -1
    winClockS = 0
    winUpd = 0
    updJumps = 0
    updMinStep = -1
    updMaxStep = -1
    clockBacks = 0
    if (n4 > 0) {
        winSamples = bJ - bI + 1
        winStartMs = s4ms[bI]
        winEndMs = s4ms[bJ]
        winClockS = s4clk[bJ] - s4clk[bI]
        winUpd = s4upd[bJ] - s4upd[bI]
        for (k = bI + 1; k <= bJ; k++) {
            step = s4upd[k] - s4upd[k - 1]
            if (step != cadence) updJumps++
            if (updMinStep < 0 || step < updMinStep) updMinStep = step
            if (step > updMaxStep) updMaxStep = step
            if (s4clk[k] < s4clk[k - 1]) clockBacks++
        }
    }
    if (bestSpan < 0) bestSpan = 0

    clockRate = 0
    clockPctIdeal = 0
    updRate = 0
    updPctCadence = 0
    enough = 0
    if (bestSpan > 0) {
        clockRate = winClockS / bestSpan
        updRate = winUpd / bestSpan
        dev = clockRate - 1.0
        if (dev < 0) dev = -dev
        clockPctIdeal = 100.0 * dev
        dev = updRate - cadence
        if (dev < 0) dev = -dev
        updPctCadence = 100.0 * dev / cadence
    }
    if (bestSpan >= need) enough = 1

    printf "%d %d %d %d %d %d %d %d %.1f %.1f %d %d %d %d %d %d %d %d %.0f %.0f %.3f %.3f %d %.6f %.3f %.4f %.3f %d %d %d %d %d %d\n",
        lines, unread, distinct, live, goalish, idle, other,
        cycles, clockMax, durMax, scoreMax, sdLines, scores,
        firstState, lastState,
        msLines, updLines,
        winSamples, winStartMs, winEndMs, bestSpan, winClockS, winUpd,
        clockRate, clockPctIdeal, updRate, updPctCadence,
        updJumps, updMinStep, updMaxStep, clockBacks,
        windows, enough
}

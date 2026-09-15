# What the engine's own pad held while a real match was on screen, from the port's own consume:
# lines, and whether the game answered a press whose mapping can be watched in its own state.
#
# Input is the app's own log from tests/native/scenarios/f04-live-match.scn. Every consume: line is
# one frame in which the port's PadStatus::s_Current[0] changed, printed from inside the host's
# frame tick beside the offer the host made for that frame. The scenario holds the main stick and
# then presses each control in turn, so what this program measures is the reading doc 34's F04 wants
# on a *live match* rather than on a menu: a nonzero main stick and a nonzero action mask in the
# same sample the game's tasks read, and a press the game itself answers.
#
# The bracket is not a stopwatch. The scenario dumps the port's own match state before the sweep and
# again after it, and do_dump prints "[dump] match valid=1 state=N ..." -- so the region counted here
# is the region the engine said was a live match, opened by the first dump and closed by the second
# whatever state the second names. A run whose dumps never appear reads as bracket 0 and fails
# rather than silently measuring the whole log.
#
# Fields, in order:
#   1 total        consume: lines inside the bracket whose fields were readable
#   2 ok           those the engine reported no pad error on
#   3 errored      those it reported one on
#   4 simult       ok lines whose engine pad held a nonzero main stick *and* a nonzero mask
#   5 covered      of the twelve controls, how many of them those lines held
#   6 missing      the controls never seen in one, or - when the list is empty
#   7 sticknz      ok lines whose engine pad held a nonzero main stick
#   8 masks        distinct nonzero button masks among the simult lines
#   9 pause        dump lines after the bracket opened naming the front-end pause menu as open
#  10 bracket      0 the dumps never named a match, 1 opened only, 2 opened and closed
#  11 state        the match state the opening dump named, or -1
#  12 stickval     the main stick on the first simult line, x,y, or - when there was none
#  13 unread       lines this program could not read

function hex2dec(h,   i, c, n, d) {
    sub(/^0x/, "", h)
    n = 0
    for (i = 1; i <= length(h); i++) {
        c = tolower(substr(h, i, 1))
        d = index("0123456789abcdef", c) - 1
        if (d < 0)
            return -1
        n = n * 16 + d
    }
    return n
}

function hasbit(n, bit) {
    return int(n / bit) % 2
}

BEGIN {
    split("1:LEFT 2:RIGHT 4:DOWN 8:UP 16:Z 32:R 64:L 256:A 512:B 1024:X 2048:Y 4096:START", w, " ")
    nwant = 12
    for (i = 1; i <= nwant; i++) {
        p = index(w[i], ":")
        wbit[i] = substr(w[i], 1, p - 1) + 0
        wname[i] = substr(w[i], p + 1)
    }
    livestate = -1
}

# Normalize before any rule reads fields. On the F04 bundle the port's own `[dump]` records arrive
# CRLF-terminated (the run that exposed this had `pause=1\r` as field 6), so a string comparison
# against a field would otherwise never hold. The match rule below survived it only because it coerces
# with +0; every rule here should not depend on that accident. Assigning to $0 re-splits on next access.
{ sub(/\r$/, "") }

# The bracket: the port's own match dump, opened by the first and closed by the second.
/^\[dump\] match / {
    if (bracket == 0) {
        bracket = 1
        for (i = 1; i <= NF; i++)
            if ($i ~ /^state=/) {
                s = $i
                sub(/^state=/, "", s)
                livestate = s + 0
            }
    } else if (bracket == 1) {
        bracket = 2
    }
    next
}

# The front-end pause menu, which is how this row reads the game's answer to a press rather than the
# press itself. Counted from the bracket's opening onwards, so the dump that closes the bracket is
# inside the window too: the press is executed later in a frame than PortDebugFrame fills the dump.
/^\[dump\] session / {
    if (bracket >= 1)
        for (i = 1; i <= NF; i++)
            if ($i == "pause=1")
                pauseopen++
    next
}

/ consume: / {
    if (bracket != 1)
        next
    vErr = ""
    vBtn = ""
    vStick = ""
    vScene = ""
    for (i = 1; i <= NF; i++) {
        if ($i == "--")
            break
        if ($i == "err")
            vErr = $(i + 1)
        else if ($i == "buttons")
            vBtn = $(i + 1)
        else if ($i == "stick")
            vStick = $(i + 1)
        else if ($i == "scene")
            vScene = $(i + 1)
    }
    if (vErr == "" || vBtn == "" || vStick == "" || vScene == "") {
        unread++
        next
    }
    bn = hex2dec(vBtn)
    if (bn < 0 || split(vStick, ea, ",") != 2) {
        unread++
        next
    }
    total++
    if (vErr + 0 != 0) {
        errored++
        next
    }
    ok++
    ex = ea[1] + 0
    ey = ea[2] + 0
    if (ex != 0 || ey != 0)
        sticknz++
    # The row's central reading: the game's own sample carrying a moved main stick and a pressed
    # control at the same time, which is the clause no single-finger touch can produce.
    if ((ex != 0 || ey != 0) && bn != 0) {
        simult++
        masks[bn] = 1
        if (firststick == "")
            firststick = vStick
        for (k = 1; k <= nwant; k++)
            if (hasbit(bn, wbit[k]) && !seen[k]) {
                seen[k] = 1
                ncov++
            }
    }
}

END {
    for (m in masks)
        nmask++
    miss = ""
    for (i = 1; i <= nwant; i++)
        if (!seen[i])
            miss = miss (miss == "" ? "" : ",") wname[i]
    printf "%d %d %d %d %d %s %d %d %d %d %d %s %d\n",
        total + 0, ok + 0, errored + 0, simult + 0, ncov + 0, (miss == "" ? "-" : miss),
        sticknz + 0, nmask + 0, pauseopen + 0, bracket + 0, livestate + 0,
        (firststick == "" ? "-" : firststick), unread + 0
}

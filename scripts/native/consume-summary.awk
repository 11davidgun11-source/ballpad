# What the engine's own pad held, read beside the offer the host made for the same frame.
#
# Input is the app's own log, and every consume: line in it is one frame where the port's
# PadStatus::s_Current[0] changed: the sample cPlatPad::IsPressed and the game's tasks read, printed
# beside the poll the adapter made for that frame. This program turns those lines into the nineteen
# numbers the runner's F04 row is judged from, so the row states a measurement rather than a verdict.
#
# The one asymmetry, and it is arithmetic rather than assumption. The port builds a frame in the
# order src/Game/main.cpp lays out: PortUpdateSyntheticInput (which calls PortHostUIPollPad), then
# PortHostUIFrame, then PortInvokePadSamplingCallback, which runs the registered VBlankPadUpdate --
# the pass that calls PADRead, clamps what it read and swaps it into PadStatus::s_Current. The
# adapter prints from inside PortHostUIFrame, so the sample it reads was assembled by the previous
# frame's VBlank pass, out of the previous frame's offer. That is why the engine's reading is
# compared against "prev" and only contrasted with "now": a row judged against the offer of the same
# frame disagrees on every ramp, and every disagreement is the game's own clamp of a value one poll
# back rather than a fault.
#
# The clamp is PADClampCircle in extern/aurora/lib/dolphin/pad/pad.cpp, whose ClampRegion holds
# triggers to 30..180, the main stick to a 15 deadzone and a 56 radius, and the C-stick to a 15
# deadzone and a 44 radius. Its arithmetic is restated here exactly: a component inside the deadzone
# becomes 0, a component outside it loses the deadzone, and a vector longer than the radius is
# scaled down with integer sqrt and truncating division.
#
# The one thing the engine adds on top of the offer is its own: platpad.cpp's left-analog-to-d-pad
# map ORs a compass sector into the sample's buttons whenever the sample's own clamped stick reaches
# 0.6 of the stick's radius, which is a bit the host never offered. The angle is carried the way the
# original carries it, through a 16-bit unsigned tick, so the sectors a negative angle wraps into are
# the sectors the port actually produces rather than the ones geometry would suggest.
#
# Fields, in order:
#   1 total        consume: lines whose every field was readable
#   2 ok           those with no engine pad error
#   3 errored      those the engine reported an error on
#   4 prevall      ok lines whose whole pad is the clamp of the previous poll's offer
#   5 dpad         ok lines whose pad is that clamp plus the port's own d-pad sector bits
#   6 nowall       ok lines whose whole pad is the clamp of the same frame's offer
#   7 bmissing     lines whose engine pad lacked a bit the previous poll's offer carried
#   8 bextra       lines whose engine pad carried a bit that offer lacked and the map does not explain
#   9 agree        lines whose engine pad is nonzero and equal to that offer's mask
#  10 ncov         of the twelve controls, how many those agreeing lines held
#  11 missing      the controls never seen in one, or - when the list is empty
#  12 scenes       distinct front-end scenes the lines name
#  13 sticknz      lines whose engine pad held a nonzero main stick
#  14 stickbad     of those, the lines whose main stick is not the clamp of the previous offer
#  15 subnz        lines whose engine pad held a nonzero C-stick
#  16 subbad       of those, the lines whose C-stick is not that clamp
#  17 trignz       lines whose engine pad held a nonzero shoulder trigger
#  18 trigbad      of those, the lines whose triggers are not that clamp
#  19 unread       lines this program could not read

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

# A field may not name a bit this program has no name for: a mask outside the twelve controls is an
# unreadable line rather than a silent zero.
function onlyknown(n,   bit) {
    for (bit = 1; bit <= 32768; bit *= 2)
        if (hasbit(n, bit) && !named[bit])
            return 0
    return 1
}

# clamptrig is ClampTrigger: below the minimum the trigger reads zero, above the maximum it reads the
# maximum, and what is left over is measured from the minimum -- so a full press of 255 is 150.
function clamptrig(v, mn, mx) {
    if (v <= mn)
        return 0
    if (v > mx)
        v = mx
    return v - mn
}

# clampxy is ClampCircle for one stick, and it leaves its answer in gx and gy because awk has one
# return value. Both axes are scaled by the same length, as the original does with its single integer
# sqrt, and each axis truncates toward zero, as the original's division does.
function clampxy(px, py, rad, mn,   len, l2) {
    if (px > -mn && px < mn)
        px = 0
    else if (px < 0)
        px += mn
    else
        px -= mn
    if (py > -mn && py < mn)
        py = 0
    else if (py < 0)
        py += mn
    else
        py -= mn
    l2 = px * px + py * py
    if (l2 > rad * rad) {
        len = int(sqrt(l2))
        if (len > 0) {
            px = int(px * rad / len)
            py = int(py * rad / len)
        }
    }
    gx = px
    gy = py
}

# sectorbits is platpad.cpp's left-analog-to-d-pad map, restated: it only fires past 0.6 of the
# stick's radius, it zeroes whichever component is inside that threshold, and it rounds the angle to
# one of eight 45 degree sectors before naming the buttons.
function sectorbits(sx, sy,   nx, ny, ax, ay, u, deg, rd) {
    nx = sx / 56.0
    ny = sy / 56.0
    ax = (nx < 0) ? -nx : nx
    ay = (ny < 0) ? -ny : ny
    if (ax < 0.6 && ay < 0.6)
        return 0
    if (ax >= 0.6 && ay >= 0.6) {
        # both components are past the threshold, so the angle decides
    } else if (ax >= 0.6) {
        ny = 0
    } else {
        nx = 0
    }
    u = int(atan2(ny, nx) * 10430.378)
    u = u % 65536
    if (u < 0)
        u += 65536
    deg = u * 0.005493164
    rd = int(int(deg) / 45) * 45
    if (rd == 0)
        return 2
    if (rd == 45)
        return 10
    if (rd == 90)
        return 8
    if (rd == 135)
        return 9
    if (rd == 180)
        return 1
    if (rd == 225)
        return 5
    if (rd == 270)
        return 4
    if (rd == 315)
        return 6
    return 0
}

# covers is a set test: 1 when every bit of own is also a bit of sup.
function covers(sup, own,   bit) {
    for (bit = 1; bit <= 32768; bit *= 2)
        if (hasbit(own, bit) && !hasbit(sup, bit))
            return 0
    return 1
}

# pair judges one line's engine pad against one offer, and leaves its answers in globals because awk
# has one return value: p_axok says the sticks and triggers are that offer's clamp, p_miss says the
# offer carried a bit the pad lacked, and p_unexplained says the pad carried a bit neither the offer
# nor the engine's own d-pad map accounts for.
function pair(offer, ostick, osub, otrig, ex, ey, esx, esy, etl, etr,   oa, ob, oc, bit, sx, sy, tx, ty) {
    p_axok = 0
    p_miss = 0
    p_unexplained = 0
    if (split(ostick, oa, ",") != 2 || split(osub, ob, ",") != 2 || split(otrig, oc, ",") != 2)
        return
    clampxy(oa[1] + 0, oa[2] + 0, 56, 15)
    sx = gx
    sy = gy
    clampxy(ob[1] + 0, ob[2] + 0, 44, 15)
    tx = gx
    ty = gy
    if (sx == ex && sy == ey && tx == esx && ty == esy &&
        clamptrig(oc[1] + 0, 30, 180) == etl &&
        clamptrig(oc[2] + 0, 30, 180) == etr)
        p_axok = 1
    if (!covers(bn, offer))
        p_miss = 1
    for (bit = 1; bit <= 32768; bit *= 2)
        if (hasbit(bn, bit) && !hasbit(offer, bit) && !hasbit(derived, bit))
            p_unexplained = 1
}

BEGIN {
    split("1:LEFT 2:RIGHT 4:DOWN 8:UP 16:Z 32:R 64:L 256:A 512:B 1024:X 2048:Y 4096:START", w, " ")
    nwant = 12
    for (i = 1; i <= nwant; i++) {
        p = index(w[i], ":")
        wbit[i] = substr(w[i], 1, p - 1) + 0
        wname[i] = substr(w[i], p + 1)
        named[wbit[i]] = 1
    }
}

/ consume: / {
    vErr = ""
    vBtn = ""
    vStick = ""
    vSub = ""
    vTrig = ""
    vNow = ""
    vNstick = ""
    vNsub = ""
    vNtrig = ""
    vPrev = ""
    vPstick = ""
    vPsub = ""
    vPtrig = ""
    vScene = ""
    for (i = 1; i <= NF; i++) {
        if ($i == "--")
            break
        if ($i == "err")
            vErr = $(i + 1)
        else if ($i == "buttons")
            vBtn = $(i + 1)
        else if ($i == "now")
            vNow = $(i + 1)
        else if ($i == "prev")
            vPrev = $(i + 1)
        else if ($i == "stick")
            vStick = $(i + 1)
        else if ($i == "sub")
            vSub = $(i + 1)
        else if ($i == "trig")
            vTrig = $(i + 1)
        else if ($i == "nstick")
            vNstick = $(i + 1)
        else if ($i == "nsub")
            vNsub = $(i + 1)
        else if ($i == "ntrig")
            vNtrig = $(i + 1)
        else if ($i == "pstick")
            vPstick = $(i + 1)
        else if ($i == "psub")
            vPsub = $(i + 1)
        else if ($i == "ptrig")
            vPtrig = $(i + 1)
        else if ($i == "scene")
            vScene = $(i + 1)
    }
    if (vErr == "" || vBtn == "" || vNow == "" || vPrev == "" || vScene == "" ||
        vStick == "" || vSub == "" || vTrig == "" ||
        vNstick == "" || vNsub == "" || vNtrig == "" ||
        vPstick == "" || vPsub == "" || vPtrig == "") {
        unread++
        next
    }
    if (vScene !~ /^-?[0-9]+$/) {
        unread++
        next
    }
    bn = hex2dec(vBtn)
    nn = hex2dec(vNow)
    pn = hex2dec(vPrev)
    if (bn < 0 || nn < 0 || pn < 0 || !onlyknown(bn) || !onlyknown(nn) || !onlyknown(pn)) {
        unread++
        next
    }
    if (split(vStick, ea, ",") != 2 || split(vSub, eb, ",") != 2 || split(vTrig, ec, ",") != 2) {
        unread++
        next
    }
    total++
    if (vScene + 0 >= 0)
        scenes[vScene] = 1
    if (vErr + 0 != 0) {
        errored++
        next
    }
    ok++

    ex = ea[1] + 0
    ey = ea[2] + 0
    esx = eb[1] + 0
    esy = eb[2] + 0
    etl = ec[1] + 0
    etr = ec[2] + 0
    derived = sectorbits(ex, ey)

    # the previous poll's offer: the one the engine's own VBlank pass clamped into this sample
    pair(pn, vPstick, vPsub, vPtrig, ex, ey, esx, esy, etl, etr)
    prevax = p_axok
    prevmiss = p_miss
    prevextra = p_unexplained
    if (prevmiss)
        bmissing++
    if (prevextra)
        bextra++
    # Which of the two explained shapes this line is: the whole pad is that clamp, or it is that
    # clamp plus the port's own d-pad bit. A line the map explains is not "extra" -- it is a press
    # the port itself made, so it is counted as the map's rather than left as a deviation.
    hasextra = 0
    for (bit = 1; bit <= 32768; bit *= 2)
        if (hasbit(bn, bit) && !hasbit(pn, bit))
            hasextra = 1
    if (prevax && !prevmiss && !prevextra) {
        if (hasextra)
            dpad++
        else
            prevall++
    }

    # the same frame's offer, for contrast: a row where the two agree on every line would not have
    # measured the pairing at all
    pair(nn, vNstick, vNsub, vNtrig, ex, ey, esx, esy, etl, etr)
    if (p_axok && !p_miss && !p_unexplained)
        nowall++

    if (bn != 0 && bn == pn) {
        agree++
        for (k = 1; k <= nwant; k++)
            if (hasbit(bn, wbit[k]) && !seen[k]) {
                seen[k] = 1
                ncov++
            }
    }

    if (ex != 0 || ey != 0) {
        sticknz++
        split(vPstick, sxv, ",")
        clampxy(sxv[1] + 0, sxv[2] + 0, 56, 15)
        if (gx != ex || gy != ey)
            stickbad++
    }
    if (esx != 0 || esy != 0) {
        subnz++
        split(vPsub, sxw, ",")
        clampxy(sxw[1] + 0, sxw[2] + 0, 44, 15)
        if (gx != esx || gy != esy)
            subbad++
    }
    if (etl != 0 || etr != 0) {
        trignz++
        split(vPtrig, tcv, ",")
        if (clamptrig(tcv[1] + 0, 30, 180) != etl || clamptrig(tcv[2] + 0, 30, 180) != etr)
            trigbad++
    }
}

END {
    for (s in scenes)
        nsc++
    miss = ""
    for (i = 1; i <= nwant; i++)
        if (!seen[i])
            miss = miss (miss == "" ? "" : ",") wname[i]
    printf "%d %d %d %d %d %d %d %d %d %d %s %d %d %d %d %d %d %d %d\n",
        total + 0, ok + 0, errored + 0, prevall + 0, dpad + 0, nowall + 0, bmissing + 0,
        bextra + 0, agree + 0, ncov + 0, (miss == "" ? "-" : miss), nsc + 0,
        sticknz + 0, stickbad + 0, subnz + 0, subbad + 0, trignz + 0, trigbad + 0, unread + 0
}

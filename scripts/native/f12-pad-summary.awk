# The physical-controller bridge's own record, and whether the state it published reached the
# boundary doc 34's F12 names.
#
# Input is the app's own log from tests/native/scenarios/f12-pad.scn. The injector there drives a
# real GCVirtualController -- a real GCController in GCController.controllers that posts the real
# connect and disconnect notifications and delivers through the real valueChangedHandler -- so the
# code under test is the shipping bridge in mobile/interface/BallpadPhysicalControllers.mm rather
# than a stub of it. Only the hand holding the pad is synthetic. Each step is held for
# kScriptStepFrames port frames, so the run is counted in the engine's own clock rather than in wall
# time and the reading is deterministic.
#
# What the adapter's sampler prints is three claims in the order a press makes them: `pub` (what the
# bridge published into the mixer's controller half), `offer` (what the host's per-frame poll made of
# that mixer), and `engine` (the engine's own PadStatus::s_Current[0] as the VBlank pad pass last
# assembled it). One line per change rather than one per frame, so a step that never ran can be told
# from a step that ran and changed nothing.
#
# The clamps this program applies, and why each one can fail:
#
#   * `offer` must equal `pub` on every record. The port's poll merges the mixer's two halves; the
#     touch half is at rest for the whole scripted run, so a merge that produced anything other than
#     the bridge's own state would mean a second contributor -- which is the duplicate sampling this
#     row is asked to rule out.
#   * `engine` may only carry what the previous record's offer carried, plus the low nibble. That
#     nibble is the port's own left-analog-to-d-pad map (src/NL/plat/platpad.cpp), which ORs a
#     compass sector in once the clamped stick passes 0.6 of its 56 radius; the injector holds the
#     main stick at full on one step, so the port is expected to add a direction there and nowhere
#     else. A face, shoulder or Start bit the previous offer did not carry is a bit nothing pressed.
#   * the engine's own pad is expected to answer a step on a record *of that step*, because each step
#     is held for thirty frames and the engine's read-back lags the offer by one pad-assembly pass
#     rather than by a step.
#   * the frames must strictly increase, and consecutive steps' first changed offers must be one
#     step apart: an injector that advanced twice in a port frame, or a sampler that read the same
#     frame twice, would break one of those two and is the other half of "without duplicate
#     sampling".
#
# Fields, in order:
#   1  lines       `controller: frame` records read
#   2  map         1 when exactly one `controller: mapping` line carries the app-side map at the
#                  vendored threshold and this injector's own two frame counts
#   3  connect     `script controller connected` lines
#   4  assigned    1 when the script's own virtual pad is the controller the bridge assigned the
#                  offered slot to
#   5  displaced   `... is left unassigned` lines: the other pads named rather than left silent
#   6  merge       1 when every record carries offer == pub
#   7  mono        1 when the frames strictly increase
#   8  cadence     1 when each step's first changed offer is one step after the previous step's
#   9  offered     of the eleven press steps, how many offered their own bit
#  10  read        of those, how many had the engine's own pad carry it on that same step
#  11  stick       1 when a record offers the main stick at full and the engine's own main stick
#                  answers nonzero on that step
#  12  cstick      1 when a record offers the C-stick at full and the engine's own substick answers
#  13  triggers    1 when a record offers each analog line at full and the engine's own trigger
#                  answers on it
#  14  release     1 when the release step's record has the engine's own pad at rest
#  15  disconnect  1 when the script's own pad is disconnected once, named as removed
#  16  rest        1 when the last record has the engine's own pad at rest
#  17  bounded     1 when no record carries an engine bit outside the previous offer plus the
#                  port's own d-pad nibble
#  18  unread      records this program could not read

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

# 1 when n carries a bit above the port's own d-pad nibble that allowed does not carry.
function straybit(n, allowed,   b) {
    b = 16
    while (b <= 65536) {
        if (hasbit(n, b) && !hasbit(allowed, b))
            return 1
        b *= 2
    }
    return 0
}

# -1 when the pair is unreadable, else 1 when either half is nonzero.
function nzxy(v,   xy) {
    if (split(v, xy, ",") != 2)
        return -1
    return (xy[1] + 0 != 0 || xy[2] + 0 != 0) ? 1 : 0
}

function pairx(v,   xy) {
    if (split(v, xy, ",") != 2)
        return -1
    return xy[1] + 0
}

function pairy(v,   xy) {
    if (split(v, xy, ",") != 2)
        return -1
    return xy[2] + 0
}

BEGIN {
    split("press-a:256 press-b:512 press-x:1024 press-y:2048 press-z:16 press-start:4096 press-dpad-up:8 press-dpad-left:1 press-l:64 press-r:32 press-right-shoulder:32", s, " ")
    nstep = 11
    for (i = 1; i <= nstep; i++) {
        p = index(s[i], ":")
        sname[i] = substr(s[i], 1, p - 1)
        sbit[i] = substr(s[i], p + 1) + 0
    }
    norder = split("press-a press-b press-x press-y press-z press-start press-dpad-up press-dpad-left press-l press-r press-right-shoulder move-stick move-cstick release", ord, " ")
    # The app-side map the panel reads, at the vendored default and this injector's own clock.
    expectedmap = "a 0x01 b 0x02 x 0x04 y 0x08 z 0x10 threshold 30 settle 20 step 30"
}

# Normalize before any rule reads a field: a CRLF-terminated record would otherwise never compare
# equal to a bare string.
{ sub(/\r$/, "") }

/controller: mapping / {
    maplines++
    at = index($0, "controller: mapping ")
    got = substr($0, at + length("controller: mapping "))
    sub(/\r$/, "", got)
    if (got == expectedmap)
        mapok = 1
    next
}

/controller: script controller connected/ {
    connects++
    next
}

/ is left unassigned/ {
    displaced++
    next
}

/controller: assigned instance / {
    at = index($0, "controller: assigned instance ")
    rest = substr($0, at + length("controller: assigned instance "))
    n = split(rest, t, " ")
    vend = ""
    if (n >= 5 && t[2] == "slot" && t[3] == "1" && t[4] == "vendor")
        for (j = 5; j <= n; j++)
            vend = vend (vend == "" ? "" : " ") t[j]
    # The script's own pad is the framework's virtual controller, and its vendor string is what the
    # framework reports for it. Every other controller in the session is named as left unassigned,
    # so the instance that did take the offered slot is the one this row is about.
    if (vend == "Touch Controller") {
        scriptinstance = t[1]
        assignedok = 1
    }
    next
}

/controller: removed instance / {
    at = index($0, "controller: removed instance ")
    rest = substr($0, at + length("controller: removed instance "))
    n = split(rest, t, " ")
    if (n >= 3 && t[2] == "slot" && t[3] == "1" && scriptinstance != "" && t[1] == scriptinstance)
        scriptremovals++
    next
}

/controller: script controller done, / {
    at = index($0, "controller: script controller done, ")
    rest = substr($0, at + length("controller: script controller done, "))
    if (split(rest, t, " ") >= 1 && t[1] + 0 == 14 && index(rest, "disconnecting") > 0)
        doneok = 1
    next
}

index($0, "controller: frame ") > 0 {
    at = index($0, "controller: frame ")
    rest = substr($0, at + length("controller: frame "))
    if (split(rest, t, " ") < 34) {
        unread++
        next
    }
    if (t[2] != "connected" || t[4] != "pub" || t[12] != "offer" || t[20] != "engine" \
        || t[23] != "buttons" || t[27] != "sub" || t[31] != "script" || t[33] != "step") {
        unread++
        next
    }
    fr = t[1] + 0
    pbtn = t[5]; pstick = t[7]; pcstick = t[9]; ptrig = t[11]
    obtn = t[13]; ostick = t[15]; ocstick = t[17]; otrig = t[19]
    ebtn = t[24]; estick = t[26]; esub = t[28]; etrig = t[30]
    step = t[34]
    pn = hex2dec(pbtn)
    on = hex2dec(obtn)
    en = hex2dec(ebtn)
    if (pn < 0 || on < 0 || en < 0) {
        unread++
        next
    }
    lines++
    if (pbtn != obtn || pstick != ostick || pcstick != ocstick || ptrig != otrig)
        mergebad++
    if (lines > 1 && fr <= lastframe)
        monobad++
    lastframe = fr
    if (lines > 1 && straybit(en, prevon))
        boundbad++
    prevon = on
    sig = obtn "|" ostick "|" ocstick "|" otrig
    # The first record is the state at launch rather than a step's first offer, so it seeds the
    # comparison instead of being read as a step boundary: the pad connects at rest and the first
    # thing a step changes is what the cadence below is about.
    if (lines > 1 && sig != prevsig) {
        for (k = 1; k <= norder; k++)
            if (ord[k] == step && !(k in stepframe))
                stepframe[k] = fr
    }
    prevsig = sig
    for (k = 1; k <= nstep; k++)
        if (step == sname[k]) {
            if (hasbit(on, sbit[k]))
                offeredseen[k] = 1
            if (hasbit(en, sbit[k]))
                readseen[k] = 1
        }
    if (step == "move-stick") {
        if (ostick == "127,0")
            stickoff = 1
        if (nzxy(estick) == 1)
            stickread = 1
    }
    if (step == "move-cstick") {
        if (ocstick == "127,0")
            cstickoff = 1
        if (nzxy(esub) == 1)
            cstickread = 1
    }
    if (otrig == "255,0" && pairx(etrig) > 0)
        trigl = 1
    if (otrig == "0,255" && pairy(etrig) > 0)
        trigr = 1
    if (step == "release" && en == 0 && estick == "0,0" && esub == "0,0")
        releaseok = 1
    lasten = en
    laststick = estick
    lastsub = esub
    lasttrig = etrig
    lastok = 1
    next
}

END {
    for (k = 1; k <= nstep; k++) {
        if (offeredseen[k])
            noffered++
        if (readseen[k])
            nread++
    }
    cadok = 1
    cadlast = -1
    for (k = 1; k <= norder; k++) {
        if (!(k in stepframe)) {
            cadok = 0
            continue
        }
        if (cadlast >= 0) {
            d = stepframe[k] - cadlast
            if (d < 27 || d > 33)
                cadok = 0
        }
        cadlast = stepframe[k]
    }
    restok = (lastok && lasten == 0 && laststick == "0,0" && lastsub == "0,0" && lasttrig == "0,0") ? 1 : 0
    printf "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
        lines + 0, (maplines == 1 && mapok) ? 1 : 0, connects + 0, assignedok ? 1 : 0,
        displaced + 0, (lines > 0 && mergebad == 0) ? 1 : 0, (lines > 0 && monobad == 0) ? 1 : 0,
        cadok ? 1 : 0, noffered + 0, nread + 0, (stickoff && stickread) ? 1 : 0,
        (cstickoff && cstickread) ? 1 : 0, (trigl && trigr) ? 1 : 0, releaseok ? 1 : 0,
        (doneok && scriptremovals == 1 && assignedok) ? 1 : 0, restok,
        (lines > 0 && boundbad == 0) ? 1 : 0, unread + 0
}

# The physical-controller bridge's own record of the map it applies, and whether the presses the
# scripted injector makes reached the engine's own pad as the GameCube buttons that map names.
#
# Input is the app's own log from the interface suite's rebind row
# (tests/native/uitest/BallpadNativeUITests/BallpadSunPadInterfaceTests.swift). That row drives the
# mapping panel's real rows with real taps -- rebinding GameCube Z to the physical Y button, then
# putting the interface's default back through the panel's own Reset -- and relaunches with
# STRIKERS_FAKE_PAD=controller after each edit. Every scripted launch prints the map it read from
# the vendored store at start-up and then drives a real GCVirtualController through the 14-step
# sweep, so the log carries two things per session: the map the app said was in force, and the bits
# the bridge published and the engine's own pad held while the script pressed.
#
# What this program judges is the join between them, and it needs both halves to be readable:
#
#   * The press steps press-a, press-b, press-x, press-y and press-z press one physical button
#     each (SampleForStep in mobile/interface/BallpadPhysicalControllers.mm: A, B, X, Y and the left
#     shoulder), and those five are exactly the five buttons the store maps. So each of those
#     steps' records is a reading of the map: the GameCube bit the bridge publishes for a physical
#     press has to be the bit of the GameCube button that this session's own map line binds that
#     physical button to.
#   * The same bit has to appear on the engine's own pad -- the port's PadStatus::s_Current[0] as
#     the VBlank pad pass last assembled it -- on a record of that step. The engine's read-back
#     lags the offer by one pad-assembly pass, which is why the record that carries the bit may be
#     the second one of the step rather than the first.
#   * Every non-zero pub on one of those steps must be exactly that one bit. The script presses one
#     button at a time, so a mask carrying anything else is a press this row cannot account for,
#     and a step whose records all publish zero is a step that ran and pressed nothing.
#   * The five values on the map line must be the five physical buttons one for one. Assigning is a
#     swap, so a map that repeated a button would leave another unbound, and a line that named one
#     twice would make the expectation above ambiguous rather than wrong. Neither the panel's choice
#     nor the store can produce one, and a line that carried one would not be read generously here.
#   * The map line itself must be the vendored shape at this injector's own threshold and clock, so
#     a session whose line drifts from the code under test is not read at all.
#
# Fields, in order:
#   1  sessions   controller: mapping lines: one per scripted launch in the log
#   2  maps       of those, how many carried the vendored shape with the five physical buttons as a
#                 permutation and this injector's threshold and frame counts
#   3  sweeps     of those, how many ran all five of the mapped press steps
#   4  applies    of those, how many had every non-zero pub on those steps be exactly the one
#                 GameCube bit that this session's own map binds that physical button to
#   5  engines    of those, how many had the engine's own pad carry that bit in the same step
#   6  distinct   distinct five-button maps the sessions carried. The two scripted launches are the
#                 ones this row's own edit and Reset produce, so they have to differ: a run whose
#                 launches all read the same map is a run where the panel's edit never reached one,
#                 and the join below would then say nothing about the store.
#   7  unread     controller: frame records this program could not read, or that arrived before any
#                 map line to compare them against

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
    # The physical button each mapped press step presses, from SampleForStep: A 1, B 2, X 4,
    # Y 8, left shoulder 16 -- the same five values the store's own options are.
    phys["press-a"] = 1
    phys["press-b"] = 2
    phys["press-x"] = 4
    phys["press-y"] = 8
    phys["press-z"] = 16
    nphys = split("1 2 4 8 16", pbits, " ")
    nmap = split("A B X Y Z", gnames, " ")
    # The GameCube bits the port's own pad carries for those buttons, read out of the port exactly
    # the way the F12 row reads them: A 0x100, B 0x200, X 0x400, Y 0x800, Z 0x10.
    gbit["A"] = 256
    gbit["B"] = 512
    gbit["X"] = 1024
    gbit["Y"] = 2048
    gbit["Z"] = 16
    sessions = 0
}

# Normalize before any rule reads a field: a CRLF-terminated record would otherwise never compare
# equal to a bare string.
{ sub(/\r$/, "") }

/controller: mapping / {
    # A session begins at its map line, so the previous one is finished here: what it ran and what
    # it published is complete by the time the next launch has printed its own map.
    if (sessions > 0)
        finishSession()
    sessions++
    okline = 0
    at = index($0, "controller: mapping ")
    rest = substr($0, at + length("controller: mapping "))
    n = split(rest, t, " ")
    if (n == 16 && t[1] == "a" && t[3] == "b" && t[5] == "x" && t[7] == "y" && t[9] == "z" \
        && t[11] == "threshold" && t[12] + 0 == 30 && t[13] == "settle" && t[14] + 0 == 20 \
        && t[15] == "step" && t[16] + 0 == 30) {
        okline = 1
        for (i = 1; i <= nmap; i++) {
            v = hex2dec(t[i * 2])
            mapg[gnames[i]] = v
            if (v < 0)
                okline = 0
        }
        # One for one, or the expectation below would name two GameCube buttons for one press.
        for (i = 1; i <= nphys; i++) {
            seenv[pbits[i]] = 0
            for (j = 1; j <= nmap; j++)
                if (mapg[gnames[j]] == pbits[i])
                    seenv[pbits[i]]++
            if (seenv[pbits[i]] != 1)
                okline = 0
        }
        if (okline) {
            mapokline[sessions] = 1
            key = ""
            for (i = 1; i <= nphys; i++)
                key = key (key == "" ? "" : ",") t[i * 2]
            distinct[key] = 1
            # Which GameCube bit a press of each physical button has to produce under this map.
            for (i = 1; i <= nphys; i++) {
                expect[sessions, pbits[i]] = -1
                for (j = 1; j <= nmap; j++)
                    if (mapg[gnames[j]] == pbits[i])
                        expect[sessions, pbits[i]] = gbit[gnames[j]]
            }
        }
    }
    next
}

index($0, "controller: frame ") > 0 {
    at = index($0, "controller: frame ")
    rest = substr($0, at + length("controller: frame "))
    if (sessions == 0) {
        unread++
        next
    }
    if (split(rest, t, " ") < 34) {
        unread++
        next
    }
    if (t[2] != "connected" || t[4] != "pub" || t[12] != "offer" || t[20] != "engine" \
        || t[23] != "buttons" || t[27] != "sub" || t[31] != "script" || t[33] != "step") {
        unread++
        next
    }
    lines++
    step = t[34]
    if (!(step in phys))
        next
    pb = phys[step]
    ran[sessions, pb] = 1
    pn = hex2dec(t[5])
    en = hex2dec(t[24])
    if (pn < 0 || en < 0) {
        unread++
        next
    }
    want = expect[sessions, pb]
    if (pn != 0) {
        if (want > 0 && pn == want)
            offered[sessions, pb] = 1
        else
            strayed[sessions, pb] = 1
    }
    if (want > 0 && hasbit(en, want))
        read[sessions, pb] = 1
    next
}

function finishSession(   i, pb, ok) {
    if (mapokline[sessions])
        maps++
    ok = 1
    for (i = 1; i <= nphys; i++)
        if (!ran[sessions, pbits[i]])
            ok = 0
    if (ok)
        sweeps++
    ok = 1
    for (i = 1; i <= nphys; i++) {
        pb = pbits[i]
        if (!ran[sessions, pb] || !offered[sessions, pb] || strayed[sessions, pb])
            ok = 0
    }
    if (ok)
        applies++
    ok = 1
    for (i = 1; i <= nphys; i++)
        if (!read[sessions, pbits[i]])
            ok = 0
    if (ok)
        engines++
}

END {
    if (sessions > 0)
        finishSession()
    for (k in distinct)
        ndistinct++
    printf "%d %d %d %d %d %d %d\n",
        sessions + 0, maps + 0, sweeps + 0, applies + 0, engines + 0, ndistinct + 0, unread + 0
}


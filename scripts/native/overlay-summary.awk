# overlay-summary.awk -- what the drawn touch controls say about the touch settings (R1 item 5).
#
# The input is the app's own `overlay:` family, one line per settled drawn tree:
#
#   <ts> overlay: the touch controls as drawn -- controllers C hide-requested H opacity O size S
#        drawn N hidden V | ID alpha WxH @x,y kK[ hidden] | ...
#
# The reading exists because the settings store is a different witness from the overlay: the store
# can hold an opacity that no control was ever drawn at, and only the drawn tree is what a player
# touches. Every field below is taken off that tree, and the six settings R1 item 5 owes are judged
# as relations between the drawn numbers and the settings on the same line:
#
#   opacity         the alpha every visible control is drawn at, against the line's own opacity
#   control size    a control's drawn width against the line's own size, as one constant base
#   hide            the setting, the controller count and how many controls were drawn hidden
#   modern C-stick  the axis the port was handed, which is judged by the app's `c-stick:` family
#   move            a control's drawn centre, changed one control at a time
#   resize          the per-control k, judged by the drawn width it produces against the width the
#                   same control is drawn at with no override
#   reset           a centre that returns to where it was, with every k back at 1.00
#
# Two of these need a word of explanation, because they are the two a reader could otherwise take
# for a mistaken measurement.
#
# The layout editor is the one state that draws a tree the panel's settings do not describe: its
# pass paints every control at an alpha of 1.0 whatever the opacity setting says. A line whose
# controls all sit at 1.00 while the setting says something else is therefore counted as the
# editor's paint (field 5) rather than as a mismatch, and every other line has to track the setting
# exactly (field 4). A line that is neither is a drawn opacity no setting asked for, which is the
# failure this family exists to show.
#
# k is the per-control size override the editor writes, 1.0 when there is none, and it is the only
# thing that tells the editor's own resize apart from the panel's global size setting: both change a
# drawn width, and only the override leaves every other control alone. The size relation is
# therefore judged only on lines where no override is in play (field 8 onward), and the override is
# judged on the line where exactly one control carries one (field 12) by the width that override
# produced (field 13): that control's own base width -- the width it is drawn at over the size
# setting, taken from the lines that carry no override -- times the line's size, times its k.
#
# The centre is deliberately *not* the resize test, and the reason for that is a measurement rather
# than a preference. A control that sits against the edge of the surface is pinned to that edge and
# grows inward: on the iPhone 17e the editor's Z, resized to k 1.72 at a size of 1.35, is drawn
# 100x100 at x=747 with its right edge at 797 -- 797 both before and after -- so a resize there
# moves the centre, and a test that demanded the centre hold would report the editor's own resize as
# a fault. The iPad behaves the other way round (Z grows about its centre, 62 wide to 146, at x=977
# both times), so the centre neither holds nor moves as a rule, and it cannot be the criterion on
# either form factor. The width is what an override *is*, and it is judged as a distance to an
# interval rather than to a value because the log writes a width in whole points and a size to two
# decimals -- 0.52pt of interval on the iPad, 0.04pt on the phone.
#
# Output, one line, in this order:
#
#   total unread | opacity-values opacity-tracked opacity-unit opacity-tracked-below-unit
#   alpha-values | size-values size-widths size-spread | k-lines k-solo k-scaled k-values
#   | moved-pairs reset-returns | hide-values hidden-lines visible-lines
#
# Two passes: the first parses every line into arrays, the second reasons over the whole run,
# because four of the readings (a move pair, a reset return, a resize judged against its base width,
# a size base held across settings) are relations between two lines rather than properties of one.
# Lines this program cannot read are counted in field 2 and left out of the reasoning, so a shape it
# was not written for lands as a FAIL row rather than as a silently smaller sample.

# --- pass one: parse ---------------------------------------------------------

function parseOverlay(body,   nseg, seg, hcount, head, i, id, slot, bad) {
    mark = index(body, "-- ")
    if (mark == 0)
        return 0
    body = substr(body, mark + 3)
    # The header and every control are separated by " | ". Splitting on a newline rather than on a
    # regular expression keeps this portable to the awk on this host, which is not gawk.
    gsub(/ \| /, "\n", body)
    nseg = split(body, seg, "\n")
    if (nseg < 2)
        return 0

    hcount = split(seg[1], head, " ")
    controllers = hide = opacity = size = drawnCount = hiddenCount = ""
    for (i = 1; i <= hcount; i++) {
        if (head[i] == "controllers") controllers = head[i + 1]
        else if (head[i] == "hide-requested") hide = head[i + 1]
        else if (head[i] == "opacity") opacity = head[i + 1]
        else if (head[i] == "size") size = head[i + 1]
        else if (head[i] == "drawn") drawnCount = head[i + 1]
        else if (head[i] == "hidden") hiddenCount = head[i + 1]
    }
    if (controllers == "" || hide == "" || opacity == "" || size == "" ||
        drawnCount == "" || hiddenCount == "")
        return 0
    # The header's own count has to agree with the list after it, or the line is not the shape the
    # fields below are read in and its positions mean nothing.
    if (nseg - 1 != drawnCount + 0)
        return 0

    line++
    lineOk[line] = 1
    lineHide[line] = hide + 0
    lineOpacity[line] = opacity + 0
    lineSize[line] = size + 0
    lineCount[line] = drawnCount + 0
    lineHidden[line] = hiddenCount + 0
    lineControllers[line] = controllers + 0

    bad = 0
    for (i = 2; i <= nseg; i++) {
        if (split(seg[i], field, " ") < 5) { bad = 1; break }
        id = field[1]
        if (split(field[3], wh, "x") != 2) { bad = 1; break }
        if (substr(field[4], 1, 1) != "@") { bad = 1; break }
        if (split(substr(field[4], 2), xy, ",") != 2) { bad = 1; break }
        if (substr(field[5], 1, 1) != "k") { bad = 1; break }
        slot = line SUBSEP id
        if (slot in controlWidth) { bad = 1; break }
        controlId[line, i - 1] = id
        controlWidth[slot] = wh[1] + 0
        controlHeight[slot] = wh[2] + 0
        controlX[slot] = xy[1] + 0
        controlY[slot] = xy[2] + 0
        controlAlpha[slot] = field[2] + 0
        controlK[slot] = substr(field[5], 2) + 0
        controlHidden[slot] = (field[6] == "hidden") ? 1 : 0
    }
    if (bad) {
        # The line is half-parsed and is left out of the reasoning; pass two skips it by flag rather
        # than by unsetting what it already wrote, because unsetting an entry per field is how a
        # reading like this acquires a bug that only shows on the malformed line nobody has.
        delete lineOk[line]
        line--
        return 0
    }
    return 1
}

# --- helpers -----------------------------------------------------------------

function countOf(a,   n, k) {
    n = 0
    for (k in a)
        n++
    return n
}

function near(a, b, tol) {
    return ((a - b) <= tol) && ((b - a) <= tol)
}

# --- pass two: reason --------------------------------------------------------

function analyse(   l, j, m, k, x, s, i, id, slot, base, allTrack, allUnit, overrides, only,
                    dx, dy, d, moved, stray, who, key, same, allUnitK, idb) {
    for (l = 1; l <= line; l++) {
        if (!(l in lineOk))
            continue

        opacitySeen[lineOpacity[l]] = 1
        hideSeen[lineHide[l]] = 1
        if (lineHidden[l] > 0)
            hiddenLines++
        else
            visibleLines++

        # opacity: what every control the overlay drew is painted at, against the setting on the
        # same line. A hidden control is painted at zero by definition and is left out.
        allTrack = 1
        allUnit = 1
        for (j = 1; j <= lineCount[l]; j++) {
            slot = l SUBSEP controlId[l, j]
            if (controlHidden[slot])
                continue
            if (!near(controlAlpha[slot], lineOpacity[l], 0.015))
                allTrack = 0
            if (!near(controlAlpha[slot], 1.0, 0.015))
                allUnit = 0
        }
        if (allTrack) {
            tracked++
            if (lineOpacity[l] < 0.99)
                trackedBelowUnit++
        } else if (allUnit) {
            unit++
        }
        slot = l SUBSEP "A"
        if (slot in controlAlpha)
            alphaSeen[sprintf("%.2f", controlAlpha[slot])] = 1

        # the per-control overrides on this line, and the ones that are the editor's own resize:
        # exactly one control carrying a scale and every other control back at 1.00.
        overrides = 0
        only = ""
        for (j = 1; j <= lineCount[l]; j++) {
            slot = l SUBSEP controlId[l, j]
            if (!near(controlK[slot], 1.0, 0.005)) {
                overrides++
                only = controlId[l, j]
                kSeen[sprintf("%.2f", controlK[slot])] = 1
            }
        }
        if (overrides > 0)
            overrideLines++
        if (overrides == 1) {
            soloLines++
            soloLine[soloLines] = l
            soloControl[l] = only
        }

        # the size relation, judged only where no per-control override can be confused with it:
        # the panel's own scale, and the width one control is drawn at under it.
        if ((l SUBSEP "A") in controlK && near(controlK[l SUBSEP "A"], 1.0, 0.005)) {
            base = controlWidth[l SUBSEP "A"] / lineSize[l]
            sizeAtUnitK[lineSize[l]] = 1
            widthAtUnitK[sprintf("%.0f", controlWidth[l SUBSEP "A"])] = 1
            if (baseCount == 0) {
                baseMin = base
                baseMax = base
            } else {
                if (base < baseMin)
                    baseMin = base
                if (base > baseMax)
                    baseMax = base
            }
            baseCount++
        }

        # and the base this control is drawn at per unit of size, for the override judgement
        # below. A line where this control carries no override is a base line whatever the other
        # controls on it are doing, because one control's k cannot resize another. A hidden
        # control is left out: the log does not say what size a hidden control is drawn at, and
        # an override is only ever written for one the editor is showing.
        for (j = 1; j <= lineCount[l]; j++) {
            id = controlId[l, j]
            if (controlHidden[l SUBSEP id])
                continue
            if (!near(controlK[l SUBSEP id], 1.0, 0.005))
                continue
            base = controlWidth[l SUBSEP id] / lineSize[l]
            baseCountById[id]++
            if (baseCountById[id] == 1) {
                baseMinById[id] = base
                baseMaxById[id] = base
            } else {
                if (base < baseMinById[id])
                    baseMinById[id] = base
                if (base > baseMaxById[id])
                    baseMaxById[id] = base
            }
        }
    }

    # a resize, judged by the width the override produced rather than by a centre it did or did
    # not keep. The centre cannot be the test: a control pinned against the surface edge grows
    # inward and its centre moves by design (the iPhone's Z goes 58 wide at x=768 to 100 wide at
    # x=747 with its right edge at 797 both times), while the same control on the iPad grows about
    # its centre and does not move (62 wide to 146, at x=977 both times). What an override *is* is
    # a width: this control's own drawn width against the base width it is drawn at over the size
    # setting, times the line's size, times its k. The base is an interval rather than a value
    # because the log writes a width in whole points and a size to two decimals, so the tolerance
    # is stated in drawn points -- 0.75, well clear of the 0.39pt and 0.25pt that interval is worth
    # on the two form factors -- and the drawn width has to land inside [baseMin, baseMax] scaled
    # by the line's size and the control's k.
    for (s = 1; s <= soloLines; s++) {
        l = soloLine[s]
        id = soloControl[l]
        slot = l SUBSEP id
        if (!(id in baseCountById))
            continue
        if (controlWidth[slot] >= baseMinById[id] * lineSize[l] * controlK[slot] - 0.75 &&
            controlWidth[slot] <= baseMaxById[id] * lineSize[l] * controlK[slot] + 0.75)
            kScaled++
    }

    # a move: two settled readings at the same published size where exactly one control's centre
    # differs and every other control's is where it was. A dragged control looks like this; a
    # relayout (a turn, a rebuild) moves the whole set and is left out by the same test.
    for (i = 1; i <= line; i++) {
        if (!(i in lineOk))
            continue
        for (j = i + 1; j <= line; j++) {
            if (!(j in lineOk))
                continue
            if (lineSize[i] != lineSize[j] || lineCount[i] != lineCount[j])
                continue
            moved = 0
            stray = 0
            who = ""
            for (x = 1; x <= lineCount[i]; x++) {
                id = controlId[i, x]
                dx = controlX[i SUBSEP id] - controlX[j SUBSEP id]
                if (dx < 0) dx = -dx
                dy = controlY[i SUBSEP id] - controlY[j SUBSEP id]
                if (dy < 0) dy = -dy
                d = (dx > dy) ? dx : dy
                if (d > 8.0) {
                    moved++
                    who = id
                } else if (d > 0.6) {
                    stray++
                }
            }
            if (moved != 1 || stray != 0)
                continue
            key = who " from " controlX[i SUBSEP who] "," controlY[i SUBSEP who] \
                  " to " controlX[j SUBSEP who] "," controlY[j SUBSEP who]
            moveSeen[key] = 1

            # and the reset: a later reading that puts every control back on the centres of the
            # reading before the move, with every k at 1.00. The whole set is compared rather than
            # the one control, so a second, differently-placed layout cannot stand in for it.
            for (k = j + 1; k <= line; k++) {
                if (!(k in lineOk) || lineCount[k] != lineCount[i])
                    continue
                same = 1
                allUnitK = 1
                for (x = 1; x <= lineCount[i]; x++) {
                    idb = controlId[i, x]
                    if (!near(controlX[i SUBSEP idb], controlX[k SUBSEP idb], 0.6) ||
                        !near(controlY[i SUBSEP idb], controlY[k SUBSEP idb], 0.6)) {
                        same = 0
                        break
                    }
                    if (!near(controlK[k SUBSEP idb], 1.0, 0.005))
                        allUnitK = 0
                }
                if (same && allUnitK) {
                    resetSeen[who " back to " controlX[i SUBSEP who] "," controlY[i SUBSEP who]] = 1
                    break
                }
            }
        }
    }

    printf "%d %d %d %d %d %d %d %d %d %.2f %d %d %d %d %d %d %d %d %d\n",
           line, unread,
           countOf(opacitySeen), tracked, unit, trackedBelowUnit, countOf(alphaSeen),
          countOf(sizeAtUnitK), countOf(widthAtUnitK), (baseCount > 0) ? baseMax - baseMin : 0,
           overrideLines, soloLines, kScaled, countOf(kSeen),
           countOf(moveSeen), countOf(resetSeen),
           countOf(hideSeen), hiddenLines, visibleLines
}

/ overlay: / {
    if (!parseOverlay($0))
        unread++
}

END {
    analyse()
}

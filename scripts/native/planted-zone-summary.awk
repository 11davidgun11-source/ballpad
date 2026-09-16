# The kartpad-style touch zone each stick carries, read off the app's own `planted zone:` lines.
#
# The ask this family answers is that the analog stick stops being a target the size of its own
# face: a thumb that comes down anywhere near the stick picks it up, the stick moves under the
# thumb, and the travel from there is read at the stick's own radius. What the app publishes per
# stick is the zone's drawn frame beside the stick's resting frame, the radius the zone publishes
# at, the margin it grew by, the four distances a thumb may land from the stick's own centre before
# the zone's edge clamps the plant, and whether the zone is inert.
#
# Four claims, each an arrow that has to be non-empty rather than a report:
#
#   * the zone is strictly larger than the stick on both axes. This is the ask itself: a zone
#     exactly the stick's size would be the old behaviour with extra views.
#   * every one of the four plant distances is at least a quarter of the stick's own smaller side.
#     That distance is how far from the stick's resting centre the plant may land before the zone's
#     edge clamps it, so the floor is a statement about the freedom the origin has: the clamp is
#     `MIN(half the control, half the space)`, and the stick's drawn face is a whole side across, so
#     a zone that grew by this much puts at least this much travel between the rest centre and the
#     edge of where a plant may land. A zone that only re-drew the old geometry would report zero.
#   * the radius the zone publishes at is half that same smaller side, which is the quantity the
#     vendored handler reads at, so what the zone reports is full deflection at the travel the stick
#     always had and only the origin has moved.
#   * the zone is inert exactly while the layout editor is open. The editor's own drags begin on the
#     stick, so a zone that stayed live under the editor would take the gesture that moves the stick
#     in the layout instead of driving it.
#
# A line written with the editor open is not a defect: it is the inert half of the fourth claim,
# and the run requires at least one so that claim is not vacuous.
#
# Fields, in order:
#   1  lines          `planted zone:` records read
#   2  sticks         stick segments read out of them
#   3  zoneBigger     segments whose zone is larger than its stick on both axes
#   4  plantCovered   segments whose four plant distances are each at least a quarter of the side
#   5  radiusOk       segments publishing at the stick's own half-side radius
#   6  inertOk        segments whose inert reading agrees with the line's editing state
#   7  editingLines   records written with the layout editor open
#   8  unreadable     records carrying a stick segment this program could not read

/ planted zone: / {
    editing = ""
    for (i = 1; i <= NF; i++)
        if ($i == "editing") editing = $(i + 1)

    lines++
    if (editing == "1") editingLines++

    read = 0
    for (i = 2; i < NF; i++)
    {
        # A stick segment reads `<id> zone <w>x<h> @<x>,<y> stick <w>x<h> @<x>,<y> radius <r>
        # margin <m> plant l<a> u<b> r<c> d<d> inert <0|1>`, so the size token after `zone` and the
        # one after the literal `stick` three tokens later are the whole of what this program needs
        # to parse a segment at all.
        if ($i != "zone" || $(i + 3) != "stick") continue
        if (split($(i + 1), zone, "x") != 2 || split($(i + 4), stickSize, "x") != 2) continue

        radius = ""; plant = ""; inert = ""
        for (j = i; j < NF; j++)
        {
            if ($j == "radius") radius = $(j + 1)
            if ($j == "plant") plant = $(j + 1) " " $(j + 2) " " $(j + 3) " " $(j + 4)
            if ($j == "inert") { inert = $(j + 1); break }
        }
        if (radius == "" || plant == "" || inert == "" || split(plant, away, " ") != 4)
        {
            unreadable++
            continue
        }

        read++
        sticks++
        side = (stickSize[1] + 0) < (stickSize[2] + 0) ? (stickSize[1] + 0) : (stickSize[2] + 0)
        half = side / 2.0
        floor = side / 4.0

        if ((zone[1] + 0) > (stickSize[1] + 0) && (zone[2] + 0) > (stickSize[2] + 0)) zoneBigger++

        # The four distances arrive as `l<a>`, `u<b>`, `r<c>`, `d<d>`, one letter then a number, so
        # the number is the token less its first character.
        covered = 1
        for (k = 1; k <= 4; k++)
        {
            value = away[k]
            sub(/^[a-z]/, "", value)
            if (value == "" || (value + 0) < floor) covered = 0
        }
        if (covered) plantCovered++

        # The radius is compared against the stick's own half-side at the precision the line
        # carries it at rather than the precision the app holds it at. The line prints whole
        # points, and a stick whose smaller side is odd -- the C stick is 81 points wide on the
        # wide phone -- has a half-side that is not a whole number, so the printed radius is that
        # value rounded down and a strict comparison would fail two segments out of eight for a
        # zone that is publishing exactly what it should. Half a point either side is the whole of
        # the slack, and it stays far tighter than the distance between the stick's own half-side
        # and a zone's -- 24 points on the wide phone -- so a zone publishing at its own radius, or
        # at nothing at all, still fails here.
        if ((radius + 0) >= half - 0.5 && (radius + 0) <= half + 0.5) radiusOk++

        if ((editing == "1" && (inert + 0) == 1) || (editing == "0" && (inert + 0) == 0)) inertOk++
    }

}

END {
    printf "%d %d %d %d %d %d %d %d\n", lines + 0, sticks + 0, zoneBigger + 0, plantCovered + 0,
        radiusOk + 0, inertOk + 0, editingLines + 0, unreadable + 0
}

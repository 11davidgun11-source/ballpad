# The memory half of doc 34's endurance row, reduced from the samples the driver's host memory
# action appends to <proof>/memory.csv.
#
# Input format, written by scripts/native/lib/driver.py sample_memory():
#   wall_s,pid,cpu_pct,rss_kb,vsz_kb
# One row per sample, appended while the run is live. A sample the driver could not attribute to
# this run's own process is written with empty numbers rather than skipped -- see app_process(),
# which matches both the .app/<name> path and the device UDID so it cannot sample another
# Simulator's copy -- so a row that cannot be read is counted here instead of dropped.
#
# What is reported and why. doc 34 asks for startup, peak and steady-state memory, and for the two
# quantities on either side of it to be told apart: rss is the resident (physical) footprint and
# vsz the virtual reservation, and a growing reservation with a flat footprint is a different
# finding from a growing footprint. Steady state is taken as the last quarter of the samples and
# reported as a median with the band it sat in, because a single final sample cannot distinguish a
# plateau from a sawtooth. Growth is measured from the first sample to that median rather than from
# peak to peak: the peak of a load is not steady state, and using it would report the loading
# spike as the run's working set.
#
# newMaxTail is the count of tail samples that set a new running maximum of the whole series. A
# footprint that climbs without a plateau records one on nearly every sample; a footprint that
# settles records almost none. It is reported as a number rather than as a verdict so the row can
# state what the series did without this program deciding what counts as stabilized.
#
# Fields, in order:
#   1  rows        samples read
#   2  n           samples the statistics are over
#   3  startRss    first sample's resident footprint, MB
#   4  peakRss     the series' largest resident footprint, MB
#   5  peakAt      wall_s of that sample
#   6  endRss      last sample's resident footprint, MB
#   7  steadyRss   median resident footprint of the final quarter, MB
#   8  steadyMin   smallest of that quarter, MB
#   9  steadyMax   largest of that quarter, MB
#  10  growth      steadyRss - startRss, MB
#  11  growthPct   growth as a percentage of startRss
#  12  spread      steadyMax - steadyMin, MB
#  13  cpuMean     mean cpu_pct
#  14  cpuMax      largest cpu_pct
#  15  vszMean     mean virtual reservation, MB
#  16  vszMax      largest virtual reservation, MB
#  17  newMaxTail  tail samples that set a new running maximum of the series
#  18  unread      rows that did not carry five readable numbers

BEGIN {
    FS = ","
    rows = 0
    unread = 0
    n = 0
    sumRss = 0
    sumCpu = 0
    sumVsz = 0
    peakRss = -1
    peakAt = 0
    cpuMax = -1
    vszMax = -1
    runningMax = -1
}

# The header the driver writes once, before the first sample, and any comment line.
/^wall_s,/ { next }
/^#/ { next }

{
    if (NF < 5 || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "") {
        unread++
        next
    }
    rows++
    n++
    wall[n] = $1 + 0
    rss[n] = $4 + 0
    cpu[n] = $3 + 0
    vsz[n] = $5 + 0
    sumRss += rss[n]
    sumCpu += cpu[n]
    sumVsz += vsz[n]
    if (rss[n] > peakRss) { peakRss = rss[n]; peakAt = wall[n] }
    if (cpu[n] > cpuMax) cpuMax = cpu[n]
    if (vsz[n] > vszMax) vszMax = vsz[n]
    if (rss[n] > runningMax) {
        runningMax = rss[n]
        isMax[n] = 1
    }
}

function count_le(arr, v,   k, s) {
    s = 0
    for (k in arr)
        if ((k + 0) <= v)
            s += arr[k]
    return s
}

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

END {
    if (n <= 0) {
        printf "%d 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 %d\n", rows, unread
        exit 0
    }

    tailStart = n - int(n / 4) + 1
    if (tailStart < 1) tailStart = 1
    tailN = n - tailStart + 1

    histMin = -1
    histMax = -1
    tailMin = -1
    tailMax = -1
    newMaxTail = 0
    for (i = tailStart; i <= n; i++) {
        hist[rss[i]]++
        if (histMin == -1 || rss[i] < histMin) histMin = rss[i]
        if (histMax == -1 || rss[i] > histMax) histMax = rss[i]
        if (tailMin == -1 || rss[i] < tailMin) tailMin = rss[i]
        if (rss[i] > tailMax) tailMax = rss[i]
        if (isMax[i]) newMaxTail++
    }

    median = value_at(hist, histMin, histMax, int(tailN / 2) + 1)
    startRss = rss[1]
    growthMb = (median - startRss) / 1024.0
    growthPct = (startRss > 0) ? (100.0 * (median - startRss) / startRss) : 0.0

    printf "%d %d %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %d %d\n",
        rows, n,
        startRss / 1024.0, peakRss / 1024.0, peakAt, rss[n] / 1024.0,
        median / 1024.0, tailMin / 1024.0, tailMax / 1024.0,
        growthMb, growthPct, (tailMax - tailMin) / 1024.0,
        sumCpu / n, cpuMax,
        sumVsz / n / 1024.0, vszMax / 1024.0,
        newMaxTail, unread
}

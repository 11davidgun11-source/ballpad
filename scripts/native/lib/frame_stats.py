#!/usr/bin/env python3
"""Summarise binary PPM frames the port writes, one line per frame.

The port's captures (``shot <path>`` and ``STRIKERS_CAPTURE_EVERY``) are binary P6 PPMs of the
render target.  A question about a frame -- "was this frame black?", "is the black frame bounded
by lit ones or is it a ramp?" -- is a question about pixel content, and this is the smallest tool
that answers it without pulling in an image library.

Use: frame_stats.py DIR [DIR ...] [--black N] [--csv]

  --black N   a frame counts as black when every channel of every pixel is <= N (default 8)
  --csv       emit CSV instead of the aligned table

"""

import argparse
import os
import sys

# Mean luma is exact, not sampled.  The histogram is the whole cost, and it is the same
# integer histogram either way.  numpy is present in this workspace and turns a 278-frame
# burst from minutes into about a second; the ``bytes.count`` fallback stays because the
# tool must not require a library to answer a question about pixels.
try:
    import numpy as _numpy
except Exception:  # pragma: no cover - exercised only where numpy is absent
    _numpy = None


def read_ppm(path):
    """Return (width, height, pixels) for a binary P6 PPM; pixels is the raw RGB bytes."""
    with open(path, "rb") as handle:
        data = handle.read()
    if not data.startswith(b"P6"):
        raise ValueError("not a binary PPM: " + path)
    fields = []
    i = 2
    while len(fields) < 3:
        while i < len(data) and data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while i < len(data) and data[i:i + 1] != b"\n":
                i += 1
            continue
        start = i
        while i < len(data) and not data[i:i + 1].isspace():
            i += 1
        fields.append(int(data[start:i]))
    i += 1  # the single whitespace byte after maxval
    width, height, maxval = fields
    if maxval != 255:
        raise ValueError("only 8-bit PPMs are supported: " + path)
    pixels = data[i:i + width * height * 3]
    return width, height, pixels


def histogram(pixels):
    if _numpy is not None:
        counts = _numpy.bincount(_numpy.frombuffer(pixels, dtype=_numpy.uint8), minlength=256)
        return counts.tolist()
    hist = [0] * 256
    for value in range(256):
        hist[value] = pixels.count(value)
    return hist


def stats(path, black_threshold):
    width, height, pixels = read_ppm(path)
    hist = histogram(pixels)
    total = len(pixels)
    if total == 0:
        raise ValueError("empty frame: " + path)
    mean = sum(value * count for value, count in enumerate(hist)) / float(total)
    maxv = max(value for value, count in enumerate(hist) if count)
    minv = min(value for value, count in enumerate(hist) if count)
    black = sum(hist[:black_threshold + 1])
    return {
        "path": path,
        "name": os.path.basename(path),
        "width": width,
        "height": height,
        "mean": mean,
        "min": minv,
        "max": maxv,
        "black_fraction": black / float(total),
    }


def collect(paths):
    files = []
    for path in paths:
        if os.path.isdir(path):
            for name in os.listdir(path):
                if name.lower().endswith(".ppm"):
                    files.append(os.path.join(path, name))
        else:
            files.append(path)
    files.sort()
    return files


def frame_number(name):
    """The trailing integer in strikers-shot-NNN.ppm, or -1."""
    stem = name.rsplit(".", 1)[0]
    tail = stem.rsplit("-", 1)[-1]
    return int(tail) if tail.isdigit() else -1


def main(argv):
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--black", type=int, default=8)
    parser.add_argument("--csv", action="store_true")
    args = parser.parse_args(argv)

    files = collect(args.paths)
    if not files:
        print("no PPM files found", file=sys.stderr)
        return 1

    rows = [stats(path, args.black) for path in files]

    if args.csv:
        print("name,index,width,height,mean,min,max,black_fraction")
        for row in rows:
            print("%s,%d,%d,%d,%.4f,%d,%d,%.4f" % (
                row["name"], frame_number(row["name"]), row["width"], row["height"],
                row["mean"], row["min"], row["max"], row["black_fraction"]))
        return 0

    print("%-28s %9s %7s %7s %5s %5s %8s" %
          ("frame", "index", "size", "mean", "min", "max", "black%"))
    for row in rows:
        print("%-28s %9d %3dx%-3d %7.2f %5d %5d %7.2f%%" % (
            row["name"], frame_number(row["name"]), row["width"], row["height"],
            row["mean"], row["min"], row["max"], row["black_fraction"] * 100.0))

    # The shape of the black region is the actual answer to the question this tool exists for:
    # a ramp out of black, or isolated black frames between lit ones.
    black = [frame_number(row["name"]) for row in rows if row["max"] <= args.black]
    print("")
    print("%d frames, %d black (max <= %d): %s" % (
        len(rows), len(black), args.black,
        ", ".join(str(value) for value in black) if black else "none"))
    runs = []
    for value in black:
        if runs and value == runs[-1][1] + 1:
            runs[-1][1] = value
        else:
            runs.append([value, value])
    for start, end in runs:
        print("  black run %d..%d (%d frame%s)" %
              (start, end, end - start + 1, "" if end == start else "s"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

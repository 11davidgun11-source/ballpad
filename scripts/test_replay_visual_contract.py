#!/usr/bin/env python3
"""Red native-EFB contract for the reported replay flat-sky corruption.

The input is the Aurora native BGRA dump, before SwiftUI/CGImage presentation.
The mustard signature is measured from the captured iPad regression frame; it
is deliberately a tolerance band, not a display-layer color constant.
"""

from __future__ import annotations

import argparse
from pathlib import Path


MUSTARD_RGB = (206, 186, 107)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=528)
    parser.add_argument("--max-flat-sky-ratio", type=float, default=0.40)
    parser.add_argument("--tolerance", type=int, default=2)
    args = parser.parse_args()

    data = args.raw.read_bytes()
    expected = args.width * args.height * 4
    if len(data) != expected:
        raise SystemExit(
            f"native EFB size mismatch: got {len(data)}, expected {expected}"
        )

    # Only inspect the upper 45%, where the reported replay frame loses the
    # stadium/sky material. BGRA is the native dump order.
    rows = max(1, int(args.height * 0.45))
    pixels = data[: rows * args.width * 4]
    hits = 0
    total = len(pixels) // 4
    for b, g, r, _a in zip(*[iter(pixels)] * 4):
        if all(abs(actual - wanted) <= args.tolerance for actual, wanted in zip((r, g, b), MUSTARD_RGB)):
            hits += 1
    ratio = hits / total
    if ratio > args.max_flat_sky_ratio:
        print(
            "replay visual contract: FAIL "
            f"flat-mustard upper-EFB ratio={ratio:.3f} "
            f"limit={args.max_flat_sky_ratio:.3f}"
        )
        return 1
    print(f"replay visual contract: PASS flat-mustard ratio={ratio:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

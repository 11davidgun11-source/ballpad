#!/usr/bin/env bash
# C1: the Simulator's simctl screenshot API captures a portrait framebuffer
# even for this landscape-only app, so every proof PNG comes out rotated.
# Normalize a captured proof in place: rotate any portrait PNG -90 degrees to
# landscape (verified against the EFB content: text is upright after -90).
set -euo pipefail

for f in "$@"; do
  [ -f "$f" ] || { echo "skip (missing): $f" >&2; continue; }
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
  if [ "${h:-0}" -gt "${w:-0}" ]; then
    tmp="${f}.tmp.png"
    sips -r -90 "$f" --out "$tmp" >/dev/null
    mv "$tmp" "$f"
    echo "rotated -90: $f (${w}x${h} -> landscape)"
  else
    echo "already landscape: $f"
  fi
done

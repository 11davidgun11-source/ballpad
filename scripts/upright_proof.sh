#!/usr/bin/env bash
# C1: the Simulator's simctl screenshot API captures a portrait framebuffer
# even for this landscape-only app, so proof PNGs can come out rotated.
# Normalize a captured proof in place only after visually inspecting it. The
# simulator's screenshot framebuffer and the landscape app can disagree: some
# iPad captures are a portrait canvas containing an already-upright,
# letterboxed landscape app. Rotating those captures corrupts the evidence.
# Use an explicit rotation only when the *game content* is visibly sideways.
# Usage: upright_proof.sh [-90|+90|0] FILE...
# Default 0 is intentionally non-destructive.
set -euo pipefail

ROT="0"
case "${1:-}" in
  -90|+90|0) ROT="$1"; shift ;;
esac

for f in "$@"; do
  [ -f "$f" ] || { echo "skip (missing): $f" >&2; continue; }
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
  if [ "$ROT" = "0" ]; then
    echo "unchanged: $f (${w}x${h})"
  elif [ "${h:-0}" -gt "${w:-0}" ]; then
    tmp="${f}.tmp.png"
    sips -r "$ROT" "$f" --out "$tmp" >/dev/null
    mv "$tmp" "$f"
    echo "rotated $ROT: $f (${w}x${h} -> landscape)"
  else
    echo "already landscape: $f"
  fi
done

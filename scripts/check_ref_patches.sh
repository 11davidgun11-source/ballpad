#!/usr/bin/env bash
# D1: enforce that docs/patches/*.patch matches the LIVE local edits inside
# ref/ (GXRuntime + StrikersRecomp are untracked trees with 35+ locally
# modified files the product build depends on; a git checkout inside ref/
# silently bricks the build, and stale patches lose the local work).
#
# Usage:
#   scripts/check_ref_patches.sh            # fail if live diffs != patches
#   scripts/check_ref_patches.sh --regen    # rewrite docs/patches/ from ref/
#
# Exit code 0 = fresh, 1 = stale/missing. With --regen, always regenerates
# (best-effort) and exits 0.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGMODE=0
if [ "${1:-}" = "--regen" ]; then REGMODE=1; fi

declare -a PAIRS=(
  "$ROOT/ref/GXRuntime|$ROOT/docs/patches/gxruntime-local.patch"
  "$ROOT/ref/StrikersRecomp|$ROOT/docs/patches/strikersrecomp-local.patch"
)

fail=0
for pair in "${PAIRS[@]}"; do
  refdir="${pair%%|*}"
  patch="${pair##*|}"
  name="$(basename "$refdir")"

  if [ ! -d "$refdir/.git" ]; then
    echo "SKIP: $refdir is not a git tree" >&2
    continue
  fi

  tmp="$(mktemp)"
  git -C "$refdir" diff > "$tmp"
  if [ "$REGMODE" = 1 ]; then
    cp "$tmp" "$patch"
    echo "regen: $name -> $patch ($(wc -l < "$tmp") lines)"
  elif cmp -s "$tmp" "$patch"; then
    echo "ok: $name live diff matches $patch"
  else
    echo "STALE: $name live diff differs from $patch" >&2
    echo "  run: scripts/check_ref_patches.sh --regen" >&2
    fail=1
  fi
  rm -f "$tmp"
done

if [ "$fail" != 0 ]; then
  echo "check_ref_patches: FAIL (stale patches)" >&2
  exit 1
fi
echo "check_ref_patches: OK"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/build/env.sh"
PY="${BALLPAD_PYTHON:-python3}"
if ! "$PY" -c 'import sys; assert sys.version_info >= (3, 10)' 2>/dev/null; then
  for cand in /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.11 /usr/local/bin/python3.11 python3; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys; assert sys.version_info >= (3, 10)' 2>/dev/null; then
      PY="$cand"
      break
    fi
  done
fi
echo "Using Python: $PY ($($PY --version 2>&1))"
mkdir -p "$ROOT/work/strikers"
OUT="$ROOT/work/strikers/generated"
ISO="${STRIKERS_ISO:-$ROOT/.local-assets/Super Mario Strikers.iso}"
test -f "$ISO" || { echo "ISO missing: $ISO" >&2; exit 1; }

DOLRECOMP="$ROOT/ref/DolRecomp-aharonahdoot"
if [ ! -d "$DOLRECOMP" ]; then
  DOLRECOMP="$ROOT/ref/DolRecomp"
fi

"$PY" "$ROOT/ref/StrikersRecomp/tools/generate.py" \
  --iso "$ISO" \
  --dolrecomp "$DOLRECOMP" \
  --output "$OUT" \
  --jobs "$(sysctl -n hw.ncpu)"

"$PY" - <<PY
from pathlib import Path
import sys
sys.path.insert(0, "$ROOT/ref/StrikersRecomp/tools")
from fix_generated import fix_generated_sources
print("fixes", fix_generated_sources(Path("$OUT")))
PY

"$PY" "$ROOT/ref/StrikersRecomp/tools/symbols.py" \
  --decomp "$ROOT/ref/smstrikers-decomp" \
  --aurora "$ROOT/ref/GXRuntime/graphics/aurora" \
  --out "$OUT/sdk_symbols.inc"

# Gate checks
test -f "$OUT/generated.h"
test -f "$OUT/main.dol"
test -s "$OUT/sdk_symbols.inc"
chunks=$(ls "$OUT"/chunks/*.c 2>/dev/null | wc -l | tr -d ' ')
if [ "${chunks:-0}" -lt 150 ]; then
  echo "FAIL: chunk count $chunks < 150" >&2
  exit 1
fi
if ! rg -n "DolRecomp constant-time chunk dispatch" "$OUT/generated.h" >/dev/null; then
  echo "FAIL: dispatch marker missing in generated.h" >&2
  exit 1
fi
echo "generate_strikers OK: chunks=$chunks"

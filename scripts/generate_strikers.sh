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
DECOMP="${BALLPAD_DECOMP:-$ROOT/work/decomp/smstrikers-decomp-c0bf2ed}"
test -d "$DECOMP" || { echo "pinned decomp checkout missing: $DECOMP" >&2; exit 1; }

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
  --decomp "$DECOMP" \
  --aurora "$ROOT/ref/GXRuntime/graphics/aurora" \
  --out "$OUT/sdk_symbols.inc" \
  --game-out "$OUT" \
  --allowlist "$ROOT/ref/StrikersRecomp/tools/ballpad_symbols.json" \
  --extra-allowlist "$ROOT/ref/StrikersRecomp/tools/ballpad_hle_symbols.json" \
  --commit c0bf2ed65f6220e69a8db1f8f115c867737f315f \
  --dol-sha1 376d699c99b6b0949abe1b4ceccefdef7828d2b5 \
  --sdk-sha256 a2b5da87203a8ea118cab30f7fdc8070280041e80de6cdf6fbf4fca7ac1789bb

"$PY" - <<PY
import sys
sys.path.insert(0, "$ROOT/ref/StrikersRecomp/tools")
from symbols import verify_decomp_contract
print(verify_decomp_contract(
    "$DECOMP", "$OUT/main.dol",
    "c0bf2ed65f6220e69a8db1f8f115c867737f315f",
    "376d699c99b6b0949abe1b4ceccefdef7828d2b5",
    "$OUT/sdk_symbols.inc",
    "a2b5da87203a8ea118cab30f7fdc8070280041e80de6cdf6fbf4fca7ac1789bb",
    ["Run__15FixedUpdateTaskFf", "Run__14GameRenderTaskFf"]))
PY

# Gate checks
test -f "$OUT/generated.h"
test -f "$OUT/main.dol"
test -s "$OUT/sdk_symbols.inc"
test -s "$OUT/game_symbols.inc"
test -s "$OUT/game_addresses.h"
test -s "$OUT/decomp_contract.inc"
test -s "$OUT/decomp_contract.json"
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

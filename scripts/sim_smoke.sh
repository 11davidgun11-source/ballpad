#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/build/env.sh"
# shellcheck disable=SC1091
source "$ROOT/scripts/sim_mutex.sh"
: "${BALLPAD_UDID:?set BALLPAD_UDID}"
sim_boot "$BALLPAD_UDID"
sim_only_one_booted
echo "sim_smoke: booted $BALLPAD_UDID"

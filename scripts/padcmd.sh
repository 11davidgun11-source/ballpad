#!/usr/bin/env bash
# Send a Dolphin Pipes command to the chassis pad0 device.
# Usage: padcmd.sh "PRESS A" ["PRESS A" ...]   (each arg is one command line)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIPE="${REPO_ROOT}/work/dolphin-user/Pipes/pad0"
if [ ! -p "$PIPE" ]; then
  echo "pad pipe missing: $PIPE (start the chassis first)" >&2
  exit 1
fi
exec 3>"$PIPE"
for cmd in "$@"; do
  printf '%s\n' "$cmd" >&3
done
exec 3>&-

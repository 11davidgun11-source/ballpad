#!/usr/bin/env bash
set -euo pipefail
# Usage: prove_step.sh NN "note"
NN="${1:?step number}"
NOTE="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROOF="$ROOT/build/proofs"
mkdir -p "$PROOF"
stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "[$stamp] step-$NN $NOTE" | tee -a "$PROOF/PROGRESS.md"

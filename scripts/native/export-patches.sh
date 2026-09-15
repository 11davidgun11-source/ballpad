#!/usr/bin/env bash
# Export every intended engine/dependency change from the ignored working fork
# into the tracked patch series, then prove the series reapplies cleanly on a
# clean checkout of the pin.
#
# Use: scripts/native/export-patches.sh [--check-only]

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

CHECK_ONLY=0
[ "${1:-}" = "--check-only" ] && CHECK_ONLY=1

[ -d "${ENGINE_DIR}/.git" ] || die "no engine fork at ${ENGINE_DIR}; run bootstrap.sh first"

BASE="${ENGINE_PIN}"
HEAD="$(git -C "${ENGINE_DIR}" rev-parse HEAD)"

dirty="$(git -C "${ENGINE_DIR}" status --porcelain)"
if [ -n "$dirty" ] && [ "$CHECK_ONLY" = "0" ]; then
    warn "the working fork has uncommitted changes that no patch will carry:"
    printf '%s\n' "$dirty" | sed 's/^/    /'
    die "commit or discard them first; an essential fix must not live only in the ignored tree"
fi

if [ "$CHECK_ONLY" = "0" ]; then
    log "exporting pin..HEAD into ${PATCH_DIR}"
    rm -f "${PATCH_DIR}"/*.patch
    mkdir -p "${PATCH_DIR}"
    git -C "${ENGINE_DIR}" format-patch -o "${PATCH_DIR}" --zero-commit --no-signature \
        --no-numbered "${BASE}..${HEAD}" >/dev/null
    ls -1 "${PATCH_DIR}" | sed 's/^/    /'
fi

# ── Prove the series reapplies on a clean checkout of the pin ─────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
log "verifying the series against a clean checkout of ${ENGINE_PIN}"
git -C "${ENGINE_DIR}" worktree add --quiet --detach "$tmp/verify" "${ENGINE_PIN}"

for p in $(find "${PATCH_DIR}" -name '*.patch' | LC_ALL=C sort); do
    git -C "$tmp/verify" apply "$p" || die "series does not reapply: $(basename "$p")"
done

expected="$(git -C "${ENGINE_DIR}" rev-parse "${HEAD}^{tree}")"
actual="$(git -C "$tmp/verify" add -A >/dev/null 2>&1; git -C "$tmp/verify" write-tree)"
git -C "${ENGINE_DIR}" worktree remove --force "$tmp/verify"

if [ "$expected" != "$actual" ]; then
    die "series tree $actual does not match fork HEAD tree $expected"
fi
log "series reproduces the fork tree exactly ($actual)"

# A digest of the series so doc 36 and the manifest can name one value.
digest="$(cat "${PATCH_DIR}"/*.patch | sha256_of /dev/stdin)"
printf 'patch series sha256: %s\n' "$digest"
printf '%s\n' "$digest" > "${BUILD_ROOT}/patch-series.sha256"

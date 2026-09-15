#!/usr/bin/env bash
# Prove that every component this app ships is attributed: the tracked notices, the
# machine-readable inventory and the documents must agree, a built bundle must carry the
# same notice text offline, and it must contain no game-derived branding.
#
# Use: scripts/native/verify-notices.sh [--platform simulator|device] [options]
#
#   --platform NAME     which built app bundle to inspect (default simulator). macOS is a
#                       development host only, never a distribution artifact
#   --inventory-only    check the manifest, the tracked notices and the documents only.
#                       This passes before anything is built and is the cheap gate (B05)
#   --final             treat recorded notice gaps and components still marked planned as
#                       failures; this is the N7 form of the check
#   --require-bundle    fail instead of skipping when the app bundle has not been built
#
# The exit status is 0 only when nothing failed. Per doc 35 this must fail when a shipped
# component lacks a required notice, when the manifest disagrees with the resources the
# bundle actually carries, or when a notice the manifest claims is not shipped verbatim.

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PLATFORM=simulator
INVENTORY_ONLY=0
FINAL=0
REQUIRE_BUNDLE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --platform) PLATFORM="$2"; shift 2 ;;
        --platform=*) PLATFORM="${1#*=}"; shift ;;
        --inventory-only) INVENTORY_ONLY=1; shift ;;
        --final) FINAL=1; shift ;;
        --require-bundle) REQUIRE_BUNDLE=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

case "$PLATFORM" in
    simulator|device) ;;
    macos) die "macOS is a development host, not a shipped artifact; use --platform simulator" ;;
    *) die "unknown platform: $PLATFORM" ;;
esac

require_cmd python3
[ -f "$MANIFEST" ] || die "dependency manifest is missing: $MANIFEST"
[ -f "${BALLPAD_ROOT}/scripts/native/lib/notices_check.py" ] \
    || die "missing scripts/native/lib/notices_check.py"

BUNDLE="$(platform_build_dir "$PLATFORM")/BallpadStrikers.app"

args=(
    --repo-root "$BALLPAD_ROOT"
    --manifest "$MANIFEST"
    --bundle "$BUNDLE"
)
[ "$INVENTORY_ONLY" = 1 ] && args+=(--inventory-only)
[ "$FINAL" = 1 ] && args+=(--final)
[ "$REQUIRE_BUNDLE" = 1 ] && args+=(--require-bundle)

log "notices: platform $PLATFORM, inventory ${MANIFEST#$BALLPAD_ROOT/}"
if [ "$INVENTORY_ONLY" = 1 ]; then
    log "notices: inventory only, no bundle inspection"
else
    log "notices: bundle ${BUNDLE#$BALLPAD_ROOT/}"
fi

status=0
python3 "${BALLPAD_ROOT}/scripts/native/lib/notices_check.py" "${args[@]}" || status=$?
if [ "$status" -ne 0 ]; then
    die "notices verification failed"
fi
log "notices verification passed"


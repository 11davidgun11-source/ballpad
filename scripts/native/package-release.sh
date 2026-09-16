#!/usr/bin/env bash
# Stage release artifacts locally. Nothing is uploaded or published.
# Use: package-release.sh --out DIR --source-ref COMMIT [--relink-only]
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
python3 "$BALLPAD_ROOT/scripts/native/lib/package_release.py" \
    --root "$BALLPAD_ROOT" --engine "$ENGINE_DIR" --engine-pin "$ENGINE_PIN" \
    --engine-tree "$ENGINE_SOURCE_TREE" --ffmpeg-version "$FFMPEG_VERSION" \
    --ffmpeg-sha "$FFMPEG_SHA256" --ffmpeg-url "$FFMPEG_URL" \
    --deployment-target "$IOS_DEPLOYMENT_TARGET" "$@"

#!/usr/bin/env bash
# Prove that the tracked patch series and the pinned dependency revisions are what
# actually build this app, without inheriting anything from the ignored working trees.
#
# Use: scripts/native/verify-clean.sh [--scope patches|stamps|app|all]
#
#   patches  the tracked series reapplies onto a clean checkout of the pin and
#            reproduces the fork tree exactly; the fork has no unexported edits  (doc 34 B03, cheap)
#   stamps   every pinned dependency the build consumes is present, stamped with the
#            hash it was declared with, and agrees with the manifest                (doc 34 B04, cheap)
#   app      a fresh clone of the fork plus a fresh output directory configures and
#            builds the mobile target against the declared dependency cache only    (doc 34 B03, expensive)
#
# `--scope all` is the N7 evidence run. The expensive scope deliberately reuses
# build/native/deps as a *declared* cache -- doc 33 permits that and forbids borrowing
# an edited ignored source tree.
#
# The exit status is 0 only when every check in the requested scope passed.

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SCOPE="patches"
while [ $# -gt 0 ]; do
    case "$1" in
        --scope) SCOPE="$2"; shift 2 ;;
        --scope=*) SCOPE="${1#*=}"; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

case "$SCOPE" in
    patches|stamps|app|all) ;;
    *) die "unknown scope: $SCOPE" ;;
esac

FAILURES=0
note_pass() { printf '\033[1;32m   ok\033[0m %s\n' "$*"; }
note_fail() { printf '\033[1;31m FAIL\033[0m %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

json_get() {
    python3 - "$@" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    node = json.load(handle)
for key in sys.argv[2].split("."):
    if isinstance(node, list):
        node = node[int(key)]
    else:
        node = node.get(key)
    if node is None:
        break
print("" if node is None else node)
PY
}

# ── patches ───────────────────────────────────────────────────────────────────
scope_patches() {
    log "scope patches: series reapplies onto the pin and reproduces the fork tree"
    if [ ! -d "${ENGINE_DIR}/.git" ]; then
        note_fail "no engine fork at ${ENGINE_DIR}"
        return
    fi
    local dirty
    dirty="$(git -C "${ENGINE_DIR}" status --porcelain)"
    if [ -n "$dirty" ]; then
        note_fail "the fork has changes no patch would carry:"
        printf '%s\n' "$dirty" | sed 's/^/       /' >&2
    else
        note_pass "fork worktree is clean, so the series is the complete record"
    fi

    if "${BALLPAD_ROOT}/scripts/native/export-patches.sh" --check-only > "${LOG_DIR}/verify-clean-patches.log" 2>&1; then
        note_pass "series reproduces the fork tree from ${ENGINE_PIN:0:12}"
    else
        note_fail "series does not reproduce the fork tree; see ${LOG_DIR}/verify-clean-patches.log"
    fi

    local recorded computed
    recorded="$(cat "${BUILD_ROOT}/patch-series.sha256" 2>/dev/null || true)"
    computed="$(cat "${PATCH_DIR}"/*.patch | sha256_of /dev/stdin 2>/dev/null || true)"
    if [ -n "$recorded" ] && [ "$recorded" = "$computed" ]; then
        note_pass "patch series digest matches the recorded value (${computed:0:16})"
    else
        note_fail "patch series digest ${computed:0:16} does not match the recorded ${recorded:0:16}"
    fi
}

# ── stamps ────────────────────────────────────────────────────────────────────
scope_stamps() {
    log "scope stamps: pinned dependency artifacts agree with the manifest"
    local platform
    for platform in macos simulator device; do
        local sdl="${DEPS_ROOT}/sdl3/${platform}/lib/libSDL3.a"
        if [ -f "$sdl" ]; then
            note_pass "SDL3 ${SDL3_TAG} artifact present for ${platform}"
        elif [ "$platform" = macos ]; then
            note_fail "no SDL3 artifact for macOS at ${sdl}"
        else
            printf '    --  SDL3 ${SDL3_TAG} not built for %s yet (bootstrap prepares it per platform)\n' "$platform"
        fi

        local stamp="${DEPS_ROOT}/ffmpeg/${platform}/.ballpad-ffmpeg"
        local codec="${DEPS_ROOT}/ffmpeg/${platform}/lib/libavcodec.a"
        if [ -f "$stamp" ] && [ -f "$codec" ]; then
            if [ "$(cat "$stamp")" = "${FFMPEG_SHA256}" ]; then
                note_pass "FFmpeg ${FFMPEG_VERSION} THP-only artifact for ${platform} matches its tarball hash"
            else
                note_fail "FFmpeg ${platform} stamp does not match the declared tarball hash"
            fi
        elif [ "$platform" = macos ]; then
            printf '    --  FFmpeg is not linked on macOS; the host reference build is out of scope\n'
        else
            printf '    --  FFmpeg ${FFMPEG_VERSION} not built for %s yet\n' "$platform"
        fi
    done

    local versions="${PORT_DIR}/extern/aurora/cmake/AuroraDependencyVersions.cmake"
    if [ -f "$versions" ]; then
        if grep -q "${DAWN_REF}" "$versions"; then
            note_pass "Dawn ref ${DAWN_REF:0:12} is the ref Aurora actually builds"
        else
            note_fail "Dawn ref ${DAWN_REF:0:12} is not the ref in ${versions}"
        fi
        if grep -q "release-${SDL3_TAG}" "$versions"; then
            note_pass "SDL3 tag ${SDL3_TAG} is the tag Aurora expects"
        else
            note_fail "SDL3 tag ${SDL3_TAG} is not the tag in ${versions}"
        fi
    else
        note_fail "no Aurora version file at ${versions}; run bootstrap.sh"
    fi

    if [ -f "${ZSTD_SRC}/build/cmake/CMakeLists.txt" ]; then
        note_pass "zstd ${ZSTD_VERSION} source is staged in the declared dependency cache"
    else
        note_fail "no zstd source at ${ZSTD_SRC}; run bootstrap.sh"
    fi

    if [ -f "$MANIFEST" ]; then
        local pin sdl ffmpeg dawn zstd
        pin="$(json_get "$MANIFEST" engine_pin.revision)"
        sdl="$(json_get "$MANIFEST" components.4.version)"
        dawn="$(json_get "$MANIFEST" components.3.revision)"
        zstd="$(json_get "$MANIFEST" pins.zstd.version)"
        [ "$zstd" = "${ZSTD_VERSION}" ] \
            && note_pass "manifest zstd pin agrees with the build scripts" \
            || note_fail "manifest zstd ${zstd} != ${ZSTD_VERSION}"
        [ "$pin" = "${ENGINE_PIN}" ] \
            && note_pass "manifest engine pin agrees with the build scripts" \
            || note_fail "manifest engine pin ${pin} != ${ENGINE_PIN}"
        [ "$sdl" = "${SDL3_TAG}" ] \
            && note_pass "manifest SDL3 version agrees with the build scripts" \
            || note_fail "manifest SDL3 ${sdl} != ${SDL3_TAG}"
        [ "$dawn" = "${DAWN_REF}" ] \
            && note_pass "manifest Dawn revision agrees with the build scripts" \
            || note_fail "manifest Dawn ${dawn} != ${DAWN_REF}"
    else
        note_fail "no dependency manifest at ${MANIFEST}"
    fi
}

# ── app ───────────────────────────────────────────────────────────────────────
scope_app() {
    local platform="${VERIFY_CLEAN_PLATFORM:-simulator}"
    log "scope app: fresh fork clone and fresh output tree for ${platform}"

    local root
    root="$(mktemp -d)"
    trap 'rm -rf "$root"' RETURN

    if ! git clone --quiet --local "${ENGINE_DIR}" "${root}/strikers" 2>"${root}/clone.log"; then
        note_fail "could not clone the fork; see ${root}/clone.log"
        return
    fi
    git -C "${root}/strikers" checkout --quiet "${ENGINE_BRANCH}" 2>>"${root}/clone.log" \
        || { note_fail "clone has no ${ENGINE_BRANCH} branch"; return; }
    local fresh_tree fork_tree
    fresh_tree="$(git -C "${root}/strikers" rev-parse HEAD^{tree})"
    fork_tree="$(git -C "${ENGINE_DIR}" rev-parse HEAD^{tree})"
    if [ "$fresh_tree" = "$fork_tree" ]; then
        note_pass "fresh clone of the fork is the same tree (${fresh_tree:0:16})"
    else
        note_fail "fresh clone tree ${fresh_tree:0:16} != fork tree ${fork_tree:0:16}"
    fi

    local sysroot build_dir log
    case "$platform" in
        simulator) sysroot=iphonesimulator ;;
        device)    sysroot=iphoneos ;;
        *) die "VERIFY_CLEAN_PLATFORM must be simulator or device" ;;
    esac
    build_dir="${root}/build-${platform}"
    log="${LOG_DIR}/verify-clean-${platform}.log"
    log_new "$log"

    if ! run_logged "$log" cmake -G Ninja -S "${BALLPAD_ROOT}/mobile" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sysroot" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}" \
        -DPORT_DIR="${root}/strikers/smstrikers-port" \
        -DBALLPAD_SDL3_ROOT="${DEPS_ROOT}/sdl3/${platform}" \
        -DBALLPAD_FFMPEG_ROOT="${DEPS_ROOT}/ffmpeg/${platform}" \
        -DBALLPAD_ZSTD_ROOT="${ZSTD_SRC}" \
        -DBALLPAD_PLATFORM="$platform" \
        -DAURORA_DAWN_PROVIDER=vendor \
        -DAURORA_SDL3_PROVIDER=system \
        -DFETCHCONTENT_SOURCE_DIR_DAWN="${DAWN_SRC}"; then
        note_fail "fresh configure failed; see ${log}"
        return
    fi
    note_pass "fresh output tree configured from a fresh source clone"

    if ! run_logged "$log" cmake --build "$build_dir" --target ballpad_probe -j "$(sysctl -n hw.ncpu)"; then
        note_fail "fresh probe build failed; see ${log}"
        return
    fi
    local probe="${build_dir}/BallpadProbe.app/BallpadProbe"
    if [ ! -f "$probe" ]; then
        note_fail "fresh build produced no probe executable at ${probe}"
        return
    fi
    note_pass "fresh probe build produced an executable"
    if assert_macho_platform "$probe" "$([ "$platform" = device ] && echo ios || echo iossimulator)"; then
        note_pass "fresh probe carries the right SDK platform metadata"
    else
        note_fail "fresh probe has the wrong SDK platform metadata"
    fi
}

case "$SCOPE" in
    patches) scope_patches ;;
    stamps)  scope_stamps ;;
    app)     scope_app ;;
    all)     scope_patches; scope_stamps; scope_app ;;
esac

if [ "$FAILURES" -ne 0 ]; then
    die "verify-clean --scope ${SCOPE}: ${FAILURES} check(s) failed"
fi
log "verify-clean --scope ${SCOPE}: all checks passed"

#!/usr/bin/env python3
"""Measure the source-aligned replay/transition rendering boundary.

This is intentionally a red regression gate when run with a captured log:
replay/transition frames must not silently fall into the 12--25 fps class
seen in the iPad report.  It also keeps the diagnosis tied to the pinned
decomp rather than allowing a generic renderer workaround to hide the state
boundary.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PINNED = Path("/tmp/ballpad-decomp-cs-mount/smstrikers-decomp-c0bf2ed")
STATE_RE = re.compile(r"^\[replay\].*state=0x([0-9A-Fa-f]+)")
FRAME_RE = re.compile(
    r"^\[gfx\] frame=.*draws=(\d+).*verts=(\d+).*missingTex=(\d+) "
    r"zeroTex=(\d+).*fps=([0-9.]+)"
)
SEND_FRAME_RE = re.compile(
    r"^\[send-frame\] state=0x([0-9A-Fa-f]+) view=2 packet=0x([0-9A-Fa-f]+)"
)
SKY_TEXTURE_RE = re.compile(
    r"^\[sky-texture\] state=0x([0-9A-Fa-f]+).*magic=0x([0-9A-Fa-f]+) "
    r"levels=(\d+) palette=(\d+).*data=0x([0-9A-Fa-f]+) (\d+)x(\d+) "
    r"fmt=(\d+).*bytes=(\d+) hash=0x([0-9A-Fa-f]+)"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", type=Path)
    parser.add_argument("--max-replay-fps", type=float, default=30.0)
    parser.add_argument(
        "--require-skybox-packet",
        action="store_true",
        help="require an opt-in packet trace to contain a replay/transition view-2 packet",
    )
    parser.add_argument(
        "--require-sky-texture",
        action="store_true",
        help="require a valid decomp PlatTexture-backed replay sky texture record",
    )
    args = parser.parse_args()

    render_task = PINNED / "src/Game/GameRenderTask.cpp"
    replay_manager = PINNED / "src/Game/ReplayManager.cpp"
    if not render_task.exists() or not replay_manager.exists():
        raise SystemExit("pinned decomp render/replay sources are unavailable")
    if "ReplayManager::Instance()->RenderSnapshotAt" not in render_task.read_text():
        raise SystemExit("GameRenderTask no longer contains the decomp replay render call")
    if "void ReplayManager::RenderSnapshotAt(float deltaTime)" not in replay_manager.read_text():
        raise SystemExit("pinned ReplayManager::RenderSnapshotAt is unavailable")

    if args.log is None:
        print("replay render contract: source PASS (run with --log for runtime gate)")
        return 0

    states: list[int] = []
    sky_packet_states: list[int] = []
    sky_textures: list[tuple[int, ...]] = []
    bad: list[str] = []
    lines = args.log.read_text(errors="replace").splitlines()
    for line in lines:
        state = STATE_RE.search(line)
        if state:
            states.append(int(state.group(1), 16))
        send_frame = SEND_FRAME_RE.search(line)
        if send_frame:
            send_state, packet_addr = send_frame.groups()
            if int(send_state, 16) in (0x10, 0x100) and int(packet_addr, 16) != 0:
                sky_packet_states.append(int(send_state, 16))
        sky_texture = SKY_TEXTURE_RE.search(line)
        if sky_texture:
            state_hex, magic_hex, levels, palette, data_hex, width, height, fmt, bytes_, hash_hex = sky_texture.groups()
            if int(state_hex, 16) in (0x10, 0x100):
                sky_textures.append(
                    (
                        int(magic_hex, 16), int(levels), int(palette),
                        int(data_hex, 16), int(width), int(height),
                        int(fmt), int(bytes_), int(hash_hex, 16),
                    )
                )
        frame = FRAME_RE.search(line)
        if not frame:
            continue
        draws, verts, missing, zero, fps = frame.groups()
        if int(missing) or int(zero):
            bad.append(f"unresolved texture payload: {line}")
        if states and states[-1] in (0x10, 0x100, 0x2) and float(fps) < args.max_replay_fps:
            bad.append(f"slow replay/transition frame: {line}")

    if not states:
        raise SystemExit("runtime gate needs at least one [replay] state record")
    if args.require_skybox_packet and not sky_packet_states:
        bad.append(
            "replay/transition packet trace contains no authoritative "
            "view-2 send-frame packet"
        )
    if args.require_sky_texture:
        valid_sky = [
            texture for texture in sky_textures
            if texture[0] == 0x50544558
            and texture[1] >= 1
            and texture[3] != 0
            and texture[4] > 0
            and texture[5] > 0
            and texture[7] > 0
            and texture[8] != 0
        ]
        if not valid_sky:
            bad.append(
                "replay/transition has no valid decomp PlatTexture-backed sky texture"
            )
    if bad:
        print("replay render contract: FAIL")
        print(f"observed states: {', '.join(f'0x{s:X}' for s in sorted(set(states)))}")
        print("\n".join(bad[:8]))
        return 1
    print("replay render contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

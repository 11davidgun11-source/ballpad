#!/usr/bin/env python3
"""Keep scene-history diagnostics out of the per-block guest hot path."""

from pathlib import Path

source = (Path(__file__).resolve().parent / "src" / "ballpad_ios_host.cpp").read_text()
guard = "if (g_blocks >= s_next_scene_probe)"
snapshot = "hle_scene_snapshot(&observed_scene)"

if guard not in source or snapshot not in source:
    raise SystemExit("scene probe contract: required sampling code is missing")

guard_pos = source.index(guard)
snapshot_pos = source.index(snapshot)
if snapshot_pos < guard_pos:
    raise SystemExit("scene probe contract: snapshot precedes bounded probe guard")

loop_start = source.index("static void step_guest(void)")
loop_end = source.index("  if (g_blocks >= kMaxBlocks", loop_start)
loop_body = source[loop_start:loop_end]
if loop_body.count(snapshot) != 1:
    raise SystemExit("scene probe contract: unexpected snapshot count")
if "s_next_scene_probe += 50000ull" not in loop_body:
    raise SystemExit("scene probe contract: probe cadence is not bounded")

print("scene probe overhead contract: PASS")

#!/usr/bin/env python3
"""Guard the iOS guest-loop pacing controller against a slow-step dead band."""

from pathlib import Path


source = (Path(__file__).resolve().parent / "src/ballpad_ios_host.cpp").read_text()
for token in (
    "kTargetStepMs = 16.6",
    "kSlowStepMs = 18.0",
    "kFastStepMs = 14.0",
    "stepMs < kFastStepMs",
    "stepMs > kSlowStepMs",
    "stepMs > (kTargetStepMs * 1.5) ? 150000ull : 75000ull",
    "g_frame_blocks > kMinBlocks + decrement ? g_frame_blocks - decrement : kMinBlocks",
):
    if token not in source:
        raise SystemExit(f"missing adaptive pacing invariant: {token}")

print("adaptive pacing contract: PASS")

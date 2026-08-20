#!/usr/bin/env python3
"""Guard the guest loop from outrunning the host audio clock."""

from pathlib import Path


source = (Path(__file__).resolve().parent / "src/ballpad_ios_host.cpp").read_text()
for token in (
    "kTargetStepMs = 16.6",
    "if (stepMs < kTargetStepMs)",
    "std::this_thread::sleep_for(std::chrono::duration<double, std::milli>(",
    "kTargetStepMs - stepMs",
):
    if token not in source:
        raise SystemExit(f"missing real-time pacing invariant: {token}")

print("real-time pacing contract: PASS")

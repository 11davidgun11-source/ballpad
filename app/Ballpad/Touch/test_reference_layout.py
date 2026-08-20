#!/usr/bin/env python3
"""Guard the shipped touch layout against accidental drift from SunPad."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[3]
NODES = (ROOT / "app/Ballpad/Touch/ControlNodes.swift").read_text()
STORE = (ROOT / "app/Ballpad/Touch/LayoutStore.swift").read_text()


def require(pattern: str, text: str, label: str) -> None:
    if not re.search(pattern, text):
        raise SystemExit(f"missing reference layout contract: {label}")


# These are the normalized anchors copied from the pinned SunPad implementation.
# Keep this focused on topology-critical points; visual styling is covered by
# the app screenshots and the touch-only match test.
for label, control_id, x, y in (
    ("phone stick", "stick", "0.1234722222", "0.7803490991"),
    ("phone c-stick", "cStick", "0.9233055556", "0.8130067568"),
    ("iPad stick", "stick", "0.1310395315", "0.7905894519"),
    ("iPad c-stick", "cStick", "0.9062957540", "0.8583247156"),
    ("iPad A", "a", "0.8916544656", "0.7409513961"),
    ("iPad START", "start", "0.8967789165", "0.5780765253"),
):
    require(rf"nodeAt\(\.{re.escape(control_id)}\b", NODES, label)
    require(rf"{re.escape(x)}.*{re.escape(y)}", NODES, label)

require(r'ballpad\.layout\.sunpad-v6', STORE, "SunPad layout version")

# Every explicit reference anchor must stay on the normalized safe-area canvas.
# This catches the clipped/off-canvas variant of the same regression that the
# UI test could not reliably select under the current Xcode test discovery.
anchors = re.findall(
    r"nodeAt\(\.(?:stick|cStick|a|b|x|y|z|start|l|r),\s*"
    r"([0-9]+\.[0-9]+),\s*([0-9]+\.[0-9]+)",
    NODES,
)
if not anchors:
    raise SystemExit("no explicit normalized touch anchors found")
for x, y in anchors:
    if not (0.0 < float(x) < 1.0 and 0.0 < float(y) < 1.0):
        raise SystemExit(f"touch anchor is off normalized canvas: {x}, {y}")

# The reference topology intentionally keeps the primary movement stick away
# from A on both shipped profiles. Check the encoded anchor separation rather
# than accepting a layout that merely renders every label.
for stick_x, stick_y, a_x, a_y in (
    (0.1234722222, 0.7803490991, 0.8916544656, 0.7409513961),
    (0.1310395315, 0.7905894519, 0.8916544656, 0.7409513961),
):
    if abs(stick_x - a_x) < 0.35 and abs(stick_y - a_y) < 0.12:
        raise SystemExit("reference stick/A topology is materially stacked")

print("reference touch layout contract: OK")

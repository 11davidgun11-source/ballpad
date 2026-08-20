#!/usr/bin/env python3
"""Guard the explicit display-mode contract used by the UIKit frame host."""

from pathlib import Path


root = Path(__file__).resolve().parent.parent
host = (root / "GameHostView.swift").read_text()
menu = (root / "Menu/OverflowMenuView.swift").read_text()

for token in (
    'case "wide":',
    "contentMode = .scaleAspectFill",
    'case "stretch":',
    "contentMode = .scaleToFill",
    "contentMode = .scaleAspectFit",
):
    if token not in host:
        raise SystemExit(f"missing display aspect invariant: {token}")

# SwiftUI can outlive the simulator console pipe. Direct FileHandle writes in
# updateUIView/updateFrame turn a harmless closed pipe into an NSException and
# abort the app, so display diagnostics must use the OS logger instead.
if "FileHandle.standardError.write" in host:
    raise SystemExit("display diagnostics must not write directly to stderr")
if "NSLog(\"[display]" not in host:
    raise SystemExit("display diagnostics must use NSLog")

for token in (
    'choice("Original 4:3"',
    'choice("16:9 Crop (Experimental)"',
    'choice("Fill Screen (Experimental)"',
):
    if token not in menu:
        raise SystemExit(f"missing aspect menu option: {token}")

print("display aspect contract: PASS")

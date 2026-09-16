#!/usr/bin/env python3
"""Compile the iPhone/iPad icon and merge Apple's generated bundle metadata."""
import argparse
import pathlib
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--assets", required=True)
parser.add_argument("--bundle", required=True)
parser.add_argument("--platform", choices=("simulator", "device"), required=True)
parser.add_argument("--minimum-os", required=True)
args = parser.parse_args()
bundle = pathlib.Path(args.bundle)
partial = bundle.parent / "app-icon-info.plist"
subprocess.run([
    "xcrun", "actool", args.assets, "--compile", str(bundle),
    "--platform", "iphonesimulator" if args.platform == "simulator" else "iphoneos",
    "--minimum-deployment-target", args.minimum_os,
    "--target-device", "iphone", "--target-device", "ipad",
    "--app-icon", "AppIcon", "--output-partial-info-plist", str(partial),
], check=True)
info_path = bundle / "Info.plist"
with info_path.open("rb") as file:
    info = plistlib.load(file)
with partial.open("rb") as file:
    info.update(plistlib.load(file))
with info_path.open("wb") as file:
    plistlib.dump(info, file)

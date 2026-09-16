#!/usr/bin/env python3
"""Relink the packaged BallPad objects using local Xcode and optional modified FFmpeg."""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--avcodec', type=Path)
    parser.add_argument('--avutil', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / 'link.json').read_text())
    output = (args.out or root / 'relinked/BallpadStrikers').resolve()
    if output.exists():
        parser.error('output already exists; choose a new --out path')
    replacements = {
        '${CXX}': subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--find', 'clang++'], text=True).strip(),
        '${SDK}': subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip(),
        '${OUTPUT}': str(output),
    }
    for option, key in [(args.avcodec, 'avcodec'), (args.avutil, 'avutil')]:
        source = (option or root / manifest[key]).resolve()
        if not source.is_file():
            parser.error('missing archive: ' + str(source))
        replacements['${' + key.upper() + '}'] = str(source)
    command = []
    for token in manifest['argv']:
        for marker, value in replacements.items():
            token = token.replace(marker, value)
        command.append(token)
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(command, cwd=root, check=True)
    print('Relinked:', output)


if __name__ == '__main__':
    main()
